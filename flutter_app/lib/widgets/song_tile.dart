import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../config/theme.dart';
import '../core/utils/json_util.dart';
import '../data/models/song.dart';

/// 歌曲列表项
class SongTile extends StatelessWidget {
  final Song song;
  final int? index;
  final bool highlight;
  final VoidCallback? onTap;
  final VoidCallback? onMore;
  final Widget? trailing;

  const SongTile({
    super.key,
    required this.song,
    this.index,
    this.highlight = false,
    this.onTap,
    this.onMore,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;

    return ListTile(
      onTap: onTap,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: index != null
          ? Container(
              width: 28,
              height: 28,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                // 序号用多彩色板轮换,前几首红橙黄绿,列表更生动
                color: highlight
                    ? primary.withOpacity(0.16)
                    : AppTheme.paletteAt(index!).withOpacity(0.14),
              ),
              child: Text(
                '${index! + 1}',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: highlight ? primary : AppTheme.paletteAt(index!),
                ),
              ),
            )
          : ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: CachedNetworkImage(
                imageUrl: song.coverUrl,
                width: 48,
                height: 48,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) => Container(
                  width: 48,
                  height: 48,
                  color: Colors.grey.shade300,
                  child: const Icon(Icons.music_note, size: 20),
                ),
              ),
            ),
      title: Text(
        song.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: highlight ? primary : null,
        ),
      ),
      subtitle: Text(
        song.subtitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 13, color: theme.hintColor),
      ),
      trailing: trailing ??
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                formatDuration(song.duration),
                style: TextStyle(fontSize: 12, color: theme.hintColor),
              ),
              if (onMore != null)
                IconButton(
                  icon: const Icon(Icons.more_vert, size: 20),
                  onPressed: onMore,
                ),
            ],
          ),
    );
  }
}
