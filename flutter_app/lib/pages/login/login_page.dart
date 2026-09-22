import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/theme.dart';
import '../../providers/auth_provider.dart';

/// 登录 / 注册页
///
/// 免登录原则:本页只在用户主动触发(收藏/评论/进入我的)时才出现,
/// 且提供"先去逛逛"直接返回,不强制登录
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nicknameController = TextEditingController();

  bool _isLogin = true;
  bool _obscure = true;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _nicknameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final auth = context.read<AuthProvider>();
    final username = _usernameController.text.trim();
    final password = _passwordController.text;

    try {
      if (_isLogin) {
        await auth.login(username, password);
      } else {
        await auth.register(
          username,
          password,
          nickname: _nicknameController.text.trim().isEmpty
              ? null
              : _nicknameController.text.trim(),
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (_) {
      // 错误信息已存入 auth.error,由页面内联提示展示
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(_isLogin ? '登录' : '注册'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 20),
                const Icon(
                  Icons.music_note_rounded,
                  size: 64,
                  color: AppTheme.primary,
                ),
                const SizedBox(height: 12),
                Text(
                  '云韵音乐',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                Text(
                  '登录后可云同步收藏与歌单',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: theme.hintColor, fontSize: 13),
                ),
                const SizedBox(height: 32),

                // 用户名
                TextFormField(
                  controller: _usernameController,
                  decoration: AppTheme.inputDecoration(
                    theme,
                    label: '用户名',
                    icon: Icons.person_outline,
                  ),
                  validator: (v) {
                    final s = v?.trim() ?? '';
                    if (s.isEmpty) return '请输入用户名';
                    if (s.length < 3) return '至少 3 个字符';
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // 昵称(仅注册)
                if (!_isLogin) ...[
                  TextFormField(
                    controller: _nicknameController,
                    decoration: AppTheme.inputDecoration(
                      theme,
                      label: '昵称(可选)',
                      icon: Icons.badge_outlined,
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // 密码
                TextFormField(
                  controller: _passwordController,
                  obscureText: _obscure,
                  decoration: AppTheme.inputDecoration(
                    theme,
                    label: '密码',
                    icon: Icons.lock_outline,
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscure ? Icons.visibility_off : Icons.visibility,
                        size: 20,
                      ),
                      onPressed: () =>
                          setState(() => _obscure = !_obscure),
                    ),
                  ),
                  validator: (v) {
                    final s = v ?? '';
                    if (s.isEmpty) return '请输入密码';
                    if (s.length < 6) return '至少 6 位';
                    return null;
                  },
                ),
                const SizedBox(height: 20),

                // 错误提示(友好文案,直接展示后端业务提示)
                if (auth.error != null) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.error_outline,
                          size: 18,
                          color: Colors.redAccent,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            auth.error!,
                            style: const TextStyle(
                              color: Colors.redAccent,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],

                // 提交
                SizedBox(
                  height: 48,
                  child: ElevatedButton(
                    onPressed: auth.loading ? null : _submit,
                    child: auth.loading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(_isLogin ? '登录' : '注册'),
                  ),
                ),
                const SizedBox(height: 16),

                // 切换登录/注册
                TextButton(
                  onPressed: () => setState(() => _isLogin = !_isLogin),
                  child: Text(
                    _isLogin ? '还没有账号?去注册' : '已有账号?去登录',
                  ),
                ),
                const SizedBox(height: 8),

                // 免登录入口
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(
                    '先去逛逛(免登录也能听歌)',
                    style: TextStyle(color: theme.hintColor),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
