import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/network/api_exception.dart';
import '../data/models/comment.dart';
import '../data/repositories/comment_repository.dart';
import '../providers/auth_provider.dart';
import 'login_guide_sheet.dart';

/// 评论底部弹窗:列表 + 发评论 + 点赞
///
/// [targetId] 目标 ID(如歌曲 ID),[targetType] 目标类型(1=歌曲)
void showCommentSheet(
  BuildContext context, {
  required int targetId,
  int targetType = 1,
}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _CommentSheet(targetId: targetId, targetType: targetType),
  );
}

class _CommentSheet extends StatefulWidget {
  final int targetId;
  final int targetType;

  const _CommentSheet({required this.targetId, required this.targetType});

  @override
  State<_CommentSheet> createState() => _CommentSheetState();
}

class _CommentSheetState extends State<_CommentSheet> {
  final CommentRepository _repo = CommentRepository();
  final TextEditingController _ctrl = TextEditingController();

  List<CommentModel> _list = [];
  bool _loading = true;
  String? _error;
  String _sort = 'hot';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await _repo.getList(
        widget.targetId,
        targetType: widget.targetType,
        sort: _sort,
      );
      if (mounted) setState(() => _list = list);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = '加载失败,请稍后重试');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _submit() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;

    final auth = context.read<AuthProvider>();
    if (!auth.isLoggedIn) {
      _showLogin();
      return;
    }

    _ctrl.clear();
    try {
      final c = await _repo.add(
        widget.targetId,
        text,
        targetType: widget.targetType,
      );
      if (mounted) setState(() => _list.insert(0, c));
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = '发送失败,请稍后重试');
    }
  }

  Future<void> _like(CommentModel c) async {
    final auth = context.read<AuthProvider>();
    if (!auth.isLoggedIn) {
      _showLogin();
      return;
    }
    try {
      final liked = await _repo.like(c.id);
      if (mounted) {
        setState(() {
          final idx = _list.indexWhere((e) => e.id == c.id);
          if (idx >= 0) {
            _list[idx] = _list[idx].copyWith(
              isLiked: liked,
              likeCount: _list[idx].likeCount + (liked ? 1 : -1),
            );
          }
        });
      }
    } catch (_) {
      // 点赞失败静默处理
    }
  }

  void _showLogin() {
    // 统一走全局的居中登录引导弹窗(两个按钮同高,样式一致)
    showLoginGuide(context, '登录后才能发表评论 / 点赞');
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return Container(
      height: mq.size.height * 0.75,
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Row(
              children: [
                Text('评论 (${_list.length})',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold)),
                const Spacer(),
                TextButton(
                  onPressed: () {
                    setState(() => _sort = _sort == 'hot' ? 'new' : 'hot');
                    _load();
                  },
                  child: Text(_sort == 'hot' ? '最热' : '最新'),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(child: _buildList()),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Text(_error!,
                  style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
            ),
          const Divider(height: 1),
          _buildInput(),
        ],
      ),
    );
  }

  Widget _buildList() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_list.isEmpty) {
      return const Center(child: Text('还没有评论,快来抢沙发'));
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _list.length,
      separatorBuilder: (_, __) =>
          const Divider(height: 1, indent: 16, endIndent: 16),
      itemBuilder: (_, i) => _buildItem(_list[i]),
    );
  }

  Widget _buildItem(CommentModel c) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundImage:
                    c.avatar.isNotEmpty ? NetworkImage(c.avatar) : null,
                child: c.avatar.isEmpty
                    ? const Icon(Icons.person, size: 16)
                    : null,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(c.nickname,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 14)),
              ),
              GestureDetector(
                onTap: () => _like(c),
                child: Row(
                  children: [
                    Icon(
                      c.isLiked ? Icons.favorite : Icons.favorite_border,
                      size: 16,
                      color: c.isLiked ? Colors.redAccent : Colors.grey,
                    ),
                    const SizedBox(width: 4),
                    Text('${c.likeCount}',
                        style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(c.content, style: const TextStyle(fontSize: 14)),
          const SizedBox(height: 4),
          Text(c.createTime,
              style: const TextStyle(fontSize: 11, color: Colors.grey)),
          if (c.replies.isNotEmpty)
            ...c.replies.map(
              (r) => Padding(
                padding: const EdgeInsets.only(top: 6, left: 24),
                child: Text(
                  '${r.nickname}: ${r.content}',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildInput() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _ctrl,
                decoration: InputDecoration(
                  hintText: '说点什么...',
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  isCollapsed: true,
                ),
                onSubmitted: (_) => _submit(),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: _submit,
              child: const Text('发送'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }
}
