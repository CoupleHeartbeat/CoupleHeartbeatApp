import 'package:flutter/material.dart';
import '../services/ble_service.dart';
import '../services/storage_service.dart';

class PairingPage extends StatefulWidget {
  final BleDeviceInfo selectedDevice;
  final List<BleDeviceInfo> allDevices;
  final Function(String nameA, String nameB) onPaired;

  const PairingPage({
    super.key,
    required this.selectedDevice,
    required this.allDevices,
    required this.onPaired,
  });

  @override
  State<PairingPage> createState() => _PairingPageState();
}

class _PairingPageState extends State<PairingPage> {
  final _nameAController = TextEditingController(text: '亲爱的A');
  final _nameBController = TextEditingController(text: '亲爱的B');
  final _codeA = TextEditingController();
  final _codeB = TextEditingController();
  BleDeviceInfo? _deviceA;
  BleDeviceInfo? _deviceB;
  bool _isPairing = false;
  String _status = '';

  @override
  void initState() {
    super.initState();
    // 默认第一个选的是设备A
    _deviceA = widget.selectedDevice;
    // 如果还有其他设备，自动选第二个作为B
    if (widget.allDevices.length >= 2) {
      for (var d in widget.allDevices) {
        if (d.device.remoteId.str != _deviceA!.device.remoteId.str) {
          _deviceB = d;
          break;
        }
      }
    }
  }

  @override
  void dispose() {
    _nameAController.dispose();
    _nameBController.dispose();
    _codeA.dispose();
    _codeB.dispose();
    super.dispose();
  }

  Future<void> _startPairing() async {
    if (_deviceA == null || _deviceB == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请选择两台设备')),
      );
      return;
    }

    setState(() {
      _isPairing = true;
      _status = '正在生成配对密钥...';
    });

    final pairId = BleService.generatePairId();
    final pairKey = BleService.generatePairKey();
    final addrA = _deviceA!.device.remoteId.str;
    final addrB = _deviceB!.device.remoteId.str;
    final nameA = _nameAController.text.trim();
    final nameB = _nameBController.text.trim();
    final codeA = _codeA.text.trim();
    final codeB = _codeB.text.trim();

    if (!RegExp(r'^\d{4}$').hasMatch(codeA) ||
        !RegExp(r'^\d{4}$').hasMatch(codeB)) {
      setState(() {
        _isPairing = false;
        _status = '请输入两台设备屏幕上的 4 位配对码';
      });
      return;
    }

    try {
      setState(() => _status = '正在配置设备 A ($nameA)...');
      final errA = await BleService.pairDevice(
        device: _deviceA!.device,
        role: 'A',
        pairId: pairId,
        pairKey: pairKey,
        partnerAddress: addrB,
        badgeName: nameA,
        pairCode: codeA,
      );

      if (errA != null) {
        throw '设备 A：$errA';
      }

      setState(() => _status = '正在配置设备 B ($nameB)...');
      final errB = await BleService.pairDevice(
        device: _deviceB!.device,
        role: 'B',
        pairId: pairId,
        pairKey: pairKey,
        partnerAddress: addrA,
        badgeName: nameB,
        pairCode: codeB,
      );

      if (errB != null) {
        throw '设备 B：$errB';
      }

      // 保存到本地
      await StorageService.setPaired(true);
      await StorageService.setMode('pair');
      await StorageService.setPairId(pairId);
      await StorageService.setDeviceName('A', nameA);
      await StorageService.setDeviceName('B', nameB);
      await StorageService.setDeviceAddress('A', addrA);
      await StorageService.setDeviceAddress('B', addrB);

      setState(() => _status = '配对成功！');

      await Future.delayed(const Duration(seconds: 1));

      if (mounted) {
        widget.onPaired(nameA, nameB);
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } catch (e) {
      setState(() {
        _isPairing = false;
        _status = '配对失败: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('配对配置')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildDeviceSelector('A', _deviceA, (d) => setState(() => _deviceA = d)),
            const SizedBox(height: 8),
            _buildNameField('A', _nameAController),
            const SizedBox(height: 24),
            _buildDeviceSelector('B', _deviceB, (d) => setState(() => _deviceB = d)),
            const SizedBox(height: 8),
            _buildNameField('B', _nameBController),
            const SizedBox(height: 24),
            _buildCodeField('A', _codeA),
            const SizedBox(height: 8),
            _buildCodeField('B', _codeB),
            const SizedBox(height: 8),
            const Text(
              '配对码显示在设备屏幕上（未配对状态）；\n已在设备上配对过的，请先短按 OK 键进入设置菜单，选择"恢复出厂设置"。',
              style: TextStyle(color: Colors.grey, fontSize: 12),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            if (_status.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(_status,
                    style: const TextStyle(color: Colors.grey),
                    textAlign: TextAlign.center),
              ),
            ElevatedButton(
              onPressed: _isPairing ? null : _startPairing,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF6B9D),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _isPairing
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('开始配对', style: TextStyle(fontSize: 16)),
            ),
            const SizedBox(height: 16),
            const Text(
              '配对成功后，两台设备靠近时会自动进入心动模式。\n距离越近，心跳越快、光效越强。',
              style: TextStyle(color: Colors.grey, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeviceSelector(String role, BleDeviceInfo? selected,
      ValueChanged<BleDeviceInfo?> onChanged) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: role == 'A'
                      ? const Color(0xFFFF6B9D)
                      : const Color(0xFF6BB5FF),
                  child: Text(role, style: const TextStyle(color: Colors.white)),
                ),
                const SizedBox(width: 12),
                const Text('设备', style: TextStyle(color: Colors.white, fontSize: 16)),
              ],
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<BleDeviceInfo>(
              value: selected,
              hint: const Text('选择设备', style: TextStyle(color: Colors.grey)),
              dropdownColor: const Color(0xFF252540),
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                filled: true,
                fillColor: Color(0xFF1A1A2E),
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              items: widget.allDevices
                  .where((d) =>
                      d.device.remoteId.str == selected?.device.remoteId.str ||
                      (role == 'A'
                          ? d.device.remoteId.str != _deviceB?.device.remoteId.str
                          : d.device.remoteId.str != _deviceA?.device.remoteId.str))
                  .map((d) => DropdownMenuItem(
                        value: d,
                        child: Text(d.name),
                      ))
                  .toList(),
              onChanged: onChanged,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCodeField(String role, TextEditingController controller) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        maxLength: 4,
        style: const TextStyle(color: Colors.white, letterSpacing: 8),
        decoration: InputDecoration(
          counterText: '',
          labelText: '设备 $role 配对码（4 位数字）',
          labelStyle: const TextStyle(color: Colors.grey),
          hintText: '0000',
          hintStyle: const TextStyle(color: Colors.grey, letterSpacing: 8),
          filled: true,
          fillColor: const Color(0xFF252540),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
    );
  }

  Widget _buildNameField(String role, TextEditingController controller) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: TextField(
        controller: controller,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          labelText: '设备 $role 昵称',
          labelStyle: const TextStyle(color: Colors.grey),
          filled: true,
          fillColor: const Color(0xFF252540),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
    );
  }
}
