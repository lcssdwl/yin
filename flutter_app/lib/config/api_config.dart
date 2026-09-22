import 'dart:io';

import 'package:flutter/services.dart';

/// 后端接口配置
///
/// # baseUrl 怎么改(按平台,从 url.txt 读取,见 [ApiConfig.loadBaseUrl])
///
/// 优先级(高 → 低):
///   1. 平台 url.txt(Android/iOS 资源 / Windows 本地文件)—— 服务器地址的唯一权威来源
///   2. 编译期 dart-define 覆盖(仅当 url.txt 缺失/为空时兜底,主要用于 CI)
///   3. 兜底默认地址 [_defaultBaseUrl]
///
/// ───────────────────────────────────────────────────────────
/// 【Android】打包固化,改的是资源文件,需要重新编译 APK
///   位置: flutter_app/assets/url.txt
///   步骤: 编辑该文件 → flutter build apk(或 flutter run)
///   说明: 内容会打进 APK 的 assets,装到手机后不可再改,换地址必须重编。
/// ───────────────────────────────────────────────────────────
/// 【Windows】放外面,改的是 exe 同目录的文件,**不用重编**
///   位置(二选一,等价):
///     - 开发构建: build\windows\x64\runner\Release\url.txt
///     - 发布目录: 云韵音乐-vX.X.X-win64\url.txt(和 music_app.exe 放一起)
///   步骤: 用记事本打开 url.txt,改完保存,重启 App 即生效。
///   说明: 外网隧道(devtunnel / cloudflared 等)换地址时,直接改这个文件最省事。
/// ───────────────────────────────────────────────────────────
/// 【开发联调】临时指定,优先级最高,会跳过上面的 url.txt
///   flutter run --dart-define=API_BASE_URL=https://xxxx.devtunnels.ms
///   flutter build apk --dart-define=API_BASE_URL=https://xxxx.devtunnels.ms
/// ───────────────────────────────────────────────────────────
/// 【url.txt 文件格式】
///   - 只有一行: 纯后端地址,例如 http://192.168.1.10:8000 或 https://xxx.devtunnels.ms
///   - 不要写注释、不要加引号、前后空格会被自动 trim 掉
///   - 文件缺失 / 内容为空 / 读取失败 → 自动退回 [_defaultBaseUrl]
/// ───────────────────────────────────────────────────────────
class ApiConfig {
  ApiConfig._();

  /// 编译期 dart-define 覆盖(优先级最高,开发期联调用)
  static const String _envBaseUrl =
      String.fromEnvironment('API_BASE_URL', defaultValue: '');

  /// 兜底默认后端地址(局域网 / 本机)
  static const String _defaultBaseUrl = 'http://10.126.126.10:8000';

  /// 运行时实际生效的后端地址,由 [loadBaseUrl] 在启动时填充。
  /// 不再是编译期常量:Android 读 assets/url.txt,Windows 读本地 url.txt。
  static String baseUrl = _defaultBaseUrl;

  static const String apiPrefix = '/api/v1';

  /// 启动时按平台加载后端地址,**必须在 DioClient.init() 之前调用**。
  ///
  ///  - Android / iOS: 读 assets/url.txt(已用 pubspec 的 assets 注册,打包固化)
  ///  - Windows: 读 exe 同目录的 url.txt,方便外网隧道换地址时直接改文件、无需重打包
  ///  - 其它平台 / 文件缺失 / 读取异常 → 退回 _defaultBaseUrl
  static Future<void> loadBaseUrl() async {
    // 1) 平台 url.txt 为最高优先级:服务器地址一律由它决定
    String? fromFile;
    if (Platform.isAndroid || Platform.isIOS) {
      try {
        fromFile = (await rootBundle.loadString('assets/url.txt')).trim();
      } catch (e) {
        print('[api] 读取 assets/url.txt 失败: $e');
      }
    } else if (Platform.isWindows) {
      try {
        final dir = File(Platform.resolvedExecutable).parent.path;
        final file = File('$dir${Platform.pathSeparator}url.txt');
        if (await file.exists()) {
          fromFile = (await file.readAsString()).trim();
        } else {
          print('[api] 未找到 url.txt(将尝试 dart-define/默认值): $dir');
        }
      } catch (e) {
        print('[api] 读取本地 url.txt 失败: $e');
      }
    }

    if (fromFile != null && fromFile.isNotEmpty) {
      baseUrl = fromFile;
      print('[api] baseUrl 来自 url.txt: $baseUrl');
      return;
    }

    // 2) 兜底:编译期 dart-define(仅当 url.txt 缺失/为空时用,主要用于 CI / 临时联调)
    if (_envBaseUrl.isNotEmpty) {
      baseUrl = _envBaseUrl;
      print('[api] baseUrl 来自 dart-define: $baseUrl');
      return;
    }

    // 3) 最终兜底:默认地址
    baseUrl = _defaultBaseUrl;
    print('[api] baseUrl 使用默认值: $baseUrl');
  }

  static const Duration connectTimeout = Duration(seconds: 15);
  static const Duration receiveTimeout = Duration(seconds: 20);
  static const Duration sendTimeout = Duration(seconds: 15);
}

/// 接口路径
class Api {
  Api._();

  // 首页
  static const String homeIndex = '${ApiConfig.apiPrefix}/home/index';
  static const String homeBanner = '${ApiConfig.apiPrefix}/home/banner';
  static const String homeRecommend = '${ApiConfig.apiPrefix}/home/recommend';
  static const String homeNewest = '${ApiConfig.apiPrefix}/home/newest';
  static const String homeGenre = '${ApiConfig.apiPrefix}/home/genre';

  // 搜索
  static const String search = '${ApiConfig.apiPrefix}/search';
  static const String searchHot = '${ApiConfig.apiPrefix}/search/hot';
  static const String searchSuggest = '${ApiConfig.apiPrefix}/search/suggest';

  // 歌曲
  static String songDetail(int id) => '${ApiConfig.apiPrefix}/song/$id';
  static const String songUrl = '${ApiConfig.apiPrefix}/song/url';
  static const String songLyric = '${ApiConfig.apiPrefix}/song/lyric';
  static const String songSimilar = '${ApiConfig.apiPrefix}/song/similar';
  static const String songBatch = '${ApiConfig.apiPrefix}/song/batch';
  static String songPlay(int id) => '${ApiConfig.apiPrefix}/song/play/$id';
  static const String songCollect = '${ApiConfig.apiPrefix}/song/collect';

  // 榜单
  static const String rankList = '${ApiConfig.apiPrefix}/rank/list';
  static String rankSongs(int id) => '${ApiConfig.apiPrefix}/rank/$id/songs';

  // 歌手
  static const String singerList = '${ApiConfig.apiPrefix}/singer/list';
  static String singerDetail(int id) => '${ApiConfig.apiPrefix}/singer/$id';
  static String singerSongs(int id) =>
      '${ApiConfig.apiPrefix}/singer/$id/songs';
  static String singerAlbums(int id) =>
      '${ApiConfig.apiPrefix}/singer/$id/albums';

  // 专辑
  static String albumDetail(int id) => '${ApiConfig.apiPrefix}/album/$id';
  static String albumSongs(int id) => '${ApiConfig.apiPrefix}/album/$id/songs';

  // 歌单
  static const String playlistHot = '${ApiConfig.apiPrefix}/playlist/hot';
  static const String playlistMy = '${ApiConfig.apiPrefix}/playlist/my';
  static const String playlistCreate = '${ApiConfig.apiPrefix}/playlist/create';
  static const String playlistAddSong =
      '${ApiConfig.apiPrefix}/playlist/addSong';
  static const String playlistRemoveSong =
      '${ApiConfig.apiPrefix}/playlist/removeSong';
  static const String playlistCollect =
      '${ApiConfig.apiPrefix}/playlist/collect';
  static const String playlistDelete = '${ApiConfig.apiPrefix}/playlist/delete';
  static String playlistDetail(int id) => '${ApiConfig.apiPrefix}/playlist/$id';
  static String playlistSongs(int id) =>
      '${ApiConfig.apiPrefix}/playlist/$id/songs';

  // 评论
  static const String commentList = '${ApiConfig.apiPrefix}/comment/list';
  static const String commentAdd = '${ApiConfig.apiPrefix}/comment/add';
  static const String commentLike = '${ApiConfig.apiPrefix}/comment/like';

  // 用户
  static const String userRegister = '${ApiConfig.apiPrefix}/user/register';
  static const String userLogin = '${ApiConfig.apiPrefix}/user/login';
  static const String userLogout = '${ApiConfig.apiPrefix}/user/logout';
  static const String userInfo = '${ApiConfig.apiPrefix}/user/info';
  static const String userUpdate = '${ApiConfig.apiPrefix}/user/update';
  static const String userPassword = '${ApiConfig.apiPrefix}/user/password';
  static const String userSync = '${ApiConfig.apiPrefix}/user/sync';
  static const String userCollects = '${ApiConfig.apiPrefix}/user/collects';
  static const String userHistory = '${ApiConfig.apiPrefix}/user/history';
  static const String userHistoryClear =
      '${ApiConfig.apiPrefix}/user/history/clear';

  // 听歌时长上报(切歌 / 暂停 / 退后台时报增量秒数)
  static const String songListen = '${ApiConfig.apiPrefix}/song/listen';

  // App 基础配置(音质列表 + 各音质是否需要登录)
  static const String appConfig = '${ApiConfig.apiPrefix}/app/config';

  // App 使用统计:上报(打开 / 使用心跳)+ 读取(在线 / 客户端数)
  static const String appReport = '${ApiConfig.apiPrefix}/app/report';
  static const String appStats = '${ApiConfig.apiPrefix}/app/stats';

  // 健康检查
  static const String ping = '${ApiConfig.apiPrefix}/ping';
}
