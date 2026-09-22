import 'package:flutter/material.dart';

import '../config/theme.dart';

/// 对话框底部的一对按钮:「取消(描边) / 主操作(彩色渐变)」
///
/// 两个按钮都放进固定高度的槽里 —— 否则主操作按钮会被主题的垂直 padding
/// 顶得更高,出现"一高一矮"。
class DialogActionRow extends StatelessWidget {
  final String cancelLabel;
  final String confirmLabel;
  final VoidCallback onCancel;

  /// 主操作回调;传 null 表示不可点(如输入为空)
  final VoidCallback? onConfirm;

  /// 按钮高度(两个按钮共用)
  final double height;

  /// 两个按钮之间的间距
  final double gap;

  const DialogActionRow({
    super.key,
    required this.cancelLabel,
    required this.confirmLabel,
    required this.onCancel,
    required this.onConfirm,
    this.height = 46,
    this.gap = 12,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final radius = BorderRadius.circular(height / 2);
    final enabled = onConfirm != null;

    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: height,
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                foregroundColor: theme.colorScheme.onSurfaceVariant,
                side: BorderSide(color: theme.colorScheme.outlineVariant),
                shape: RoundedRectangleBorder(borderRadius: radius),
              ),
              onPressed: onCancel,
              child: Text(cancelLabel),
            ),
          ),
        ),
        SizedBox(width: gap),
        Expanded(
          child: SizedBox(
            height: height,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: enabled ? AppTheme.primaryGradient : null,
                color: enabled ? null : theme.colorScheme.surfaceContainerHighest,
                borderRadius: radius,
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: radius,
                  onTap: onConfirm,
                  child: Center(
                    child: Text(
                      confirmLabel,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: enabled
                            ? Colors.white
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
