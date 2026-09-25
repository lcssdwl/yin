import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config/constants.dart';
import '../../config/theme.dart';

/// 关于 App
class AboutPage extends StatefulWidget {
  const AboutPage({super.key});

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  /// 从 pubspec.yaml 读到的真实版本号(动态获取,不会和打包版本脱节)
  String _version = '';

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((info) {
      if (!mounted) return;
      setState(() => _version = 'v${info.version}');
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('关于')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const SizedBox(height: 12),

          // Logo(多彩元素头像:圆形紫粉橙渐变 + 白色音符,与 App 图标一致)
          Center(
            child: Container(
              width: 88,
              height: 88,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: AppTheme.primaryGradient,
              ),
              child: const Icon(
                Icons.music_note_rounded,
                size: 46,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Center(
            child: Text(
              '云韵音乐',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 6),
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                _version,
                style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
          ),
          const SizedBox(height: 30),

          _card(
            context,
            title: '简介',
            child: const Text(
              '一款支持「免登录」使用的音乐播放器:\n'
              '· 游客可直接听歌、搜索、浏览\n'
              '· 登录后可云同步收藏、歌单与播放历史\n'
              '· 支持后台播放、锁屏控制、滚动歌词',
              style: TextStyle(fontSize: 13, height: 1.8),
            ),
          ),

          _card(
            context,
            title: '主要功能',
            child: Column(
              children: const [
                _InfoRow('音乐播放', '在线流媒体 · 后台播放 · 锁屏控制'),
                _InfoRow('歌词', 'LRC 逐行高亮滚动'),
                _InfoRow('歌单', '官方歌单 · 我的歌单 · 收藏'),
                _InfoRow('定时关闭', '倒计时 / 播完当前歌曲'),
                _InfoRow('主题', '浅色 / 深色 / 跟随系统'),
                _InfoRow('音质', '播放页可切换 · 标准 / 高品质 / 无损'),
              ],
            ),
          ),

          _card(
            context,
            title: '相关链接',
            child: Column(
              children: [
                _LinkRow(
                  icon: Icons.system_update_alt_rounded,
                  title: '下载 / 更新',
                  subtitle: 'Releases 里的安装包',
                  onTap: () => _openLink(AppConstants.releasesUrl),
                ),
                _LinkRow(
                  icon: Icons.language_rounded,
                  title: '项目主页',
                  subtitle: 'lcssdwl.github.io',
                  onTap: () => _openLink(AppConstants.homepageUrl),
                ),
              ],
            ),
          ),

          _card(
            context,
            title: '说明',
            child: Text(
              '本应用仅供学习交流使用,不含任何商业内容。',
              style: TextStyle(
                fontSize: 12,
                color: theme.hintColor,
                height: 1.8,
              ),
            ),
          ),

          const SizedBox(height: 26),
          Center(
            child: Text(
              '© 2026 云韵音乐 · 仅供学习交流',
              style: TextStyle(fontSize: 12, color: theme.hintColor),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  /// 用**系统浏览器**打开外链(不是应用内 WebView,用户能用上浏览器的
  /// 下载、书签等能力;Releases 页在应用内直接下载 APK 反而容易失败)
  Future<void> _openLink(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) {
      _toast('链接无效:$url');
      return;
    }
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && mounted) _toast('无法打开链接:$url');
    } catch (e) {
      _toast('打开链接失败:$e');
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Widget _card(
    BuildContext context, {
    required String title,
    required Widget child,
  }) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.dividerColor.withOpacity(0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

/// 可点击的外链行(图标 + 标题 + 说明 + 打开箭头)
class _LinkRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _LinkRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 18, color: theme.colorScheme.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 13)),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 11, color: theme.hintColor),
                  ),
                ],
              ),
            ),
            Icon(Icons.open_in_new, size: 16, color: theme.hintColor),
          ],
        ),
      ),
    );
  }
}

/// 左标题 + 右内容 的信息行
class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: TextStyle(fontSize: 13, color: theme.hintColor),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 13, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}
