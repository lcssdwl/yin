import '../../config/api_config.dart';

/// JSON 取值工具(后端可能返回 int/String 混用,统一容错处理)
class JsonUtil {
  JsonUtil._();

  static int toInt(dynamic value, [int defaultValue = 0]) {
    if (value == null) return defaultValue;
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is bool) return value ? 1 : 0;
    return int.tryParse(value.toString()) ?? defaultValue;
  }

  static String toStr(dynamic value, [String defaultValue = '']) {
    if (value == null) return defaultValue;
    if (value is String) return value;
    return value.toString();
  }

  static bool toBool(dynamic value, [bool defaultValue = false]) {
    if (value == null) return defaultValue;
    if (value is bool) return value;
    if (value is num) return value != 0;
    final s = value.toString().toLowerCase();
    return s == 'true' || s == '1';
  }

  static double toDouble(dynamic value, [double defaultValue = 0.0]) {
    if (value == null) return defaultValue;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    return double.tryParse(value.toString()) ?? defaultValue;
  }

  /// 图片 / 音频地址
  ///
  /// 后端可能返回相对路径(如 /storage/image/x.png),
  /// 统一补全为绝对地址,避免 App 无法加载;
  /// 已是 http(s):// 的地址原样返回。
  static String toUrl(dynamic value) {
    final s = toStr(value).trim();
    if (s.isEmpty) return '';
    if (s.startsWith('http://') ||
        s.startsWith('https://') ||
        s.startsWith('//') ||
        s.startsWith('data:')) {
      return s;
    }

    final base = ApiConfig.baseUrl.replaceAll(RegExp(r'/+$'), '');
    return '$base/${s.replaceFirst(RegExp(r'^/+'), '')}';
  }
}

/// 秒 → mm:ss
String formatDuration(int seconds) {
  if (seconds <= 0) return '00:00';
  final d = Duration(seconds: seconds);
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  final h = d.inHours;
  return h > 0 ? '$h:$m:$s' : '$m:$s';
}

/// 播放量人性化:128000 → 12.8万
String formatCount(int count) {
  if (count >= 100000000) {
    return '${(count / 100000000).toStringAsFixed(1)}亿';
  }
  if (count >= 10000) {
    return '${(count / 10000).toStringAsFixed(1)}万';
  }
  return count.toString();
}
