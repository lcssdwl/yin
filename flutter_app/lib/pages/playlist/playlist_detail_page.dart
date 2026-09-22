import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/models/playlist.dart';
import '../../data/models/song.dart';
import '../../core/utils/error_text.dart';
import '../../data/repositories/playlist_repository.dart';
import '../../providers/auth_provider.dart';
import '../../providers/player_provider.dart';
import '../../widgets/login_guide_sheet.dart';
import '../../widgets/song_tile.dart';

/// 歌单详情页
///
/// 🟢 游客可查看并播放
/// 🔴 收藏歌单需登录(未登录会软性引导,不阻断浏览)
class PlaylistDetailPage extends StatefulWidget {
  final int id;

  const PlaylistDetailPage({super.key, required this.id});

  @override
  State<PlaylistDetailPage> createState() => _PlaylistDetailPageState();
}

class _PlaylistDetailPageState extends State<PlaylistDetailPage> {
  final PlaylistRepository _repo = PlaylistRepository();
  late Future<Playlist> _future;

  /// 收藏态(null = 未知,交给详情接口返回)
  bool? _collected;
  bool _collecting = false;

  /// 本地可变歌曲列表(自己创建的歌单可以左滑移出歌曲)
  List<Song> _songs = [];

  /// 已初始化本地列表的歌单ID(避免 build 期间重复初始化)
  int _loadedId = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _future = _repo.getDetailWithSongs(widget.id);
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ==================== 交互 ====================

  /// 收藏 / 取消收藏(游客引导登录)
  Future<void> _toggleCollect(Playlist playlist) async {
    final auth = context.read<AuthProvider>();
    if (!auth.isLoggedIn) {
      _showLoginGuide('登录后可收藏歌单,并支持跨设备同步');
      return;
    }
    if (_collecting) return;

    setState(() => _collecting = true);
    try {
      final collected = await _repo.collect(playlist.id);
      if (!mounted) return;
      setState(() {
        _collected = collected;
        _collecting = false;
      });
      _toast(collected ? '已收藏歌单' : '已取消收藏');
    } catch (e) {
      if (!mounted) return;
      setState(() => _collecting = false);
      _toast('操作失败:${friendlyError(e)}');
    }
  }

  /// 分享歌单
  Future<void> _share(Playlist playlist) async {
    final buffer = StringBuffer()
      ..writeln('【歌单】${playlist.name}')
      ..writeln('共 ${playlist.songCount} 首歌曲');
    if (playlist.creator.isNotEmpty) {
      buffer.writeln('来自:${playlist.creator}');
    }
    if (playlist.intro.isNotEmpty) {
      buffer.writeln(playlist.intro);
    }
    buffer.write('—— 云韵音乐');

    try {
      await Share.share(buffer.toString(), subject: playlist.name);
    } catch (e) {
      _toast('分享失败:${friendlyError(e, fallback: '请稍后重试')}');
    }
  }

  /// 从歌单移出歌曲(仅自己创建的歌单)
  ///
  /// 只是把歌曲移出歌单,不会删除歌曲本身。
  Future<void> _removeSong(Playlist playlist, Song song) async {
    try {
      await _repo.removeSong(playlist.id, song.id);
      if (!mounted) return;
      setState(() {
        _songs.removeWhere((s) => s.id == song.id);
      });
      _toast('已把「${song.name}」移出歌单');
    } catch (e) {
      if (!mounted) return;
      _toast('移出失败:${friendlyError(e)}');
    }
  }

  /// 软性登录引导
  ///
  /// 统一走全局的居中弹窗(widgets/login_guide_sheet.dart):
  /// 底部 sheet 会被播放条 / 输入框压住,而且两个按钮高度对不齐。
  void _showLoginGuide(String message) {
    showLoginGuide(context, message);
  }

  // ==================== UI ====================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FutureBuilder<Playlist>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Scaffold(
              appBar: AppBar(title: const Text('歌单')),
              body: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline, size: 48),
                      const SizedBox(height: 12),
                      const Text('歌单加载失败'),
                      const SizedBox(height: 8),
                      Text(
                        '${snapshot.error}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () => setState(_load),
                        child: const Text('重试'),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }

          if (!snapshot.hasData) {
            return Scaffold(
              appBar: AppBar(title: const Text('歌单')),
              body: const Center(child: Text('没有拿到歌单数据')),
            );
          }

          return _buildContent(context, snapshot.data!);
        },
      ),
    );
  }

  Widget _buildContent(BuildContext context, Playlist playlist) {
    // 首次拿到数据时建立本地可变副本(移出歌曲后直接改它,无需重新请求)
    if (_loadedId != playlist.id) {
      _loadedId = playlist.id;
      _songs = List<Song>.from(playlist.songs);
    }

    final songs = _songs;
    final theme = Theme.of(context);

    // 是否自己创建的歌单(只有自己的歌单才能移出歌曲)
    final auth = context.watch<AuthProvider>();
    final isOwner = auth.isLoggedIn &&
        playlist.userId > 0 &&
        playlist.userId == (auth.user?.id ?? 0);

    final isCollected = _collected ?? playlist.isCollected;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // 头部封面
          SliverAppBar(
            expandedHeight: 220,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  CachedNetworkImage(
                    imageUrl: playlist.coverUrl,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => Container(
                      color: Colors.grey.shade300,
                      child: const Icon(Icons.album, size: 48),
                    ),
                  ),
                  Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Colors.black54],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 信息区
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    playlist.name,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'by ${playlist.creator} · ${songs.length} 首',
                    style: TextStyle(fontSize: 13, color: theme.hintColor),
                  ),
                  // 自己创建的歌单:提示可以左滑移出歌曲
                  if (isOwner && songs.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(
                          Icons.swipe_left_outlined,
                          size: 13,
                          color: theme.hintColor,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '左滑歌曲可移出歌单(不会删除歌曲)',
                          style: TextStyle(fontSize: 11, color: theme.hintColor),
                        ),
                      ],
                    ),
                  ],
                  if (playlist.intro.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(
                      playlist.intro,
                      style: TextStyle(fontSize: 13, color: theme.hintColor),
                    ),
                  ],
                  const SizedBox(height: 16),

                  // 播放全部 + 收藏 + 分享
                  Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 44,
                          child: ElevatedButton.icon(
                            icon: const Icon(Icons.play_arrow),
                            label: const Text('播放全部'),
                            onPressed: songs.isEmpty
                                ? null
                                : () => context
                                    .read<PlayerProvider>()
                                    .playQueue(songs, 0),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      _roundAction(
                        icon: isCollected
                            ? Icons.favorite
                            : Icons.favorite_border,
                        color: isCollected ? Colors.redAccent : null,
                        tooltip: isCollected ? '取消收藏' : '收藏',
                        onTap: () => _toggleCollect(playlist),
                      ),
                      const SizedBox(width: 10),
                      _roundAction(
                        icon: Icons.ios_share,
                        tooltip: '分享',
                        onTap: () => _share(playlist),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // 歌曲列表
          if (songs.isEmpty)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: Text('暂无歌曲')),
              ),
            )
          else
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final song = songs[index];

                  final tile = SongTile(
                    song: song,
                    index: index,
                    onTap: () {
                      context.read<PlayerProvider>().playSong(
                            song,
                            playlist: songs,
                          );
                    },
                  );

                  // 别人(或官方)的歌单:不能移出歌曲
                  if (!isOwner) return tile;

                  // 自己创建的歌单:左滑露出一小块「移出」按钮,点击才移出
                  return Slidable(
                    key: ValueKey('playlist-song-${song.id}'),
                    endActionPane: ActionPane(
                      motion: const DrawerMotion(),
                      extentRatio: 0.24,
                      children: [
                        SlidableAction(
                          onPressed: (_) => _removeSong(playlist, song),
                          backgroundColor: Colors.redAccent,
                          foregroundColor: Colors.white,
                          icon: Icons.playlist_remove,
                          label: '移出',
                        ),
                      ],
                    ),
                    child: tile,
                  );
                },
                childCount: songs.length,
              ),
            ),

          const SliverToBoxAdapter(child: SizedBox(height: 80)),
        ],
      ),
    );
  }

  Widget _roundAction({
    required IconData icon,
    required VoidCallback onTap,
    Color? color,
    String? tooltip,
  }) {
    final btn = SizedBox(
      width: 44,
      height: 44,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          padding: EdgeInsets.zero,
          shape: const CircleBorder(),
        ),
        child: Icon(icon, size: 20, color: color),
      ),
    );
    return tooltip == null ? btn : Tooltip(message: tooltip, child: btn);
  }
}
