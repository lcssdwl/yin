import 'package:flutter/material.dart';

import 'discover_page.dart';
import 'library_page.dart';
import '../search/search_page.dart';
import '../../widgets/mini_player.dart';

/// 主框架(底部 Tab)
/// Tab:发现 / 搜索 / 我的
/// 底部固定显示迷你播放器
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell>
    with SingleTickerProviderStateMixin {
  int _currentIndex = 0;

  /// 「我的」页的 key,用于切 tab 时触发它刷新歌单
  final GlobalKey<LibraryPageState> _libraryKey = GlobalKey<LibraryPageState>();

  late final List<Widget> _pages = [
    const DiscoverPage(),
    const SearchPage(),
    LibraryPage(key: _libraryKey),
  ];

  /// Tab 切换动画:淡入 + 轻微上滑
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 240),
  );
  late final Animation<double> _fade =
      CurvedAnimation(parent: _controller, curve: Curves.easeOut);
  late final Animation<Offset> _slide = Tween<Offset>(
    begin: const Offset(0, 0.02),
    end: Offset.zero,
  ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));

  @override
  void initState() {
    super.initState();
    // 初始不透明,首页正常显示;只有切 tab 时才从头播放动画
    _controller.value = 1.0;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _switchTab(int index) {
    if (index == _currentIndex) return;
    setState(() => _currentIndex = index);
    // 切到「我的」就刷新歌单:这里用 IndexedStack 常驻,
    // 页面不会重建,不主动刷就会停留在旧的收藏列表
    if (index == 2) {
      _libraryKey.currentState?.refresh();
    }
    _controller.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FadeTransition(
        opacity: _fade,
        child: SlideTransition(
          position: _slide,
          child: IndexedStack(
            index: _currentIndex,
            children: _pages,
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const MiniPlayer(),
            BottomNavigationBar(
              currentIndex: _currentIndex,
              onTap: _switchTab,
              items: const [
                BottomNavigationBarItem(
                  icon: Icon(Icons.library_music_outlined),
                  activeIcon: Icon(Icons.library_music),
                  label: '发现',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.search_outlined),
                  activeIcon: Icon(Icons.search),
                  label: '搜索',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.person_outline),
                  activeIcon: Icon(Icons.person),
                  label: '我的',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
