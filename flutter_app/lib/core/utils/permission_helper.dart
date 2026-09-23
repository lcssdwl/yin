import 'dart:io';

import 'package:permission_handler/permission_handler.dart';

/// 权限申请
///
/// 要点:Android 13+ 没有通知权限时,播放通知不会显示,
/// 必须在 AudioService 初始化之前申请。
class PermissionHelper {
  PermissionHelper._();

  /// 启动时申请必要权限
  static Future<void> requestOnStart() async {
    if (!Platform.isAndroid) return;

    // 仅申请通知权限(Android 13+):缺失则不显示播放通知
    await Permission.notification.request();
  }

  /// 仅申请通知权限,返回是否获得
  static Future<bool> requestNotification() async {
    if (!Platform.isAndroid) return true;
    final status = await Permission.notification.request();
    return status.isGranted;
  }
}
