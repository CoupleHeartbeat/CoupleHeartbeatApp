import 'dart:async';
import 'package:flutter/material.dart';
import '../services/ble_service.dart';

// Wi-Fi 配网页：向设备下发 SSID/密码，并轮询读取配网结果。
class WifiConfigPage extends StatefulWidget {
  // 目标设备蓝牙地址
  final String address;
  // 目标设备显示名（只读展示）
  final String deviceName;

  const WifiConfigPage({
    super.key,
    required this.address,
    required this.deviceName,
  });

  @override
  State<WifiConfigPage> createState() => _WifiConfigPageState();
}

class _WifiConfigPageState extends State<WifiConfigPage> {
  final _ssidController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _obscurePassword = true;
  bool _configuring = false; // 正在下发凭据
  bool _polling = false; // 正在轮询配网结果
  String _progress = ''; // 操作进度/结果文案
  WifiStatus? _wifiStatus; // 最近一次读取到的 Wi-Fi 状态

  // 轮询控制：每 2 秒一次，最多约 20 秒
  Timer? _pollTimer;
  int _pollCount = 0;
  static const int _maxPolls = 10;

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  @override
  void dispose() {
    // 页面销毁时必须停止轮询，避免 setState after dispose
    _cancelPollTimer();
    _ssidController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // 进入页面先读一次当前状态
  Future<void> _loadStatus() async {
    final s = await BleService.readWifiStatus(address: widget.address);
    if (!mounted) return;
    setState(() => _wifiStatus = s);
  }

  void _cancelPollTimer() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _polling = false;
  }

  // 开始配网：校验 SSID → 下发凭据 → 成功后轮询状态
  Future<void> _startConfig() async {
    final ssid = _ssidController.text.trim();
    if (ssid.isEmpty) {
      _showSnack('请输入 Wi-Fi 名称（SSID）');
      return;
    }

    setState(() {
      _configuring = true;
      _progress = '正在下发 Wi-Fi 凭据...';
    });

    // password 允许为空串（开放网络）
    final err = await BleService.writeWifiCredentials(
      address: widget.address,
      ssid: ssid,
      password: _passwordController.text,
    );

    if (!mounted) return;

    if (err != null) {
      setState(() {
        _configuring = false;
        _progress = err;
      });
      return;
    }

    setState(() {
      _configuring = false;
      _progress = '凭据已下发，正在等待设备连接...';
    });
    _startPolling();
  }

  // 清除配网：下发 {"clear":true}，让设备清空已保存的 Wi-Fi 配置
  Future<void> _clearConfig() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF252540),
        title: const Text('清除配网', style: TextStyle(color: Colors.white)),
        content: const Text('确定要清除该设备已保存的 Wi-Fi 配置吗？',
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

    _cancelPollTimer();
    setState(() {
      _configuring = true;
      _progress = '正在清除 Wi-Fi 配置...';
    });

    final err = await BleService.clearWifiCredentials(address: widget.address);

    if (!mounted) return;

    setState(() {
      _configuring = false;
      _progress = err ?? '已下发清除指令';
    });

    // 清除后刷新一次状态
    await _loadStatus();
    if (!mounted) return;
    setState(() {
      _ssidController.clear();
      _passwordController.clear();
    });
  }

  // 轮询读取配网结果：直到已连接(2) / 失败(3) / 超时
  void _startPolling() {
    _cancelPollTimer();
    _pollCount = 0;
    setState(() => _polling = true);
    _pollTimer =
        Timer.periodic(const Duration(seconds: 2), (_) => _doPoll());
  }

  Future<void> _doPoll() async {
    final s = await BleService.readWifiStatus(address: widget.address);
    if (!mounted || !_polling) return;

    setState(() => _wifiStatus = s);
    _pollCount++;

    if (s != null && (s.state == 2 || s.state == 3)) {
      _cancelPollTimer();
      setState(() {
        _progress = s.state == 2 ? '配网成功' : '配网失败：请检查 Wi-Fi 密码或信号后重试';
      });
      return;
    }

    if (_pollCount >= _maxPolls) {
      _cancelPollTimer();
      setState(() => _progress = '配网超时，请确认设备在附近后重试');
    }
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final busy = _configuring || _polling;

    return Scaffold(
      appBar: AppBar(title: const Text('Wi-Fi 配网')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildDeviceCard(),
            const SizedBox(height: 16),
            _buildFormCard(),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: busy ? null : _startConfig,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF6B9D),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _configuring
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('开始配网', style: TextStyle(fontSize: 16)),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: busy ? null : _clearConfig,
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red,
                side: const BorderSide(color: Colors.red),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('清除配网', style: TextStyle(fontSize: 15)),
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
              child: Icon(Icons.watch, color: Colors.white),
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

  Widget _buildFormCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Wi-Fi 信息',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            TextField(
              controller: _ssidController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Wi-Fi 名称（SSID）',
                labelStyle: const TextStyle(color: Colors.grey),
                hintText: '请输入要连接的 Wi-Fi 名称',
                hintStyle: const TextStyle(color: Colors.grey),
                filled: true,
                fillColor: const Color(0xFF1A1A2E),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _passwordController,
              obscureText: _obscurePassword,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Wi-Fi 密码',
                labelStyle: const TextStyle(color: Colors.grey),
                hintText: '留空表示开放网络',
                hintStyle: const TextStyle(color: Colors.grey),
                filled: true,
                fillColor: const Color(0xFF1A1A2E),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePassword
                        ? Icons.visibility_off
                        : Icons.visibility,
                    color: Colors.grey,
                  ),
                  onPressed: () => setState(
                      () => _obscurePassword = !_obscurePassword),
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Text('仅支持 2.4GHz Wi-Fi；密码留空表示连接开放网络。',
                style: TextStyle(color: Colors.grey, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusCard() {
    final s = _wifiStatus;
    final connected = s?.isConnected ?? false;
    final stateColor = connected
        ? Colors.green
        : (s?.state == 3 ? Colors.red : Colors.orange);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('配网状态',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            if (_progress.isNotEmpty) ...[
              Row(
                children: [
                  if (_polling)
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
              '连接状态',
              s == null ? '设备离线 / 未知' : s.stateLabel,
              color: s == null ? Colors.grey : stateColor,
            ),
            const SizedBox(height: 8),
            _statusRow('Wi-Fi 名称',
                (s?.ssid == null || s!.ssid!.isEmpty) ? '--' : s.ssid!,
                color: Colors.white),
            const SizedBox(height: 8),
            _statusRow('IP 地址',
                (s?.ip == null || s!.ip!.isEmpty) ? '--' : s.ip!,
                color: Colors.white),
            const SizedBox(height: 8),
            _statusRow(
              '信号强度',
              (s?.rssi == null || s!.rssi == 0) ? '--' : '${s.rssi} dBm',
              color: Colors.white,
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
