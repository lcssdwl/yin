import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../config/api_config.dart';
import '../../core/network/dio_client.dart';
import '../home/home_shell.dart';

/// 首次启动 / 「我的设置」里设置后端服务器地址。
/// 默认填入开发者示例地址,用户可改为自己的后端地址。
///
/// 保存前会探测 [ApiConfig.apiPrefix]/ping:仅当返回 code==200 才允许保存 / 进入首页。
class SetupAddressPage extends StatefulWidget {
  /// fromSettings=true 表示从「我的设置」进入,保存后返回上一页;
  /// 否则为首次启动引导,保存后进入首页。
  final bool fromSettings;

  const SetupAddressPage({super.key, this.fromSettings = false});

  @override
  State<SetupAddressPage> createState() => _SetupAddressPageState();
}

class _SetupAddressPageState extends State<SetupAddressPage> {
  final _controller = TextEditingController();
  String? _error;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    _controller.text = ApiConfig.baseUrl;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final url = _controller.text.trim();
    if (url.isEmpty) {
      setState(() => _error = '地址不能为空');
      return;
    }

    setState(() {
      _checking = true;
      _error = null;
    });

    // 探测服务可用性:对填写地址直接 GET /api/v1/ping,要求返回 code==200
    try {
      final pingUrl =
          url.endsWith('/') ? '${url}api/v1/ping' : '$url/api/v1/ping';
      final resp = await DioClient.instance.dio.get(
        pingUrl,
        options: Options(
          receiveTimeout: const Duration(seconds: 8),
          sendTimeout: const Duration(seconds: 8),
        ),
      );
      final body = resp.data;
      if (body is! Map || body['code'] != 200) {
        throw Exception('服务返回异常');
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _checking = false;
        _error = '无法连接该地址的服务,请确认地址正确且服务可用';
      });
      return;
    }

    if (!mounted) return;
    setState(() => _checking = false);

    await DioClient.instance.setBaseUrl(url);
    if (widget.fromSettings) {
      Navigator.of(context).pop();
    } else {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const HomeShell()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('服务器地址')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.fromSettings ? '修改后端服务器地址' : '设置后端服务器地址',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              '默认填入开发者示例服务(120.55.41.66:8000)。若你有自己的后端,'
              '请改成对应地址后保存。保存时会自动探测服务可用性。',
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _controller,
              enabled: !_checking,
              decoration: InputDecoration(
                labelText: '后端地址',
                hintText: 'http://ip:port',
                errorText: _error,
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.dns_outlined),
              ),
              keyboardType: TextInputType.url,
              autofocus: !widget.fromSettings,
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _checking ? null : _save,
                child: _checking
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(widget.fromSettings ? '保存' : '保存并进入'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
