import 'package:flutter/foundation.dart';

import 'album.dart';
import 'playlist.dart';
import 'singer.dart';
import 'song.dart';

/// 搜索结果聚合
@immutable
class SearchResult {
  final List<Song> songs;
  final List<Singer> singers;
  final List<Album> albums;
  final List<Playlist> playlists;

  const SearchResult({
    this.songs = const [],
    this.singers = const [],
    this.albums = const [],
    this.playlists = const [],
  });

  bool get isEmpty =>
      songs.isEmpty && singers.isEmpty && albums.isEmpty && playlists.isEmpty;
}
