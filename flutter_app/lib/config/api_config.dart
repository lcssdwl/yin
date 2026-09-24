import '../core/storage/storage_service.dart';

/// 后端接口配置
///
/// # baseUrl 怎么改
///
/// 地址完全可运行时配置,不再依赖 url.txt 文件:
///  - 首次启动会进入「设置服务器地址」页引导填写(默认填开发者示例地址)
///  - 「我的设置 → 服务器地址」可随时再次修改
///
/// 取值规则:有本地保存的地址就用它,否则用开发者示例地址 [developerExampleUrl]。
class ApiConfig {
  ApiConfig._();

  /// 开发者示例后端地址(首次启动默认填入,可在「我的设置」里修改)
  static const String developerExampleUrl = 'http://120.55.41.66:8000';

  /// 运行时实际生效的后端地址,由 [loadBaseUrl] 在启动时填充。
  static String baseUrl = developerExampleUrl;

  static const String apiPrefix = '/api/v1';

  /// 启动时加载后端地址,**必须在 DioClient.init() 之前调用**。
  static Future<void> loadBaseUrl() async {
    // 本地持久化地址(用户在「设置地址」页填写)优先
    final saved = StorageService.baseUrl;
    if (saved != null && saved.isNotEmpty) {
      baseUrl = saved;
      print('[api] baseUrl 来自本地存储: $baseUrl');
      return;
    }

    // 兜底:开发者示例地址
    baseUrl = developerExampleUrl;
    print('[api] baseUrl 使用示例地址: $baseUrl');
  }

  /// 是否已由用户配置过后端地址(用于首次启动引导判断)
  static bool get isConfigured {
    final saved = StorageService.baseUrl;
    return saved != null && saved.isNotEmpty;
  }

  static const Duration connectTimeout = Duration(seconds: 15);
  static const Duration receiveTimeout = Duration(seconds: 20);
  static const Duration sendTimeout = Duration(seconds: 15);
}

/// 接口路径
class Api {
  Api._();

  // 首页
  static const String homeIndex = '${ApiConfig.apiPrefix}/home/index';
  static const String homeBanner = '${ApiConfig.apiPrefix}/home/banner';
  static const String homeRecommend = '${ApiConfig.apiPrefix}/home/recommend';
  static const String homeNewest = '${ApiConfig.apiPrefix}/home/newest';
  static const String homeGenre = '${ApiConfig.apiPrefix}/home/genre';

  // 搜索
  static const String search = '${ApiConfig.apiPrefix}/search';
  static const String searchHot = '${ApiConfig.apiPrefix}/search/hot';
  static const String searchSuggest = '${ApiConfig.apiPrefix}/search/suggest';

  // 歌曲
  static String songDetail(int id) => '${ApiConfig.apiPrefix}/song/$id';
  static const String songUrl = '${ApiConfig.apiPrefix}/song/url';
  static const String songLyric = '${ApiConfig.apiPrefix}/song/lyric';
  static const String songSimilar = '${ApiConfig.apiPrefix}/song/similar';
  static const String songBatch = '${ApiConfig.apiPrefix}/song/batch';
  static String songPlay(int id) => '${ApiConfig.apiPrefix}/song/play/$id';
  static const String songCollect = '${ApiConfig.apiPrefix}/song/collect';

  // 榜单
  static const String rankList = '${ApiConfig.apiPrefix}/rank/list';
  static String rankSongs(int id) => '${ApiConfig.apiPrefix}/rank/$id/songs';

  // 歌手
  static const String singerList = '${ApiConfig.apiPrefix}/singer/list';
  static String singerDetail(int id) => '${ApiConfig.apiPrefix}/singer/$id';
  static String singerSongs(int id) =>
      '${ApiConfig.apiPrefix}/singer/$id/songs';
  static String singerAlbums(int id) =>
      '${ApiConfig.apiPrefix}/singer/$id/albums';

  // 专辑
  static String albumDetail(int id) => '${ApiConfig.apiPrefix}/album/$id';
  static String albumSongs(int id) => '${ApiConfig.apiPrefix}/album/$id/songs';

  // 歌单
  static const String playlistHot = '${ApiConfig.apiPrefix}/playlist/hot';
  static const String playlistMy = '${ApiConfig.apiPrefix}/playlist/my';
  static const String playlistCreate = '${ApiConfig.apiPrefix}/playlist/create';
  static const String playlistAddSong =
      '${ApiConfig.apiPrefix}/playlist/addSong';
  static const String playlistRemoveSong =
      '${ApiConfig.apiPrefix}/playlist/removeSong';
  static const String playlistCollect =
      '${ApiConfig.apiPrefix}/playlist/collect';
  static const String playlistDelete = '${ApiConfig.apiPrefix}/playlist/delete';
  static String playlistDetail(int id) => '${ApiConfig.apiPrefix}/playlist/$id';
  static String playlistSongs(int id) =>
      '${ApiConfig.apiPrefix}/playlist/$id/songs';

  // 评论
  static const String commentList = '${ApiConfig.apiPrefix}/comment/list';
  static const String commentAdd = '${ApiConfig.apiPrefix}/comment/add';
  static const String commentLike = '${ApiConfig.apiPrefix}/comment/like';

  // 用户
  static const String userRegister = '${ApiConfig.apiPrefix}/user/register';
  static const String userLogin = '${ApiConfig.apiPrefix}/user/login';
  static const String userLogout = '${ApiConfig.apiPrefix}/user/logout';
  static const String userInfo = '${ApiConfig.apiPrefix}/user/info';
  static const String userUpdate = '${ApiConfig.apiPrefix}/user/update';
  static const String userPassword = '${ApiConfig.apiPrefix}/user/password';
  static const String userSync = '${ApiConfig.apiPrefix}/user/sync';
  static const String userCollects = '${ApiConfig.apiPrefix}/user/collects';
  static const String userHistory = '${ApiConfig.apiPrefix}/user/history';
  static const String userHistoryClear =
      '${ApiConfig.apiPrefix}/user/history/clear';

  // 听歌时长上报(切歌 / 暂停 / 退后台时报增量秒数)
  static const String songListen = '${ApiConfig.apiPrefix}/song/listen';

  // App 基础配置(音质列表 + 各音质是否需要登录)
  static const String appConfig = '${ApiConfig.apiPrefix}/app/config';

  // App 使用统计:上报(打开 / 使用心跳)+ 读取(在线 / 客户端数)
  static const String appReport = '${ApiConfig.apiPrefix}/app/report';
  static const String appStats = '${ApiConfig.apiPrefix}/app/stats';

  // 健康检查
  static const String ping = '${ApiConfig.apiPrefix}/ping';
}
