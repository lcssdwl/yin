import '../../core/utils/json_util.dart';
import '../../config/constants.dart';
import 'song.dart';

/// 歌单模型
class Playlist {
  final int id;
  final String name;
  final int userId;
  final String cover;
  final String intro;
  final String tags;
  final int playCount;
  final int songCount;
  final int collectCount;
  final bool isOfficial;
  final bool isCollected;
  final String createTime;
  final String creator;

  /// 歌曲列表(仅详情接口带 songs 时有值)
  final List<Song> songs;

  Playlist({
    required this.id,
    required this.name,
    this.userId = 0,
    this.cover = '',
    this.intro = '',
    this.tags = '',
    this.playCount = 0,
    this.songCount = 0,
    this.collectCount = 0,
    this.isOfficial = false,
    this.isCollected = false,
    this.createTime = '',
    this.creator = '',
    this.songs = const [],
  });

  factory Playlist.fromJson(Map<String, dynamic> json) {
    final list = json['list'];
    return Playlist(
      id: JsonUtil.toInt(json['id']),
      name: JsonUtil.toStr(json['name']),
      userId: JsonUtil.toInt(json['user_id']),
      cover: JsonUtil.toUrl(json['cover']),
      intro: JsonUtil.toStr(json['intro']),
      tags: JsonUtil.toStr(json['tags']),
      playCount: JsonUtil.toInt(json['play_count']),
      songCount: JsonUtil.toInt(json['song_count']),
      collectCount: JsonUtil.toInt(json['collect_count']),
      isOfficial: JsonUtil.toBool(json['is_official']),
      isCollected: JsonUtil.toBool(json['is_collected']),
      createTime: JsonUtil.toStr(json['create_time']),
      creator: JsonUtil.toStr(json['creator']),
      songs: list is List
          ? list
              .map((e) => Song.fromJson(Map<String, dynamic>.from(e as Map)))
              .toList()
          : const [],
    );
  }

  String get coverUrl => cover.isEmpty ? AppConstants.defaultCover : cover;

  List<String> get tagList =>
      tags.isEmpty ? [] : tags.split(',').where((e) => e.isNotEmpty).toList();
}
