import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/theme.dart';
import '../data/models/song.dart';
import '../pages/player/player_page.dart';
import '../providers/player_provider.dart';
import 'rotating_cover.dart';

/// 底部迷你播放器
/// 始终显示当前播放歌曲,点击展开全屏播放页
class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerProvider>();
    final song = player.currentSong;

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 260),
      transitionBuilder: (child, animation) => SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 1),
          end: Offset.zero,
        ).animate(
          CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
        ),
        child: FadeTransition(opacity: animation, child: child),
      ),
      child: song == null
          ? const SizedBox.shrink(key: ValueKey('mini-empty'))
          : _buildPlayer(context, player, song),
    );
  }

  Widget _buildPlayer(BuildContext context, PlayerProvider player, Song song) {
    final theme = Theme.of(context);

    return GestureDetector(
      key: ValueKey('mini-${song.id}'),
      onTap: () {
        // 从下往上滑出播放页
        Navigator.of(context).push(
          PageRouteBuilder(
            // 关键:设为非不透明,让转场期间(尤其返回时)下方页面保持渲染,
            // 否则 opaque 路由会在转场结束后才渲染 HomeShell,
            // 表现就是「从播放页返回后整个页面闪白一下」。
            opaque: false,
            transitionDuration: const Duration(milliseconds: 360),
            reverseTransitionDuration: const Duration(milliseconds: 320),
            pageBuilder: (_, __, ___) => const PlayerPage(),
            transitionsBuilder: (_, animation, __, child) {
              final curved = CurvedAnimation(
                parent: animation,
                curve: Curves.easeOutCubic,
                reverseCurve: Curves.easeInCubic,
              );
              return SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 1),
                  end: Offset.zero,
                ).animate(curved),
                child: child,
              );
            },
          ),
        );
      },
      child: Container(
        height: 66,
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          // 彩色渐变背景:左上角带主题色 tint,向右下过渡到卡片底色
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppTheme.warm.withOpacity(0.22),
              AppTheme.accent.withOpacity(0.12),
              theme.cardTheme.color ?? theme.cardColor,
            ],
          ),
          border: Border.all(
            color: theme.colorScheme.primary.withOpacity(0.25),
          ),
          boxShadow: const [
            BoxShadow(color: Colors.black26, blurRadius: 16, offset: Offset(0, -3)),
            BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 2)),
          ],
        ),
        child: Stack(
          children: [
            Row(
              children: [
                const SizedBox(width: 10),
                RotatingCover(
                  imageUrl: song.coverUrl,
                  size: 46,
                  rotating: player.isPlaying,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          // 歌名前的彩色渐变竖条(播放状态点缀)
                          Container(
                            width: 3,
                            height: 14,
                            decoration: BoxDecoration(
                              gradient: AppTheme.miniGradient,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              song.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        song.singerName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.hintColor,
                        ),
                      ),
                    ],
                  ),
                ),
                player.switching || player.buffering
                    ? const SizedBox(
                        width: 40,
                        height: 40,
                        child: Padding(
                          padding: const EdgeInsets.all(9),
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(AppTheme.primary),
                          ),
                        ),
                      )
                    : IconButton(
                        icon: Icon(
                          player.isPlaying ? Icons.pause : Icons.play_arrow,
                          color: theme.colorScheme.primary,
                        ),
                        onPressed: () => context.read<PlayerProvider>().toggle(),
                      ),
                IconButton(
                  icon: const Icon(Icons.skip_next),
                  onPressed: () => context.read<PlayerProvider>().next(),
                ),
                const SizedBox(width: 4),
              ],
            ),
            // 底部进度条(渐变彩色)
            // 左右各内缩 14,避开容器 14 圆角,进度条自身两端用 1.5 半圆,
            // 不再被容器的 14 圆角削掉左端(之前左边会缺一块/越界)。
            Positioned(
              left: 14,
              right: 14,
              bottom: 0,
              child: StreamBuilder<Duration>(
                stream: player.positionStream,
                initialData: Duration.zero,
                builder: (context, snapshot) {
                  final pos = snapshot.data ?? Duration.zero;
                  final total = song.duration > 0 ? song.duration : 1;
                  final value = (pos.inMilliseconds / (total * 1000))
                      .clamp(0.0, 1.0);
                  return SizedBox(
                    height: 3,
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final w = constraints.maxWidth * value;
                        return Align(
                          alignment: Alignment.centerLeft,
                          child: Container(
                            width: w,
                            decoration: BoxDecoration(
                              gradient: AppTheme.miniGradient,
                              borderRadius: BorderRadius.circular(1.5),
                            ),
                          ),
                        );
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
