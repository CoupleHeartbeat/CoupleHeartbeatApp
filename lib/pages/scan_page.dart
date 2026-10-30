import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../services/ble_service.dart';
import 'device_config_page.dart';

// 首次启动引导：一个手机只绑定一台设备。
// 两台设备的串联在主页“设置 - 两台串联”中完成。
class ScanPage extends StatefulWidget {
  // 设备绑定保存成功后的回调，通知上层刷新
  final VoidCallback onBound;

  const ScanPage({
    super.key,
    required this.onBound,
  });

  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> {
  List<BleDeviceInfo> _devices = [];
  bool _isScanning = false;
  BluetoothAdapterState _bleState = BluetoothAdapterState.unknown;
  StreamSubscription<List<BleDeviceInfo>>? _scanSub;
  StreamSubscription<BluetoothAdapterState>? _stateSub;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await BleService.ensurePermissions();
    // 先等待蓝牙适配器状态就绪，再发起扫描，
    // 避免首次进入时 _bleState 还是 unknown 被误判为"蓝牙未开"。
    final state = await FlutterBluePlus.adapterState.first;
    if (!mounted) return;
    setState(() => _bleState = state);
    _stateSub = FlutterBluePlus.adapterState.listen((s) {
      if (mounted) setState(() => _bleState = s);
    });
    if (_bleState == BluetoothAdapterState.on) {
      await _startScan();
    }
  }

  @override
  void dispose() {
    _scanSub?.cancel();
    _stateSub?.cancel();
    super.dispose();
  }

  Future<void> _startScan() async {
    if (_bleState != BluetoothAdapterState.on) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先开启蓝牙')),
      );
      return;
    }

    await _scanSub?.cancel();
    setState(() {
      _isScanning = true;
      _devices = [];
    });

    _scanSub =
        BleService.scanDevices(timeout: const Duration(seconds: 10)).listen(
      (devices) {
        if (mounted) setState(() => _devices = devices);
      },
      onError: (Object e) {
        // 权限被拒绝 / 蓝牙异常等错误：停止扫描并明确提示
        if (!mounted) return;
        setState(() => _isScanning = false);
        String msg = '扫描失败';
        final s = e.toString();
        if (s.contains('Permission')) {
          msg = '蓝牙权限被拒绝，请在系统设置中授予本应用"附近的设备"权限后重试';
        } else if (s.contains('BluetoothAdapterState')) {
          msg = '蓝牙不可用，请开启蓝牙后重试';
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg)),
        );
      },
    );

    await Future.delayed(const Duration(seconds: 10));
    if (mounted) {
      setState(() => _isScanning = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('设备配对'),
        actions: [
          IconButton(
            icon: Icon(_isScanning ? Icons.stop : Icons.refresh),
            onPressed: _isScanning ? null : _startScan,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_bleState != BluetoothAdapterState.on) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.bluetooth_disabled, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            const Text('蓝牙未开启', style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: _init,
              child: const Text('刷新状态'),
            ),
          ],
        ),
      );
    }

    if (_devices.isEmpty && _isScanning) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(
              width: 48,
              height: 48,
              child: CircularProgressIndicator(
                color: Color(0xFFFF6B9D),
              ),
            ),
            const SizedBox(height: 16),
            const Text('正在扫描附近的 AI Passport...',
                style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    if (_devices.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.search_off, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            const Text('未发现设备', style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 8),
            const Text('请确保 AI Passport 已开机且在附近',
                style: TextStyle(color: Colors.grey, fontSize: 12)),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _startScan,
              child: const Text('重新扫描'),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _devices.length,
      itemBuilder: (context, index) {
        final device = _devices[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: const Color(0xFF3A3A5E),
              child: const Icon(Icons.watch, color: Color(0xFFFF6B9D)),
            ),
            title: Text(device.name, style: const TextStyle(color: Colors.white)),
            subtitle: Text(
              '${device.device.remoteId.str}  ·  ${device.rssi} dBm',
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
            trailing: ElevatedButton(
              onPressed: () => _selectDevice(device),
              child: const Text('选择'),
            ),
          ),
        );
      },
    );
  }

  void _selectDevice(BleDeviceInfo device) {
    // 一个手机只绑定一台设备：进入设备配置页绑定（写昵称 + 保存地址）。
    // 两台设备的串联在主页设置中完成。
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (context) => DeviceConfigPage(
              address: device.device.remoteId.str,
              deviceName: device.name,
              onSaved: widget.onBound,
            ),
          ),
        )
        // 返回后再刷新一次根状态：进入过设备配置页即代表完成了绑定，
        // 这样"未改昵称直接返回"的用户返回后也能进入主页。
        .then((_) => widget.onBound());
  }
}
