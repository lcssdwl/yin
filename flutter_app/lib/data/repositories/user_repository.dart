import '../../config/api_config.dart';
import '../../config/constants.dart';
import '../../core/network/dio_client.dart';
import '../../core/storage/storage_service.dart';
import '../models/playlist.dart';
import '../models/song.dart';
import '../models/user.dart';

/// 登录结果
class LoginResult {
  final String token;
  final UserModel user;

  LoginResult({required this.token, required this.user});
}

/// 用户仓储
/// login / register 🟢 公开;其余 🔴 需登录
class UserRepository {
  final DioClient _client = DioClient.instance;

  LoginResult _toLoginResult(dynamic data) {
    final map = Map<String, dynamic>.from(data as Map);
    return LoginResult(
      token: (map['token'] ?? '').toString(),
      user: UserModel.fromJson(
        Map<String, dynamic>.from(map['user'] as Map? ?? {}),
      ),
    );
  }

  /// 登录(请求体由 DioClient 统一加密)
  Future<LoginResult> login(String username, String password) async {
    final data = await _client.post(Api.userLogin, data: {
      'username': username,
      'password': password,
      'platform': 'android',
    });
    return _toLoginResult(data);
  }

  /// 注册(请求体由 DioClient 统一加密)
  Future<LoginResult> register(
    String username,
    String password, {
    String? nickname,
  }) async {
    final data = await _client.post(Api.userRegister, data: {
      'username': username,
      'password': password,
      if (nickname != null) 'nickname': nickname,
      'platform': 'android',
    });
    return _toLoginResult(data);
  }

  Future<void> logout() async {
    try {
      await _client.post(Api.userLogout);
    } catch (_) {
      // 忽略
    }
  }

  /// 当前用户信息
  Future<UserModel> getInfo() async {
    final data = await _client.get(Api.userInfo);
    return UserModel.fromJson(Map<String, dynamic>.from(data as Map));
  }

  /// 修改资料
  Future<UserModel> updateInfo({
    String? nickname,
    String? avatar,
    String? signature,
    int? gender,
  }) async {
    final payload = <String, dynamic>{
      if (nickname != null) 'nickname': nickname,
      if (avatar != null) 'avatar': avatar,
      if (signature != null) 'signature': signature,
      if (gender != null) 'gender': gender,
    };
    final data = await _client.post(Api.userUpdate, data: payload);
    return UserModel.fromJson(Map<String, dynamic>.from(data as Map));
  }

  /// 修改密码(🔴,请求体由 DioClient 统一加密)
  /// 成功后服务端会清空所有会话,需重新登录
  Future<void> changePassword(String oldPassword, String newPassword) async {
    await _client.post(Api.userPassword, data: {
      'old_password': oldPassword,
      'new_password': newPassword,
    });
  }

  /// 收藏 / 取消收藏歌曲(🔴)
  /// 返回最新的收藏状态
  Future<bool> collectSong(int songId) async {
    final data = await _client.post(Api.songCollect, data: {'id': songId});
    final map = Map<String, dynamic>.from(data as Map);
    return map['is_collected'] == true;
  }

  /// 游客数据合并到云端(🔴,登录后调用一次)
  Future<bool> syncGuestData() async {
    final favorites = StorageService.localFavorites;
    final history = StorageService.localHistory;
    final playlists = StorageService.localPlaylists;

    if (favorites.isEmpty && history.isEmpty && playlists.isEmpty) {
      return true;
    }

    final payload = <String, dynamic>{
      'favorites': favorites,
      'history': history.map((e) => {
            'song_id': e['songId'],
            'play_time': _formatPlayTime(e['playTime']),
          }).toList(),
      'playlists': playlists.map((e) => {
            'name': e['name'],
            'songs': List<int>.from(e['songs'] as List),
          }).toList(),
    };

    try {
      await _client.post(Api.userSync, data: payload);
      // 注意:合并后**不再清空本地游客数据**。
      // 本地数据保留作为离线兜底:登录后用云端、退出后用本地;
      // 重复条目由后端 /user/sync 去重,前端无需操心。
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 我的收藏(🔴)
  Future<List<Song>> getMyCollects({int type = 1, int page = 1}) async {
    final data = await _client.get(Api.userCollects, query: {
      'type': type,
      'page': page,
      'limit': AppConstants.pageSize,
    });
    final list = (data as Map)['list'];
    if (list is! List) return [];
    if (type == TargetType.playlist) {
      return []; // 歌单收藏用 getMyCollectedPlaylists
    }
    return list
        .map((e) => Song.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  /// 我收藏的歌单(🔴)
  Future<List<Playlist>> getMyCollectedPlaylists({int page = 1}) async {
    final data = await _client.get(Api.userCollects, query: {
      'type': TargetType.playlist,
      'page': page,
      'limit': AppConstants.pageSize,
    });
    final list = (data as Map)['list'];
    if (list is! List) return [];
    return list
        .map((e) => Playlist.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  /// 清空播放历史(🔴)
  ///
  /// 只清历史记录,不影响累计听歌时长 / 听过多少首(服务端分开存)。
  Future<void> clearHistory() async {
    await _client.post(Api.userHistoryClear);
  }

  /// 播放历史(🔴)
  Future<List<Song>> getHistory({int page = 1}) async {
    final data = await _client.get(Api.userHistory, query: {
      'page': page,
      'limit': AppConstants.pageSize,
    });
    final list = (data as Map)['list'];
    if (list is! List) return [];
    return list
        .map((e) => Song.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  /// ISO8601 → Y-m-d H:i:s(后端存储格式)
  String _formatPlayTime(dynamic value) {
    try {
      final dt = DateTime.parse(value.toString()).toLocal();
      String two(int v) => v.toString().padLeft(2, '0');
      return '${dt.year}-${two(dt.month)}-${two(dt.day)} '
          '${two(dt.hour)}:${two(dt.minute)}:${two(dt.second)}';
    } catch (_) {
      return DateTime.now().toString().substring(0, 19);
    }
  }
}
