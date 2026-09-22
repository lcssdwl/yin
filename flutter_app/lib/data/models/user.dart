import '../../core/utils/json_util.dart';

/// 用户模型
class UserModel {
  final int id;
  final String username;
  final String nickname;
  final String avatar;
  final String signature;
  final int gender;
  final int vipLevel;
  final int collectCount;
  final int historyCount;
  final int playlistCount;

  /// 累计听歌秒数(服务端按实际播放秒数累计,清空历史不影响)
  final int listenSeconds;

  /// 听过的歌曲数(不重复)
  final int listenSongs;

  UserModel({
    required this.id,
    this.username = '',
    this.nickname = '',
    this.avatar = '',
    this.signature = '',
    this.gender = 0,
    this.vipLevel = 0,
    this.collectCount = 0,
    this.historyCount = 0,
    this.playlistCount = 0,
    this.listenSeconds = 0,
    this.listenSongs = 0,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) => UserModel(
        id: JsonUtil.toInt(json['id']),
        username: JsonUtil.toStr(json['username']),
        nickname: JsonUtil.toStr(json['nickname']),
        avatar: JsonUtil.toUrl(json['avatar']),
        signature: JsonUtil.toStr(json['signature']),
        gender: JsonUtil.toInt(json['gender']),
        vipLevel: JsonUtil.toInt(json['vip_level']),
        collectCount: JsonUtil.toInt(json['collect_count']),
        historyCount: JsonUtil.toInt(json['history_count']),
        playlistCount: JsonUtil.toInt(json['playlist_count']),
        listenSeconds: JsonUtil.toInt(json['listen_seconds']),
        listenSongs: JsonUtil.toInt(json['listen_songs']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'username': username,
        'nickname': nickname,
        'avatar': avatar,
        'signature': signature,
        'gender': gender,
        'vip_level': vipLevel,
      };

  String get displayName => nickname.isEmpty ? username : nickname;
}
