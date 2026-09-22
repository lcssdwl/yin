import 'package:flutter/foundation.dart';

/// 运行日志(内存环形缓冲)
///
/// 缓存下载 / 加密 / 播放等环节的关键事件都写到这里,
/// 在「我的 → 运行日志」里查看,不再弹到界面上打扰用户。
class AppLog {
  AppLog._();

  /// 最多保留多少条(防止长时间运行后无限增长)
  static const int capacity = 500;

  static final List<String> _lines = <String>[];

  /// 日志变化通知(UI 监听后实时刷新)
  static final ValueNotifier<int> version = ValueNotifier<int>(0);

  static void add(String message) {
    final ts = _now();
    _lines.add('[$ts] $message');

    if (_lines.length > capacity) {
      _lines.removeRange(0, _lines.length - capacity);
    }

    // 同时保留 debugPrint,连着 adb 时照样能在控制台看到
    debugPrint(message);

    // 通知 UI(放到微任务,避免正在 build 时触发)
    Future.microtask(() => version.value = version.value + 1);
  }

  /// 倒序返回(最新的在前)
  static List<String> get lines => List<String>.unmodifiable(_lines.reversed);

  static void clear() {
    _lines.clear();
    Future.microtask(() => version.value = version.value + 1);
  }

  static String _now() {
    final d = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(d.hour)}:${two(d.minute)}:${two(d.second)}';
  }
}
