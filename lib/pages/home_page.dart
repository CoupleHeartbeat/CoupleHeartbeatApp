import 'package:flutter/material.dart';
import '../services/ble_service.dart';
import '../services/storage_service.dart';
import 'badge_config_page.dart';
import 'volume_page.dart';
import 'device_config_page.dart';
import 'wifi_config_page.dart';
import 'ai_key_page.dart';

class HomePage extends StatefulWidget {
  final String deviceAName;
  // 单台模式下设备 B 为空/为 null，仅渲染一张设备卡片
  final String? deviceBName;
  final VoidCallback onUnpair;

  const HomePage({
    super.key,
    required this.deviceAName,
    required this.deviceBName,
    required this.onUnpair,
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _currentIndex = 0;
  DeviceStatus? _statusA;
  DeviceStatus? _statusB;
  WifiStatus? _wifiStatus;
  bool? _aiKeyConfigured; // 设备 A 是否已配置 AI 对话 Key，null=未读取到
  String? _addrA;
  bool _loadingStatus = false;

  // 设备 B 名称为空即视为单台模式
  bool get _isSingle =>
      widget.deviceBName == null || widget.deviceBName!.isEmpty;

  @override
  void initState() {
    super.initState();
    _refreshStatus();
  }

  // 按已保存地址重连设备读取真实状态；读不到即视为离线
  Future<void> _refreshStatus() async {
    if (_loadingStatus) return;
    setState(() => _loadingStatus = true);

    final addrA = await StorageService.getDeviceAddress('A');
    final addrB = await StorageService.getDeviceAddress('B');
    final a =
        addrA == null ? null : await BleService.readDeviceStatus(address: addrA);

    DeviceStatus? b;
    if (!_isSingle) {
      b = addrB == null
          ? null
          : await BleService.readDeviceStatus(address: addrB);
    }

    // Wi-Fi 状态：单台模式用于状态卡片，两台模式用于设置页展示行
    WifiStatus? wifi;
    if (addrA != null) {
      wifi = await BleService.readWifiStatus(address: addrA);
    }

    // AI 对话 Key 状态：读取失败（离线/旧固件）返回 null，不影响其它状态
    bool? aiConfigured;
    if (addrA != null) {
      aiConfigured = await BleService.readAiKeyStatus(address: addrA);
    }

    if (!mounted) return;
    setState(() {
      _addrA = addrA;
      _statusA = a;
      _statusB = b;
      _wifiStatus = wifi;
      _aiKeyConfigured = aiConfigured;
      _loadingStatus = false;
    });
  }

  bool get _bothPaired =>
      (_statusA?.paired ?? false) && (_statusB?.paired ?? false);

  // 任一台设备上报了对方的信号强度即认为心跳通信正常
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
          // 心形动画区
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
              child: Icon(
                Icons.favorite,
                size: 80,
                color: Color(0xFFFF6B9D),
              ),
            ),
          ),
          const SizedBox(height: 24),

          // 设备状态：单台模式只渲染一张卡片
          if (_isSingle)
            _deviceCard('A', widget.deviceAName, _statusA)
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

          // 连接状态
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
                  if (_isSingle) ...[
                    // 单台模式：隐藏配对状态与心跳通信，改为展示 Wi-Fi 状态
                    _statusRow('设备状态', _deviceSummary(_statusA),
                        color: _statusA == null ? Colors.grey : Colors.green),
                    const SizedBox(height: 8),
                    _statusRow(
                      'Wi-Fi 状态',
                      _wifiStatus == null ? '设备离线 / 未知' : _wifiStatus!.stateLabel,
                      color: _wifiStatus == null
                          ? Colors.grey
                          : (_wifiStatus!.isConnected
                              ? Colors.green
                              : (_wifiStatus!.state == 3
                                  ? Colors.red
                                  : Colors.orange)),
                    ),
                    const SizedBox(height: 8),
                    _statusRow(
                      'IP 地址',
                      (_wifiStatus?.ip == null || _wifiStatus!.ip!.isEmpty)
                          ? '--'
                          : _wifiStatus!.ip!,
                      color: Colors.white,
                    ),
                    const SizedBox(height: 8),
                    _statusRow(
                      '信号强度',
                      (_wifiStatus?.rssi == null || _wifiStatus!.rssi == 0)
                          ? '--'
                          : '${_wifiStatus!.rssi} dBm',
                      color: Colors.white,
                    ),
                  ] else ...[
                    _statusRow('配对状态',
                        _bothPaired ? '已配对' : '未完成配对',
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
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // 提示
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
                  Text('• 配对设备靠近时，工牌页四周会亮起光效，无需手动开启',
                      style: TextStyle(color: Colors.grey, fontSize: 13)),
                  SizedBox(height: 6),
                  Text('• 距离越近，光效越亮、呼吸越快，心跳音也越急',
                      style: TextStyle(color: Colors.grey, fontSize: 13)),
                  SizedBox(height: 6),
                  Text('• 两台设备贴得很近时，光效达到最强',
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
              child: Text(role,
                  style:
                      const TextStyle(color: Colors.white, fontSize: 24)),
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
        const Text('设备设置',
            style: TextStyle(color: Colors.grey, fontSize: 13)),
        const SizedBox(height: 8),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.edit, color: Color(0xFFFF6B9D)),
                title: const Text('修改昵称',
                    style: TextStyle(color: Colors.white)),
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
                leading: const Icon(Icons.wifi, color: Color(0xFFFF6B9D)),
                title: const Text('Wi-Fi 配网',
                    style: TextStyle(color: Colors.white)),
                subtitle: const Text('为设备下发 Wi-Fi 名称与密码',
                    style: TextStyle(color: Colors.grey)),
                trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                onTap: _openWifiConfig,
              ),
              const Divider(color: Color(0xFF3A3A5E), height: 1),
              ListTile(
                leading: const Icon(Icons.wifi_tethering, color: Color(0xFF6BB5FF)),
                title: const Text('Wi-Fi 状态',
                    style: TextStyle(color: Colors.white)),
                subtitle: Text(_wifiStatusText,
                    style: const TextStyle(color: Colors.grey)),
              ),
              const Divider(color: Color(0xFF3A3A5E), height: 1),
              ListTile(
                leading: const Icon(Icons.smart_toy, color: Color(0xFFFF6B9D)),
                title: const Text('AI 对话配置',
                    style: TextStyle(color: Colors.white)),
                subtitle: Text(_aiKeyStatusText,
                    style: const TextStyle(color: Colors.grey)),
                trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                onTap: _openAiKeyConfig,
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
                trailing: Text('1.0.0', style: TextStyle(color: Colors.grey)),
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

  // 设置页「Wi-Fi 状态」展示文案
  String get _wifiStatusText {
    final s = _wifiStatus;
    if (s == null) return '设备离线 / 未知';
    final parts = <String>[s.stateLabel];
    if (s.ssid != null && s.ssid!.isNotEmpty) parts.add(s.ssid!);
    if (s.ip != null && s.ip!.isNotEmpty) parts.add(s.ip!);
    if (s.rssi != null && s.rssi != 0) parts.add('${s.rssi} dBm');
    return parts.join(' · ');
  }

  // 设置页「AI 对话配置」展示文案：未读取到显示「--」
  String get _aiKeyStatusText {
    final configured = _aiKeyConfigured;
    if (configured == null) return '--';
    return configured ? '已配置 API Key' : '未配置 API Key';
  }

  // 修改昵称入口：单台模式进设备配置页，两台模式进双昵称页
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

  // Wi-Fi 配网入口：使用设备 A 的地址与名称
  void _openWifiConfig() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => WifiConfigPage(
          address: _addrA ?? '',
          deviceName: widget.deviceAName,
        ),
      ),
    );
  }

  // AI 对话配置入口：使用设备 A 的地址与名称，返回后刷新配置状态
  void _openAiKeyConfig() {
    Navigator.of(context)
        .push(
      MaterialPageRoute(
        builder: (context) => AiKeyPage(
          address: _addrA ?? '',
          deviceName: widget.deviceAName,
        ),
      ),
    )
        .then((_) {
      if (mounted) _refreshStatus();
    });
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
