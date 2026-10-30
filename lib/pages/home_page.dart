import 'dart:async';
import 'package:flutter/material.dart';
import '../services/ble_service.dart';
import '../services/storage_service.dart';
import '../services/voice_session.dart';
import 'badge_config_page.dart';
import 'phone_pair_page.dart';
import 'volume_page.dart';
import 'device_config_page.dart';
import 'ai_service_page.dart';

class HomePage extends StatefulWidget {
  final String deviceAName;
  // 未串联时设备 B 为空/为 null，仅渲染一张设备卡片
  final String? deviceBName;
  final VoidCallback onUnpair;
  // 设置中完成两台串联后的回调，通知根组件切换到双设备视图
  final Function(String nameA, String nameB) onLinked;

  const HomePage({
    super.key,
    required this.deviceAName,
    required this.deviceBName,
    required this.onUnpair,
    required this.onLinked,
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _currentIndex = 0;
  DeviceStatus? _statusA;
  DeviceStatus? _statusB;
  bool? _aiKeyConfigured; // 手机本地是否已保存 MiMo Key
  String? _localRole;
  String? _addrA;
  bool _loadingStatus = false;
  bool _syncingTime = false;
  bool _voiceEnabled = false;
  VoiceSessionState _voiceState = VoiceSessionState.idle;
  String _voiceStatus = '未启用';
  StreamSubscription<VoiceSessionState>? _voiceSub;

  // 设备 B 名称为空即视为单台模式
  bool get _isSingle =>
      widget.deviceBName == null || widget.deviceBName!.isEmpty;

  // 本机所配的是哪一台（'A' 或 'B'），单台模式视为 A
  String get _role => _isSingle ? 'A' : (_localRole ?? 'A');

  @override
  void initState() {
    super.initState();
    _voiceSub = VoiceSession.instance.states.listen((s) {
      if (!mounted) return;
      setState(() {
        _voiceState = s;
        _voiceStatus = VoiceSession.instance.status;
      });
    });
    _refreshStatus();
    _initVoice();
  }

  @override
  void dispose() {
    _voiceSub?.cancel();
    super.dispose();
  }

  Future<void> _initVoice() async {
    final enabled = await StorageService.getVoiceEnabled();
    if (!mounted) return;
    setState(() => _voiceEnabled = enabled);
    if (enabled) {
      await VoiceSession.instance.enable();
      if (mounted) setState(() => _voiceStatus = VoiceSession.instance.status);
    }
  }

  Future<void> _toggleVoice(bool value) async {
    setState(() => _voiceEnabled = value);
    await StorageService.setVoiceEnabled(value);
    if (value) {
      await VoiceSession.instance.enable();
    } else {
      await VoiceSession.instance.disable();
    }
    if (!mounted) return;
    setState(() => _voiceStatus = VoiceSession.instance.status);
  }

  // 按已保存地址重连设备读取真实状态；读不到即视为离线
  Future<void> _refreshStatus() async {
    if (_loadingStatus) return;
    setState(() => _loadingStatus = true);

    final addrA = await StorageService.getDeviceAddress('A');
    final addrB = await StorageService.getDeviceAddress('B');
    final role = await StorageService.getLocalRole();
    final key = await StorageService.getApiKey();

    // 本机所配设备由常驻连接直接读，避免两条 BLE 连接互相抢占
    Future<DeviceStatus?> readOne(String? addr, String role) async {
      if (addr == null) return null;
      if (role == _role && VoiceSession.instance.enabled) {
        final s = await VoiceSession.instance.readDeviceStatus();
        if (s != null) return s;
      }
      return BleService.readDeviceStatus(address: addr);
    }

    final a = await readOne(addrA, 'A');
    final b = _isSingle ? null : await readOne(addrB, 'B');

    if (!mounted) return;
    setState(() {
      _addrA = addrA;
      _statusA = a;
      _statusB = b;
      _localRole = role;
      _aiKeyConfigured = key != null && key.isNotEmpty;
      _loadingStatus = false;
    });
  }

  bool get _bothPaired =>
      (_statusA?.paired ?? false) && (_statusB?.paired ?? false);

  int? get _partnerRssi {
    for (final s in [_statusA, _statusB]) {
      final r = s?.partnerRssi;
      if (r != null && r > -100) return r;
    }
    return null;
  }

  String _deviceSummary(DeviceStatus? s) {
    if (s == null) return '离线';
    final parts = <String>['在线'];
    if (s.battery != null) parts.add('电量 ${s.battery}%');
    parts.add(s.modeName);
    return parts.join(' · ');
  }

  String get _voiceLabel {
    switch (_voiceState) {
      case VoiceSessionState.idle:
        return _voiceEnabled ? '已连接' : '未启用';
      case VoiceSessionState.connecting:
        return '连接中';
      case VoiceSessionState.listening:
        return '接收语音';
      case VoiceSessionState.thinking:
        return '识别中';
      case VoiceSessionState.replying:
        return '生成回复';
      case VoiceSessionState.error:
        return '异常';
    }
  }

  Color get _voiceColor {
    switch (_voiceState) {
      case VoiceSessionState.idle:
        return _voiceEnabled ? Colors.green : Colors.grey;
      case VoiceSessionState.connecting:
        return Colors.orange;
      case VoiceSessionState.listening:
      case VoiceSessionState.thinking:
      case VoiceSessionState.replying:
        return const Color(0xFF6BB5FF);
      case VoiceSessionState.error:
        return Colors.red;
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      _buildStatusPage(),
      _buildSettingsPage(),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('💕 情侣互动'),
        actions: [
          if (_currentIndex == 0)
            IconButton(
              tooltip: '刷新状态',
              onPressed: _loadingStatus ? null : _refreshStatus,
              icon: _loadingStatus
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh),
            ),
        ],
      ),
      body: pages[_currentIndex],
      bottomNavigationBar: NavigationBar(
        backgroundColor: const Color(0xFF16162A),
        indicatorColor: const Color(0xFFFF6B9D).withOpacity(0.3),
        selectedIndex: _currentIndex,
        onDestinationSelected: (i) => setState(() => _currentIndex = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.favorite_border),
            selectedIcon: Icon(Icons.favorite, color: Color(0xFFFF6B9D)),
            label: '状态',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings, color: Color(0xFFFF6B9D)),
            label: '设置',
          ),
        ],
      ),
    );
  }

  Widget _buildStatusPage() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 200,
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment.center,
                radius: 0.8,
                colors: [
                  const Color(0xFFFF6B9D).withOpacity(0.3),
                  const Color(0xFF1A1A2E),
                ],
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Center(
              child: Icon(Icons.favorite, size: 80, color: Color(0xFFFF6B9D)),
            ),
          ),
          const SizedBox(height: 24),

          if (_isSingle)
            _deviceCard(_role, widget.deviceAName, _statusA)
          else
            Row(
              children: [
                Expanded(child: _deviceCard('A', widget.deviceAName, _statusA)),
                const SizedBox(width: 12),
                Expanded(
                    child: _deviceCard(
                        'B', widget.deviceBName ?? '设备B', _statusB)),
              ],
            ),
          const SizedBox(height: 24),

          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('连接状态',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  _statusRow(
                      '语音服务', _voiceLabel,
                      color: _voiceColor),
                  if (_voiceState == VoiceSessionState.error) ...[
                    const SizedBox(height: 6),
                    Text(_voiceStatus,
                        style:
                            const TextStyle(color: Colors.red, fontSize: 12)),
                  ],
                  const SizedBox(height: 8),
                  if (!_isSingle) ...[
                    _statusRow('配对状态', _bothPaired ? '已配对' : '未完成配对',
                        color: _bothPaired ? Colors.green : Colors.orange),
                    const SizedBox(height: 8),
                    _statusRow('设备 A', _deviceSummary(_statusA),
                        color: _statusA == null ? Colors.grey : Colors.green),
                    const SizedBox(height: 8),
                    _statusRow('设备 B', _deviceSummary(_statusB),
                        color: _statusB == null ? Colors.grey : Colors.green),
                    const SizedBox(height: 8),
                    _statusRow(
                      '心跳通信',
                      _partnerRssi == null
                          ? '未检测到'
                          : '正常 · 信号 $_partnerRssi dBm',
                      color: _partnerRssi == null ? Colors.grey : Colors.green,
                    ),
                  ] else ...[
                    _statusRow('设备状态', _deviceSummary(_statusA),
                        color: _statusA == null ? Colors.grey : Colors.green),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('使用提示',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold)),
                  SizedBox(height: 12),
                  Text('• 设备不连 Wi-Fi，长按 OK 键说话，语音经蓝牙送到手机处理',
                      style: TextStyle(color: Colors.grey, fontSize: 13)),
                  SizedBox(height: 6),
                  Text('• 保持“后台语音服务”开启，App 退到后台也能正常对话',
                      style: TextStyle(color: Colors.grey, fontSize: 13)),
                  SizedBox(height: 6),
                  Text('• 两台设备靠近时工牌页会亮起光效，距离越近呼吸越快',
                      style: TextStyle(color: Colors.grey, fontSize: 13)),
                  SizedBox(height: 6),
                  Text('• 短按 OK 键进入设置菜单，长按 OK 键进入 AI 对话',
                      style: TextStyle(color: Colors.grey, fontSize: 13)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _deviceCard(String role, String name, DeviceStatus? status) {
    final online = status != null;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            CircleAvatar(
              radius: 28,
              backgroundColor: role == 'A'
                  ? const Color(0xFFFF6B9D)
                  : const Color(0xFF6BB5FF),
              child:
                  Text(role, style: const TextStyle(color: Colors.white, fontSize: 24)),
            ),
            const SizedBox(height: 8),
            Text(name,
                style: const TextStyle(color: Colors.white),
                textAlign: TextAlign.center),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: online ? Colors.green : Colors.grey,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 4),
                Text(online ? '在线' : '离线',
                    style: TextStyle(
                        color: online ? Colors.green : Colors.grey,
                        fontSize: 12)),
              ],
            ),
            if (status != null && status.battery != null) ...[
              const SizedBox(height: 4),
              Text('电量 ${status.battery}%',
                  style: const TextStyle(color: Colors.grey, fontSize: 12)),
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

  Widget _buildSettingsPage() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('设备设置', style: TextStyle(color: Colors.grey, fontSize: 13)),
        const SizedBox(height: 8),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.link, color: Color(0xFFFF6B9D)),
                title: const Text('两台串联', style: TextStyle(color: Colors.white)),
                subtitle: Text(
                    _isSingle
                        ? '与对方手机互扫二维码，把两台设备串成一对'
                        : '已串联：${widget.deviceAName} ↔ ${widget.deviceBName}',
                    style: const TextStyle(color: Colors.grey)),
                trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                onTap: _openLinkPage,
              ),
              const Divider(color: Color(0xFF3A3A5E), height: 1),
              ListTile(
                leading: const Icon(Icons.edit, color: Color(0xFFFF6B9D)),
                title: const Text('修改昵称', style: TextStyle(color: Colors.white)),
                subtitle: Text(
                    _isSingle
                        ? widget.deviceAName
                        : '${widget.deviceAName} / ${widget.deviceBName}',
                    style: const TextStyle(color: Colors.grey)),
                trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                onTap: _openNicknameConfig,
              ),
              const Divider(color: Color(0xFF3A3A5E), height: 1),
              ListTile(
                leading: const Icon(Icons.smart_toy, color: Color(0xFFFF6B9D)),
                title: const Text('AI 服务',
                    style: TextStyle(color: Colors.white)),
                subtitle: Text(_aiKeyStatusText,
                    style: const TextStyle(color: Colors.grey)),
                trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                onTap: _openAiService,
              ),
              const Divider(color: Color(0xFF3A3A5E), height: 1),
              SwitchListTile(
                secondary: const Icon(Icons.bluetooth_searching,
                    color: Color(0xFF6BB5FF)),
                title: const Text('后台语音服务',
                    style: TextStyle(color: Colors.white)),
                subtitle: Text('常驻蓝牙连接，退出 App 后也能接收语音\n$_voiceLabel',
                    style: const TextStyle(color: Colors.grey, fontSize: 12)),
                value: _voiceEnabled,
                activeColor: const Color(0xFFFF6B9D),
                onChanged: _toggleVoice,
              ),
              const Divider(color: Color(0xFF3A3A5E), height: 1),
              ListTile(
                leading: const Icon(Icons.access_time, color: Color(0xFF6BB5FF)),
                title: const Text('同步时间',
                    style: TextStyle(color: Colors.white)),
                subtitle: const Text('把手机当前时间同步到设备',
                    style: TextStyle(color: Colors.grey)),
                trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                onTap: _syncingTime ? null : _syncTime,
              ),
              const Divider(color: Color(0xFF3A3A5E), height: 1),
              ListTile(
                leading: const Icon(Icons.volume_up, color: Color(0xFFFF6B9D)),
                title: const Text('心跳音量',
                    style: TextStyle(color: Colors.white)),
                subtitle: const Text('调节靠近时的心跳音效',
                    style: TextStyle(color: Colors.grey)),
                trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => const VolumePage(),
                    ),
                  );
                },
              ),
              const Divider(color: Color(0xFF3A3A5E), height: 1),
              ListTile(
                leading: const Icon(Icons.battery_std, color: Colors.green),
                title: const Text('电量', style: TextStyle(color: Colors.white)),
                subtitle: Text(
                  _isSingle
                      ? 'A: ${_statusA?.battery ?? '--'}%'
                      : 'A: ${_statusA?.battery ?? '--'}%  B: ${_statusB?.battery ?? '--'}%',
                  style: const TextStyle(color: Colors.grey),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        const Text('关于', style: TextStyle(color: Colors.grey, fontSize: 13)),
        const SizedBox(height: 8),
        const Card(
          child: Column(
            children: [
              ListTile(
                leading: Icon(Icons.info_outline, color: Colors.grey),
                title: Text('版本', style: TextStyle(color: Colors.white)),
                trailing: Text('1.1.0', style: TextStyle(color: Colors.grey)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        TextButton(
          onPressed: _showUnpairDialog,
          style: TextButton.styleFrom(foregroundColor: Colors.red),
          child: const Text('解除配对'),
        ),
      ],
    );
  }

  String get _aiKeyStatusText {
    final configured = _aiKeyConfigured;
    if (configured == null) return '--';
    return configured ? '已保存 API Key' : '未配置 API Key';
  }

  void _openLinkPage() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => PhonePairPage(onLinked: widget.onLinked),
      ),
    );
  }

  void _openNicknameConfig() {
    if (_isSingle) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => DeviceConfigPage(
            address: _addrA ?? '',
            deviceName: widget.deviceAName,
            initialName: widget.deviceAName,
          ),
        ),
      );
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => BadgeConfigPage(
          deviceAName: widget.deviceAName,
          deviceBName: widget.deviceBName ?? '设备B',
        ),
      ),
    );
  }

  Future<void> _openAiService() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => const AiServicePage()),
    );
    if (mounted) _refreshStatus();
  }

  Future<void> _syncTime() async {
    final addrA = _addrA;
    if (addrA == null || addrA.isEmpty) {
      _showSnack('设备未连接，请先连接设备');
      return;
    }

    setState(() => _syncingTime = true);
    try {
      final addrs = [addrA];
      if (!_isSingle) {
        final addrB = await StorageService.getDeviceAddress('B');
        if (addrB != null && addrB.isNotEmpty) addrs.add(addrB);
      }

      final results = <String, String?>{};
      for (final addr in addrs) {
        final isLocal = addr == _addrA && VoiceSession.instance.enabled;
        if (isLocal) {
          try {
            await VoiceSession.instance.syncTime();
            results[addr] = null;
          } catch (e) {
            results[addr] = '同步失败：$e';
          }
        } else {
          results[addr] = await BleService.writeDeviceTime(address: addr);
        }
      }
      if (!mounted) return;

      final failed = <String>[];
      for (final entry in results.entries) {
        if (entry.value != null) failed.add(entry.value!);
      }
      if (failed.isEmpty) {
        _showSnack('时间已同步到 ${results.length} 台设备');
      } else if (failed.length == results.length) {
        _showSnack('同步失败：${failed.first}');
      } else {
        _showSnack('部分同步失败：${failed.first}');
      }
    } finally {
      if (mounted) setState(() => _syncingTime = false);
    }
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _showUnpairDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF252540),
        title: const Text('解除配对', style: TextStyle(color: Colors.white)),
        content: const Text('确定要解除配对吗？解除后两台设备将无法通信。',
            style: TextStyle(color: Colors.grey)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              await VoiceSession.instance.disable();
              await StorageService.setVoiceEnabled(false);
              await StorageService.clearAll();
              widget.onUnpair();
              if (mounted) Navigator.of(context).pop();
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('确定解除'),
          ),
        ],
      ),
    );
  }
}
