import 'package:flutter/material.dart';

import '../../core/log/app_log.dart';

/// 运行日志
///
/// 缓存下载 / 加密 / MD5 校验等环节的记录都在这里,
/// 排查问题时直接看这份,界面上不再弹提示打扰。
class LogPage extends StatefulWidget {
  const LogPage({super.key});

  @override
  State<LogPage> createState() => _LogPageState();
}

class _LogPageState extends State<LogPage> {
  @override
  void initState() {
    super.initState();
    AppLog.version.addListener(_onChanged);
  }

  @override
  void dispose() {
    AppLog.version.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lines = AppLog.lines;

    return Scaffold(
      appBar: AppBar(
        title: const Text('运行日志'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: '清空',
            onPressed: () {
              AppLog.clear();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('日志已清空')),
              );
            },
          ),
        ],
      ),
      body: lines.isEmpty
          ? Center(
              child: Text(
                '暂无日志',
                style: TextStyle(color: theme.hintColor),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: lines.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: SelectableText(
                  lines[i],
                  style: const TextStyle(fontSize: 12, height: 1.4),
                ),
              ),
            ),
    );
  }
}
