import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../../config/constants.dart';
import '../../config/theme.dart';
import '../../core/audio/audio_cache.dart';
import '../../core/audio/audio_service_status.dart';
import '../../core/storage/storage_service.dart';
import '../../core/utils/duration_text.dart';
import '../../core/utils/error_text.dart';
import '../../core/utils/json_util.dart';
import '../../data/models/playlist.dart';
import '../../data/models/song.dart';
import '../../data/models/user.dart';
import '../../data/repositories/music_repository.dart';
import '../../data/repositories/playlist_repository.dart';
import '../../data/repositories/user_repository.dart';
import '../../providers/auth_provider.dart';
import '../../providers/player_provider.dart';
import '../../providers/theme_provider.dart';
import '../../widgets/center_toast.dart';
import '../../widgets/gradient_icon_tile.dart';
import '../common/song_list_page.dart';
import '../login/login_page.dart';
import '../playlist/my_playlists_page.dart';
import '../playlist/playlist_detail_page.dart';
import '../profile/about_page.dart';
import '../profile/change_password_page.dart';
import '../profile/log_page.dart';

/// 「我的」页
///
/// 游客态:展示本地收藏/历史/歌单 + 登录引导
/// 登录态:展示云端收藏/历史/歌单
class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key});

  @override
  State<LibraryPage> createState() => LibraryPageState();
}

class LibraryPageState extends State<LibraryPage> {
  /// 我创建的歌单 / 我收藏的歌单(在「我的」页直接展示)
  List<Playlist> _createdPlaylists = [];
  List<Playlist> _collectedPlaylists = [];
  bool _loadingPlaylists = false;
  bool? _lastLoggedIn;

  /// 音频缓存统计
  String _cacheText = '统计中…';
  int _cacheBytes = 0;
  int _cacheCount = 0;

  @override
  void initState() {
    super.initState();
    // 本页在 IndexedStack 里常驻,切 tab 不会重建 ——
    // 监听缓存变更,播歌存下缓存后统计能立刻刷新,而不是一直停在「暂无缓存」
    AudioCache.cacheVersion.addListener(_onCacheChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadPlaylists();
      _loadCacheStat();
      _refreshUserInfo();
    });
  }

  @override
  void dispose() {
    AudioCache.cacheVersion.removeListener(_onCacheChanged);
    super.dispose();
  }

  /// 缓存写入 / 清空后刷新统计
  void _onCacheChanged() {
    if (!mounted) return;
    _loadCacheStat();
  }

  void _updateCacheText() {
    _cacheText = _cacheCount == 0
        ? '暂无缓存'
        : '$_cacheCount 首 · ${_fmtSize(_cacheBytes)}';
  }

  /// 外部(底部导航切到「我的」时)触发的刷新
  Future<void> refresh() async {
    await _loadPlaylists();
    await _refreshUserInfo();
  }

  /// 刷新用户资料
  ///
  /// 听歌时长 / 听过多少首 / 收藏数都在服务端,回到本页要重新取一次;
  /// 这里用非静默刷新,拿到新数字后卡片会立刻重建。
  Future<void> _refreshUserInfo() async {
    if (!mounted) return;
    final auth = context.read<AuthProvider>();
    if (!auth.isLoggedIn) return;
    await auth.refreshInfo();
  }

  /// 拉取「我创建的」+「我收藏的」歌单
  Future<void> _loadPlaylists() async {
    final auth = context.read<AuthProvider>();

    if (!auth.isLoggedIn) {
      if (!mounted) return;
      setState(() {
        _createdPlaylists = [];
        _collectedPlaylists = [];
        _loadingPlaylists = false;
      });
      return;
    }

    // 首次加载(还没有任何数据)才显示 loading 转圈;
    // 已有数据时静默刷新 —— 有新增歌单就更新,没变化/失败都不动,避免闪烁。
    final firstLoad = _createdPlaylists.isEmpty && _collectedPlaylists.isEmpty;
    if (!mounted) return;
    if (firstLoad) setState(() => _loadingPlaylists = true);

    try {
      final res = await Future.wait([
        PlaylistRepository().getMyPlaylists(),
        UserRepository().getMyCollectedPlaylists(),
      ]);
      if (!mounted) return;
      setState(() {
        _createdPlaylists = res[0];
        _collectedPlaylists = res[1];
        _loadingPlaylists = false;
      });
    } catch (_) {
      if (!mounted) return;
      // 刷新失败:保留已有数据,不要清空(清空会导致列表闪没)
      if (firstLoad) setState(() => _loadingPlaylists = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final theme = Theme.of(context);

    // 登录态变化(登录/退出)后重新拉取歌单
    if (_lastLoggedIn != auth.isLoggedIn) {
      _lastLoggedIn = auth.isLoggedIn;
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadPlaylists());
    }

    return Scaffold(
      appBar: AppBar(title: const Text('我的')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 20),
        cacheExtent: 1600,
        children: [
          auth.isLoggedIn ? _buildUserCard(context) : _buildGuestCard(context),
          const SizedBox(height: 12),

          // ===== 我的歌单(直接内嵌展示,无需点进二级页) =====
          if (auth.isLoggedIn) ...[
            _playlistSection(
              context,
              title: '我创建的歌单',
              list: _createdPlaylists,
              isCreated: true,
              withFavorites: true, // 首位固定为「默认收藏」
            ),
            _playlistSection(
              context,
              title: '我收藏的歌单',
              list: _collectedPlaylists,
              isCreated: false,
            ),
          ] else ...[
            _guestPlaylistEntry(context),
          ],

          const Divider(height: 24),

          // 默认收藏(仅游客:免登录可收藏,登录后并入云端,故不显示)
          if (!auth.isLoggedIn)
            _buildTile(
              context,
              icon: Icons.favorite_outline,
              iconColor: AppTheme.paletteAt(1),
              title: '默认收藏',
              subtitle: '本地收藏 ${StorageService.localFavorites.length} 首',
              onTap: () => _openFavorites(context),
            ),

          // 播放历史
          _buildTile(
            context,
            icon: Icons.history,
            iconColor: AppTheme.paletteAt(0),
            title: '播放历史',
            subtitle: auth.isLoggedIn ? '云端记录' : '本地记录',
            onTap: () => _openHistory(context),
          ),

          // 播放缓存(边播边存,二次播放秒开)
          _buildTile(
            context,
            icon: Icons.cleaning_services_outlined,
            iconColor: AppTheme.paletteAt(2),
            title: '播放缓存',
            subtitle: _cacheText,
            onTap: () => _showCacheDialog(context),
          ),

          // 主题
          Consumer<ThemeProvider>(
            builder: (context, themeProvider, _) {
              return _buildTile(
                context,
                icon: Icons.dark_mode_outlined,
                iconColor: AppTheme.paletteAt(3),
                title: '主题模式',
                subtitle: _themeLabel(themeProvider.mode),
                onTap: () => _showThemeDialog(context),
              );
            },
          ),

          // 通知栏控制状态
          _buildTile(
            context,
            icon: Icons.notifications_none,
            iconColor: AppTheme.paletteAt(4),
            title: '通知栏控制',
            subtitle: audioServiceReady
                ? '已启用 · 播放时显示控制条'
                : '未授权通知权限',
            onTap: () => _showAudioServiceTip(context),
          ),

          // 修改密码(仅登录)
          if (auth.isLoggedIn)
            _buildTile(
              context,
              icon: Icons.lock_outline,
              iconColor: AppTheme.paletteAt(5),
              title: '修改密码',
              subtitle: '账号安全',
              onTap: () => _openChangePassword(context),
            ),

          // 运行日志(缓存 / 播放排查用)
          _buildTile(
            context,
            icon: Icons.terminal,
            iconColor: AppTheme.paletteAt(6),
            title: '运行日志',
            subtitle: '缓存 / 播放记录',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const LogPage()),
            ),
          ),

          // 关于
          _buildTile(
            context,
            icon: Icons.info_outline,
            iconColor: AppTheme.paletteAt(0),
            title: '关于 App',
            subtitle: '关于云韵音乐',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const AboutPage()),
            ),
          ),

          // 退出登录
          if (auth.isLoggedIn)
            _buildTile(
              context,
              icon: Icons.logout,
              title: '退出登录',
              subtitle: '',
              iconColor: Colors.redAccent,
              onTap: () => _confirmLogout(context),
            ),

          const SizedBox(height: 16),
          Center(
            child: Text(
              auth.isLoggedIn ? '' : '免登录也能听歌,登录仅用于云同步',
              style: TextStyle(fontSize: 12, color: theme.hintColor),
            ),
          ),
        ],
      ),
    );
  }

  // ==================== 顶部卡片 ====================

  /// 顶部卡片外壳(游客卡 / 用户卡共用)
  ///
  /// 亮色:整块彩色渐变,和 App 主视觉一致;
  /// 深色:改成**黑底 + 一圈彩色描边** ——
  /// 整块大渐变在深色下太刺眼,留一道彩色边框同样有多彩的品牌感。
  Widget _topCardShell(BuildContext context, {required Widget child}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const radius = 16.0;
    const border = 1.2;

    if (!isDark) {
      return Container(
        margin: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: AppTheme.primaryGradient,
          borderRadius: BorderRadius.circular(radius),
          boxShadow: const [
            BoxShadow(
              color: Colors.black12,
              blurRadius: 12,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: child,
      );
    }

    // 深色:外层渐变只当"描边"用,内层铺黑底盖住中间
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(border),
      decoration: BoxDecoration(
        gradient: AppTheme.primaryGradient,
        borderRadius: BorderRadius.circular(radius + border),
      ),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(radius),
        ),
        child: child,
      ),
    );
  }

  Widget _buildGuestCard(BuildContext context) {
    return _topCardShell(
      context,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const CircleAvatar(
              radius: 32,
              backgroundColor: Colors.white24,
              child: Icon(
                Icons.person_outline,
                size: 32,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '未登录',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    '登录后可云同步收藏与歌单',
                    style: TextStyle(fontSize: 12, color: Colors.white70),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: 120,
                    height: 38,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: AppTheme.primary,
                        padding: EdgeInsets.zero,
                        textStyle: const TextStyle(fontSize: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onPressed: () => _gotoLogin(context),
                      child: const FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Padding(
                          padding: EdgeInsets.symmetric(horizontal: 10),
                          child: Text('登录 / 注册'),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUserCard(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.user;

    // 卡片外观交给 _topCardShell:亮色彩色渐变,深色黑底 + 彩色描边
    return _topCardShell(
      context,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            _Avatar(
              url: user?.avatar ?? '',
              name: user?.displayName ?? '用户',
              size: 64,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        user?.displayName ?? '用户',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      if ((user?.vipLevel ?? 0) > 0) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFFFFD700), Color(0xFFFFA000)],
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'VIP ${user!.vipLevel}',
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF5B3A00),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    user?.signature ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: Colors.white70),
                  ),
                  const SizedBox(height: 7),
                  // 听歌成绩:累计时长 + 听过多少首(不重复)
                  _listenStats(user),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 个性签名下方的听歌成绩
  ///
  /// 数据来自 /user/info(服务端按实际播放秒数累计);与播放历史解耦,
  /// 所以「清空播放历史」不会把这两个数字清零。
  Widget _listenStats(UserModel? user) {
    const style = TextStyle(fontSize: 11.5, color: Colors.white70);

    return Row(
      children: [
        const Icon(Icons.headphones, size: 13, color: Colors.white70),
        const SizedBox(width: 4),
        Text('听歌 ${listenTimeText(user?.listenSeconds ?? 0)}', style: style),
        const SizedBox(width: 12),
        const Icon(Icons.music_note, size: 13, color: Colors.white70),
        const SizedBox(width: 4),
        Text('${user?.listenSongs ?? 0} 首', style: style),
      ],
    );
  }

  // ==================== 菜单项 ====================

  Widget _buildTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    Color? iconColor,
  }) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        leading: Icon(icon, color: iconColor ?? theme.colorScheme.primary),
        title: Text(title),
        subtitle: subtitle.isEmpty ? null : Text(subtitle),
        trailing: const Icon(Icons.chevron_right, size: 20),
        onTap: onTap,
      ),
    );
  }

  // ==================== 跳转逻辑 ====================

  Future<void> _gotoLogin(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const LoginPage()),
    );
  }

  Future<void> _openFavorites(BuildContext context) async {
    final auth = context.read<AuthProvider>();
    late Future<List<Song>> future;

    if (auth.isLoggedIn) {
      future = UserRepository().getMyCollects(type: TargetType.song);
    } else {
      final ids = StorageService.localFavorites;
      future = MusicRepository().getBatchSongs(ids);
    }

    if (!context.mounted) return;
    final player = context.read<PlayerProvider>();

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SongListPage(
          title: '默认收藏',
          futureSongs: future,
          removeScene: '默认收藏',
          // 左滑移除 = 取消收藏(登录走云端 / 游客走本地)
          onRemove: (song) async {
            await player.toggleFavorite(song.id);
          },
        ),
      ),
    );
  }

  Future<void> _openHistory(BuildContext context) async {
    final auth = context.read<AuthProvider>();
    late Future<List<Song>> future;

    if (auth.isLoggedIn) {
      future = UserRepository().getHistory();
    } else {
      final ids = StorageService.localHistory
          .map((e) => e['songId'] as int)
          .toList();
      future = MusicRepository().getBatchSongs(ids);
    }

    if (!context.mounted) return;
    final loggedIn = auth.isLoggedIn;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SongListPage(
          title: '播放历史',
          futureSongs: future,
          removeScene: '播放历史',
          // 清空:登录清云端(听歌成绩不受影响),游客清本地记录
          onClearAll: () async {
            if (loggedIn) {
              await UserRepository().clearHistory();
              await auth.refreshInfo(); // 历史条数变了,顺带刷新卡片
            } else {
              await StorageService.clearLocalHistory();
            }
          },
        ),
      ),
    );
  }

  /// 我的歌单(独立页面:左右滑动切换 + 宫格封面)
  Future<void> _openMyPlaylists(BuildContext context) async {
    final auth = context.read<AuthProvider>();
    if (!auth.isLoggedIn) {
      final go = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('需要登录'),
          content: const Text('登录后可以创建歌单、收藏歌单,并支持跨设备同步。'),
          actions: [
            // 两个按钮统一成一样的胶囊形状:描边 / 填充,同高同圆角
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(72, 40),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('稍后'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                minimumSize: const Size(96, 40),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('立即登录'),
            ),
          ],
        ),
      );
      if (go == true && context.mounted) {
        await _gotoLogin(context);
      }
      return;
    }

    if (!context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const MyPlaylistsPage()),
    );
    // 从歌单页返回后刷新:期间可能新建 / 删除 / 收藏了歌单
    if (mounted) await _loadPlaylists();
  }

  // ==================== 歌单区块(横向滑动卡片) ====================

  /// 歌单横向滑动区块
  ///
  /// [withFavorites] 为 true 时,首位固定显示系统内置的「默认收藏」卡片
  /// (默认收藏不可删除,始终存在)。
  Widget _playlistSection(
    BuildContext context, {
    required String title,
    required List<Playlist> list,
    required bool isCreated,
    bool withFavorites = false,
  }) {
    final theme = Theme.of(context);
    final total = list.length + (withFavorites ? 1 : 0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 标题行
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 6, 0),
          child: Row(
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '$total',
                style: TextStyle(fontSize: 12, color: theme.hintColor),
              ),
              const Spacer(),
              if (list.length > 6)
                TextButton(
                  onPressed: () => _openMyPlaylists(context),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: const Size(0, 32),
                  ),
                  child: const Text('全部', style: TextStyle(fontSize: 12)),
                ),
              IconButton(
                iconSize: 20,
                tooltip: isCreated ? '新建歌单' : '查看全部',
                icon: Icon(isCreated ? Icons.add : Icons.chevron_right),
                onPressed: () => _openMyPlaylists(context),
              ),
            ],
          ),
        ),

        // 内容
        if (_loadingPlaylists)
          const SizedBox(
            height: 130,
            child: Center(child: CircularProgressIndicator()),
          )
        else if (list.isEmpty && !withFavorites)
          _emptyPlaylistHint(
            context,
            isCreated
                ? '还没有创建歌单,点右上角 + 新建一个'
                : '还没有收藏歌单,去歌单广场逛逛吧',
          )
        else
          SizedBox(
            height: 144,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              scrollDirection: Axis.horizontal,
              itemCount: total,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, i) {
                // 首位:系统内置「默认收藏」
                if (withFavorites && i == 0) {
                  return _favoritesCard(context);
                }
                final index = withFavorites ? i - 1 : i;
                return _playlistCard(
                  context,
                  list[index],
                  isCreated: isCreated,
                );
              },
            ),
          ),
      ],
    );
  }

  /// 系统内置「默认收藏」卡片(不可删除)
  Widget _favoritesCard(BuildContext context) {
    return GestureDetector(
      onTap: () => _openFavorites(context),
      child: SizedBox(
        width: 106,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 封面色块:亮色渐变 / 深色黑底 + 彩色描边(见 GradientIconTile)
            const SizedBox(
              width: 106,
              height: 106,
              child: GradientIconTile(icon: Icons.favorite, radius: 10),
            ),
            const SizedBox(height: 6),
            const Text(
              '默认收藏',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }

  /// 打开歌单详情,返回后刷新(收藏状态可能变化)
  Future<void> _openPlaylistDetail(BuildContext context, int id) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => PlaylistDetailPage(id: id)),
    );
    if (mounted) await _loadPlaylists();
  }

  /// 长按自己创建的歌单 → 删除(底部菜单 → 二次确认 → 提示)
  Future<void> _showPlaylistActions(BuildContext context, Playlist p) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
              child: Text(
                p.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(
                Icons.delete_outline,
                color: Colors.redAccent,
              ),
              title: const Text(
                '删除歌单',
                style: TextStyle(color: Colors.redAccent),
              ),
              onTap: () => Navigator.pop(ctx, 'delete'),
            ),
            ListTile(
              leading: const Icon(Icons.close),
              title: const Text('取消'),
              onTap: () => Navigator.pop(ctx, null),
            ),
          ],
        ),
      ),
    );

    if (action != 'delete' || !mounted) return;

    // 友好确认:说明影响范围
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除歌单'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('确定要删除歌单「${p.name}」吗?'),
            const SizedBox(height: 10),
            Text(
              p.songCount > 0
                  ? '歌单里的 ${p.songCount} 首歌会被移出歌单,但歌曲本身不会被删除。'
                  : '这个歌单里还没有歌曲。',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).hintColor,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              '删除后无法恢复。',
              style: TextStyle(fontSize: 12, color: Colors.redAccent),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('再想想'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              '删除',
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      await PlaylistRepository().deletePlaylist(p.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('歌单「${p.name}」已删除')),
      );
      await _loadPlaylists();
    } catch (e) {
      if (!mounted) return;
      showCenterToast(context, '删除失败:${friendlyError(e)}', error: true);
    }
  }

  /// 歌单封面卡片
  Widget _playlistCard(
    BuildContext context,
    Playlist p, {
    required bool isCreated,
  }) {
    final theme = Theme.of(context);

    return GestureDetector(
      onTap: () => _openPlaylistDetail(context, p.id),
      // 自己创建的歌单:长按可删除(收藏的别人歌单不可删)
      onLongPress: isCreated ? () => _showPlaylistActions(context, p) : null,
      child: SizedBox(
        width: 106,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: CachedNetworkImage(
                    imageUrl: p.coverUrl,
                    width: 106,
                    height: 106,
                    fit: BoxFit.cover,
                    placeholder: (_, __) => Container(
                      width: 106,
                      height: 106,
                      color: Colors.grey.shade200,
                    ),
                    errorWidget: (_, __, ___) => Container(
                      width: 106,
                      height: 106,
                      color: Colors.grey.shade300,
                      child: const Icon(Icons.album, size: 28),
                    ),
                  ),
                ),
                // 播放量角标
                Positioned(
                  top: 5,
                  right: 5,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.45),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.headphones,
                          size: 9,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 2),
                        Text(
                          formatCount(p.playCount),
                          style: const TextStyle(
                            fontSize: 9,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              p.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, height: 1.25),
            ),
            const SizedBox(height: 2),
            // 曲数(收藏的歌单同时显示创建者)
            Text(
              isCreated
                  ? '${p.songCount} 首'
                  : '${p.creator.isNotEmpty ? p.creator : '用户'} · ${p.songCount} 首',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 10, color: theme.hintColor),
            ),
          ],
        ),
      ),
    );
  }

  /// 区块空态
  Widget _emptyPlaylistHint(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Text(
        text,
        style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor),
      ),
    );
  }

  /// 游客态歌单引导
  Widget _guestPlaylistEntry(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: theme.colorScheme.primary.withOpacity(0.07),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(Icons.queue_music, color: theme.colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '我的歌单',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '登录后可创建歌单、收藏歌单,并支持跨设备同步',
                    style: TextStyle(fontSize: 12, color: theme.hintColor),
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: () => _gotoLogin(context),
              child: const Text('去登录'),
            ),
          ],
        ),
      ),
    );
  }

  /// 刷新缓存占用统计
  Future<void> _loadCacheStat() async {
    final bytes = await AudioCache.totalBytes();
    final count = await AudioCache.count();

    if (!mounted) return;
    setState(() {
      _cacheBytes = bytes;
      _cacheCount = count;
      _updateCacheText();
    });
  }

  String _fmtSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
    }
    return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
  }

  /// 缓存管理(查看占用 / 清空)
  Future<void> _showCacheDialog(BuildContext context) async {
    final theme = Theme.of(context);

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          '播放缓存',
          style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primary),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('已缓存 $_cacheCount 首,占用 ${_fmtSize(_cacheBytes)}'),
            const SizedBox(height: 10),
            Text(
              '播放过的歌曲会自动存到本地,下次播放无需下载 —— 省流量、秒开。\n'
              '缓存超过 1.5GB 时会自动清理最久未播放的。',
              style: TextStyle(
                fontSize: 12,
                color: theme.hintColor,
                height: 1.6,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('关闭'),
          ),
          if (_cacheCount > 0)
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text(
                '清空缓存',
                style: TextStyle(color: Colors.redAccent),
              ),
            ),
        ],
      ),
    );

    if (ok != true) return;

    // 保护当前正在播放的歌的明文文件:清缓存若删掉它,正在播的歌会中断。
    // 只保护本地文件(网络流播的不在 tmp 里,无需保护)。
    final player = context.read<PlayerProvider>();
    final curUrl = player.currentSong?.playUrl ?? '';
    String? protect;
    if (curUrl.isNotEmpty && !curUrl.startsWith('http')) {
      protect = curUrl.startsWith('file://')
          ? Uri.parse(curUrl).toFilePath()
          : curUrl;
    }

    await AudioCache.clear(protectPath: protect);
    if (!mounted) return;

    await _loadCacheStat();
    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('播放缓存已清空')),
    );
  }

  /// 修改密码(跳转独立页面)
  Future<void> _openChangePassword(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ChangePasswordPage()),
    );
  }

  // ==================== 设置 ====================

  String _themeLabel(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return '浅色';
      case ThemeMode.dark:
        return '深色';
      case ThemeMode.system:
        return '跟随系统';
    }
  }

  Future<void> _showThemeDialog(BuildContext context) async {
    final result = await showDialog<ThemeMode>(
      context: context,
      builder: (ctx) => SimpleDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          '主题模式',
          style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primary),
        ),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, ThemeMode.system),
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('跟随系统'),
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, ThemeMode.light),
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('浅色'),
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, ThemeMode.dark),
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('深色'),
            ),
          ),
        ],
      ),
    );
    if (result != null && context.mounted) {
      await context.read<ThemeProvider>().setMode(result);
    }
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          '退出登录',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.redAccent),
        ),
        content: const Text('退出后将以游客身份继续使用,本地数据会保留。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('退出'),
          ),
        ],
      ),
    );

    if (ok == true && context.mounted) {
      await context.read<AuthProvider>().logout();
    }
  }

  /// 通知栏控制说明
  Future<void> _showAudioServiceTip(BuildContext context) async {
    final ready = audioServiceReady;
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          '通知栏控制',
          style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primary),
        ),
        content: Text(
          ready
              ? '通知栏控制已启用:播放音乐时通知栏会显示控制条(上一首 / 播放暂停 / 下一首)。\n\n若仍看不到,请检查系统是否允许本应用发送通知。'
              : '尚未获得通知权限,通知栏不会显示控制条。\n\n请点「去设置」允许通知,然后重启 App。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('知道了'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              openAppSettings();
            },
            child: const Text('去设置'),
          ),
        ],
      ),
    );
  }
}

/// 头像
///
/// 为空或加载失败(如外网图片不可达)时,回退为「首字母圆形头像」,
/// 保证任何情况下都有头像可显示。
class _Avatar extends StatelessWidget {
  final String url;
  final String name;
  final double size;

  const _Avatar({required this.url, required this.name, this.size = 64});

  @override
  Widget build(BuildContext context) {
    final fallback = _letterAvatar(context);

    if (url.trim().isEmpty) return fallback;

    return ClipOval(
      child: CachedNetworkImage(
        imageUrl: url,
        width: size,
        height: size,
        fit: BoxFit.cover,
        placeholder: (_, __) => fallback,
        errorWidget: (_, __, ___) => fallback,
      ),
    );
  }

  Widget _letterAvatar(BuildContext context) {
    final theme = Theme.of(context);
    final trimmed = name.trim();
    final letter =
        trimmed.isEmpty ? '?' : trimmed.substring(0, 1).toUpperCase();

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: theme.colorScheme.primary.withOpacity(0.15),
      ),
      alignment: Alignment.center,
      child: Text(
        letter,
        style: TextStyle(
          fontSize: size * 0.4,
          fontWeight: FontWeight.bold,
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }
}
