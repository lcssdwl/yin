import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:provider/provider.dart';

import '../../config/constants.dart';
import '../../config/theme.dart';
import '../../core/audio/audio_cache.dart';
import '../../core/utils/json_util.dart';
import '../../data/models/song.dart';
import '../../providers/player_provider.dart';
import '../../widgets/center_toast.dart';
import '../../widgets/dialog_actions.dart';

/// 离线缓存列表
///
/// 数据**全部来自本地**:`audio_cache/index.json`(见 [AudioCache.cachedSongs]),
/// 一次网络请求都不发。这里列出的每一首都已经下载完整 ——
/// 点一下直接播本地文件,飞行模式下照样听。
///
/// 为什么需要单独建索引:缓存文件名只有「音频指纹_音质.enc」,
/// 既没有歌名也没有歌手,断网时不联网根本列不出这首歌是谁。
/// 所以每次成功缓存都把歌曲信息记一份到本地(详见 AudioCache 注释)。
class OfflineCachePage extends StatefulWidget {
  const OfflineCachePage({super.key});

  @override
  State<OfflineCachePage> createState() => _OfflineCachePageState();
}

class _OfflineCachePageState extends State<OfflineCachePage> {
  List<AudioCacheEntry> _entries = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    // 边播边存写下新缓存时,列表要跟着长出来(不必手动退出再进)
    AudioCache.cacheVersion.addListener(_reload);
    WidgetsBinding.instance.addPostFrameCallback((_) => _reload());
  }

  @override
  void dispose() {
    AudioCache.cacheVersion.removeListener(_reload);
    super.dispose();
  }

  Future<void> _reload() async {
    final list = await AudioCache.cachedSongs();
    if (!mounted) return;
    setState(() {
      _entries = list;
      _loading = false;
    });
  }

  int get _totalBytes => _entries.fold(0, (sum, e) => sum + e.bytes);

  /// 缓存记录 → 可播放的 Song
  ///
  /// 只填本地能拿到的信息,播放地址故意留空:
  /// 播放时会先按 [Song.offlineQuality] 查本地缓存并解密出明文文件,
  /// 查不到才联网 —— 离线场景下这一步根本不会走到。
  Song _toSong(AudioCacheEntry e) => Song(
        id: e.songId,
        name: e.displayName,
        singerName: e.singerName,
        albumName: e.albumName,
        duration: e.duration,
        cover: e.cover,
        md5: e.md5,
        md5128: e.quality == '128' ? e.md5 : '',
        md5320: e.quality == '320' ? e.md5 : '',
        md5Flac: e.quality == 'flac' ? e.md5 : '',
        offlineQuality: e.quality,
      );

  void _play(AudioCacheEntry e) {
    final songs = _entries.map(_toSong).toList();
    final index = _entries.indexOf(e);
    if (index < 0) return;
    context.read<PlayerProvider>().playQueue(songs, index);
  }

  /// 删掉这一首的缓存(先改 UI,再删文件)
  Future<void> _remove(AudioCacheEntry e) async {
    setState(() {
      _entries.removeWhere((x) => x.md5 == e.md5 && x.quality == e.quality);
    });
    await AudioCache.removeEntry(e.md5, e.quality);
    if (!mounted) return;
    showCenterToast(context, '已清除这首歌的缓存');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('离线缓存'),
        actions: [
          if (_entries.isNotEmpty)
            TextButton(
              onPressed: _confirmClearAll,
              child: Text(
                '清空',
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _reload,
              child: _entries.isEmpty
                  ? ListView(children: [_buildEmptyHint(context)])
                  : ListView.builder(
                      padding: const EdgeInsets.only(bottom: 24),
                      // 首项是统计卡,后面是歌曲
                      itemCount: _entries.length + 1,
                      itemBuilder: (context, i) {
                        if (i == 0) return _buildSummary(context);
                        final e = _entries[i - 1];

                        return Slidable(
                          key: ValueKey('offline-${e.md5}-${e.quality}'),
                          endActionPane: ActionPane(
                            motion: const DrawerMotion(),
                            extentRatio: 0.24,
                            children: [
                              SlidableAction(
                                onPressed: (_) => _remove(e),
                                backgroundColor: Colors.redAccent,
                                foregroundColor: Colors.white,
                                icon: Icons.delete_outline,
                                label: '清除',
                              ),
                            ],
                          ),
                          child: _CacheTile(entry: e, onTap: () => _play(e)),
                        );
                      },
                    ),
            ),
    );
  }

  /// 顶部统计卡:多少首 / 占多少空间
  Widget _buildSummary(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: theme.colorScheme.primary.withOpacity(0.07),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(Icons.download_done_outlined, color: theme.colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '离线可播',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${_entries.length} 首 · 占用 ${_fmtSize(_totalBytes)}',
                    style: TextStyle(fontSize: 12, color: theme.hintColor),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '这些歌已完整存到本地,断网也能播放',
                    style: TextStyle(fontSize: 12, color: theme.hintColor),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyHint(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 80, 16, 16),
      child: Column(
        children: [
          Icon(
            Icons.download_for_offline_outlined,
            size: 56,
            color: theme.disabledColor,
          ),
          const SizedBox(height: 14),
          const Text(
            '还没有离线歌曲',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            '听过的歌会自动缓存到本地。完整缓存下来的歌会出现在这里,之后不联网也能播。\n'
            '缓存上限 1.5GB,超限时先清理最久没听的。',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, height: 1.6, color: theme.hintColor),
          ),
        ],
      ),
    );
  }

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
                '清空离线缓存',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(ctx).colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '会删掉本地 ${_entries.length} 首歌的音频(${_fmtSize(_totalBytes)})。\n'
                '删除后这些歌需要联网才能再听。',
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

    // 保护当前正在播放的歌的明文文件:正在播本地缓存时把它删了会直接断音
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

    await _reload();
    if (!mounted) return;
    showCenterToast(context, '离线缓存已清空');
  }

  String _fmtSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
    }
    return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
  }
}

/// 单行缓存项:封面 + 歌名 + 歌手 + 已缓存音质 + 大小 + 时长
class _CacheTile extends StatelessWidget {
  final AudioCacheEntry entry;
  final VoidCallback onTap;

  const _CacheTile({required this.entry, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final coverUrl =
        entry.cover.isEmpty ? AppConstants.defaultCover : entry.cover;

    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: CachedNetworkImage(
          imageUrl: coverUrl,
          width: 48,
          height: 48,
          fit: BoxFit.cover,
          placeholder: (_, __) => Container(
            width: 48,
            height: 48,
            color: Colors.grey.shade200,
            child: const Icon(Icons.album, size: 20, color: Colors.grey),
          ),
          // 离线时封面取不到,回退成音符图标(不能因为封面取不到就整行不可用)
          errorWidget: (_, __, ___) => Container(
            width: 48,
            height: 48,
            color: Colors.grey.shade300,
            child: const Icon(Icons.offline_pin, size: 20),
          ),
        ),
      ),
      title: Text(
        entry.displayName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        _entryLabel(context, entry),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 13, color: theme.hintColor),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            formatDuration(entry.duration),
            style: TextStyle(fontSize: 12, color: theme.hintColor),
          ),
          const SizedBox(width: 6),
          const Icon(Icons.play_circle_outline, size: 18),
        ],
      ),
    );
  }
}

/// 「歌手 · 已缓存音质 · 大小」
///
/// 之所以显示音质:同一首歌可能只缓存了标准档(当时选的就是标准),
/// 写清楚用户才知道离线放出的是哪一档。
String _entryLabel(BuildContext context, AudioCacheEntry e) {
  final quality = context.read<PlayerProvider>().labelOfQuality(e.quality);
  final size = e.bytes <= 0
      ? ''
      : e.bytes >= 1024 * 1024
          ? '${(e.bytes / 1024 / 1024).toStringAsFixed(1)}MB'
          : '${(e.bytes / 1024).ceil()}KB';

  return [
    e.displaySubtitle,
    '已缓存$quality',
    if (size.isNotEmpty) size,
  ].join(' · ');
}
