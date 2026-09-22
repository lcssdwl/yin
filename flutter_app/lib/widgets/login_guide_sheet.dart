import 'package:flutter/material.dart';

import '../config/theme.dart';
import '../pages/login/login_page.dart';
import 'dialog_actions.dart';

/// 统一的「需要登录」引导弹窗(屏幕居中)
///
/// 在两种场景复用:
/// 1. 播放被后端「需登录才能播放」拦截(由 PlayerProvider.onRequireLogin 全局触发)
/// 2. 发表评论 / 点赞前未登录(comment_sheet 调用)
///
/// 之前是从底部弹的 sheet:容易被播放条 / 输入框压住,也容易被当成无关提示划走。
/// 现在改成居中对话框,两个按钮放在同高的槽里(高度必然一致),观感更整齐。
void showLoginGuide(BuildContext context, String message) {
  showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => _LoginGuideDialog(message: message),
  );
}

class _LoginGuideDialog extends StatelessWidget {
  /// 提示文案(由调用方给出,如「请先登录后播放」)
  final String message;

  const _LoginGuideDialog({required this.message});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 图标:彩色渐变圆 + 白色锁,和 App 的多彩主视觉呼应
            Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: AppTheme.primaryGradient,
              ),
              child: const Icon(
                Icons.lock_outline,
                color: Colors.white,
                size: 30,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '需要登录',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                height: 1.5,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            DialogActionRow(
              cancelLabel: '稍后',
              confirmLabel: '立即登录',
              onCancel: () => Navigator.pop(context),
              onConfirm: () {
                // 先取到 Navigator 再关弹窗:关掉之后本 context 会失效,
                // 那时再 Navigator.of(context) 会踩到「已卸载的祖先」
                final nav = Navigator.of(context);
                nav.pop();
                nav.push(MaterialPageRoute(builder: (_) => const LoginPage()));
              },
            ),
          ],
        ),
      ),
    );
  }
}
