import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:provider/provider.dart';

import '../../config/theme.dart';
import '../../core/utils/error_text.dart';
import '../../data/models/song.dart';
import '../../providers/player_provider.dart';
import '../../widgets/center_toast.dart';
import '../../widgets/dialog_actions.dart';
import '../../widgets/song_tile.dart';

/// 通用歌曲列表页
///
/// 榜单 / 歌手歌曲 / 收藏 / 历史 等场景复用。
/// 传入 [onRemove] 时,列表项支持「左滑露出一小块删除按钮,点击才删除」。
class SongListPage extends StatefulWidget {
  final String title;

  /// 已有歌曲列表(直接渲染)
  final List<Song>? songs;

  /// 或异步加载
  final Future<List<Song>>? futureSongs;

  /// 删除回调(提供时启用侧滑删除)
  final Future<void> Function(Song song)? onRemove;

  /// 删除提示中的场景名,如「默认收藏」
  final String removeScene;

  /// 「清空全部」回调(提供时标题栏出现「清空」按钮,点击前二次确认)
  ///
  /// 播放历史用它:登录时清云端、游客清本地(由调用方决定)。
  final Future<void> Function()? onClearAll;

  const SongListPage({
    super.key,
    required this.title,
    this.songs,
    this.futureSongs,
    this.onRemove,
    this.removeScene = '列表',
    this.onClearAll,
  }) : assert(songs != null || futureSongs != null);

  @override
  State<SongListPage> createState() => _SongListPageState();
}

class _SongListPageState extends State<SongListPage> {
  List<Song> _songs = [];
  bool _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    if (widget.songs != null) {
      setState(() {
        _songs = List<Song>.from(widget.songs!);
        _loading = false;
      });
      return;
    }

    try {
      final list = await widget.futureSongs;
      if (!mounted) return;
      setState(() {
        _songs = list ?? [];
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  /// 先从本地列表移除(保证 UI 立即响应),再异步同步到后端 / 本地存储
  void _remove(Song song) {
    setState(() => _songs.removeWhere((e) => e.id == song.id));
    widget.onRemove?.call(song);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已从${widget.removeScene}移除')),
    );
  }

  /// 清空全部:二次确认 → 回调 → 本地列表清空
  Future<void> _confirmClearAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: AppTheme.primaryGradient,
                ),
                child: const Icon(
                  Icons.delete_sweep_outlined,
                  color: Colors.white,
                  size: 26,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                '清空${widget.removeScene}',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(ctx).colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '清空后无法恢复。累计听歌时长与听过的歌曲数不受影响。',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 20),
              DialogActionRow(
                cancelLabel: '取消',
                confirmLabel: '清空',
                onCancel: () => Navigator.pop(ctx, false),
                onConfirm: () => Navigator.pop(ctx, true),
              ),
            ],
          ),
        ),
      ),
    );

    if (ok != true || !mounted) return;

    try {
      await widget.onClearAll?.call();
      if (!mounted) return;
      setState(() => _songs = []);
      showCenterToast(context, '已清空${widget.removeScene}');
    } catch (e) {
      if (!mounted) return;
      showCenterToast(
        context,
        '清空失败:${friendlyError(e)}',
        error: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          if (widget.onClearAll != null && _songs.isNotEmpty)
            TextButton(
              onPressed: _confirmClearAll,
              child: Text(
                '清空',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(child: Text('加载失败:${_error}'));
    }

    if (_songs.isEmpty) {
      return const Center(child: Text('暂无歌曲'));
    }

    return ListView.builder(
      itemCount: _songs.length,
      itemBuilder: (context, index) {
        final song = _songs[index];

        final tile = SongTile(
          song: song,
          index: index,
          onTap: () => context.read<PlayerProvider>().playSong(
                song,
                playlist: _songs,
              ),
        );

        if (widget.onRemove == null) return tile;

        // 左滑露出一小块删除按钮,点击按钮才真正删除
        return Slidable(
          key: ValueKey('slidable-${song.id}'),
          endActionPane: ActionPane(
            motion: const DrawerMotion(),
            extentRatio: 0.24,
            children: [
              SlidableAction(
                onPressed: (_) => _remove(song),
                backgroundColor: Colors.redAccent,
                foregroundColor: Colors.white,
                icon: Icons.delete_outline,
                label: '删除',
              ),
            ],
          ),
          child: tile,
        );
      },
    );
  }
}
