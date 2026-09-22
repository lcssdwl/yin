import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'config/constants.dart';
import 'config/theme.dart';
import 'core/audio/audio_cache.dart';
import 'core/audio/audio_handler.dart';
import 'core/audio/audio_service_status.dart';
import 'core/network/dio_client.dart';
import 'core/storage/storage_service.dart';
import 'core/usage/app_usage.dart';
import 'core/utils/permission_helper.dart';
import 'pages/splash/splash_page.dart';
import 'providers/auth_provider.dart';
import 'providers/player_provider.dart';
import 'providers/theme_provider.dart';
import 'widgets/login_guide_sheet.dart';

/// 全局播放引擎
late MusicAudioHandler audioHandler;

/// 全局导航 key(点击通知后跳转播放页)
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 全局错误兜底:避免异常导致白屏
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
  };

  // 本地存储(超时/失败都不阻塞启动)
  try {
    await StorageService.init().timeout(const Duration(seconds: 5));
    print('BOOT: storage ok');
  } catch (_) {
    print('BOOT: storage failed');
  }

  // 网络层
  DioClient.instance.init();
  print('BOOT: dio ok');

  // App 使用统计:上报一次「打开」,之后每 90 秒一次心跳(后端据此算在线)
  unawaited(AppUsage.start());
  print('BOOT: app usage reporting started');

  // 清理上次运行遗留的「播放临时明文」(加密缓存保留)
  unawaited(AudioCache.clearTemp());
  print('BOOT: audio cache temp cleared');

  // 清理旧版按「歌曲 ID」命名的缓存:
  // ID 会随后端重扫/重建而变,一变老缓存就会被别的歌认领(串歌),
  // 现在缓存键改成音频指纹,旧文件永远命不中,顺手删掉
  unawaited(AudioCache.purgeLegacy());
  print('BOOT: audio cache legacy purge started');

  // 申请通知/存储权限
  // 关键:必须在 AudioService 初始化之前,否则 Android 13+ 不显示播放通知
  try {
    await PermissionHelper.requestOnStart()
        .timeout(const Duration(seconds: 20));
    print('BOOT: permission ok');
  } catch (_) {
    print('BOOT: permission failed');
  }

  // 关键:通知必须带一个实色 —— Android 13/14 的 SystemUI 会拿 notification.color
  // 给媒体按钮图标着色,默认 0 就是透明(按钮能点但看不见)。
  //
  // 通知主色:见下方 AudioServiceConfig 里的说明。

  // 系统媒体通知(MediaSession)—— 必须用 audio_service 初始化。
  // 配合 targetSdk 33 规避 Android 14+ 对前台媒体服务的限制。
  // 桌面端(Windows/Linux)与 Web 无 audio_service 原生实现,
  // 直接降级为普通播放器,避免 AudioService.init 的 10s 超时等待。
  final bool isDesktop = Platform.isWindows || Platform.isLinux;
  try {
    if (isDesktop) {
      audioHandler = MusicAudioHandler();
      audioServiceReady = false;
      print('BOOT: audio service skipped (desktop)');
    } else {
      audioHandler = await AudioService.init<MusicAudioHandler>(
        builder: () => MusicAudioHandler(),
      config: AudioServiceConfig(
        // 关键:必须指定通知小图标,而且必须是**真正的 PNG 位图**。
        // 不指定时原生端拿到的是 null → setSmallIcon(0) →
        // notify() 抛 "Invalid notification (no valid small icon)",
        // 通知是残缺的,媒体按钮就画不出来(iQOO 上的表现就是按钮透明)。
        androidNotificationIcon: 'drawable/ic_stat_music',

        // 通知主色:iQOO 的 SystemUI 拿它当主色再算配对的前景(按钮)色,
        // 给深色前景就会算成白 → 在浅底通知上等于隐形,所以这里给浅色。
        // 注意不能用 0xFFFFFFFF:它在 Java 里等于 -1,会被当成「没设置」。
        notificationColor: const Color(0xFFF5F5F5),
        androidNotificationChannelId: 'com.yunyun.music.channel.audio',
        androidNotificationChannelName: '音乐播放',
        androidNotificationChannelDescription: '播放控制(上一首 / 播放暂停 / 下一首)',
        // 注意:这里不要再指定 androidNotificationIcon ——
        // 换成矢量图后部分 ROM 直接不显示媒体通知,用默认的 mipmap/ic_launcher 最稳
        // 关键:让前台服务常驻(暂停也不停止),避免 MIUI 反复 start/stop
        // 抵消 MediaSession 的 setActive(true) —— 否则妙播会把会话当作未激活而丢弃
        androidNotificationOngoing: false,
        androidShowNotificationBadge: true,
        androidStopForegroundOnPause: false,
      ),
      ).timeout(const Duration(seconds: 10));
      audioServiceReady = true;
      print('BOOT: audio service ok');
    }
  } catch (e) {
    // 系统通知起不来时降级为本地通知兜底
    audioHandler = MusicAudioHandler();
    audioServiceReady = false;
    print('BOOT: audio service failed: $e');
  }

  // 恢复登录态(无 token 则保持游客)
  final authProvider = AuthProvider();
  try {
    await authProvider.init().timeout(const Duration(seconds: 5));
    print('BOOT: auth ok');
  } catch (_) {
    print('BOOT: auth failed');
  }

  // 401 回调:登录失效时退回游客态
  DioClient.instance.onUnauthorized = authProvider.handleUnauthorized;

  // 播放器
  final playerProvider = PlayerProvider(audioHandler, authProvider);
  // 未登录播放被「需登录才能播放」拦截时,用全局 navigator 弹登录引导,
  // 覆盖首页 / 搜索 / 歌单等任意页面发起的播放,不依赖 PlayerPage 是否挂载。
  playerProvider.onRequireLogin = (message) {
    final ctx = appNavigatorKey.currentContext;
    if (ctx != null) showLoginGuide(ctx, message);
  };
  unawaited(playerProvider.loadFavorites());
  // 拉取后台音质策略(供播放页底部提示「此音质需要登录」)
  unawaited(playerProvider.loadAppConfig());

  // 退到后台时先把当前这首先听的秒数上报掉,否则这段听歌时间会丢
  AppLifecycleListener(
    onPause: () => unawaited(playerProvider.flushListen()),
  );

  final themeProvider = ThemeProvider();
  try {
    await themeProvider.load().timeout(const Duration(seconds: 3));
    print('BOOT: theme ok');
  } catch (_) {
    print('BOOT: theme failed');
  }

  print('BOOT: runApp');

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
        ChangeNotifierProvider<ThemeProvider>.value(value: themeProvider),
        ChangeNotifierProvider<PlayerProvider>.value(value: playerProvider),
      ],
      child: const MyApp(),
    ),
  );
}


class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();

    return MaterialApp(
      title: AppConstants.appName,
      navigatorKey: appNavigatorKey,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeProvider.mode,
      home: const SplashPage(),
    );
  }
}
