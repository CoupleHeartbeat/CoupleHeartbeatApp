import 'package:flutter/material.dart';
import '../services/ble_service.dart';

// AI 对话 API Key 配置页：向设备下发/清除 Key，并读取是否已配置。
// Key 只保存在设备本地（NVS），App 不保存也不上传，设备绝不回传 Key 明文。
// 成对模式下（secondAddress 非空）可在开关打开时同时给两台设备下发同一个 Key。
class AiKeyPage extends StatefulWidget {
  // 目标设备蓝牙地址
  final String address;
  // 目标设备显示名（只读展示）
  final String deviceName;
  // 第二台设备地址（成对模式，可空）
  final String? secondAddress;
  // 第二台设备显示名（成对模式，可空）
  final String? secondDeviceName;

  const AiKeyPage({
    super.key,
    required this.address,
    required this.deviceName,
    this.secondAddress,
    this.secondDeviceName,
  });

  @override
  State<AiKeyPage> createState() => _AiKeyPageState();
}

class _AiKeyPageState extends State<AiKeyPage> {
  final _keyController = TextEditingController();

  bool _obscureKey = true; // Key 默认隐藏，可切换明文
  bool _busy = false; // 正在下发保存/清除指令
  String _progress = ''; // 操作进度/结果文案
  bool? _configured; // 主设备最近读取到的配置状态，null=未读取到
  bool? _secondConfigured; // 第二台最近读取到的配置状态
  bool _configSecond = true; // 成对配置开关（默认开启）

  // 是否存在第二台设备（成对模式）
  bool get _hasSecond =>
      widget.secondAddress != null && widget.secondAddress!.isNotEmpty;

  // 主设备展示名
  String get _primaryLabel =>
      widget.deviceName.isEmpty ? '当前设备' : widget.deviceName;

  // 第二台设备展示名
  String get _secondLabel {
    final n = widget.secondDeviceName;
    return (n == null || n.isEmpty) ? '另一台设备' : n;
  }

  // 本次是否要同时下发两台
  bool get _configureBoth => _hasSecond && _configSecond;

  // 本次下发的目标地址列表
  List<String> get _targetAddresses =>
      _configureBoth ? [widget.address, widget.secondAddress!] : [widget.address];

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

  // 进入页面先读一次当前配置状态（成对模式下两台都读）
  Future<void> _loadStatus() async {
    final configured = await BleService.readAiKeyStatus(
      address: widget.address,
    );
    bool? second;
    if (_hasSecond) {
      second = await BleService.readAiKeyStatus(address: widget.secondAddress!);
    }
    if (!mounted) return;
    setState(() {
      _configured = configured;
      if (_hasSecond) _secondConfigured = second;
    });
  }

  // 保存 Key：校验非空 → 成对模式下同时下发两台 → 逐台报告结果
  Future<void> _saveKey() async {
    final key = _keyController.text.trim();
    if (key.isEmpty) {
      _showSnack('请输入 API Key');
      return;
    }

    setState(() {
      _busy = true;
      _progress = _configureBoth ? '正在同时下发两台设备...' : '正在保存 API Key...';
    });

    if (_configureBoth) {
      final results = await BleService.writeAiKeyToMany(
        addresses: _targetAddresses,
        apiKey: key,
      );
      if (!mounted) return;

      final errA = results[widget.address];
      final errB = results[widget.secondAddress!];
      if (errA == null && errB == null) {
        setState(() => _progress = 'API Key 已保存到两台设备');
        _keyController.clear();
      } else {
        final parts = <String>[
          errA == null
              ? '$_primaryLabel 下发成功'
              : '$_primaryLabel 下发失败：$errA',
          errB == null
              ? '$_secondLabel 下发成功'
              : '$_secondLabel 下发失败：$errB',
        ];
        setState(() => _progress = parts.join('；'));
        // 两台都成功才清空输入框
      }
      setState(() => _busy = false);
      await _loadStatus();
      return;
    }

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

  // 清除 Key：带确认弹窗；成对模式下同时清除两台，逐台报告结果
  Future<void> _clearKey() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF252540),
        title: const Text('清除 API Key', style: TextStyle(color: Colors.white)),
        content: Text(
            _configureBoth ? '确定要清除两台设备已保存的 AI 对话 API Key 吗？' : '确定要清除该设备已保存的 AI 对话 API Key 吗？',
            style: const TextStyle(color: Colors.grey)),
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
      _progress = _configureBoth ? '正在同时清除两台设备的 Key...' : '正在清除 API Key...';
    });

    if (_configureBoth) {
      final results = await BleService.clearAiKeyToMany(
        addresses: _targetAddresses,
      );
      if (!mounted) return;

      final errA = results[widget.address];
      final errB = results[widget.secondAddress!];
      final parts = <String>[
        errA == null ? '$_primaryLabel 已清除' : '$_primaryLabel 清除失败：$errA',
        errB == null ? '$_secondLabel 已清除' : '$_secondLabel 清除失败：$errB',
      ];
      setState(() {
        _busy = false;
        _progress = parts.join('；');
      });
      await _loadStatus();
      return;
    }

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
            if (_hasSecond) ...[
              const SizedBox(height: 12),
              _buildPairSwitchCard(),
            ],
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

  // 只读展示当前设备（成对模式下同时展示两台）
  Widget _buildDeviceCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _deviceRow(Icons.smart_toy, '当前设备', widget.deviceName),
            if (_hasSecond) ...[
              const Divider(color: Colors.white12, height: 20),
              _deviceRow(Icons.devices, '第二台设备', _secondLabel),
            ],
          ],
        ),
      ),
    );
  }

  Widget _deviceRow(IconData icon, String title, String name) {
    return Row(
      children: [
        CircleAvatar(
          backgroundColor: const Color(0xFFFF6B9D),
          child: Icon(icon, color: Colors.white),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(color: Colors.grey, fontSize: 12)),
              const SizedBox(height: 4),
              Text(
                name,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // 成对模式下的「同时下发另一台设备」开关
  Widget _buildPairSwitchCard() {
    return Card(
      child: SwitchListTile(
        value: _configSecond,
        onChanged: _busy ? null : (v) => setState(() => _configSecond = v),
        activeThumbColor: const Color(0xFFFF6B9D),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        secondary: const Icon(Icons.devices, color: Colors.grey),
        title: const Text('同时下发另一台设备',
            style: TextStyle(color: Colors.white, fontSize: 15)),
        subtitle: Text(
          _configSecond
              ? '第二台设备：$_secondLabel'
              : '仅下发当前设备：$_primaryLabel',
          style: const TextStyle(color: Colors.grey, fontSize: 12),
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
              '$_primaryLabel Key 状态',
              _configured == null ? '--' : (_configured! ? '已配置' : '未配置'),
              color: _configured == null
                  ? Colors.grey
                  : (_configured! ? Colors.green : Colors.orange),
            ),
            if (_hasSecond) ...[
              const SizedBox(height: 8),
              _statusRow(
                '$_secondLabel Key 状态',
                _secondConfigured == null
                    ? '--'
                    : (_secondConfigured! ? '已配置' : '未配置'),
                color: _secondConfigured == null
                    ? Colors.grey
                    : (_secondConfigured! ? Colors.green : Colors.orange),
              ),
            ],
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
