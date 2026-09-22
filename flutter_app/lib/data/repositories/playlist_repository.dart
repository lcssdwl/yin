import '../../config/api_config.dart';
import '../../config/constants.dart';
import '../../core/network/dio_client.dart';
import '../models/playlist.dart';
import '../models/song.dart';

/// 歌单仓储
/// hot / detail / songs 🟢 公开;my / create / addSong / removeSong / collect 🔴 需登录
class PlaylistRepository {
  final DioClient _client = DioClient.instance;

  List<Playlist> _parsePlaylists(dynamic raw) {
    if (raw is! List) return [];
    return raw
        .map((e) => Playlist.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  List<Song> _parseSongs(dynamic raw) {
    if (raw is! List) return [];
    return raw
        .map((e) => Song.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  /// 热门歌单(🟢)
  Future<List<Playlist>> getHot({int page = 1}) async {
    final data = await _client.get(Api.playlistHot, query: {
      'page': page,
      'limit': AppConstants.pageSize,
    });
    return _parsePlaylists((data as Map)['list']);
  }

  /// 歌单详情(🟢)
  Future<Playlist> getDetail(int id) async {
    final data = await _client.get(Api.playlistDetail(id));
    return Playlist.fromJson(Map<String, dynamic>.from(data as Map));
  }

  /// 歌单歌曲(🟢)
  Future<List<Song>> getSongs(int id) async {
    final data = await _client.get(Api.playlistSongs(id));
    return _parseSongs((data as Map)['list']);
  }

  /// 详情 + 歌曲(🟢,组合接口方便页面使用)
  Future<Playlist> getDetailWithSongs(int id) async {
    final detail = await getDetail(id);
    final songs = await getSongs(id);
    return Playlist(
      id: detail.id,
      name: detail.name,
      userId: detail.userId,
      cover: detail.cover,
      intro: detail.intro,
      tags: detail.tags,
      playCount: detail.playCount,
      songCount: songs.length,
      collectCount: detail.collectCount,
      isOfficial: detail.isOfficial,
      isCollected: detail.isCollected,
      createTime: detail.createTime,
      creator: detail.creator,
      songs: songs,
    );
  }

  /// 我的歌单(🔴)
  Future<List<Playlist>> getMyPlaylists() async {
    final data = await _client.get(Api.playlistMy);
    return _parsePlaylists(data);
  }

  /// 创建歌单(🔴),返回新歌单ID
  Future<int> create(String name, {String intro = '', int isPublic = 1}) async {
    final data = await _client.post(Api.playlistCreate, data: {
      'name': name,
      'intro': intro,
      'is_public': isPublic,
    });
    final map = Map<String, dynamic>.from(data as Map);
    return map['id'] is int ? map['id'] as int : int.tryParse('${map['id']}') ?? 0;
  }

  /// 添加歌曲到歌单(🔴)
  Future<void> addSong(int playlistId, int songId) async {
    await _client.post(Api.playlistAddSong, data: {
      'playlist_id': playlistId,
      'song_id': songId,
    });
  }

  /// 从歌单移除歌曲(🔴)
  Future<void> removeSong(int playlistId, int songId) async {
    await _client.post(Api.playlistRemoveSong, data: {
      'playlist_id': playlistId,
      'song_id': songId,
    });
  }

  /// 删除自己创建的歌单(🔴)
  /// 只能删自己创建的;收藏的别人的歌单后端会拒绝
  Future<void> deletePlaylist(int id) async {
    await _client.post(Api.playlistDelete, data: {'id': id});
  }

  /// 收藏 / 取消收藏歌单(🔴)
  Future<bool> collect(int id) async {
    final data = await _client.post(Api.playlistCollect, data: {'id': id});
    final map = Map<String, dynamic>.from(data as Map);
    return map['is_collected'] == true;
  }
}
