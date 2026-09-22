import '../../core/utils/json_util.dart';
import 'song.dart';

/// 歌手模型
class Singer {
  final int id;
  final String name;
  final String avatar;
  final String cover;
  final String area;
  final String initial;
  final int songCount;
  final int albumCount;
  final int fansCount;
  final String intro;
  final bool isFollowed;
  final List<Song> hotSongs;

  Singer({
    required this.id,
    required this.name,
    this.avatar = '',
    this.cover = '',
    this.area = '',
    this.initial = '',
    this.songCount = 0,
    this.albumCount = 0,
    this.fansCount = 0,
    this.intro = '',
    this.isFollowed = false,
    this.hotSongs = const [],
  });

  factory Singer.fromJson(Map<String, dynamic> json) {
    final hot = json['hot_songs'];
    return Singer(
      id: JsonUtil.toInt(json['id']),
      name: JsonUtil.toStr(json['name']),
      avatar: JsonUtil.toUrl(json['avatar']),
      cover: JsonUtil.toUrl(json['cover']),
      area: JsonUtil.toStr(json['area']),
      initial: JsonUtil.toStr(json['initial']),
      songCount: JsonUtil.toInt(json['song_count']),
      albumCount: JsonUtil.toInt(json['album_count']),
      fansCount: JsonUtil.toInt(json['fans_count']),
      intro: JsonUtil.toStr(json['intro']),
      isFollowed: JsonUtil.toBool(json['is_followed']),
      hotSongs: hot is List
          ? hot
              .map((e) => Song.fromJson(Map<String, dynamic>.from(e as Map)))
              .toList()
          : const [],
    );
  }
}
