/// 歌词行
class LyricLine {
  final Duration timestamp;
  final String text;

  LyricLine({required this.timestamp, required this.text});
}

/// LRC 歌词解析
class LyricsParser {
  LyricsParser._();

  /// 匹配 [mm:ss.xx]文本,兼容 [mm:ss] / [mm:ss:xx]
  static final RegExp _reg =
      RegExp(r'\[(\d{1,2}):(\d{2})(?:[.:](\d{1,3}))?\]\s*(.*)');

  static List<LyricLine> parse(String lrc) {
    final lines = <LyricLine>[];
    if (lrc.isEmpty) return lines;

    for (final raw in lrc.split('\n')) {
      final match = _reg.firstMatch(raw.trim());
      if (match == null) continue;

      final minute = int.tryParse(match.group(1) ?? '') ?? 0;
      final second = int.tryParse(match.group(2) ?? '') ?? 0;
      final msRaw = match.group(3) ?? '';
      final millis = msRaw.isEmpty ? 0 : int.parse(msRaw.padRight(3, '0'));

      final text = (match.group(4) ?? '').trim();

      lines.add(
        LyricLine(
          timestamp: Duration(
            minutes: minute,
            seconds: second,
            milliseconds: millis,
          ),
          text: text,
        ),
      );
    }

    lines.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return lines;
  }

  /// 根据播放进度返回当前行索引(未开始返回 -1)
  static int indexAt(List<LyricLine> lines, Duration position) {
    if (lines.isEmpty) return -1;

    int index = -1;
    for (int i = 0; i < lines.length; i++) {
      if (lines[i].timestamp <= position) {
        index = i;
      } else {
        break;
      }
    }
    return index;
  }
}
