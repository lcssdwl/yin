import '../../core/utils/json_util.dart';

/// 单个音质选项(值 + 显示名 + 是否需要登录)
class QualityOption {
  final String value;
  final String label;
  final bool requiresLogin;

  const QualityOption({
    required this.value,
    required this.label,
    this.requiresLogin = false,
  });

  factory QualityOption.fromJson(Map<String, dynamic> json) {
    return QualityOption(
      value: JsonUtil.toStr(json['value']),
      label: JsonUtil.toStr(json['label']),
      requiresLogin: JsonUtil.toBool(json['requires_login']),
    );
  }
}

/// App 基础配置(GET /app/config)
///
/// 由后台下发「音质列表 + 各音质是否需要登录」,
/// 播放页据此提前提示「此音质需要登录」,而不必等播放被 401 拦截。
class AppConfig {
  /// 音频是否需要登录才能播放(总开关)
  final bool audioRequireLogin;

  /// 免登录音质(游客可直接播放)
  final List<String> noLoginQualities;

  /// 全部音质选项
  final List<QualityOption> qualities;

  const AppConfig({
    this.audioRequireLogin = true,
    this.noLoginQualities = const [],
    this.qualities = const [],
  });

  factory AppConfig.fromJson(Map<String, dynamic> json) {
    final rawQualities = json['qualities'];
    final qualities = rawQualities is List
        ? rawQualities
            .map((e) => QualityOption.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList()
        : <QualityOption>[];

    final rawNoLogin = json['no_login_qualities'];
    final noLogin = rawNoLogin is List
        ? rawNoLogin.map((e) => e.toString()).toList()
        : <String>[];

    return AppConfig(
      audioRequireLogin: JsonUtil.toBool(json['audio_require_login'], true),
      noLoginQualities: noLogin,
      qualities: qualities,
    );
  }

  /// 该音质是否需要登录(找不到时按总开关判定)
  bool requiresLogin(String quality) {
    for (final q in qualities) {
      if (q.value == quality) return q.requiresLogin;
    }
    if (!audioRequireLogin) return false;
    return !noLoginQualities.contains(quality);
  }

  /// 音质显示名
  String labelOf(String quality) {
    for (final q in qualities) {
      if (q.value == quality) return q.label;
    }
    switch (quality) {
      case '128':
        return '标准';
      case 'flac':
        return '无损';
      default:
        return '高品质';
    }
  }
}
