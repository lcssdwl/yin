import 'package:flutter/material.dart';

import '../config/theme.dart';
import 'dialog_actions.dart';

/// 「新建歌单」输入弹窗
///
/// 返回用户输入的歌单名(取消 / 关闭返回 null)。
/// 与登录引导弹窗同一套观感:彩色渐变图标 + 圆角卡片 + 同高按钮,
/// 输入框复用全局的 [AppTheme.inputDecoration]。
Future<String?> showPlaylistNameDialog(
  BuildContext context, {
  String title = '新建歌单',
  String confirmLabel = '创建',
  String hint = '给歌单起个名字',
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _PlaylistNameDialog(
      title: title,
      confirmLabel: confirmLabel,
      hint: hint,
    ),
  );
}

class _PlaylistNameDialog extends StatefulWidget {
  final String title;
  final String confirmLabel;
  final String hint;

  const _PlaylistNameDialog({
    required this.title,
    required this.confirmLabel,
    required this.hint,
  });

  @override
  State<_PlaylistNameDialog> createState() => _PlaylistNameDialogState();
}

class _PlaylistNameDialogState extends State<_PlaylistNameDialog> {
  /// 名字长度上限(与后端一致)
  static const int _maxLen = 30;

  final _controller = TextEditingController();
  bool _canSubmit = false;

  @override
  void initState() {
    super.initState();
    // 空名字不给提交:直接置灰按钮,而不是点了再报错
    _controller.addListener(() {
      final ok = _controller.text.trim().isNotEmpty;
      if (ok != _canSubmit) setState(() => _canSubmit = ok);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _controller.text.trim();
    if (name.isEmpty) return;
    Navigator.pop(context, name);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: AppTheme.primaryGradient,
              ),
              child: const Icon(
                Icons.playlist_add,
                color: Colors.white,
                size: 26,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              widget.title,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 18),
            TextField(
              controller: _controller,
              autofocus: true,
              maxLength: _maxLen,
              textInputAction: TextInputAction.done,
              style: const TextStyle(fontSize: 15),
              onSubmitted: (_) => _submit(),
              decoration: AppTheme.inputDecoration(
                theme,
                label: '歌单名称',
                icon: Icons.queue_music,
                hint: widget.hint,
                helper: '最多 $_maxLen 个字',
              ).copyWith(counterText: ''),
            ),
            const SizedBox(height: 10),
            DialogActionRow(
              cancelLabel: '取消',
              confirmLabel: widget.confirmLabel,
              onCancel: () => Navigator.pop(context),
              onConfirm: _canSubmit ? _submit : null,
            ),
          ],
        ),
      ),
    );
  }
}
