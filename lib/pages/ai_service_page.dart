import 'package:flutter/material.dart';
import '../services/storage_service.dart';

// AI 服务配置：只保存小米 MiMo API Key 到手机本地。
// 语音识别与大模型请求都在手机上完成，设备端不再保存任何密钥。
class AiServicePage extends StatefulWidget {
  const AiServicePage({super.key});

  @override
  State<AiServicePage> createState() => _AiServicePageState();
}

class _AiServicePageState extends State<AiServicePage> {
  final _controller = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  bool _obscure = true;
  String? _savedKey;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final key = await StorageService.getApiKey();
    if (!mounted) return;
    setState(() {
      _savedKey = key;
      _controller.text = key ?? '';
      _loading = false;
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final key = _controller.text.trim();
    if (key.isEmpty) {
      _snack('请输入 API Key');
      return;
    }
    setState(() => _saving = true);
    await StorageService.setApiKey(key);
    if (!mounted) return;
    setState(() {
      _saving = false;
      _savedKey = key;
    });
    _snack('已保存到本机');
  }

  Future<void> _clear() async {
    await StorageService.clearApiKey();
    if (!mounted) return;
    setState(() {
      _savedKey = null;
      _controller.clear();
    });
    _snack('已清除本机 Key');
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final configured = _savedKey != null && _savedKey!.isNotEmpty;
    return Scaffold(
      appBar: AppBar(title: const Text('AI 服务')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.smart_toy,
                                color: Color(0xFFFF6B9D)),
                            const SizedBox(width: 8),
                            const Text('小米 MiMo API Key',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold)),
                            const Spacer(),
                            Text(
                              configured ? '已配置' : '未配置',
                              style: TextStyle(
                                  color: configured
                                      ? Colors.green
                                      : Colors.orange,
                                  fontSize: 12),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _controller,
                          obscureText: _obscure,
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            labelText: 'API Key',
                            labelStyle: const TextStyle(color: Colors.grey),
                            hintText: '填写后保存在本机，不会下发到设备',
                            hintStyle: const TextStyle(color: Colors.grey),
                            filled: true,
                            fillColor: const Color(0xFF1A1A2E),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscure
                                    ? Icons.visibility_off
                                    : Icons.visibility,
                                color: Colors.grey,
                              ),
                              onPressed: () =>
                                  setState(() => _obscure = !_obscure),
                            ),
                          ),
                        ),
                        const SizedBox(height: 5),
                        const Text(
                          '语音识别用 mimo-v2.5-asr，对话用 mimo-v2.6-flash。',
                          style: TextStyle(color: Colors.grey, fontSize: 12),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: _saving ? null : _save,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFFF6B9D),
                            foregroundColor: Colors.white,
                            minimumSize: const Size.fromHeight(48),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: _saving
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text('保存到本机'),
                        ),
                        if (configured)
                          TextButton(
                            onPressed: _clear,
                            style:
                                TextButton.styleFrom(foregroundColor: Colors.red),
                            child: const Text('清除 Key'),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      '设备不再连接 Wi-Fi，也不再保存任何密钥。\n'
                      '长按设备 OK 键录音后，手机会把音频送到 MiMo 识别并请求大模型，'
                      '再把回复文本通过蓝牙回传给设备显示。',
                      style: TextStyle(color: Colors.grey, fontSize: 13),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
