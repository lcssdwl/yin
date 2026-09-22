import '../../core/utils/json_util.dart';

/// 专辑模型
class Album {
  final int id;
  final String name;
  final int singerId;
  final String singerName;
  final String cover;
  final String intro;
  final int songCount;
  final String publishDate;

  Album({
    required this.id,
    required this.name,
    this.singerId = 0,
    this.singerName = '',
    this.cover = '',
    this.intro = '',
    this.songCount = 0,
    this.publishDate = '',
  });

  factory Album.fromJson(Map<String, dynamic> json) => Album(
        id: JsonUtil.toInt(json['id']),
        name: JsonUtil.toStr(json['name']),
        singerId: JsonUtil.toInt(json['singer_id']),
        singerName: JsonUtil.toStr(json['singer_name']),
        cover: JsonUtil.toUrl(json['cover']),
        intro: JsonUtil.toStr(json['intro']),
        songCount: JsonUtil.toInt(json['song_count']),
        publishDate: JsonUtil.toStr(json['publish_date']),
      );
}
