import '../../config/api_config.dart';
import '../../config/constants.dart';
import '../../core/network/dio_client.dart';
import '../models/album.dart';
import '../models/app_config.dart';
import '../models/home_models.dart';
import '../models/playlist.dart';
import '../models/search_result.dart';
import '../models/singer.dart';
import '../models/song.dart';

/// 内容浏览仓储(首页 / 歌曲 / 歌手 / 榜单 / 搜索)
/// 这些接口全部 🟢 公开,游客可直接调用
class MusicRepository {
  final DioClient _client = DioClient.instance;

  List<T> _parseList<T>(
    dynamic raw,
    T Function(Map<String, dynamic>) parser,
  ) {
    if (raw is! List) return <T>[];
    return raw
        .map((e) => parser(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  // ==================== 首页 ====================

  Future<HomeData> getHomeData() async {
    final data = await _client.get(Api.homeIndex);
    return HomeData.fromJson(Map<String, dynamic>.from(data as Map));
  }

  Future<List<Song>> getRecommend({int page = 1}) async {
    final data = await _client.get(Api.homeRecommend, query: {
      'page': page,
      'limit': AppConstants.pageSize,
    });
    return _parseList((data as Map)['list'], Song.fromJson);
  }

  Future<List<Song>> getNewest({int page = 1}) async {
    final data = await _client.get(Api.homeNewest, query: {
      'page': page,
      'limit': AppConstants.pageSize,
    });
    return _parseList((data as Map)['list'], Song.fromJson);
  }

  // ==================== 歌曲 ====================

  Future<Song> getSongDetail(int id) async {
    final data = await _client.get(Api.songDetail(id));
    return Song.fromJson(Map<String, dynamic>.from(data as Map));
  }

  /// 获取播放地址(按音质)
  ///
  /// 同时返回该音质音频的 MD5,供客户端缓存落盘后校验完整性。
  Future<SongUrl> getSongUrl(int id, {String quality = '128'}) async {
    final data = await _client.get(Api.songUrl, query: {
      'id': id,
      'quality': quality,
    });
    final map = Map<String, dynamic>.from(data as Map);
    return SongUrl(
      url: (map['url'] ?? '').toString(),
      md5: (map['md5'] ?? '').toString(),
      quality: (map['quality'] ?? quality).toString(),
      actualQuality: (map['actual_quality'] ?? '').toString(),
      fallback: map['fallback'] == true,
    );
  }

  Future<String> getLyric(int id) async {
    final data = await _client.get(Api.songLyric, query: {'id': id});
    final map = Map<String, dynamic>.from(data as Map);
    return (map['lyric'] ?? '').toString();
  }

  /// 上报播放(游客也调用,后端仅计数)
  ///
  /// [duration] 是客户端解析出的真实时长(秒):
  /// 后端只在库里缺失时补写,避免列表一直显示 00:00。
  Future<void> reportPlay(int id, {int duration = 0}) async {
    try {
      await _client.post(
        Api.songPlay(id),
        data: duration > 0 ? {'duration': duration} : <String, dynamic>{},
      );
    } catch (_) {
      // 上报失败不影响播放
    }
  }

  Future<List<Song>> getSimilarSongs(int id, {int limit = 10}) async {
    final data = await _client.get(Api.songSimilar, query: {
      'id': id,
      'limit': limit,
    });
    return _parseList(data, Song.fromJson);
  }

  /// 批量歌曲详情
  Future<List<Song>> getBatchSongs(List<int> ids) async {
    if (ids.isEmpty) return [];
    final data = await _client.get(Api.songBatch, query: {
      'ids': ids.join(','),
    });
    return _parseList(data, Song.fromJson);
  }

  // ==================== 歌手 ====================

  Future<List<Singer>> getSingers({
    String? area,
    String? initial,
    int page = 1,
  }) async {
    final query = <String, dynamic>{
      'page': page,
      'limit': AppConstants.pageSize,
    };
    if (area != null && area.isNotEmpty) query['area'] = area;
    if (initial != null && initial.isNotEmpty) query['initial'] = initial;

    final data = await _client.get(Api.singerList, query: query);
    return _parseList((data as Map)['list'], Singer.fromJson);
  }

  Future<Singer> getSingerDetail(int id) async {
    final data = await _client.get(Api.singerDetail(id));
    return Singer.fromJson(Map<String, dynamic>.from(data as Map));
  }

  Future<List<Song>> getSingerSongs(int id, {int page = 1}) async {
    final data = await _client.get(Api.singerSongs(id), query: {
      'page': page,
      'limit': AppConstants.pageSize,
    });
    return _parseList((data as Map)['list'], Song.fromJson);
  }

  Future<List<Album>> getSingerAlbums(int id) async {
    final data = await _client.get(Api.singerAlbums(id));
    return _parseList((data as Map)['list'], Album.fromJson);
  }

  // ==================== 专辑 ====================

  Future<Album> getAlbumDetail(int id) async {
    final data = await _client.get(Api.albumDetail(id));
    return Album.fromJson(Map<String, dynamic>.from(data as Map));
  }

  Future<List<Song>> getAlbumSongs(int id) async {
    final data = await _client.get(Api.albumSongs(id));
    return _parseList((data as Map)['list'], Song.fromJson);
  }

  // ==================== 榜单 ====================

  Future<List<RankItem>> getRankList() async {
    final data = await _client.get(Api.rankList);
    return _parseList(data, RankItem.fromJson);
  }

  /// 榜单详情(返回 榜单信息 + 歌曲列表)
  Future<Map<String, dynamic>> getRankSongs(int id, {int limit = 50}) async {
    final data = await _client.get(Api.rankSongs(id), query: {'limit': limit});
    final map = Map<String, dynamic>.from(data as Map);
    final rankRaw = map['rank'];
    return {
      'rank': rankRaw is Map
          ? RankItem.fromJson(Map<String, dynamic>.from(rankRaw))
          : RankItem(id: id, name: ''),
      'songs': _parseList(map['list'], Song.fromJson),
    };
  }

  // ==================== 搜索 ====================

  Future<SearchResult> search(String keyword, {int type = 0}) async {
    final data = await _client.get(Api.search, query: {
      'keyword': keyword,
      'type': type,
    });
    final map = Map<String, dynamic>.from(data as Map);

    return SearchResult(
      songs: _parseList(map['song'], Song.fromJson),
      singers: _parseList(map['singer'], Singer.fromJson),
      albums: _parseList(map['album'], Album.fromJson),
      playlists: _parseList(map['playlist'], (e) => Playlist.fromJson(e)),
    );
  }

  Future<List<String>> getHotWords() async {
    final data = await _client.get(Api.searchHot);
    if (data is! List) return [];
    return data.map((e) => e.toString()).toList();
  }

  Future<List<String>> getSuggest(String keyword) async {
    final data = await _client.get(Api.searchSuggest, query: {
      'keyword': keyword,
    });
    if (data is! List) return [];
    return data.map((e) => e.toString()).toList();
  }

  // ==================== 分类 ====================

  /// 某个分类下的歌曲(发现页点分类进来)
  ///
  /// 分类体系由后台「分类管理」维护(豆瓣 → 关键词 → 兜底三级自动归类)。
  ///
  /// 一个分类动辄几十上百首,所以这里**把分页全部拉完**再返回:
  /// 后端是按 `page` / `limit` 分页的,只请求第 1 页的话,
  /// 92 首的分类列表里也只会显示 20 条。
  Future<List<Song>> getGenreSongs(
    int genreId, {
    int pageSize = 100, // 单页取大一点,减少请求次数
    int maxSongs = 1000, // 兜底上限,防异常数据撑爆内存
  }) async {
    final songs = <Song>[];
    var page = 1;

    while (songs.length < maxSongs) {
      final data = await _client.get(
        '${ApiConfig.apiPrefix}/genre/$genreId/songs',
        query: {'page': page, 'limit': pageSize},
      );
      final map = data as Map;
      final list = map['list'];
      if (list is! List || list.isEmpty) break;

      songs.addAll(
        list.map((e) => Song.fromJson(Map<String, dynamic>.from(e as Map))),
      );

      final total = (map['total'] as num?)?.toInt() ?? 0;
      // 不足一页 = 已经是最后一页;拿得到 total 时以它为准
      if (list.length < pageSize) break;
      if (total > 0 && songs.length >= total) break;

      page++;
      if (page > 20) break; // 安全阀
    }

    return songs;
  }

  // ==================== 听歌时长 ====================

  /// 上报「这首歌实际听了多少秒」(🔴 需登录)
  ///
  /// 只报增量;服务端还会按真实流逝时间限频,报多了也不会多算。
  Future<void> reportListen(int songId, int seconds) async {
    if (songId <= 0 || seconds <= 0) return;
    await _client.post(Api.songListen, data: {
      'song_id': songId,
      'seconds': seconds,
    });
  }

  // ==================== App 基础配置 ====================

  /// 拉取后台基础配置(音质列表 + 各音质是否需要登录)
  Future<AppConfig> getAppConfig() async {
    final data = await _client.get(Api.appConfig);
    return AppConfig.fromJson(Map<String, dynamic>.from(data as Map));
  }
}
