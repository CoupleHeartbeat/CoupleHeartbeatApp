import 'package:flutter/material.dart';
import '../services/ble_service.dart';
import '../services/storage_service.dart';

// 单台设备配置页：设置昵称（设备不再连 Wi-Fi）。
class DeviceConfigPage extends StatefulWidget {
  // 设备蓝牙地址
  final String address;
  // 设备显示名（用于展示与 Wi-Fi 配网页标题）
  final String deviceName;
  // 初始昵称（可选）
  final String? initialName;
  // 配置保存成功后的回调，通知上层刷新（如切换到 HomePage）
  final VoidCallback? onSaved;

  const DeviceConfigPage({
    super.key,
    required this.address,
    required this.deviceName,
    this.initialName,
    this.onSaved,
  });

  @override
  State<DeviceConfigPage> createState() => _DeviceConfigPageState();
}

class _DeviceConfigPageState extends State<DeviceConfigPage> {
  late final TextEditingController _nameController;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameController =
        TextEditingController(text: widget.initialName ?? widget.deviceName);
    // 进入设备配置页即视为选择"单台模式"：先把模式、角色与地址落库，
    // 这样不改昵称直接返回的用户也能进入单设备主页。
    _persistSingleMode();
  }

  Future<void> _persistSingleMode() async {
    await StorageService.setMode('single');
    await StorageService.setLocalRole('A');
    await StorageService.setDeviceAddress('A', widget.address);
    final existing = await StorageService.getDeviceName('A');
    if (existing == null || existing.isEmpty) {
      await StorageService.setDeviceName('A',
          widget.initialName ?? widget.deviceName);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  // 保存昵称到设备（0xFFE2）；成功后落库单台模式信息并通知上层
  Future<void> _saveName() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      _showSnack('请输入昵称');
      return;
    }

    setState(() => _saving = true);

    final err = await BleService.writeBadgeName(
      address: widget.address,
      name: name,
    );

    if (!mounted) return;

    if (err != null) {
      setState(() => _saving = false);
      _showSnack(err);
      return;
    }

    // 单台配置成功：记录运行模式与设备 A 信息
    await StorageService.setMode('single');
    await StorageService.setLocalRole('A');
    await StorageService.setDeviceName('A', name);
    await StorageService.setDeviceAddress('A', widget.address);

    if (!mounted) return;
    setState(() => _saving = false);
    _showSnack('昵称已保存');
    widget.onSaved?.call();
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设备配置')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 设备信息（只读）
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const CircleAvatar(
                    backgroundColor: Color(0xFFFF6B9D),
                    child: Icon(Icons.watch, color: Colors.white),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('已选择设备',
                            style: TextStyle(color: Colors.grey, fontSize: 12)),
                        const SizedBox(height: 4),
                        Text(
                          widget.deviceName,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.address,
                          style:
                              const TextStyle(color: Colors.grey, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // 昵称设置
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('设备昵称',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _nameController,
                    style: const TextStyle(color: Colors.white),
                    maxLength: 10,
                    decoration: InputDecoration(
                      labelText: '昵称',
                      labelStyle: const TextStyle(color: Colors.grey),
                      hintText: '请输入昵称（最多10字）',
                      hintStyle: const TextStyle(color: Colors.grey),
                      filled: true,
                      fillColor: const Color(0xFF1A1A2E),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      counterStyle: const TextStyle(color: Colors.grey),
                    ),
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton(
                    onPressed: _saving ? null : _saveName,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF6B9D),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      minimumSize: const Size.fromHeight(0),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _saving
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('保存昵称', style: TextStyle(fontSize: 15)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
