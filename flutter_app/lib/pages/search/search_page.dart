import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/theme.dart';
import '../../data/models/search_result.dart';
import '../../data/repositories/music_repository.dart';
import '../../providers/player_provider.dart';
import '../../widgets/song_tile.dart';
import '../common/song_list_page.dart';
import '../playlist/playlist_detail_page.dart';

/// 搜索页(🟢 游客可搜索)
class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final MusicRepository _repo = MusicRepository();
  final TextEditingController _controller = TextEditingController();

  List<String> _hotWords = [];
  SearchResult? _result;
  bool _searching = false;
  bool _hasSearched = false;

  @override
  void initState() {
    super.initState();
    _loadHotWords();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadHotWords() async {
    try {
      final words = await _repo.getHotWords();
      if (!mounted) return;
      setState(() => _hotWords = words);
    } catch (_) {
      // 忽略
    }
  }

  Future<void> _search(String keyword) async {
    final kw = keyword.trim();
    if (kw.isEmpty) return;

    setState(() {
      _searching = true;
      _hasSearched = true;
    });

    try {
      final result = await _repo.search(kw);
      if (!mounted) return;
      setState(() {
        _result = result;
        _searching = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _searching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          textInputAction: TextInputAction.search,
          onSubmitted: _search,
          decoration: InputDecoration(
            hintText: '搜索歌曲、歌手、歌单',
            isDense: true,
            filled: true,
            prefixIcon: const Icon(Icons.search, size: 20),
            suffixIcon: _controller.text.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.clear, size: 20),
                    onPressed: () {
                      _controller.clear();
                      setState(() {
                        _hasSearched = false;
                        _result = null;
                      });
                    },
                  ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(24),
              borderSide: BorderSide.none,
            ),
          ),
        ),
      ),
      body: _searching
          ? const Center(child: CircularProgressIndicator())
          : (!_hasSearched ? _buildHot() : _buildResult()),
    );
  }

  /// 热搜词(小胶囊标签)
  Widget _buildHot() {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          '热门搜索',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _hotWords.map((w) {
            return GestureDetector(
              onTap: () {
                _controller.text = w;
                _search(w);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 13,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: primary.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  w,
                  style: TextStyle(fontSize: 13, color: primary),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  /// 搜索结果
  Widget _buildResult() {
    final result = _result;
    if (result == null || result.isEmpty) {
      return const Center(child: Text('没有找到相关内容'));
    }

    final player = context.read<PlayerProvider>();

    return ListView(
      padding: const EdgeInsets.only(bottom: 20),
      cacheExtent: 1600,
      children: [
        if (result.songs.isNotEmpty) ...[
          _sectionTitle('单曲'),
          ...result.songs.asMap().entries.map(
            (e) => SongTile(
              song: e.value,
              index: e.key,
              onTap: () => player.playSong(e.value, playlist: result.songs),
            ),
          ),
        ],
        if (result.singers.isNotEmpty) ...[
          _sectionTitle('歌手'),
          ...result.singers.asMap().entries.map((e) {
            final s = e.value;
            final c = AppTheme.paletteAt(e.key);
            return ListTile(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              leading: CircleAvatar(
                radius: 22,
                backgroundColor: c.withOpacity(0.15),
                child: Text(
                  s.name.isNotEmpty ? s.name[0] : '歌',
                  style: TextStyle(
                    color: c,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              title: Text(s.name),
              subtitle: Text('${s.songCount} 首歌曲'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => SongListPage(
                      title: s.name,
                      futureSongs: _repo.getSingerSongs(s.id),
                    ),
                  ),
                );
              },
            );
          }),
        ],
        if (result.playlists.isNotEmpty) ...[
          _sectionTitle('歌单'),
          ...result.playlists.asMap().entries.map((e) {
            final p = e.value;
            final c = AppTheme.paletteAt(e.key);
            return ListTile(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              leading: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.network(
                  p.coverUrl,
                  width: 48,
                  height: 48,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [c.withOpacity(0.5), c],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: const Icon(Icons.album_outlined, color: Colors.white),
                  ),
                ),
              ),
              title: Text(p.name),
              subtitle: Text('${p.songCount} 首'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => PlaylistDetailPage(id: p.id),
                  ),
                );
              },
            );
          }),
        ],
      ],
    );
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
      child: Text(
        title,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
      ),
    );
  }
}
