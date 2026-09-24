/// 全局常量
class AppConstants {
  AppConstants._();

  static const String appName = '云韵音乐';

  /// Hive 存储 Box 名称
  static const String boxSettings = 'settings';
  static const String boxLocalData = 'local_data';

  /// 本地存储 Key
  static const String keyToken = 'token';
  static const String keyUserId = 'user_id';
  static const String keyUserInfo = 'user_info';
  static const String keyDeviceId = 'device_id';
  static const String keyThemeMode = 'theme_mode';
  static const String keyQuality = 'play_quality';

  /// 用户配置的后端服务器地址(可运行时修改,首次启动引导填写)
  static const String keyBaseUrl = 'base_url';

  /// 音效预设 id('off' = 原声/关闭)
  static const String keyAudioEffect = 'audio_effect';

  /// 自定义音效的 5 点增益曲线(低 → 高,JSON 数组)
  static const String keyAudioEffectCurve = 'audio_effect_curve';

  /// 游客本地数据 Key(存于 boxLocalData)
  static const String keyLocalFavorites = 'local_favorites';
  static const String keyLocalHistory = 'local_history';
  static const String keyLocalPlaylists = 'local_playlists';

  /// 默认封面占位图
  static const String defaultCover =
      'https://picsum.photos/seed/default/400/400';

  /// 列表分页大小
  static const int pageSize = 20;
}

/// 播放模式
enum PlayMode {
  /// 顺序播放(播完最后一首停下)
  sequence,

  /// 列表循环(播完最后一首自动回到第一首)
  listLoop,

  /// 单曲循环
  single,

  /// 随机播放
  shuffle,
}

extension PlayModeExt on PlayMode {
  String get label {
    switch (this) {
      case PlayMode.sequence:
        return '顺序播放';
      case PlayMode.listLoop:
        return '列表循环';
      case PlayMode.single:
        return '单曲循环';
      case PlayMode.shuffle:
        return '随机播放';
    }
  }
}

/// 音质
enum PlayQuality {
  standard('128'),
  high('320'),
  lossless('flac');

  final String value;
  const PlayQuality(this.value);

  String get label {
    switch (this) {
      case PlayQuality.standard:
        return '标准';
      case PlayQuality.high:
        return '高品质';
      case PlayQuality.lossless:
        return '无损';
    }
  }
}

/// 收藏/评论目标类型(必须与后端一致:1歌曲 2歌单 3专辑 4歌手)
class TargetType {
  TargetType._();
  static const int song = 1;
  static const int playlist = 2;
  static const int album = 3;
  static const int singer = 4;
}
