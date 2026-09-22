import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';

import '../../config/constants.dart';
import '../../config/theme.dart';
import '../../core/audio/audio_effect.dart';
import '../../core/audio/lyrics_parser.dart';
import '../../core/log/app_log.dart';
import '../../core/utils/error_text.dart';
import '../../core/utils/json_util.dart';
import '../../data/models/playlist.dart';
import '../../data/models/song.dart';
import '../../data/repositories/playlist_repository.dart';
import '../../providers/auth_provider.dart';
import '../../providers/player_provider.dart';
import '../../widgets/audio_effect_sheet.dart';
import '../../widgets/center_toast.dart';
import '../../widgets/comment_sheet.dart';
import '../../widgets/playlist_name_dialog.dart';
import '../../widgets/rotating_cover.dart';
import '../login/login_page.dart';

/// 全屏播放页
/// 唱片旋转 + 歌词 + 播放控制 + 收藏(游客存本地)
class PlayerPage extends StatefulWidget {
  const PlayerPage({super.key});

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  /// 进度条拖动中的值(null = 未拖动,跟随播放进度)
  double? _dragValue;

  /// 已提示过的错误内容(避免重复弹)
  String? _shownError;

  /// 已写过「打开播放器」日志的歌曲(避免每帧重复写)
  int? _loggedSongId;

  /// 已记录过的封面加载失败(同一张图只记一次,避免刷屏)
  String? _loggedCoverError;

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerProvider>();
    final song = player.currentSong;

    // 播放错误提示(显示一次后清除)
    // 注意:「需登录才能播放」的拦截提示由全局弹窗(onRequireLogin)统一处理,
    // 这里只处理其它播放错误,避免重复弹窗。
    final err = player.errorMessage;
    if (err != null && err != _shownError) {
      _shownError = err;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (!player.needLogin) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(err), duration: const Duration(seconds: 4)),
          );
        }
        player.clearError();
      });
    }

    if (song == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('播放器')),
        body: const Center(child: Text('暂无播放歌曲')),
      );
    }

    // 排查用:每次进入播放器记一条(歌名 / 音质 / 封面 / 播放地址),
    // 出现黑屏或放不出声时,在「我的 → 运行日志」里能直接看到当时的关键信息。
    //
    // 注意:这里打的是**队列里还没解析的原始地址**,不代表真正拿去播的地址。
    // 真正播放的地址看随后的「用本地缓存 / 秒播 / 取流成功」那几条。
    if (song.id != _loggedSongId) {
      _loggedSongId = song.id;
      AppLog.add(
        '[player] 打开播放器 #${song.id} ${song.name} '
        '音质=${player.quality} '
        '封面=${song.cover.isEmpty ? "(空)" : song.cover} '
        '时长=${song.duration}s '
        '队列原始地址=${song.playUrl.isEmpty ? "(空,待联网解析)" : song.playUrl}',
      );
    }

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 模糊背景(封面缺失 / 加载失败时自动落回深色渐变,不会黑屏)
          _buildBackground(
            song,
            isDark: Theme.of(context).brightness == Brightness.dark,
          ),

          // 内容
          SafeArea(
            child: Column(
              children: [
                _buildAppBar(context, song),
                Expanded(
                  child: Column(
                    children: [
                      // 唱片(缩小,始终显示在上方)
                      const SizedBox(height: 8),
                      RotatingCover(
                        imageUrl: song.coverUrl,
                        size: 150,
                        rotating: player.isPlaying,
                      ),
                      const SizedBox(height: 4),
                      // 歌词(下方常驻,不用点击切换就直接显示)
                      Expanded(child: _buildLyricView(player)),
                    ],
                  ),
                ),
                _buildControls(context, player, song),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ==================== 背景 ====================

  Widget _buildBackground(Song song, {required bool isDark}) {
    final cover = song.cover.trim();
    final hasCover = cover.isNotEmpty;

    return Stack(
      fit: StackFit.expand,
      children: [
        // 1) 兜底底色(深紫渐变)。
        //
        // 这是「黑屏」的根治点:原来最底层什么都没有,只铺了一张模糊封面图。
        // 一旦封面为空、或图片没加载出来(断网 / 404 / 证书错误),
        // 整层就是透明的,直接透出 Scaffold 背景 —— 深色模式下即纯黑。
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF33235C), Color(0xFF120E1C)],
            ),
          ),
        ),

        // 2) 模糊封面。用 ImageFiltered 模糊封面图本身,而不是 BackdropFilter:
        //    BackdropFilter 会捕获它「后面」已绘制的内容做模糊 —— 播放页返回
        //    转场时,它会去模糊下方露出的 HomeShell,导致背面看起来是白的/糊的,
        //    而且合成开销大。ImageFiltered 只模糊封面图,不碰下方页面。
        //
        //    外面套 RepaintBoundary:大半径模糊开销很大,隔离成独立图层后
        //    切歌 / 拖动进度条时不会每帧重新光栅化,避免低端机上闪黑。
        if (hasCover)
          RepaintBoundary(
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 26, sigmaY: 26),
              child: Image(
                image: CachedNetworkImageProvider(cover),
                fit: BoxFit.cover,
                // 封面加载失败 → 只画底层渐变,并把失败原因写进运行日志
                errorBuilder: (_, __, error) {
                  if (_loggedCoverError != cover) {
                    _loggedCoverError = cover;
                    AppLog.add('[player] 封面加载失败 #${song.id} $cover → $error');
                  }
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),

        // 3) 遮罩:浅色模式(白色模式)下把黑色遮罩调浅,封面色彩透出来,不再黑乎乎;
        //    深色模式保持较重的遮罩压住背景,保证白字可读。
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: isDark
                  ? [
                      Colors.black.withOpacity(0.45),
                      Colors.black.withOpacity(0.72),
                    ]
                  : [
                      Colors.black.withOpacity(0.18),
                      Colors.black.withOpacity(0.42),
                    ],
            ),
          ),
        ),
      ],
    );
  }

  // ==================== 顶部 ====================

  Widget _buildAppBar(BuildContext context, Song song) {
    // 用 Stack 让标题相对整屏绝对居中:
    // 之前用 Row + Expanded,标题只会在「左右按钮之间的剩余空间」里居中,
    // 右侧有 2 个按钮而左侧只有 1 个,导致标题视觉上偏左。
    return SizedBox(
      height: 56,
      child: Stack(
        children: [
          // 标题(绝对居中)
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 100),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // 顶部彩色渐变装饰条
                  Container(
                    width: 36,
                    height: 3,
                    decoration: BoxDecoration(
                      gradient: AppTheme.primaryGradient,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 4),
                  // 歌名用主题渐变着色,顶部更出彩
                  ShaderMask(
                    shaderCallback: (bounds) =>
                        AppTheme.primaryGradient.createShader(bounds),
                    blendMode: BlendMode.srcIn,
                    child: Text(
                      song.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    song.singerName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 左侧:收起
          Align(
            alignment: Alignment.centerLeft,
            child: IconButton(
              icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),

          // 右侧:添加到歌单 + 收藏
          Align(
            alignment: Alignment.centerRight,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.playlist_add, color: Colors.white),
                  tooltip: '添加到歌单',
                  onPressed: () => _showAddToPlaylistSheet(context, song),
                ),
                Consumer<PlayerProvider>(
                  builder: (context, player, _) {
                    return IconButton(
                      icon: Icon(
                        player.isCurrentFavorite
                            ? Icons.favorite
                            : Icons.favorite_border,
                        color: player.isCurrentFavorite
                            ? Colors.redAccent
                            : Colors.white,
                      ),
                      onPressed: () => _toggleFavorite(context),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ==================== 歌词 ====================

  Widget _buildLyricView(PlayerProvider player) {
    final lines = player.lyricLines;

    if (lines.isEmpty) {
      return const Center(
        key: ValueKey('no-lyric'),
        child: Text(
          '暂无歌词',
          style: TextStyle(color: Colors.white70, fontSize: 15),
        ),
      );
    }

    return StreamBuilder<Duration>(
      key: const ValueKey('lyric'),
      stream: player.positionStream,
      initialData: Duration.zero,
      builder: (context, snapshot) {
        final position = snapshot.data ?? Duration.zero;
        final index = LyricsParser.indexAt(lines, position);

        // 当前行 + 前后各 2 行,当前行放大高亮
        final rows = <Widget>[];
        final start = (index - 2) < 0 ? 0 : index - 2;
        final end = (index + 2) >= lines.length ? lines.length - 1 : index + 2;

        for (int i = start; i <= end; i++) {
          final isCurrent = i == index;
          final text = Text(
            lines[i].text,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isCurrent ? Colors.white : Colors.white38,
              fontSize: isCurrent ? 19 : 14,
              fontWeight: isCurrent ? FontWeight.w700 : FontWeight.normal,
              height: 1.5,
            ),
          );

          rows.add(
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              // 当前行用主题渐变着色(紫→粉→橙),唱到哪一行就亮成彩色
              child: isCurrent
                  ? ShaderMask(
                      shaderCallback: (bounds) =>
                          AppTheme.primaryGradient.createShader(bounds),
                      blendMode: BlendMode.srcIn,
                      child: text,
                    )
                  : text,
            ),
          );
        }

        return Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: rows,
            ),
          ),
        );
      },
    );
  }

  // ==================== 控制区 ====================

  Widget _buildControls(BuildContext context, PlayerProvider player, Song song) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      child: Column(
        children: [
          // 进度条
          //
          // 时长优先用**播放器解析出来的值**(durationStream):
          // 数据库里的 duration 可能为 0(批量上传解析失败 / 手动填的没写时长),
          // 那样分母就变成 1,滑块永远算不出比例 —— 表现就是「进度条卡住不动」。
          StreamBuilder<Duration?>(
            stream: player.durationStream,
            builder: (context, durSnap) {
              final dbTotal = Duration(seconds: song.duration);
              final total = (durSnap.data != null && durSnap.data!.inSeconds > 0)
                  ? durSnap.data!
                  : dbTotal;
              final totalMs =
                  total.inMilliseconds > 0 ? total.inMilliseconds : 1;

              return StreamBuilder<Duration>(
                stream: player.positionStream,
                initialData: Duration.zero,
                builder: (context, snapshot) {
                  final pos = snapshot.data ?? Duration.zero;
                  final value = (pos.inMilliseconds / totalMs).clamp(0.0, 1.0);

                  return Column(
                    children: [
                      Slider(
                        value: (_dragValue ?? value).clamp(0.0, 1.0),
                        // 拖动过程只更新本地值,松手才真正 seek。
                        // 原来在 onChanged 里直接 seek:每帧都发请求,
                        // 且 positionStream 会立刻把滑块拉回旧位置 —— 表现为「拖不动/拖了不播」。
                        onChangeStart: (v) => setState(() => _dragValue = v),
                        onChanged: (v) => setState(() => _dragValue = v),
                        onChangeEnd: (v) async {
                          final ms = (v * totalMs).toInt();
                          setState(() => _dragValue = null);

                          // 拖到最末尾(距结尾 200ms 以内)当作「本曲结束」:
                          //   单曲循环 → 从头重新开始
                          //   顺序 / 随机 → 切歌
                          //
                          // 不能只靠 seek 到末尾触发 completed —— 实测播放器
                          // 停在末尾却不发 completed 事件,会卡住不动。
                          if (totalMs > 0 && ms >= totalMs - 200) {
                            debugPrint('[player] seek -> end');
                            await player.seekToEnd();
                            return;
                          }

                          debugPrint(
                              '[player] seek -> ${(ms / 1000).toStringAsFixed(1)}s');
                          await player.seek(Duration(milliseconds: ms));
                        },
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            formatDuration(pos.inSeconds),
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 12),
                          ),
                          Text(
                            total.inSeconds > 0
                                ? formatDuration(total.inSeconds)
                                : '--:--',
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 12),
                          ),
                        ],
                      ),
                    ],
                  );
                },
              );
            },
          ),

          const SizedBox(height: 8),

          // 音质 + 评论(放在进度条下方)
          // 「此音质需要登录」提示也常驻在这一区域
          _buildQualityCommentRow(context, player, song),

          const SizedBox(height: 10),

          // 控制按钮
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              // 播放模式
              IconButton(
                iconSize: 28,
                color: Colors.white,
                icon: Icon(_modeIcon(player.mode)),
                onPressed: () => player.switchMode(),
              ),
              // 上一首
              IconButton(
                iconSize: 34,
                color: Colors.white,
                icon: const Icon(Icons.skip_previous),
                onPressed: () => player.previous(),
              ),
              // 播放/暂停
              Container(
                width: 64,
                height: 64,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                ),
                child: player.switching || player.buffering
                    ? Padding(
                        padding: const EdgeInsets.all(18),
                        child: CircularProgressIndicator(
                          strokeWidth: 3,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(AppTheme.primary),
                        ),
                      )
                    : IconButton(
                        iconSize: 36,
                        color: AppTheme.primary,
                        icon: Icon(
                          player.isPlaying ? Icons.pause : Icons.play_arrow,
                        ),
                        onPressed: () => player.toggle(),
                      ),
              ),
              // 下一首
              IconButton(
                iconSize: 34,
                color: Colors.white,
                icon: const Icon(Icons.skip_next),
                onPressed: () => player.next(),
              ),
              // 播放列表
              IconButton(
                iconSize: 28,
                color: Colors.white,
                icon: const Icon(Icons.queue_music),
                onPressed: () => _showQueueSheet(context, player),
              ),
            ],
          ),

          const SizedBox(height: 10),

          // 底部:播放模式 + 定时关闭
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                player.mode.label,
                style: const TextStyle(color: Colors.white54, fontSize: 11),
              ),
              const SizedBox(width: 20),
              InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () => _showSleepSheet(context),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        player.sleepActive
                            ? Icons.timer
                            : Icons.timer_outlined,
                        size: 15,
                        color: player.sleepActive
                            ? Colors.amber
                            : Colors.white54,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        player.sleepActive
                            ? (player.sleepSecondsLeft > 0
                                ? '定时中 ${_fmtSleep(player.sleepSecondsLeft)}'
                                : '本首结束后停止')
                            : '定时关闭',
                        style: TextStyle(
                          fontSize: 11,
                          color: player.sleepActive
                              ? Colors.amber
                              : Colors.white54,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ==================== 音质 + 评论(进度条下方) ====================

  /// 进度条下方的操作区
  ///
  /// - 左侧:音质切换(默认「标准」,需登录的音质会提示)
  /// - 右侧:评论入口
  /// - 上侧:需登录提示(如「「无损」此音质需要登录后播放」),常驻同区域
  Widget _buildQualityCommentRow(
    BuildContext context,
    PlayerProvider player,
    Song song,
  ) {
    final loginHint = player.qualityLoginHint;
    final notice = player.qualityNotice;
    final noticeActual = player.qualityNoticeActual;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 需登录提示(常驻,可一键去登录)
        if (loginHint != null)
          _hintBanner(
            icon: Icons.lock_outline,
            color: Colors.amber,
            text: loginHint,
            actionLabel: '去登录',
            onAction: () {
              player.clearQualityLoginHint();
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const LoginPage()),
              );
            },
          ),

        // 音质提示:如「「标准」暂无音源,已用「高品质」播放」。
        //
        // 只做告知,不给按钮 —— 已经自动兜底播了,再让用户点一次
        // 「切到高品质」纯属多余(而且点了只是改设置项,听着没任何变化)。
        // 只有「取流失败」这类需要用户动作的提示(noticeActual 为空)才留「换个音质」。
        if (notice != null)
          _hintBanner(
            icon: Icons.info_outline,
            color: Colors.lightBlueAccent,
            text: notice,
            actionLabel: noticeActual == null ? '换个音质' : null,
            onAction: noticeActual == null
                ? () => _showQualitySheet(context, player)
                : null,
          ),

        Row(
          children: [
            // 音质:占左侧剩余空间。
            // 用 Expanded + Align 而不是 Spacer —— 后者不会让出宽度,
            // 窄屏 / 大字号下三个胶囊挤在一起就是「右边溢出」。
            // 现在空间不够只压缩「音质」的文字,右侧的评论 / 音效始终可读。
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: _bottomPill(
                  icon: Icons.high_quality,
                  label: '音质 · ${player.qualityLabel}',
                  onTap: () => _showQualitySheet(context, player),
                ),
              ),
            ),
            // 评论
            _bottomPill(
              icon: Icons.comment_outlined,
              label: '评论',
              onTap: () => showCommentSheet(
                context,
                targetId: song.id,
                targetType: 1,
              ),
            ),
            const SizedBox(width: 8),
            // 音效(均衡器):开启后直接显示音效名(如「重低音」),并主色高亮
            ListenableBuilder(
              listenable: AudioEffects.instance,
              builder: (_, __) {
                final fx = AudioEffects.instance;
                return _bottomPill(
                  icon: Icons.graphic_eq,
                  label: fx.enabled ? fx.preset.label : '音效',
                  active: fx.enabled,
                  onTap: () => showAudioEffectSheet(context),
                );
              },
            ),
          ],
        ),
      ],
    );
  }

  /// 播放页底部的小提示条(「需登录」/「音质回退」共用)
  ///
  /// [actionLabel] 为空时不显示右侧操作 —— 纯告知类提示不需要按钮。
  Widget _hintBanner({
    required IconData icon,
    required Color color,
    required String text,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.35),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white24),
      ),
      child: Row(
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
          ),
          // 没有操作时连间距一起省掉,文字自然占满整条
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(width: 8),
            GestureDetector(
              onTap: onAction,
              child: Text(
                actionLabel,
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _bottomPill({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool active = false,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          // 开启状态用主色填充(如「音效」已生效),否则保持半透明白
          color: active
              ? AppTheme.primary
              : Colors.white.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: Colors.white),
            const SizedBox(width: 6),
            // 允许在极窄屏 / 大字号下省略号收尾,而不是溢出
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 音质选择面板:需登录的音质显示锁标与「需要登录」
  void _showQualitySheet(BuildContext context, PlayerProvider player) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: Consumer<PlayerProvider>(
            builder: (sheetCtx, p, _) {
              final nav = Navigator.of(sheetCtx);
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
                    child: Column(
                      children: [
                        const Text(
                          '播放音质',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        // 所选档位这首歌没有音源时,明确写出"实际在放哪一档",
                        // 免得用户以为选了就真的在放那一档
                        if (p.qualityFallback) ...[
                          const SizedBox(height: 4),
                          Text(
                            '「${p.labelOfQuality(p.quality)}」暂无音源,'
                            '当前播放「${p.qualityLabel}」',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(sheetCtx).hintColor,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  ...p.qualityOptions.map((q) {
                    final selected = q.value == p.quality;
                    final locked = p.qualityNeedsLogin(q.value);
                    // 列表已下发分音质地址时,能直接看出这首歌有没有该音质。
                    // (扫描/转码生成分音质文件需要时间,没生成时这里标「暂无音源」)
                    final has = p.currentSongHasQuality(q.value);
                    final unavailable = has == false;
                    final primary = Theme.of(sheetCtx).colorScheme.primary;
                    // 发生回退时,真正在放的那一档标出来
                    final playing =
                        p.qualityFallback && q.value == p.actualQuality;
                    return ListTile(
                      leading: Icon(
                        locked
                            ? Icons.lock_outline
                            : (unavailable
                                ? Icons.music_off_outlined
                                : Icons.music_note),
                        color: selected ? primary : null,
                      ),
                      title: Text(q.label),
                      subtitle: locked
                          ? const Text('需要登录')
                          : (unavailable
                              ? const Text('暂无音源')
                              : (playing
                                  ? Text(
                                      '当前播放中',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: primary,
                                      ),
                                    )
                                  : null)),
                      trailing: selected
                          ? Icon(Icons.check_circle, color: primary, size: 20)
                          : null,
                      onTap: () async {
                        // 需登录的音质不会切换,关闭面板后由底部常驻提示「此音质需要登录」
                        await p.setQuality(q.value);
                        nav.pop();
                      },
                    );
                  }),
                  const SizedBox(height: 8),
                ],
              );
            },
          ),
        );
      },
    );
  }

  IconData _modeIcon(PlayMode mode) {
    switch (mode) {
      case PlayMode.sequence:
        return Icons.repeat;
      case PlayMode.single:
        return Icons.repeat_one;
      case PlayMode.shuffle:
        return Icons.shuffle;
    }
  }

  // ==================== 收藏 ====================

  Future<void> _toggleFavorite(BuildContext context) async {
    final player = context.read<PlayerProvider>();
    final auth = context.read<AuthProvider>();
    final song = player.currentSong;
    if (song == null) return;

    final result = await player.toggleFavorite(song.id);
    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          auth.isLoggedIn
              ? (result ? '已收藏到「默认收藏」' : '已从「默认收藏」移除')
              : (result
                  ? '已收藏到「默认收藏」(本地),登录可云同步'
                  : '已从「默认收藏」移除'),
        ),
      ),
    );
  }

  // ==================== 添加到歌单 ====================

  Future<void> _showAddToPlaylistSheet(BuildContext context, Song song) async {
    final auth = context.read<AuthProvider>();
    if (!auth.isLoggedIn) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('登录后可以把歌曲添加到自己的歌单')),
      );
      return;
    }

    List<Playlist> myPlaylists = [];
    try {
      myPlaylists = await PlaylistRepository().getMyPlaylists();
    } catch (_) {}

    if (!context.mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: SizedBox(
          height: MediaQuery.of(ctx).size.height * 0.55,
          child: Column(
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  '添加到歌单',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
              // 默认收藏(歌曲默认收藏夹)
              ListTile(
                leading: const Icon(Icons.favorite, color: Colors.redAccent),
                title: const Text('默认收藏'),
                subtitle: const Text('收藏的歌曲默认都存这里'),
                onTap: () {
                  Navigator.pop(ctx);
                  _toggleFavorite(context);
                },
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.add),
                title: const Text('新建歌单并添加'),
                onTap: () {
                  Navigator.pop(ctx);
                  _createPlaylistAndAdd(context, song);
                },
              ),
              const Divider(height: 1),
              Expanded(
                child: myPlaylists.isEmpty
                    ? const Center(
                        child: Text(
                          '还没有创建歌单,先新建一个吧',
                          style: TextStyle(color: Colors.grey),
                        ),
                      )
                    : ListView(
                        children: myPlaylists
                            .map((p) => _addableTile(ctx, context, p, song))
                            .toList(),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _addableTile(
    BuildContext sheetCtx,
    BuildContext pageCtx,
    Playlist p,
    Song song,
  ) {
    return ListTile(
      leading: const Icon(Icons.queue_music),
      title: Text(p.name),
      subtitle: Text('${p.songCount} 首'),
      onTap: () async {
        Navigator.pop(sheetCtx);
        try {
          await PlaylistRepository().addSong(p.id, song.id);
          if (pageCtx.mounted) {
            ScaffoldMessenger.of(pageCtx).showSnackBar(
              SnackBar(content: Text('已添加到「${p.name}」')),
            );
          }
        } catch (e) {
          if (pageCtx.mounted) {
            showCenterToast(
              pageCtx,
              '添加失败:${friendlyError(e)}',
              error: true,
            );
          }
        }
      },
    );
  }

  /// 新建歌单并立即把当前歌曲加进去
  Future<void> _createPlaylistAndAdd(BuildContext context, Song song) async {
    final name = await showPlaylistNameDialog(
      context,
      confirmLabel: '创建并添加',
    );
    if (name == null || name.isEmpty) return;
    if (!context.mounted) return;

    try {
      final pid = await PlaylistRepository().create(name);
      if (pid > 0) {
        await PlaylistRepository().addSong(pid, song.id);
      }
      if (context.mounted) {
        showCenterToast(context, '已添加到歌单「$name」');
      }
    } catch (e) {
      if (context.mounted) {
        // 只显示后端给的业务文案(不要 ApiException(...) 这种开发者内容)
        showCenterToast(context, '创建失败:${friendlyError(e)}', error: true);
      }
    }
  }

  // ==================== 播放队列 ====================

  void _showQueueSheet(BuildContext context, PlayerProvider player) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) {
        return _QueueSheet(
          queue: List<Song>.of(player.queue),
          currentIndex: player.currentIndex,
          onPick: (index) {
            Navigator.pop(ctx);
            // 点当前这首只是关掉面板,不重头播
            if (index != player.currentIndex) {
              player.playAt(index);
            }
          },
        );
      },
    );
  }

  /// 定时关闭面板
  void _showSleepSheet(BuildContext context) {
    final player = context.read<PlayerProvider>();

    showModalBottomSheet(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: Consumer<PlayerProvider>(
            builder: (context, p, _) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      '定时关闭',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  if (p.sleepSecondsLeft > 0)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Text(
                        '将在 ${_fmtSleep(p.sleepSecondsLeft)} 后暂停播放',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ListTile(
                    leading: const Icon(Icons.close),
                    title: const Text('关闭定时'),
                    onTap: () {
                      player.cancelSleepTimer();
                      Navigator.pop(ctx);
                    },
                  ),
                  ...[15, 30, 60].map(
                    (m) => ListTile(
                      leading: const Icon(Icons.timer_outlined),
                      title: Text('$m 分钟'),
                      onTap: () {
                        player.startSleepTimer(m);
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('已设置 $m 分钟后暂停播放')),
                        );
                      },
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.music_note_outlined),
                    title: const Text('本首歌结束后'),
                    onTap: () {
                      player.setSleepEndOfSong(true);
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('本首歌结束后将停止播放')),
                      );
                    },
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  /// 秒 → mm:ss
  String _fmtSleep(int seconds) {
    final d = Duration(seconds: seconds);
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }
}

/// 播放列表面板
///
/// 两处体验:
///   - 打开时自动滚动到「正在播放」那一首并尽量居中,长队列不用自己往下翻
///   - 当前项用与歌词当前行一致的渐变着色(紫→粉→橙),一眼看到播到哪
class _QueueSheet extends StatefulWidget {
  const _QueueSheet({
    required this.queue,
    required this.currentIndex,
    required this.onPick,
  });

  final List<Song> queue;
  final int currentIndex;
  final ValueChanged<int> onPick;

  @override
  State<_QueueSheet> createState() => _QueueSheetState();
}

class _QueueSheetState extends State<_QueueSheet> {
  /// 行高固定:定位是按「第几行 × 行高」算偏移的,行高必须确定。
  /// 所以这里不用 ListTile —— 它的高度会随主题 visualDensity 变化,
  /// 用 itemExtent 硬压还可能把内容压溢出。自己拼固定高度的行最稳。
  static const double _rowHeight = 64;

  final ScrollController _controller = ScrollController();

  @override
  void initState() {
    super.initState();
    // 等首帧布局完成再定位:这时 viewportDimension / maxScrollExtent 才是准的。
    // 不用 initialScrollOffset 的原因:队列不满一屏时它会先滚出去再弹回来。
    WidgetsBinding.instance.addPostFrameCallback((_) => _locateCurrent());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 滚动到当前播放项:尽量让它落在视口中间
  void _locateCurrent() {
    if (!mounted || !_controller.hasClients) return;
    final index = widget.currentIndex;
    // 第 1 首或越界时不用滚(本来就在最上面)
    if (index <= 0 || index >= widget.queue.length) return;

    final position = _controller.position;
    final target =
        index * _rowHeight - (position.viewportDimension - _rowHeight) / 2;
    _controller.jumpTo(target.clamp(0.0, position.maxScrollExtent));
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                const Text(
                  '播放列表',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  '共 ${widget.queue.length} 首',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
          Flexible(
            child: ListView.builder(
              controller: _controller,
              shrinkWrap: true,
              itemExtent: _rowHeight,
              itemCount: widget.queue.length,
              itemBuilder: (context, index) => _buildRow(context, index),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildRow(BuildContext context, int index) {
    final s = widget.queue[index];
    final isCurrent = index == widget.currentIndex;

    // 序号徽标:当前项用主题渐变填充,其余用调色板淡色底
    final badge = Container(
      width: 28,
      height: 28,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        // color 与 gradient 不能同时给,所以按状态二选一
        gradient: isCurrent ? AppTheme.primaryGradient : null,
        color: isCurrent ? null : AppTheme.paletteAt(index).withOpacity(0.14),
      ),
      child: Text(
        '${index + 1}',
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          // 渐变底上必须是白字,否则会和底色糊在一起
          color: isCurrent ? Colors.white : AppTheme.paletteAt(index),
        ),
      ),
    );

    final title = Text(
      s.name,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 15,
        // 当前项先铺白字,再由 ShaderMask 上渐变(与歌词当前行同一套做法)
        color: isCurrent ? Colors.white : null,
        fontWeight: isCurrent ? FontWeight.w700 : FontWeight.normal,
      ),
    );

    return InkWell(
      onTap: () => widget.onPick(index),
      child: SizedBox(
        height: _rowHeight,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              badge,
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 正在播放:套歌词同款渐变着色
                    isCurrent
                        ? ShaderMask(
                            shaderCallback: (bounds) =>
                                AppTheme.primaryGradient.createShader(bounds),
                            blendMode: BlendMode.srcIn,
                            child: title,
                          )
                        : title,
                    const SizedBox(height: 2),
                    Text(
                      s.singerName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
