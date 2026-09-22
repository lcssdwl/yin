import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config/theme.dart';
import '../../core/utils/error_text.dart';
import '../../data/models/home_models.dart';
import '../../data/models/playlist.dart';
import '../../data/models/song.dart';
import '../../data/repositories/music_repository.dart';
import '../../providers/player_provider.dart';
import '../../widgets/song_tile.dart';
import '../album/album_detail_page.dart';
import '../common/song_list_page.dart';
import '../playlist/playlist_detail_page.dart';
import '../singer/singer_detail_page.dart';

/// 轮播跳转目标类型(必须与后端一致:1歌曲 2歌单 3专辑 4歌手)
const int _targetSong = 1;
const int _targetPlaylist = 2;
const int _targetAlbum = 3;
const int _targetSinger = 4;

/// 发现页(首页)
/// 全部接口 🟢 公开,游客可直接浏览与播放
class DiscoverPage extends StatefulWidget {
  const DiscoverPage({super.key});

  @override
  State<DiscoverPage> createState() => _DiscoverPageState();
}

class _DiscoverPageState extends State<DiscoverPage> {
  final MusicRepository _repo = MusicRepository();
  late Future<HomeData> _future;

  @override
  void initState() {
    super.initState();
    _future = _repo.getHomeData();
  }

  Future<void> _refresh() async {
    setState(() {
      _future = _repo.getHomeData();
    });
    try {
      await _future;
    } catch (_) {}
  }

  void _playSong(Song song, List<Song> list) {
    context.read<PlayerProvider>().playSong(song, playlist: list);
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _push(Widget page) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }

  /// 打开外部链接(轮播图 url 字段)
  ///
  /// 用应用内建 webview 打开,不跳第三方浏览器。
  Future<void> _openExternalLink(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) {
      _toast('链接无效:$url');
      return;
    }
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.inAppWebView);
      if (!ok) {
        _toast('无法打开链接:$url');
      }
    } catch (e) {
      _toast('打开链接失败:${friendlyError(e, fallback: '请稍后重试')}');
    }
  }

  /// 轮播点击统一入口:优先外部 url,其次按 target_type 跳转
  Future<void> _onBannerTap(BannerItem b) async {
    final url = b.url.trim();
    if (url.isNotEmpty) {
      await _openExternalLink(url);
      return;
    }

    if (b.targetId <= 0) {
      _toast('该内容暂未配置跳转');
      return;
    }

    switch (b.targetType) {
      case _targetSong:
        await _playSongById(b.targetId);
        break;
      case _targetPlaylist:
        _push(PlaylistDetailPage(id: b.targetId));
        break;
      case _targetAlbum:
        _push(AlbumDetailPage(id: b.targetId));
        break;
      case _targetSinger:
        _push(SingerDetailPage(id: b.targetId));
        break;
      default:
        _toast('该内容暂不支持跳转');
    }
  }

  Future<void> _playSongById(int id) async {
    try {
      final song = await _repo.getSongDetail(id);
      if (!mounted) return;
      context.read<PlayerProvider>().playSong(song, playlist: [song]);
    } catch (e) {
      _toast('播放失败:${friendlyError(e)}');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('发现'),
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<HomeData>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting &&
                !snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            if (snapshot.hasError) {
              return ListView(
                children: [
                  const SizedBox(height: 100),
                  const Icon(
                    Icons.wifi_off_rounded,
                    size: 56,
                    color: Colors.grey,
                  ),
                  const SizedBox(height: 16),
                  const Center(
                    child: Text(
                      '加载失败，请检查网络后重试',
                      style: TextStyle(fontSize: 15, color: Colors.grey),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Center(
                    child: FilledButton.icon(
                      onPressed: _refresh,
                      icon: const Icon(Icons.refresh),
                      label: const Text('重新加载'),
                    ),
                  ),
                ],
              );
            }

            final data = snapshot.data;
            if (data == null) {
              return const Center(child: Text('暂无数据'));
            }

            return ListView(
              padding: const EdgeInsets.only(bottom: 20),
              // 预渲染下方内容:从播放页返回后滑到「推荐/最新」区块时,
              // 避免惰性构建导致的短暂白屏。
              cacheExtent: 1600,
              children: [
                if (data.banner.isNotEmpty)
                  _BannerCarousel(items: data.banner, onTap: _onBannerTap),
                if (data.hotPlaylist.isNotEmpty)
                  _buildHotPlaylist(data.hotPlaylist),
                if (data.rank.isNotEmpty) _buildRank(data.rank),
                // 分类放在排行榜下面(带栏目框,字号比其它栏目小一档)
                if (data.genres.isNotEmpty) _buildGenres(data.genres),
                if (data.recommend.isNotEmpty)
                  _buildSongSection('推荐歌曲', data.recommend),
                if (data.newSong.isNotEmpty)
                  _buildSongSection('最新音乐', data.newSong),
              ],
            );
          },
        ),
      ),
    );
  }

  // ==================== 分类 ====================

  /// 分类栏目:圆角卡片框 + 胶囊标签(带歌曲数)
  ///
  /// 数据来自后台「分类管理」——豆瓣标签 → 各分类关键词 → 兜底「其他」三级自动归类。
  /// 有歌的分类优先展示;一个都没有时展示全部并给一句提示,避免整栏凭空消失。
  Widget _buildGenres(List<GenreItem> genres) {
    final theme = Theme.of(context);

    // 一个分类都没歌:多半是后台还没跑「一键分类」。
    final allEmpty = genres.every((g) => g.songCount == 0);

    return _sectionCard(
      title: '分类',
      // 比其它栏目小一号:分类是"入口",不该抢推荐/最新音乐的主视觉
      titleSize: 15,
      gap: 10,
      padding: const EdgeInsets.only(top: 12, bottom: 12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (allEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  '分类已就绪,后台「分类管理」点一次「一键分类」后这里就会有歌',
                  style: TextStyle(fontSize: 11, color: theme.hintColor),
                ),
              ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var i = 0; i < genres.length; i++)
                  _genreChip(genres[i], AppTheme.paletteAt(i), theme),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _genreChip(GenreItem g, Color color, ThemeData theme) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () => _push(
        SongListPage(
          // 带上总数,和胶囊上的数字对得上,一眼能看出列表是不是全的
          title: g.songCount > 0 ? '${g.name}(${g.songCount})' : g.name,
          futureSongs: _repo.getGenreSongs(g.id),
        ),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          // 底色用淡主色:栏目的卡片底也是 cardColor,同色会看不出胶囊形状
          color: theme.colorScheme.primary.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: theme.colorScheme.primary.withValues(alpha: 0.22),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(shape: BoxShape.circle, color: color),
            ),
            const SizedBox(width: 6),
            Text(g.name, style: const TextStyle(fontSize: 12)),
            const SizedBox(width: 5),
            Text(
              '${g.songCount}',
              style: TextStyle(fontSize: 10, color: theme.hintColor),
            ),
          ],
        ),
      ),
    );
  }

  // ==================== 热门歌单 ====================

  Widget _buildHotPlaylist(List<Playlist> playlists) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('热门歌单'),
        SizedBox(
          height: 150,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            scrollDirection: Axis.horizontal,
            itemCount: playlists.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final p = playlists[index];
              return GestureDetector(
                onTap: () => _push(PlaylistDetailPage(id: p.id)),
                child: SizedBox(
                  width: 110,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: CachedNetworkImage(
                          imageUrl: p.coverUrl,
                          width: 110,
                          height: 110,
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) => Container(
                            width: 110,
                            height: 110,
                            color: Colors.grey.shade300,
                            child: const Icon(Icons.album_outlined),
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        p.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // ==================== 榜单 ====================

  Widget _buildRank(List<RankItem> ranks) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('排行榜'),
        ...ranks.map((r) {
          return Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: ListTile(
              shape:
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              leading: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: CachedNetworkImage(
                  imageUrl: r.cover,
                  width: 56,
                  height: 56,
                  fit: BoxFit.cover,
                  errorWidget: (_, __, ___) => Container(
                    width: 56,
                    height: 56,
                    color: Colors.grey.shade300,
                    child: const Icon(Icons.leaderboard_outlined),
                  ),
                ),
              ),
              title: Text(r.name),
              subtitle: Text(
                r.top.isEmpty ? r.intro : r.top.join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                _push(
                  SongListPage(
                    title: r.name,
                    futureSongs: _repo
                        .getRankSongs(r.id)
                        .then((res) => res['songs'] as List<Song>),
                  ),
                );
              },
            ),
          );
        }),
      ],
    );
  }

  // ==================== 歌曲区块 ====================

  /// 栏目框:圆角卡片 + 渐变竖条标题
  ///
  /// 「推荐歌曲 / 最新音乐 / 分类」共用同一套外观。以后加新栏目直接套这个,
  /// 别再各写一份 Container —— 之前就是因为没统一,分类才会是"裸"的。
  Widget _sectionCard({
    required String title,
    required Widget child,
    EdgeInsets padding = const EdgeInsets.only(top: 14, bottom: 14),
    double gap = 12,

    /// 标题字号:默认 18(推荐歌曲 / 最新音乐);分类这类次要栏目给小一号
    double titleSize = 18,
  }) {
    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      padding: padding,
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.primary.withOpacity(0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Container(
                  width: 4,
                  height: 18,
                  decoration: BoxDecoration(
                    gradient: AppTheme.primaryGradient,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: titleSize,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: gap),
          child,
        ],
      ),
    );
  }

  Widget _buildSongSection(String title, List<Song> songs) {
    // 独立卡片框:推荐歌曲 / 最新音乐各自一个圆角卡片,和轮播、歌单、榜单区分开
    return _sectionCard(
      title: title,
      padding: const EdgeInsets.only(top: 14, bottom: 6),
      gap: 4,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ...songs.asMap().entries.map((entry) {
            return SongTile(
              song: entry.value,
              index: entry.key,
              onTap: () => _playSong(entry.value, songs),
            );
          }),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 10),
      child: Row(
        children: [
          // 彩色渐变竖条装饰
          Container(
            width: 4,
            height: 18,
            decoration: BoxDecoration(
              gradient: AppTheme.primaryGradient,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}

/// 自动轮播图
///
/// - 每 4 秒自动切换
/// - 手指拖动时暂停,松手后继续
/// - 底部指示点
class _BannerCarousel extends StatefulWidget {
  final List<BannerItem> items;
  final Future<void> Function(BannerItem) onTap;

  const _BannerCarousel({required this.items, required this.onTap});

  @override
  State<_BannerCarousel> createState() => _BannerCarouselState();
}

class _BannerCarouselState extends State<_BannerCarousel> {
  final PageController _controller = PageController(viewportFraction: 0.92);
  Timer? _timer;
  int _current = 0;

  @override
  void initState() {
    super.initState();
    _startAutoPlay();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _startAutoPlay() {
    _timer?.cancel();
    if (widget.items.length <= 1) return;

    _timer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted || !_controller.hasClients) return;
      final next = (_current + 1) % widget.items.length;
      _controller.animateToPage(
        next,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.items;

    return SizedBox(
      height: 178,
      child: Stack(
        children: [
          NotificationListener<ScrollNotification>(
            onNotification: (n) {
              // 用户手动拖动时暂停自动播放,结束后恢复
              if (n is ScrollStartNotification &&
                  n.dragDetails != null) {
                _timer?.cancel();
              } else if (n is ScrollEndNotification) {
                _startAutoPlay();
              }
              return false;
            },
            child: PageView.builder(
              controller: _controller,
              itemCount: items.length,
              onPageChanged: (i) => setState(() => _current = i),
              itemBuilder: (context, index) {
                final b = items[index];
                return GestureDetector(
                  onTap: () => widget.onTap(b),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 8,
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          CachedNetworkImage(
                            imageUrl: b.image,
                            fit: BoxFit.cover,
                            placeholder: (_, __) =>
                                Container(color: Colors.grey.shade300),
                            errorWidget: (_, __, ___) => Container(
                              color: Colors.grey.shade300,
                              child: const Icon(
                                Icons.image_not_supported_outlined,
                              ),
                            ),
                          ),
                          // 底部渐变 + 标题
                          if (b.title.isNotEmpty)
                            Positioned(
                              left: 0,
                              right: 0,
                              bottom: 0,
                              child: Container(
                                padding: const EdgeInsets.fromLTRB(
                                  12,
                                  24,
                                  12,
                                  10,
                                ),
                                decoration: const BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      Colors.transparent,
                                      Colors.black87,
                                    ],
                                  ),
                                ),
                                child: Text(
                                  b.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          // 指示点
          if (items.length > 1)
            Positioned(
              bottom: 14,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(items.length, (i) {
                  final active = i == _current;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: active ? 16 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: active ? Colors.white : Colors.white54,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  );
                }),
              ),
            ),
        ],
      ),
    );
  }
}
