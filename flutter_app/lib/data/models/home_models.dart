import '../../core/utils/json_util.dart';
import 'playlist.dart';
import 'song.dart';

/// 首页 Banner
class BannerItem {
  final int id;
  final String title;
  final String image;
  final int targetType;
  final int targetId;
  final String url;

  BannerItem({
    required this.id,
    this.title = '',
    this.image = '',
    this.targetType = 0,
    this.targetId = 0,
    this.url = '',
  });

  factory BannerItem.fromJson(Map<String, dynamic> json) => BannerItem(
        id: JsonUtil.toInt(json['id']),
        title: JsonUtil.toStr(json['title']),
        image: JsonUtil.toUrl(json['image']),
        targetType: JsonUtil.toInt(json['target_type']),
        targetId: JsonUtil.toInt(json['target_id']),
        url: JsonUtil.toStr(json['url']),
      );
}

/// 榜单
class RankItem {
  final int id;
  final String name;
  final String cover;
  final String intro;
  final int type;
  final String updateCycle;
  final List<String> top;

  RankItem({
    required this.id,
    required this.name,
    this.cover = '',
    this.intro = '',
    this.type = 1,
    this.updateCycle = '',
    this.top = const [],
  });

  factory RankItem.fromJson(Map<String, dynamic> json) {
    final top = json['top'];
    return RankItem(
      id: JsonUtil.toInt(json['id']),
      name: JsonUtil.toStr(json['name']),
      cover: JsonUtil.toUrl(json['cover']),
      intro: JsonUtil.toStr(json['intro']),
      type: JsonUtil.toInt(json['type']),
      updateCycle: JsonUtil.toStr(json['update_cycle']),
      top: top is List ? top.map((e) => e.toString()).toList() : const [],
    );
  }
}

/// 分类(后端「分类管理」里的一个分类)
class GenreItem {
  final int id;
  final String name;
  final String icon;

  /// 该分类下的歌曲数(已上架且在库里的)
  final int songCount;

  GenreItem({
    required this.id,
    this.name = '',
    this.icon = '',
    this.songCount = 0,
  });

  factory GenreItem.fromJson(Map<String, dynamic> json) => GenreItem(
        id: JsonUtil.toInt(json['id']),
        name: JsonUtil.toStr(json['name']),
        icon: JsonUtil.toUrl(json['icon']),
        songCount: JsonUtil.toInt(json['song_count']),
      );
}

/// 首页聚合数据
class HomeData {
  final List<BannerItem> banner;
  final List<Playlist> hotPlaylist;
  final List<RankItem> rank;
  final List<Song> recommend;
  final List<Song> newSong;

  /// 分类(带歌曲数,发现页分类区块用)
  final List<GenreItem> genres;

  HomeData({
    this.banner = const [],
    this.hotPlaylist = const [],
    this.rank = const [],
    this.recommend = const [],
    this.newSong = const [],
    this.genres = const [],
  });

  factory HomeData.fromJson(Map<String, dynamic> json) {
    List<T> parseList<T>(
      dynamic raw,
      T Function(Map<String, dynamic>) parser,
    ) {
      if (raw is! List) return <T>[];
      return raw
          .map((e) => parser(Map<String, dynamic>.from(e as Map)))
          .toList();
    }

    final genres = parseList(json['genre'], GenreItem.fromJson);

    // 优先只展示「有歌」的分类(空的点进去就是空列表,没必要占位置);
    // 但如果一个都没有歌(后台还没跑「一键分类」),仍然把分类返回出去 ——
    // 否则发现页整块「分类」会凭空消失,用户只会以为功能没生效。
    final withSongs = genres.where((g) => g.songCount > 0).toList();

    return HomeData(
      banner: parseList(json['banner'], BannerItem.fromJson),
      hotPlaylist: parseList(json['hot_playlist'], Playlist.fromJson),
      rank: parseList(json['rank'], RankItem.fromJson),
      recommend: parseList(json['recommend'], Song.fromJson),
      newSong: parseList(json['new_song'], Song.fromJson),
      genres: withSongs.isNotEmpty ? withSongs : genres,
    );
  }
}
