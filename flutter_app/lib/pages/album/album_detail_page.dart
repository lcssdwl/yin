import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';

import '../../data/models/album.dart';
import '../../data/models/song.dart';
import '../../data/repositories/music_repository.dart';
import '../../providers/player_provider.dart';
import '../../widgets/song_tile.dart';
import '../singer/singer_detail_page.dart';

/// 专辑详情页(🟢 游客可查看并播放)
class AlbumDetailPage extends StatefulWidget {
  final int id;

  const AlbumDetailPage({super.key, required this.id});

  @override
  State<AlbumDetailPage> createState() => _AlbumDetailPageState();
}

class _AlbumDetailPageState extends State<AlbumDetailPage> {
  final MusicRepository _repo = MusicRepository();
  late Future<_AlbumData> _future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _future = _fetch();
  }

  Future<_AlbumData> _fetch() async {
    final album = await _repo.getAlbumDetail(widget.id);
    final songs = await _repo.getAlbumSongs(widget.id);
    return _AlbumData(album, songs);
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
        const SnackBar(content: Text('该专辑暂无歌曲')),
      );
      return;
    }
    context.read<PlayerProvider>().playQueue(songs, 0);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('专辑')),
      body: FutureBuilder<_AlbumData>(
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
            return _errorView('没有拿到专辑数据');
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
            const Text('专辑加载失败'),
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

  Widget _buildContent(_AlbumData data) {
    final album = data.album;
    final songs = data.songs;
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.only(bottom: 90),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: CachedNetworkImage(
                  imageUrl: album.cover,
                  width: 120,
                  height: 120,
                  fit: BoxFit.cover,
                  errorWidget: (_, __, ___) => Container(
                    width: 120,
                    height: 120,
                    color: Colors.grey.shade300,
                    child: const Icon(Icons.album, size: 40),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      album.name,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    if (album.singerName.isNotEmpty)
                      GestureDetector(
                        onTap: album.singerId > 0
                            ? () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        SingerDetailPage(id: album.singerId),
                                  ),
                                )
                            : null,
                        child: Text(
                          '歌手:${album.singerName} >',
                          style: TextStyle(
                            fontSize: 13,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ),
                    const SizedBox(height: 6),
                    Text(
                      '${songs.length} 首'
                      '${album.publishDate.isEmpty ? '' : ' · ${album.publishDate.substring(0, album.publishDate.length >= 10 ? 10 : album.publishDate.length)}'}',
                      style: TextStyle(fontSize: 12, color: theme.hintColor),
                    ),
                    if (album.intro.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        album.intro,
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
            child: Center(child: Text('该专辑暂无歌曲')),
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

class _AlbumData {
  final Album album;
  final List<Song> songs;

  _AlbumData(this.album, this.songs);
}
