import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';

import '../../data/models/singer.dart';
import '../../data/models/song.dart';
import '../../data/repositories/music_repository.dart';
import '../../providers/player_provider.dart';
import '../../widgets/song_tile.dart';

/// 歌手详情页(🟢 游客可查看并播放)
class SingerDetailPage extends StatefulWidget {
  final int id;

  const SingerDetailPage({super.key, required this.id});

  @override
  State<SingerDetailPage> createState() => _SingerDetailPageState();
}

class _SingerDetailPageState extends State<SingerDetailPage> {
  final MusicRepository _repo = MusicRepository();
  late Future<_SingerData> _future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _future = _fetch();
  }

  Future<_SingerData> _fetch() async {
    final singer = await _repo.getSingerDetail(widget.id);

    // 详情接口若已带热门歌曲就直接用,否则单独拉歌曲列表
    List<Song> songs = singer.hotSongs;
    if (songs.isEmpty) {
      songs = await _repo.getSingerSongs(widget.id);
    }
    return _SingerData(singer, songs);
  }

  Future<void> _refresh() async {
    setState(_load);
    try {
      await _future;
    } catch (_) {}
  }

  void _playAll(List<Song> songs) {
    if (songs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('该歌手暂无歌曲')),
      );
      return;
    }
    context.read<PlayerProvider>().playQueue(songs, 0);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('歌手')),
      body: FutureBuilder<_SingerData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _errorView('${snapshot.error}');
          }
          final data = snapshot.data;
          if (data == null) {
            return _errorView('没有拿到歌手数据');
          }
          return RefreshIndicator(
            onRefresh: _refresh,
            child: _buildContent(data),
          );
        },
      ),
    );
  }

  Widget _errorView(String msg) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48),
            const SizedBox(height: 12),
            const Text('歌手加载失败'),
            const SizedBox(height: 8),
            Text(
              msg,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => setState(_load),
              child: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(_SingerData data) {
    final singer = data.singer;
    final songs = data.songs;
    final theme = Theme.of(context);
    final avatar = singer.avatar.isNotEmpty ? singer.avatar : singer.cover;

    return ListView(
      padding: const EdgeInsets.only(bottom: 90),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipOval(
                child: CachedNetworkImage(
                  imageUrl: avatar,
                  width: 96,
                  height: 96,
                  fit: BoxFit.cover,
                  errorWidget: (_, __, ___) => Container(
                    width: 96,
                    height: 96,
                    color: Colors.grey.shade300,
                    child: const Icon(Icons.person, size: 40),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      singer.name,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      [
                        if (singer.area.isNotEmpty) singer.area,
                        '${songs.length} 首歌',
                        if (singer.fansCount > 0) '${singer.fansCount} 粉丝',
                      ].join(' · '),
                      style: TextStyle(fontSize: 12, color: theme.hintColor),
                    ),
                    if (singer.intro.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        singer.intro,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: theme.hintColor),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: SizedBox(
            width: double.infinity,
            height: 44,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.play_arrow),
              label: const Text('播放全部'),
              onPressed: () => _playAll(songs),
            ),
          ),
        ),
        if (songs.isEmpty)
          const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: Text('该歌手暂无歌曲')),
          )
        else
          ...songs.asMap().entries.map((e) {
            return SongTile(
              song: e.value,
              index: e.key,
              onTap: () => context.read<PlayerProvider>().playSong(
                    e.value,
                    playlist: songs,
                  ),
            );
          }),
      ],
    );
  }
}

class _SingerData {
  final Singer singer;
  final List<Song> songs;

  _SingerData(this.singer, this.songs);
}
