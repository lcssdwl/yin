import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../../data/models/song.dart';
import 'audio_effect.dart';

/// 音频服务
///
/// 基于 audio_service + just_audio:
/// - 后台播放(前台服务)
/// - 通知栏 / 锁屏 / 蓝牙耳机控制
/// - 向系统广播播放状态与媒体信息
class MusicAudioHandler extends BaseAudioHandler with SeekHandler {
  /// 音效(均衡器 / 响度增强)必须在**构造播放器时**就挂进 pipeline ——
  /// just_audio 没有运行时替换 pipeline 的接口,晚一步就挂不上了。
  /// 非 Android 平台内部返回空 pipeline,不挂任何 Android 专用 effect。
  final AudioPlayer player = AudioPlayer(
    audioPipeline: AudioEffects.instance.createPipeline(),
  );

  /// 切歌回调(由 PlayerProvider 注入,因为队列逻辑在 Provider 里)
  VoidCallback? onSkipNext;
  VoidCallback? onSkipPrevious;
  VoidCallback? onComplete;

  /// 播放出错回调(常见:24bit FLAC 等本机解码器不支持的格式)
  VoidCallback? onPlaybackError;

  /// 收藏切换回调(由 PlayerProvider 注入)
  Future<void> Function()? onToggleFavorite;

  /// 指定歌曲是否收藏(由 PlayerProvider 注入)
  bool Function(int)? isFavorite;

  /// 当前播放歌曲的 id(从 mediaItem.extras 取)
  int? get _currentSongId {
    final item = mediaItem.value;
    if (item == null) return null;
    return item.extras?['songId'] as int?;
  }

  Timer? _ticker;
  int _lastTickSecond = -1;

  MusicAudioHandler() {
    // 恢复上次选中的音效(存储此时已初始化)
    AudioEffects.instance.loadSaved();
    _listen();
  }

  /// 按 1Hz 主动推送进度
  ///
  /// 系统通知的进度条理论上可由 MediaSession 自行推算,但部分 ROM(尤其 Android 13+)
  /// 只在收到新的 PlaybackState 时重绘,所以这里主动喂一次。
  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!player.playing) return;
      final pos = player.position;

      if (pos.inSeconds == _lastTickSecond) return;
      _lastTickSecond = pos.inSeconds;
      playbackState.add(
        playbackState.value.copyWith(
          updatePosition: pos,
          bufferedPosition: player.bufferedPosition,
          speed: player.speed,
        ),
      );
    });
  }

  void _stopTicker() => _ticker?.cancel();

  void _listen() {
    player.playbackEventStream.listen(
      (_) => _emitPlaybackState(),
      onError: (Object e, StackTrace st) {
        debugPrint('[audio] playback error: $e');

        // abort / Connection aborted 通常是「切歌时上一个请求被取消」,
        // 属于正常现象,不是真的播放失败 ——
        // 若当成失败处理会触发无谓的重试与切歌。
        final msg = e.toString().toLowerCase();
        if (msg.contains('abort')) {
          debugPrint('[audio] ignore abort (cancelled by skip)');
          return;
        }

        onPlaybackError?.call();
      },
    );

    player.processingStateStream.listen((state) {
      debugPrint('[audio] state=$state playing=${player.playing} '
          'pos=${player.position.inSeconds}s dur=${player.duration?.inSeconds}s');

      if (state == ProcessingState.completed) {
        onComplete?.call();
      }
    });
  }

  /// 载入歌曲(不自动播放)
  ///
  /// playUrl 可能是网络签名地址,也可能是本地缓存文件路径 ——
  /// 本地文件必须用 setFilePath,否则 just_audio 会当成 URL 解析而失败。
  Future<void> loadSong(Song song) async {
    debugPrint('[audio] loadSong #${song.id} 「${song.name}」');
    mediaItem.add(_toMediaItem(song));

    // ★ Windows 必须先对齐播放状态再换源(见 _alignBeforeLoad 的说明)。
    //   顺序很重要:先 pause(把两边拉平)→ 再 setUrl/setFilePath。
    await _alignBeforeLoad();

    final source = song.playUrl;

    try {
      // setUrl/setFilePath 的返回值就是解析出的时长,比 player.duration
      // (durationStream 当前值,可能还没 emit)更可靠。
      Duration? duration;
      if (source.startsWith('http')) {
        duration = await player.setUrl(source);
      } else {
        duration = await player.setFilePath(
          source.startsWith('file://') ? Uri.parse(source).toFilePath() : source,
        );
      }

      final realDuration = duration ?? player.duration;
      debugPrint('[audio] loadSong ok dur=${realDuration?.inSeconds}s '
          '(song.duration=${song.duration})');

      // 时长以播放器实测为准:接口给的 duration 可能是 0(列表接口常不下发),
      // 而 MediaItem.duration == 0 时系统通知不会渲染进度条。
      if (realDuration != null &&
          realDuration.inSeconds > 0 &&
          realDuration.inSeconds != song.duration) {
        mediaItem.add(_toMediaItem(song).copyWith(duration: realDuration));
      }

      _startTicker();

      // 音效:设备的频段表要等播放器激活后才拿得到,所以每次载歌成功都推一次。
      // 还没挂上 / 非 Android / 拿不到频段表时,内部会自己跳过,不影响播放。
      unawaited(AudioEffects.instance.apply());
    } catch (e) {
      debugPrint('[audio] loadSong ERROR: $e');
      rethrow;
    }
  }

  /// Windows:换源前把播放状态对齐(其它平台什么都不做)
  ///
  /// 为什么必须做:
  ///   Windows 端 just_audio 走 WinRT MediaPlayer(WMF)。给 `MediaPlayer.Source`
  ///   赋值(= 换源)会让 WMF **立刻回到暂停态**并回报 `playing=false`;
  ///   而 just_audio 核心的 `playing` 这时还是 true(它只认 pause/平台事件)。
  ///   于是换源后会有一个「核心说在播、WMF 没出声」的窗口 —— 界面显示暂停图标
  ///   但没有声音,用户此时点播放按钮,toggle() 看到 `playing==true` 就当成
  ///   「要暂停」,真的把它按停了:表现就是「点播放反而变暂停,再点一次才响」。
  ///
  ///   在换源**之前**先 pause,能让两边状态始终一致:
  ///   后面那次 play() 才是真正会下发到平台的请求(core 的 play() 第一行是
  ///   `if (playing) return;`,状态不一致时它是空转的)。
  Future<void> _alignBeforeLoad() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.windows) return;
    if (!player.playing) return;
    try {
      await player.pause();
      debugPrint('[audio] Windows 换源前已暂停:核心与 WMF 状态对齐');
    } catch (e) {
      debugPrint('[audio] 换源前 pause 失败(不影响继续换源): $e');
    }
  }

  Future<void> setQueue(List<Song> songs, {int index = 0}) async {
    queue.add(songs.map(_toMediaItem).toList());
  }

  MediaItem _toMediaItem(Song song) => MediaItem(
        id: song.id.toString(),
        title: song.name,
        artist: song.singerName.isNotEmpty ? song.singerName : '未知歌手',
        album: song.albumName,
        duration: Duration(seconds: song.duration),
        artUri: Uri.parse(song.coverUrl),
        extras: {'songId': song.id},
      );

  // ==================== 控制 ====================

  @override
  Future<void> play() => player.play();

  @override
  Future<void> pause() => player.pause();

  @override
  Future<void> seek(Duration position) => player.seek(position);

  @override
  Future<void> stop() async {
    await player.stop();
    await super.stop();
  }

  @override
  Future<void> skipToNext() async {
    onSkipNext?.call();
  }

  @override
  Future<void> skipToPrevious() async {
    onSkipPrevious?.call();
  }

  /// 构造通知栏控件列表:上一首 / 播放暂停 / 下一首 / 收藏(心形,放最右边)
  List<MediaControl> _buildControls() {
    final songId = _currentSongId;
    final fav = songId != null && (isFavorite?.call(songId) ?? false);
    return [
      MediaControl.skipToPrevious,
      if (player.playing) MediaControl.pause else MediaControl.play,
      MediaControl.skipToNext,
      MediaControl.custom(
        androidIcon: fav
            ? 'drawable/audio_service_heart_filled'
            : 'drawable/audio_service_heart',
        label: '收藏',
        name: 'favorite',
      ),
    ];
  }

  /// 广播播放状态给系统(通知栏/锁屏)
  void _emitPlaybackState() {
    playbackState.add(
      playbackState.value.copyWith(
        controls: _buildControls(),
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
        },
        androidCompactActionIndices: const [0, 1, 2],
        processingState: const {
          ProcessingState.idle: AudioProcessingState.idle,
          ProcessingState.loading: AudioProcessingState.loading,
          ProcessingState.buffering: AudioProcessingState.buffering,
          ProcessingState.ready: AudioProcessingState.ready,
          ProcessingState.completed: AudioProcessingState.completed,
        }[player.processingState]!,
        playing: player.playing,
        updatePosition: player.position,
        bufferedPosition: player.bufferedPosition,
        speed: player.speed,
      ),
    );
  }

  /// 在收藏状态变化后主动刷新通知栏(含收藏图标)
  void refreshControls() => _emitPlaybackState();

  /// 通知栏自定义动作(如收藏)的入口
  @override
  Future<dynamic> customAction(String action, [Map<String, dynamic>? extras]) async {
    if (action == 'favorite') {
      await onToggleFavorite?.call();
      _emitPlaybackState(); // 刷新收藏图标(空心/实心)
      return;
    }
    return super.customAction(action, extras);
  }

  /// 强制激活 MediaSession
  ///
  /// MIUI 等 ROM 下,audio_service 内部的 setActive(true) 可能未生效,
  /// 导致系统(妙播/媒体中心)看到 active=false 而把会话当作"暂停"。
  /// 这里通过"先广播未播放、再广播播放",触发它内部的 enterPlayingState()
  /// (该逻辑只在 playing 由 false 变 true 时执行)。
  Future<void> ensureSessionActive() async {
    if (!player.playing) return;

    playbackState.add(playbackState.value.copyWith(playing: false));
    await Future.delayed(const Duration(milliseconds: 60));
    playbackState.add(
      playbackState.value.copyWith(
        playing: true,
        processingState: AudioProcessingState.ready,
        updatePosition: player.position,
        bufferedPosition: player.bufferedPosition,
      ),
    );
  }

  Future<void> dispose() async {
    _stopTicker();
    await player.dispose();
  }
}
