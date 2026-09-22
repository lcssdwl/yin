import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/theme.dart';
import '../../core/network/api_exception.dart';
import '../../data/repositories/user_repository.dart';
import '../../providers/auth_provider.dart';

/// 修改密码(独立页面)
///
/// 修改成功后服务端会清空所有会话,因此这里会主动退出登录并返回上一页。
class ChangePasswordPage extends StatefulWidget {
  const ChangePasswordPage({super.key});

  @override
  State<ChangePasswordPage> createState() => _ChangePasswordPageState();
}

class _ChangePasswordPageState extends State<ChangePasswordPage> {
  final _oldCtrl = TextEditingController();
  final _newCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();

  bool _obscureOld = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _oldCtrl.dispose();
    _newCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final oldPwd = _oldCtrl.text.trim();
    final newPwd = _newCtrl.text.trim();
    final confirm = _confirmCtrl.text.trim();

    if (oldPwd.isEmpty || newPwd.isEmpty || confirm.isEmpty) {
      setState(() => _error = '请填写完整');
      return;
    }
    if (newPwd.length < 6) {
      setState(() => _error = '新密码至少 6 位');
      return;
    }
    if (newPwd != confirm) {
      setState(() => _error = '两次输入的新密码不一致');
      return;
    }
    if (oldPwd == newPwd) {
      setState(() => _error = '新密码不能与原密码相同');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      await UserRepository().changePassword(oldPwd, newPwd);
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('密码已修改,请用新密码重新登录')),
      );

      // 服务端已清空会话,这里同步退出登录
      await context.read<AuthProvider>().logout();
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = e is ApiException ? e.message : '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('修改密码')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 12),
            // 顶部彩色图标 + 标题 + 副标题(与登录页同款)
            const Icon(
              Icons.lock_reset,
              size: 64,
              color: AppTheme.primary,
            ),
            const SizedBox(height: 12),
            Text(
              '修改密码',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              '修改后所有设备需重新登录',
              textAlign: TextAlign.center,
              style: TextStyle(color: theme.hintColor, fontSize: 13),
            ),
            const SizedBox(height: 26),

            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 18,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '修改成功后,所有设备都会退出登录,需要用新密码重新登录。',
                      style: TextStyle(fontSize: 12, color: theme.hintColor),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 26),

            _field(
              controller: _oldCtrl,
              label: '原密码',
              icon: Icons.lock_outline,
              obscure: _obscureOld,
              onToggle: () => setState(() => _obscureOld = !_obscureOld),
            ),
            const SizedBox(height: 16),
            _field(
              controller: _newCtrl,
              label: '新密码(至少 6 位)',
              icon: Icons.lock_reset,
              obscure: _obscureNew,
              onToggle: () => setState(() => _obscureNew = !_obscureNew),
            ),
            const SizedBox(height: 16),
            _field(
              controller: _confirmCtrl,
              label: '确认新密码',
              icon: Icons.verified_outlined,
              obscure: _obscureConfirm,
              onToggle: () =>
                  setState(() => _obscureConfirm = !_obscureConfirm),
            ),

            if (_error != null) ...[
              const SizedBox(height: 20),
              Container(
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
                        _error!,
                        style: const TextStyle(
                          color: Colors.redAccent,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 30),
            SizedBox(
              height: 48,
              child: ElevatedButton(
                onPressed: _submitting ? null : _submit,
                child: _submitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('确认修改'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    required bool obscure,
    required IconData icon,
    required VoidCallback onToggle,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      decoration: AppTheme.inputDecoration(
        Theme.of(context),
        label: label,
        icon: icon,
        suffixIcon: IconButton(
          icon: Icon(
            obscure ? Icons.visibility_off : Icons.visibility,
            size: 20,
          ),
          onPressed: onToggle,
        ),
      ),
    );
  }
}
