import 'package:flutter/material.dart';
import '../services/ble_service.dart';

// AI 对话 API Key 配置页：向设备下发/清除 Key，并读取是否已配置。
// Key 只保存在设备本地（NVS），App 不保存也不上传，设备绝不回传 Key 明文。
class AiKeyPage extends StatefulWidget {
  // 目标设备蓝牙地址
  final String address;
  // 目标设备显示名（只读展示）
  final String deviceName;

  const AiKeyPage({
    super.key,
    required this.address,
    required this.deviceName,
  });

  @override
  State<AiKeyPage> createState() => _AiKeyPageState();
}

class _AiKeyPageState extends State<AiKeyPage> {
  final _keyController = TextEditingController();

  bool _obscureKey = true; // Key 默认隐藏，可切换明文
  bool _busy = false; // 正在下发保存/清除指令
  String _progress = ''; // 操作进度/结果文案
  bool? _configured; // 最近一次读取到的配置状态，null=未读取到

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  @override
  void dispose() {
    // 先释放控制器，异步回调中已用 mounted 守卫，避免 setState after dispose
    _keyController.dispose();
    super.dispose();
  }

  // 进入页面先读一次当前配置状态
  Future<void> _loadStatus() async {
    final configured = await BleService.readAiKeyStatus(
      address: widget.address,
    );
    if (!mounted) return;
    setState(() => _configured = configured);
  }

  // 保存 Key：校验非空 → 下发 {"api_key":"..."} → 成功后刷新状态
  Future<void> _saveKey() async {
    final key = _keyController.text.trim();
    if (key.isEmpty) {
      _showSnack('请输入 API Key');
      return;
    }

    setState(() {
      _busy = true;
      _progress = '正在保存 API Key...';
    });

    final err = await BleService.writeAiKey(
      address: widget.address,
      apiKey: key,
    );

    if (!mounted) return;

    setState(() {
      _busy = false;
      _progress = err ?? 'API Key 已保存到设备';
    });

    if (err != null) return;

    // 保存成功后清空输入框并刷新状态
    _keyController.clear();
    await _loadStatus();
  }

  // 清除 Key：带确认弹窗，成功后刷新状态
  Future<void> _clearKey() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF252540),
        title: const Text('清除 API Key', style: TextStyle(color: Colors.white)),
        content: const Text('确定要清除该设备已保存的 AI 对话 API Key 吗？',
            style: TextStyle(color: Colors.grey)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('确定清除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _busy = true;
      _progress = '正在清除 API Key...';
    });

    final err = await BleService.clearAiKey(address: widget.address);

    if (!mounted) return;

    setState(() {
      _busy = false;
      _progress = err ?? '已下发清除指令';
    });

    // 清除后刷新一次状态
    await _loadStatus();
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('AI 对话配置')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildDeviceCard(),
            const SizedBox(height: 16),
            _buildKeyCard(),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _busy ? null : _saveKey,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF6B9D),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _busy
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('保存 Key', style: TextStyle(fontSize: 16)),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: _busy ? null : _clearKey,
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red,
                side: const BorderSide(color: Colors.red),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('清除 Key', style: TextStyle(fontSize: 15)),
            ),
            const SizedBox(height: 24),
            _buildStatusCard(),
          ],
        ),
      ),
    );
  }

  // 只读展示当前设备名
  Widget _buildDeviceCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const CircleAvatar(
              backgroundColor: Color(0xFFFF6B9D),
              child: Icon(Icons.smart_toy, color: Colors.white),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('当前设备',
                      style: TextStyle(color: Colors.grey, fontSize: 12)),
                  const SizedBox(height: 4),
                  Text(
                    widget.deviceName,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // API Key 输入卡片（可切换明文/隐藏）
  Widget _buildKeyCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('API Key',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            TextField(
              controller: _keyController,
              obscureText: _obscureKey,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'API Key',
                labelStyle: const TextStyle(color: Colors.grey),
                hintText: '请输入 AI 对话服务的 API Key',
                hintStyle: const TextStyle(color: Colors.grey),
                filled: true,
                fillColor: const Color(0xFF1A1A2E),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscureKey ? Icons.visibility_off : Icons.visibility,
                    color: Colors.grey,
                  ),
                  onPressed: () =>
                      setState(() => _obscureKey = !_obscureKey),
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Key 只保存在设备本地（NVS），App 不保存也不上传；'
              '开源仓库中不含密钥。',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusCard() {
    final configured = _configured;
    final statusColor = configured == null
        ? Colors.grey
        : (configured ? Colors.green : Colors.orange);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('配置状态',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            if (_progress.isNotEmpty) ...[
              Row(
                children: [
                  if (_busy)
                    const Padding(
                      padding: EdgeInsets.only(right: 8),
                      child: SizedBox(
                        height: 14,
                        width: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Color(0xFFFF6B9D),
                        ),
                      ),
                    ),
                  Expanded(
                    child: Text(_progress,
                        style: const TextStyle(
                            color: Colors.grey, fontSize: 13)),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],
            _statusRow(
              'API Key 状态',
              configured == null ? '--' : (configured ? '已配置' : '未配置'),
              color: statusColor,
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusRow(String label, String value, {Color? color}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 14)),
        Text(value,
            style: TextStyle(
                color: color ?? Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w500)),
      ],
    );
  }
}
