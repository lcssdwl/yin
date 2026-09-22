import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../data/repositories/app_repository.dart';

/// App 使用统计上报
///
/// 后端按设备号累加三类数据(后台「App 使用情况」卡片):
///   - 打开次数:启动一次 + 每次从后台切回前台
///   - 使用次数:每 [interval] 一次心跳(也是「在线」的依据)
///   - 客户端数:设备号个数
///
/// 全程静默失败:统计只是附带功能,离线 / 后端未更新都不能影响听歌。
class AppUsage {
  AppUsage._();

  /// 心跳间隔
  ///
  /// 后端「在线」窗口是 3 分钟,这里 90 秒一次:丢一两次心跳
  /// (弱网、息屏被系统挂起)也不会被误判成离线。
  static const Duration interval = Duration(seconds: 90);

  static Timer? _timer;
  static AppLifecycleListener? _lifecycle;
  static bool _started = false;
  static String _platform = '';
  static String _version = '';

  /// 开始上报(必须在 StorageService / DioClient 初始化之后调用)
  static Future<void> start() async {
    if (_started) return;
    _started = true;

    _platform = _platformName();
    try {
      final info = await PackageInfo.fromPlatform();
      _version = info.version;
    } catch (_) {
      // 拿不到版本号不影响统计
    }

    // 从后台切回前台也算一次「打开」
    _lifecycle = AppLifecycleListener(
      onResume: () => unawaited(_send('open')),
    );

    unawaited(_send('open'));

    _timer?.cancel();
    _timer = Timer.periodic(interval, (_) => unawaited(_send('use')));
  }

  /// 停止上报(退出登录之类的场合不需要用到,留着方便排查)
  static void stop() {
    _timer?.cancel();
    _timer = null;
    _lifecycle?.dispose();
    _lifecycle = null;
    _started = false;
  }

  static Future<void> _send(String event) async {
    try {
      await AppRepository().report(
        event: event,
        platform: _platform,
        version: _version,
      );
    } catch (_) {
      // 统计失败不影响任何功能
    }
  }

  static String _platformName() {
    if (kIsWeb) return 'web';
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'android';
      case TargetPlatform.iOS:
        return 'ios';
      case TargetPlatform.windows:
        return 'windows';
      case TargetPlatform.macOS:
        return 'macos';
      case TargetPlatform.linux:
        return 'linux';
      case TargetPlatform.fuchsia:
        return 'fuchsia';
    }
  }
}
