import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';

import '../../config/constants.dart';
import '../../core/storage/storage_service.dart';
import '../../core/utils/error_text.dart';
import '../../core/utils/json_util.dart';
import '../../data/models/playlist.dart';
import '../../data/models/song.dart';
import '../../data/repositories/music_repository.dart';
import '../../data/repositories/playlist_repository.dart';
import '../../data/repositories/user_repository.dart';
import '../../providers/auth_provider.dart';
import '../../providers/player_provider.dart';
import '../../widgets/center_toast.dart';
import '../../widgets/gradient_icon_tile.dart';
import '../../widgets/playlist_name_dialog.dart';
import '../common/song_list_page.dart';
import '../login/login_page.dart';
import 'playlist_detail_page.dart';

/// 我的歌单(独立页面)
///
/// · 左滑 / 右滑在「我创建的」「我收藏的」之间切换
/// · 宫格展示封面卡片
class MyPlaylistsPage extends StatefulWidget {
  const MyPlaylistsPage({super.key});

  @override
  State<MyPlaylistsPage> createState() => _MyPlaylistsPageState();
}

class _MyPlaylistsPageState extends State<MyPlaylistsPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;

  List<Playlist> _created = [];
  List<Playlist> _collected = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final auth = context.read<AuthProvider>();
    if (!auth.isLoggedIn) {
      setState(() {
        _loading = false;
        _created = [];
        _collected = [];
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final res = await Future.wait([
        PlaylistRepository().getMyPlaylists(),
        UserRepository().getMyCollectedPlaylists(),
      ]);
      if (!mounted) return;
      setState(() {
        _created = res[0];
        _collected = res[1];
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = friendlyError(e, fallback: '加载失败,请稍后重试');
      });
    }
  }

  // ==================== 创建歌单 ====================

  Future<void> _createPlaylist() async {
    final name = await showPlaylistNameDialog(context);
    if (name == null || name.isEmpty) return;
    if (!mounted) return;

    try {
      await PlaylistRepository().create(name);
      if (!mounted) return;
      // 居中提示(底部 SnackBar 容易被播放条压住,也容易错过)
      showCenterToast(context, '歌单「$name」已创建');
      _tab.animateTo(0);
      await _load();
    } catch (e) {
      if (!mounted) return;
      // 只显示后端给的业务文案(不要 ApiException(...) 这种开发者内容)
      showCenterToast(context, '创建失败:${friendlyError(e)}', error: true);
    }
  }

  // ==================== UI ====================

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final theme = Theme.of(context);

    if (!auth.isLoggedIn) {
      return Scaffold(
        appBar: AppBar(title: const Text('我的歌单')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.queue_music,
                  size: 56,
                  color: theme.hintColor,
                ),
                const SizedBox(height: 16),
                const Text('登录后可以创建歌单、收藏歌单'),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const LoginPage()),
                  ),
                  child: const Text('立即登录'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('我的歌单'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: '新建歌单',
            onPressed: _createPlaylist,
          ),
        ],
        bottom: TabBar(
          controller: _tab,
          indicatorColor: theme.colorScheme.primary,
          labelColor: theme.colorScheme.primary,
          unselectedLabelColor: theme.hintColor,
          tabs: [
            Tab(text: '我创建的 (${_created.length})'),
            Tab(text: '我收藏的 (${_collected.length})'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : (_error != null && _created.isEmpty && _collected.isEmpty)
              ? _errorView()
              : TabBarView(
                  controller: _tab,
                  children: [
                    _grid(_created, isCreated: true),
                    _grid(_collected, isCreated: false),
                  ],
                ),
    );
  }

  Widget _errorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 44),
            const SizedBox(height: 12),
            const Text('加载失败'),
            const SizedBox(height: 6),
            Text(
              _error ?? '',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: _load, child: const Text('重试')),
          ],
        ),
      ),
    );
  }

  /// 宫格列表
  ///
  /// 「我创建的」Tab 首位固定为「默认收藏」(系统内置,与「我的」页保持一致)
  Widget _grid(List<Playlist> list, {required bool isCreated}) {
    final withFavorites = isCreated;
    final total = list.length + (withFavorites ? 1 : 0);

    if (total == 0) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isCreated ? Icons.queue_music : Icons.favorite_border,
              size: 48,
              color: Theme.of(context).hintColor,
            ),
            const SizedBox(height: 12),
            Text(
              isCreated ? '还没有创建歌单,点右上角 + 新建' : '还没有收藏歌单,去歌单广场逛逛',
              style: TextStyle(fontSize: 13, color: Theme.of(context).hintColor),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: GridView.builder(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: 16,
          crossAxisSpacing: 12,
          childAspectRatio: 0.72,
        ),
        itemCount: total,
        itemBuilder: (context, i) {
          if (withFavorites && i == 0) {
            return _favoritesCard();
          }
          final index = withFavorites ? i - 1 : i;
          return _card(list[index], isCreated: isCreated);
        },
      ),
    );
  }

  /// 系统内置「默认收藏」卡片(不可删除)
  Widget _favoritesCard() {
    return GestureDetector(
      onTap: _openFavorites,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 封面色块:亮色渐变 / 深色黑底 + 彩色描边(见 GradientIconTile)
          const Expanded(
            child: GradientIconTile(icon: Icons.favorite),
          ),
          const SizedBox(height: 7),
          const Text(
            '默认收藏',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 2),
          Text(
            '系统收藏夹',
            style: TextStyle(fontSize: 10, color: Theme.of(context).hintColor),
          ),
        ],
      ),
    );
  }

  /// 打开「默认收藏」歌曲列表(可左滑移除)
  Future<void> _openFavorites() async {
    final auth = context.read<AuthProvider>();
    late Future<List<Song>> future;

    if (auth.isLoggedIn) {
      future = UserRepository().getMyCollects(type: TargetType.song);
    } else {
      future = MusicRepository().getBatchSongs(StorageService.localFavorites);
    }

    if (!mounted) return;
    final player = context.read<PlayerProvider>();

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SongListPage(
          title: '默认收藏',
          futureSongs: future,
          removeScene: '默认收藏',
          onRemove: (song) async {
            await player.toggleFavorite(song.id);
          },
        ),
      ),
    );
  }

  /// 打开歌单详情,返回后刷新(收藏状态可能变化)
  Future<void> _openDetail(int id) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => PlaylistDetailPage(id: id)),
    );
    if (mounted) await _load();
  }

  /// 长按自己创建的歌单 → 删除(底部菜单 → 二次确认 → 提示)
  Future<void> _showPlaylistActions(Playlist p) async {
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
      await _load();
    } catch (e) {
      if (!mounted) return;
      showCenterToast(context, '删除失败:${friendlyError(e)}', error: true);
    }
  }

  /// 歌单卡片(封面 + 播放量角标 + 名称)
  Widget _card(Playlist p, {required bool isCreated}) {
    final theme = Theme.of(context);

    return GestureDetector(
      onTap: () => _openDetail(p.id),
      // 自己创建的歌单:长按可删除(收藏的别人歌单不可删)
      onLongPress: isCreated ? () => _showPlaylistActions(p) : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Stack(
              children: [
                // 封面
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: CachedNetworkImage(
                      imageUrl: p.coverUrl,
                      fit: BoxFit.cover,
                      placeholder: (_, __) =>
                          Container(color: Colors.grey.shade200),
                      errorWidget: (_, __, ___) => Container(
                        color: Colors.grey.shade300,
                        child: const Icon(Icons.album, size: 30),
                      ),
                    ),
                  ),
                ),
                // 播放量角标
                Positioned(
                  top: 6,
                  right: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.45),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.headphones,
                          size: 10,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 3),
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
          ),
          const SizedBox(height: 7),
          Text(
            p.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 2),
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
    );
  }
}
