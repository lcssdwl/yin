import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../log/app_log.dart';
import '../storage/storage_service.dart';

/// 音频本地缓存(加密存储)
///
/// 策略:**边播边存 + AES-256-GCM 加密(原生硬件加速)**
///   1. 播放时用网络地址立即开始(不等待下载)
///   2. 后台下载音频 → **加密**后写入本地
///   3. 下次播放同一首歌:解密到临时文件后直接播放 —— 秒开、零流量
///
/// 存储结构:
///   audio_cache/{md5}_{quality}.enc   ← 加密缓存(12 字节 nonce + 密文 + 16 字节 MAC 标签)
///   audio_cache/tmp/{md5}_{quality}   ← 播放用临时明文(每次播放前清掉其它明文,
///                                          保证 tmp 同一时刻只有当前这一份)
///
/// **缓存键用音频 MD5,不用歌曲 ID**:
///   ID 是后端的自增序号,重新扫描 / 重建库之后会变。一旦变了,
///   老缓存 `3_128.enc` 会被新 ID 为 3 的那首歌认领 ——
///   表现就是「缓存里明明是这首歌,播出来却是另一首的声音」。
///   MD5 是音频内容本身的指纹,内容不变键就不变,和 ID 怎么变都无关。
///   音质档位一起写进文件名:同一首歌的不同档位是不同文件、指纹也不同,
///   分开存才不会互相覆盖。
///
/// 密钥:sha256(内置串 + 设备ID) → 每台设备不同。
///       把 .enc 文件拷到别的设备也解不开,更无法直接当音频播放。
///
/// 为什么要加密:签名播放地址每次都变,HTTP 缓存必然失效;
/// 而缓存明文文件会被任何文件管理器/工具直接识别播放,
/// 加密后缓存文件即使被拷走也只是一堆无用数据。
///
/// 为什么用 GCM 而非 CBC:
///   cryptography_flutter 在 Android/iOS 上对 AES-GCM 走原生硬件加速
///   (Android Keystore / iOS CommonCrypto),比纯 Dart 快 10~100 倍;
///   AES-CBC 在 Android 上无原生支持,会退回纯 Dart,速度没有提升。
///   GCM 还自带完整性校验(MAC),无需额外 HMAC。
class AudioCache {
  AudioCache._();

  /// 缓存上限:只按**总大小**算(默认 1.5GB),不限制歌曲数量
  ///
  /// 超限时删最久没播过的,一首一首删到总大小回到上限内。
  /// 曲数再多也没关系,只要总量不超就一直留着。
  static const int maxBytes = 1500 * 1024 * 1024;

  /// GCM nonce 长度(标准 96 位)
  static const int _nonceLen = 12;

  /// GCM MAC 标签长度(标准 128 位)
  static const int _tagLen = 16;

  /// 文件头最小有效长度(nonce + MAC,不含密文)
  static const int _headerMinLen = _nonceLen + _tagLen;

  static Directory? _root;
  static Directory? _tmp;
  static SecretKey? _key;
  static Uint8List? _keyBytes;

  /// 缓存变更通知(写入成功 / 清空后 +1)
  ///
  /// 「我的」页监听它实时刷新「已缓存 N 首」,
  /// 否则统计只在页面首次加载时算一次,播完歌切回去还是显示 0 首。
  static final ValueNotifier<int> cacheVersion = ValueNotifier<int>(0);

  static void _notifyChanged() {
    // 回调里可能触发 UI 重建,放到下一帧更安全
    Future.microtask(() => cacheVersion.value = cacheVersion.value + 1);
  }

  /// 缓存进度(供「我的」页显示,排查用;空串 = 空闲)
  static final ValueNotifier<String> progress = ValueNotifier<String>('');

  /// 最近一次缓存失败原因(供「我的」页显示,排查用)
  static String lastError = '';

  static void _setProgress(String text) {
    Future.microtask(() => progress.value = text);
  }

  /// 单文件下载最大重试次数(整文件失败从头重下;单线程顺序下载)
  static const int _maxRetry = 3;

  /// 待下载队列上限(只是排队上限,不是缓存曲数上限;缓存曲数不设限)
  ///
  /// 这里只用来防止「疯狂切歌」时队列无限膨胀,实际能存多少首取决于
  /// 总大小是否超过 [maxBytes]。
  static const int _maxQueued = 500;

  /// 待缓存队列(串行消化)
  static final List<_CacheTask> _queue = <_CacheTask>[];
  static bool _pumping = false;

  // ==================== 目录 ====================

  static Future<Directory> _rootDir() async {
    final cached = _root;
    if (cached != null) return cached;

    final base = await getApplicationSupportDirectory();
    final d = Directory('${base.path}${Platform.pathSeparator}audio_cache');

    if (!await d.exists()) {
      await d.create(recursive: true);
    }

    return _root = d;
  }

  static Future<Directory> _tmpDir() async {
    final cached = _tmp;
    if (cached != null) return cached;

    final root = await _rootDir();
    final d = Directory('${root.path}${Platform.pathSeparator}tmp');

    if (!await d.exists()) {
      await d.create(recursive: true);
    }

    return _tmp = d;
  }

  /// 日志 / 进度条上的短标识(全 32 位指纹太长,刷屏)
  static String _tag(String md5, String quality) {
    final short = md5.length > 8 ? md5.substring(0, 8) : md5;
    return '$short/$quality';
  }

  /// 是否合法指纹(32 位十六进制)。
  /// 老版本用歌曲 ID 当文件名,不满足这个形状 —— 用来识别并清理旧缓存。
  static bool _looksLikeMd5(String s) {
    if (s.length != 32) return false;
    for (final c in s.codeUnits) {
      final isDigit = c >= 0x30 && c <= 0x39;
      final isLower = c >= 0x61 && c <= 0x66;
      final isUpper = c >= 0x41 && c <= 0x46;
      if (!isDigit && !isLower && !isUpper) return false;
    }
    return true;
  }

  static Future<String> _encPath(String md5, String quality) async {
    final d = await _rootDir();
    return '${d.path}${Platform.pathSeparator}${md5}_$quality.enc';
  }

  static Future<String> _tmpPath(String md5, String quality) async {
    final d = await _tmpDir();
    return '${d.path}${Platform.pathSeparator}${md5}_$quality';
  }

  // ==================== 密钥 ====================

  static SecretKey _cacheKey() {
    final cached = _key;
    if (cached != null) return cached;

    // 缓存版本号:升级后旧缓存用旧密钥加密,解密必然失败被自动丢弃,
    // 从而让「改了播放/缓存逻辑后,旧缓存不再生效」—— 相当于自动清缓存。
    var seed = 'yunyun_music_cache_v2';
    try {
      // 绑定设备:换设备后旧缓存自动失效(解密失败会被丢弃)
      seed = '$seed|${StorageService.deviceId}';
    } catch (_) {
      // storage 未就绪时退化为内置串
    }

    final digest = sha256.convert(utf8.encode(seed)).bytes;
    return _key = SecretKeyData(Uint8List.fromList(digest));
  }

  /// **同步**取密钥字节(供 compute 跨 isolate 传递)
  ///
  /// 注意:这里绝不能用 `extractBytes()` —— 它返回的是 `Future<List<int>>`,
  /// Future 无法跨 isolate 序列化,compute() 会直接失败,导致加解密 100% 失败
  /// (表现就是:歌照播,但一首都缓存不下来)。
  static Uint8List _cacheKeyBytes() {
    final cached = _keyBytes;
    if (cached != null) return cached;
    return _keyBytes = Uint8List.fromList((_cacheKey() as SecretKeyData).bytes);
  }

  // ==================== 读取(供播放) ====================

  /// 取可供播放的**本地明文路径**
  ///
  /// [md5] 是音频指纹(见类注释:不能用歌曲 ID)。为空说明后端还没算出指纹,
  /// 这时直接返回 null 走网络 —— 宁可不缓存,也不用一个会变的键去错认别的歌。
  ///
  /// 有加密缓存则解密到 tmp 目录并返回其路径;没有则返回 null。
  static Future<String?> localPath(String md5, String quality) async {
    if (md5.isEmpty) return null;

    try {
      final encFile = File(await _encPath(md5, quality));
      if (!await encFile.exists()) return null;

      final encStat = await encFile.stat();
      if (encStat.size <= _headerMinLen) {
        // 空壳文件,丢掉
        await encFile.delete();
        return null;
      }

      final plain = File(await _tmpPath(md5, quality));

      // 播放本地缓存前,先把 tmp 里**其它**明文全清掉(保护当前目标路径),
      // 保证播放期间 tmp 同时只有当前这一份明文 —— 上一首的明文在此被删除
      // (即「播放后删除解密明文」:切歌/重播时旧明文不再残留)。
      await clearTemp(protectPath: plain.path);

      // 已解密过且比加密文件新 → 直接用,不必重复解密
      if (await plain.exists()) {
        final pStat = await plain.stat();
        if (pStat.size > 0 && pStat.modified.isAfter(encStat.modified)) {
          return plain.path;
        }
      }

      // 解密:放后台 isolate(compute)执行,不卡 UI。
      // 只传路径 + 密钥(几十字节),几十 MB 的音频数据不跨 isolate 搬运。
      // isolate 里用纯 Dart ChaCha20(快),比纯 Dart AES-GCM 快一个量级。
      final ok = await compute(_decryptFile, {
        'src': encFile.path,
        'dst': plain.path,
        'key': _cacheKeyBytes(),
        'nonceLen': _nonceLen,
        'tagLen': _tagLen,
        // 绑定「这一份音频」:AAD 参与认证,内容和指纹/音质对不上就解不开。
        // 多一层保险:即使有人手工把文件名改成另一首的指纹,也一样解不开。
        'aad': '$md5|$quality',
      });

      if (!ok) {
        // 解密失败(密钥版本变了 / 文件损坏)→ 删掉坏缓存,以后直接走网络
        try {
          await encFile.delete();
        } catch (_) {}
        return null;
      }

      return plain.path;
    } catch (_) {
      // 解密失败(密钥变了 / 文件损坏)→ 丢掉这份缓存
      try {
        await File(await _encPath(md5, quality)).delete();
      } catch (_) {}
      return null;
    }
  }

  // ==================== 写入(后台下载) ====================

  /// 下载 → MD5 校验 → 加密 → 存盘
  ///
  /// [md5] 既是**缓存键**(文件名就是它)也是**校验值**:下载完必须比对,
  /// 对不上整份丢弃 —— 既避免把「下了一半 / 被网关塞了错内容」的当成缓存,
  /// 也保证「键 = 内容指纹」这个前提成立(键错了缓存就认错歌)。
  ///
  /// @return 是否已经成功建立缓存
  static Future<bool> save(
    String md5,
    String quality,
    String url,
  ) async {
    if (md5.isEmpty) {
      // 没有指纹就没有可靠的键,宁可不缓存
      AppLog.add('[cache] skip $quality:后端未下发音频指纹,不缓存(用 ID 会串歌)');
      return false;
    }
    if (url.isEmpty || !url.startsWith('http')) {
      AppLog.add('[cache] skip ${_tag(md5, quality)}: url 不是 http($url)');
      return false;
    }

    final tag = _tag(md5, quality);
    File? part;

    try {
      final target = File(await _encPath(md5, quality));

      // 已有缓存就不重复下载
      if (await target.exists() && await target.length() > _headerMinLen) {
        AppLog.add('[cache] $tag 已有缓存,跳过');
        return true;
      }

      part = File('${target.path}.part');
      if (await part.exists()) {
        await part.delete();
      }

      AppLog.add('[cache] 开始下载 $tag');
      _setProgress('缓存中 $tag …');

      final okDown = await _downloadTo(url, part, tag);

      if (!okDown || !await part.exists() || await part.length() <= 0) {
        AppLog.add('[cache] $tag 下载失败: $lastError');
        _setProgress('');
        return false;
      }

      final size = await part.length();
      AppLog.add('[cache] 下载完成 $tag ${(size / 1024 / 1024).toStringAsFixed(2)}MB');

      // 指纹校验(必做):键就是指纹,对不上说明下的不是这一份
      final actual = await compute(_md5File, part.path);

      if (actual.toLowerCase() != md5.trim().toLowerCase()) {
        lastError = 'MD5 不符: 期望 $md5 实际 $actual';
        AppLog.add('[cache] $tag $lastError');

        await part.delete();
        return false;
      }

      AppLog.add('[cache] $tag 指纹校验通过');
      _setProgress('加密中 ${(size / 1024 / 1024).toStringAsFixed(1)}MB');

      // 加密写入
      await _encryptTo(part, target, md5, quality);
      await part.delete();

      AppLog.add('[cache] 已加密缓存 $tag → ${target.path}');

      lastError = '';
      _setProgress('');
      _notifyChanged();
      await _trimIfNeeded();
      return true;
    } catch (e) {
      lastError = '缓存失败: $e';
      AppLog.add('[cache] $tag 缓存失败: $e');
      _setProgress('');

      // 缓存失败不影响播放
      try {
        if (part != null && await part.exists()) {
          await part.delete();
        }
      } catch (_) {}

      return false;
    }
  }

  /// 后台预缓存(**边播边存**,不阻塞播放)
  ///
  /// [md5] 为音频指纹,同时也是缓存键(见类注释)。
  /// 播放永远先用网络地址「流播放」—— 秒开、不等下载;
  /// 缓存只是顺手在后台做,下次再听这首歌才走本地(秒开 + 零流量)。
  /// 失败也不影响当前播放,静默忽略。
  ///
  /// **串行队列**:同时只下一首。多个下载并发会互相抢带宽,
  /// 在隧道 / 弱网下还会被服务端掐连接,结果是「只有第一次能下完」。
  static Future<void> prefetch(
    String md5,
    String quality,
    String url,
  ) async {
    // 没有指纹就不排队:没有可靠的键,缓存下来也认不出是谁
    if (md5.isEmpty || url.isEmpty) return;

    // 同一份音频 + 同一音质只排一次
    if (_queue.any((t) => t.md5 == md5 && t.quality == quality)) {
      return;
    }

    // 队列上限:切歌太快时丢掉最早的,避免堆积几十首
    if (_queue.length >= _maxQueued) {
      _queue.removeAt(0);
    }

    _queue.add(_CacheTask(md5, quality, url));
    _setProgress(_queueLabel());
    unawaited(_pump());
  }

  static String _queueLabel() {
    final n = _queue.length;
    return n <= 1 ? '缓存中…' : '缓存队列 $n 首';
  }

  /// 依次消化队列(同时只有一个在跑)
  static Future<void> _pump() async {
    if (_pumping) return;
    _pumping = true;

    try {
      while (_queue.isNotEmpty) {
        final task = _queue.removeAt(0);

        try {
          // 单首最多给 3 分钟:超时/异常都只放弃这一首,
          // 否则一首卡死就会拖住整个队列(表现就是"失败后再也不缓存了")
          await save(task.md5, task.quality, task.url)
              .timeout(const Duration(minutes: 3));
        } catch (e) {
          AppLog.add('[cache] ${_tag(task.md5, task.quality)} 任务异常,继续下一首: $e');
        }
      }
    } finally {
      _pumping = false;
      _setProgress('');
    }
  }

  /// 把明文文件加密写入目标(格式:12 字节 nonce + 密文 + 16 字节 MAC)
  ///
  /// 加密计算在后台 isolate 执行,避免大文件卡死 UI。
  /// 使用 AES-GCM:cryptography_flutter 在 Android/iOS 上走原生硬件加速。
  static Future<void> _encryptTo(
    File src,
    File dst,
    String md5,
    String quality,
  ) async {
    // 同理:加密放后台 isolate(compute)执行,纯 Dart ChaCha20 快且不卡 UI。
    final ok = await compute(_encryptFile, {
      'src': src.path,
      'dst': dst.path,
      'key': _cacheKeyBytes(),
      'nonceLen': _nonceLen,
      // 与解密端一致:把 音频指纹|音质 作为 AAD 写进认证标签
      'aad': '$md5|$quality',
    });

    if (!ok) {
      throw StateError('encrypt failed: ${src.path}');
    }
  }

  // ==================== 下载 ====================

  /// 单线程整文件下载到 [part]
  ///
  /// 之前的多线程分块(Range)下载在并发合并时会把文件拼坏 —— 尤其 FLAC 大文件,
  /// 残留的分段或乱序合并会导致「文件损坏 / MD5 不符」,缓存永远写不下来。
  /// 改为单连接顺序下载:内容和后端完全一致,MD5 必然对得上。
  /// 整文件失败最多重试 [_maxRetry] 次(从头重下),不分段、不并发。
  static Future<bool> _downloadTo(String url, File part, String tag) async {
    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(minutes: 5),
        sendTimeout: const Duration(seconds: 15),
        headers: const {'Accept-Encoding': 'identity'},
        followRedirects: true,
      ),
    );

    for (var attempt = 0; attempt < _maxRetry; attempt++) {
      try {
        AppLog.add('[cache] $tag 单线程下载(第 ${attempt + 1}/${_maxRetry} 次)');
        final res = await dio.get<ResponseBody>(
          url,
          options: Options(responseType: ResponseType.stream),
        );
        final raf = await part.open(mode: FileMode.write);
        try {
          await _pipe(res.data!.stream, raf);
        } finally {
          await raf.close();
        }

        final size = await part.length();
        if (size <= 0) {
          lastError = '下载为空';
          AppLog.add('[cache] $tag $lastError');
          return false;
        }
        AppLog.add('[cache] $tag 下载完成 ${(size / 1024 / 1024).toStringAsFixed(2)}MB');
        return true;
      } catch (e) {
        lastError = '下载失败(第 ${attempt + 1} 次): $e';
        AppLog.add('[cache] $tag $lastError');
        // 清掉半截文件,下次重试从头来
        try {
          if (await part.exists()) await part.delete();
        } catch (_) {}
        await Future<void>.delayed(Duration(seconds: attempt + 1));
      }
    }
    return false;
  }

  /// 把响应流写进文件(边收边写,不整包驻留内存)
  static Future<void> _pipe(Stream<List<int>> stream, RandomAccessFile raf) async {
    await for (final chunk in stream) {
      await raf.writeFrom(chunk);
    }
  }

  // ==================== 统计 / 清理 ====================

  /// 缓存占用(加密缓存 + 播放临时文件)
  static Future<int> totalBytes() async {
    var total = 0;

    try {
      final root = await _rootDir();
      await for (final e in root.list()) {
        // 排除下载中的临时文件(.part 及其分段 .part.0/.part.1 …)
        if (e is File && !e.path.contains('.part')) {
          try {
            total += await e.length();
          } catch (_) {}
        }
      }
    } catch (_) {}

    try {
      final tmp = await _tmpDir();
      await for (final e in tmp.list()) {
        if (e is File) {
          try {
            total += await e.length();
          } catch (_) {}
        }
      }
    } catch (_) {}

    return total;
  }

  /// 已缓存的歌曲数量(按加密文件数)
  static Future<int> count() async {
    try {
      final root = await _rootDir();
      var n = 0;

      await for (final e in root.list()) {
        if (e is File && e.path.endsWith('.enc')) n++;
      }

      return n;
    } catch (_) {
      return 0;
    }
  }

  /// 清理播放用的临时明文文件(App 启动时调用)
  ///
  /// 加密缓存保留,只是把上次运行残留的明文清掉 ——
  /// 正常播放中的文件不会被删(每次播放都会重新解密)。
  ///
  /// [protectPath] 为需要保护的明文路径(当前正在播放),跳过不删。
  static Future<void> clearTemp({String? protectPath}) async {
    try {
      final tmp = await _tmpDir();
      await for (final e in tmp.list()) {
        if (e is File) {
          if (protectPath != null && e.path == protectPath) continue;
          try {
            await e.delete();
          } catch (_) {}
        }
      }
    } catch (_) {}
  }

  /// 清理旧命名规则的缓存(老版本用「歌曲ID」当文件名)
  ///
  /// 换键的原因见类注释:ID 会变,一变就串歌。旧文件不符合新命名
  /// (应当以 32 位指纹开头),留着既占空间又永远命不中,启动时顺手删掉。
  /// 命不中本身不影响播放 —— 会当作「没有缓存」直接走网络。
  ///
  /// @return 清掉的旧缓存份数
  static Future<int> purgeLegacy() async {
    var n = 0;

    try {
      final root = await _rootDir();
      await for (final e in root.list()) {
        if (e is! File) continue;

        var head = e.path.split(Platform.pathSeparator).last;

        // 尾巴可能是 .enc / .enc.part / .enc.part.0(下载没完成留下的)
        final dotPart = head.indexOf('.part');
        if (dotPart >= 0) head = head.substring(0, dotPart);
        if (!head.endsWith('.enc')) continue;

        final base = head.substring(0, head.length - 4); // 去掉 .enc
        final cut = base.lastIndexOf('_');
        if (cut <= 0) continue;

        // 合法形状:{32位指纹}_{音质};不符合的都算旧缓存
        if (_looksLikeMd5(base.substring(0, cut))) continue;

        try {
          await e.delete();
          n++;
        } catch (_) {}
      }
    } catch (_) {}

    if (n > 0) {
      AppLog.add('[cache] 已清理 $n 份旧缓存(旧版按歌曲 ID 命名,后端换 ID 后会串歌)');
      _notifyChanged();
    }
    return n;
  }

  /// 清空全部缓存(加密文件 + 临时明文)
  ///
  /// [protectPath] 为当前正在播放的明文文件路径:清缓存会删掉它的话,
  /// 正在播放的歌就会中断 —— 所以这里跳过它,等下次启动再清。
  static Future<void> clear({String? protectPath}) async {
    try {
      final root = await _rootDir();
      await for (final e in root.list()) {
        if (e is File) {
          try {
            await e.delete();
          } catch (_) {}
        }
      }
    } catch (_) {}

    await clearTemp(protectPath: protectPath);
    _notifyChanged();
  }

  /// 超过上限时,按最后访问时间删掉最旧的加密缓存
  static Future<void> _trimIfNeeded() async {
    try {
      final root = await _rootDir();
      final entries = <MapEntry<File, int>>[];
      var total = 0;

      await for (final e in root.list()) {
        if (e is! File || !e.path.endsWith('.enc')) continue;

        try {
          final st = await e.stat();
          total += st.size;
          entries.add(MapEntry(e, st.accessed.millisecondsSinceEpoch));
        } catch (_) {}
      }

      if (total <= maxBytes) return;

      entries.sort((a, b) => a.value.compareTo(b.value));

      for (final item in entries) {
        if (total <= maxBytes) break;

        try {
          final size = await item.key.length();
          await item.key.delete();
          total -= size;
        } catch (_) {}
      }
    } catch (_) {}
  }
}

/// 一条待缓存任务
class _CacheTask {
  /// 音频指纹:既是缓存键,也是下载后的校验值
  final String md5;

  final String quality;
  final String url;

  const _CacheTask(this.md5, this.quality, this.url);
}

/// 后台 isolate:算文件 MD5(边读边算,不整包进内存)
Future<String> _md5File(String path) async {
  final digest = await md5.bind(File(path).openRead()).first;
  return digest.toString();
}

// ==================== 加解密(主 isolate 异步执行,走原生硬件加速) ====================

/// 后台 isolate:读明文 → ChaCha20-Poly1305 加密 → 写 [nonce + 密文 + MAC]
///
/// 顶层函数,由 compute() 序列化到后台 isolate 执行(只传路径,不传音频数据)。
Future<bool> _encryptFile(Map<String, dynamic> args) async {
  try {
    final src = File(args['src'] as String);
    final dst = File(args['dst'] as String);
    final keyBytes = args['key'] as Uint8List;
    final nonceLen = args['nonceLen'] as int;
    final aad = utf8.encode((args['aad'] as String?) ?? '');

    final plain = await src.readAsBytes();

    // GCM 要求同一密钥下 nonce 不重复 → 每次用安全随机源现生成
    final rnd = Random.secure();
    final nonceBytes = Uint8List.fromList(
      List<int>.generate(nonceLen, (_) => rnd.nextInt(256)),
    );

    // ChaCha20-Poly1305:纯 Dart 实现快(AES 需查表,ChaCha20 只是算术运算),
    // 且自带 Poly1305 认证,安全性与 GCM 同级。跑在后台 isolate 里。
    final cipher = DartChacha20.poly1305Aead();
    final secretKey = SecretKeyData(keyBytes);

    final secretBox = await cipher.encrypt(
      plain,
      secretKey: secretKey,
      nonce: nonceBytes,
      aad: aad,
    );

    // 打包:nonce + 密文 + MAC 标签
    final out = BytesBuilder()
      ..add(nonceBytes)
      ..add(secretBox.cipherText)
      ..add(secretBox.mac.bytes);

    await dst.writeAsBytes(out.toBytes(), flush: true);
    return true;
  } catch (_) {
    return false;
  }
}

/// 后台 isolate:读密文 → ChaCha20-Poly1305 解密 → 写明文
///
/// 文件格式:[nonce(12B) + 密文 + MAC(16B)]
Future<bool> _decryptFile(Map<String, dynamic> args) async {
  try {
    final src = File(args['src'] as String);
    final dst = File(args['dst'] as String);
    final keyBytes = args['key'] as Uint8List;
    final nonceLen = args['nonceLen'] as int;
    final tagLen = args['tagLen'] as int;
    final aad = utf8.encode((args['aad'] as String?) ?? '');

    final raw = await src.readAsBytes();
    if (raw.length <= nonceLen + tagLen) return false;

    final nonceBytes = Uint8List.sublistView(raw, 0, nonceLen);
    final cipherText = Uint8List.sublistView(raw, nonceLen, raw.length - tagLen);
    final macBytes = Uint8List.sublistView(raw, raw.length - tagLen);

    final cipher = DartChacha20.poly1305Aead();
    final secretKey = SecretKeyData(keyBytes);

    final secretBox = SecretBox(cipherText, nonce: nonceBytes, mac: Mac(macBytes));

    // AAD 不匹配(缓存不属于这首歌 / 音质)会抛 SecretBoxAuthenticationError →
    // 返回 false,上层当作「没有缓存」重新走网络,绝不串歌
    final plain = await cipher.decrypt(secretBox, secretKey: secretKey, aad: aad);

    await dst.writeAsBytes(plain, flush: true);
    return true;
  } catch (_) {
    return false;
  }
}
