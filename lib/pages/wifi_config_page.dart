import 'dart:async';
import 'package:flutter/material.dart';
import '../services/ble_service.dart';

// Wi-Fi 配网页：向设备下发 SSID/密码，并轮询读取配网结果。
// 成对模式下（secondAddress 非空）可在开关打开时同时给两台设备下发同一套凭据，
// 并支持扫描附近网络后点选填入 SSID。
class WifiConfigPage extends StatefulWidget {
  // 主设备蓝牙地址（单台模式即唯一目标设备）
  final String address;
  // 主设备显示名（只读展示）
  final String deviceName;
  // 成对模式下第二台设备的蓝牙地址（为空表示单台模式）
  final String? secondAddress;
  // 成对模式下第二台设备的显示名
  final String? secondDeviceName;

  const WifiConfigPage({
    super.key,
    required this.address,
    required this.deviceName,
    this.secondAddress,
    this.secondDeviceName,
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
  WifiStatus? _wifiStatus; // 主设备最近一次读取到的 Wi-Fi 状态
  WifiStatus? _secondWifiStatus; // 第二台设备最近一次读取到的 Wi-Fi 状态
  bool _configSecond = true; // 成对配置开关（默认开启）

  // 附近网络扫描
  bool _scanning = false; // 正在扫描
  String _scanProgress = ''; // 扫描进度/结果文案
  List<WifiAp>? _aps; // 扫描到的网络列表（null 表示尚未扫描）
  Timer? _scanTimer;
  int _scanPollCount = 0;
  bool _scanInFlight = false; // 防止扫描读取重入
  static const int _maxScanPolls = 8; // 最多读 8 次
  static const Duration _scanInterval = Duration(milliseconds: 1500); // 每 1.5 秒读一次

  // 配网结果轮询：每 2 秒一次，最多约 20 秒
  Timer? _pollTimer;
  int _pollCount = 0;
  bool _pollInFlight = false; // 防止轮询读取重入
  List<String> _pollAddresses = []; // 本轮轮询目标（下发时确定，避免中途变化）
  static const int _maxPolls = 10;

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

  // 本次是否要同时配置两台
  bool get _configureBoth => _hasSecond && _configSecond;

  // 是否正在执行耗时操作（下发 / 轮询 / 扫描）
  bool get _busy => _configuring || _polling || _scanning;

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  @override
  void dispose() {
    // 页面销毁时必须停止所有轮询，避免 setState after dispose
    _cancelPollTimer();
    _cancelScanTimer();
    _ssidController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // 进入页面先读一次当前状态（成对模式下同时读取第二台）
  Future<void> _loadStatus() async {
    final s = await BleService.readWifiStatus(address: widget.address);
    WifiStatus? s2;
    if (_hasSecond) {
      s2 = await BleService.readWifiStatus(address: widget.secondAddress!);
    }
    if (!mounted) return;
    setState(() {
      _wifiStatus = s;
      _secondWifiStatus = s2;
    });
  }

  void _cancelPollTimer() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _polling = false;
  }

  void _cancelScanTimer() {
    _scanTimer?.cancel();
    _scanTimer = null;
    _scanning = false;
  }

  // ---------- 附近网络扫描 ----------

  // 扫描附近网络：先下发扫描指令，再每 1.5 秒读一次结果（最多 8 次），
  // 直到设备回报 scanning == false。整个过程的轮询在 dispose 后停止。
  Future<void> _startScan() async {
    _cancelScanTimer();
    setState(() {
      _scanning = true;
      _aps = null;
      _scanProgress = '正在请求设备扫描附近网络...';
    });

    final err = await BleService.startWifiScan(address: widget.address);
    if (!mounted) return;

    if (err != null) {
      setState(() {
        _scanning = false;
        _scanProgress = err;
      });
      return;
    }

    setState(() => _scanProgress = '设备扫描中（约 2~4 秒）...');
    _scanPollCount = 0;
    _scanTimer = Timer.periodic(_scanInterval, (_) => _doScanPoll());
  }

  Future<void> _doScanPoll() async {
    if (_scanInFlight) return;
    _scanInFlight = true;
    try {
      final result =
          await BleService.readWifiScanResult(address: widget.address);
      // dispose 后 _scanning 已被 _cancelScanTimer 置 false，直接返回
      if (!mounted || !_scanning) return;

      _scanPollCount++;
      if (result != null) {
        setState(() => _aps = result.aps);
      }

      final done = result != null && result.scanning == false;
      if (done || _scanPollCount >= _maxScanPolls) {
        _cancelScanTimer();
        if (!mounted) return;
        setState(() {
          if (result == null) {
            _scanProgress = '扫描失败：未读取到扫描结果，请靠近设备后重试';
          } else if (result.aps.isEmpty) {
            _scanProgress = '未扫描到附近的 Wi-Fi 网络，请确认设备已开启且靠近路由器';
          } else {
            _scanProgress = '扫描完成，点击下方网络可填入 Wi-Fi 名称';
          }
        });
      } else {
        setState(() => _scanProgress = '设备扫描中（约 2~4 秒）...');
      }
    } finally {
      _scanInFlight = false;
    }
  }

  // ---------- 配网下发 ----------

  // 开始配网：校验 SSID → 下发凭据（成对模式下同时下发两台）→ 成功后轮询状态
  Future<void> _startConfig() async {
    final ssid = _ssidController.text.trim();
    if (ssid.isEmpty) {
      _showSnack('请输入 Wi-Fi 名称（SSID）');
      return;
    }

    // 扫描与配网互斥，先停掉扫描
    _cancelScanTimer();

    setState(() {
      _configuring = true;
      _progress = _configureBoth ? '正在同时下发两台设备...' : '正在下发 Wi-Fi 凭据...';
    });

    if (_configureBoth) {
      await _configBoth(ssid);
      return;
    }

    // 单台：只下发当前设备（保持既有语义）
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

  // 同时下发两台设备：任一台失败都要能看出是哪一台
  Future<void> _configBoth(String ssid) async {
    final results = await BleService.writeWifiCredentialsToMany(
      addresses: [widget.address, widget.secondAddress!],
      ssid: ssid,
      password: _passwordController.text,
    );

    if (!mounted) return;

    final errA = results[widget.address];
    final errB = results[widget.secondAddress!];

    // 两台都失败：直接报错，不再轮询
    if (errA != null && errB != null) {
      setState(() {
        _configuring = false;
        _progress = '$_primaryLabel 下发失败：$errA；'
            '$_secondLabel 下发失败：$errB';
      });
      return;
    }

    final parts = <String>[
      errA == null ? '$_primaryLabel 下发成功' : '$_primaryLabel 下发失败：$errA',
      errB == null ? '$_secondLabel 下发成功' : '$_secondLabel 下发失败：$errB',
    ];
    setState(() {
      _configuring = false;
      _progress = '${parts.join('；')}，正在等待设备连接...';
    });
    _startPolling();
  }

  // 清除配网：下发 {"clear":true}，让设备清空已保存的 Wi-Fi 配置（仅主设备，保持既有语义）
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

  // 轮询读取配网结果：逐台读取，直到各自已连接(2) / 失败(3) / 超时。
  // 目标设备在开始时固定，避免轮询过程中开关变化影响结果。
  void _startPolling() {
    _cancelPollTimer();
    _pollAddresses = _configureBoth
        ? [widget.address, widget.secondAddress!]
        : [widget.address];
    _pollCount = 0;
    setState(() => _polling = true);
    _pollTimer =
        Timer.periodic(const Duration(seconds: 2), (_) => _doPoll());
  }

  Future<void> _doPoll() async {
    if (_pollInFlight) return;
    _pollInFlight = true;
    try {
      final dual = _pollAddresses.length > 1;

      final s1 = await BleService.readWifiStatus(address: widget.address);
      WifiStatus? s2;
      if (dual) {
        s2 = await BleService.readWifiStatus(address: _pollAddresses[1]);
      }
      if (!mounted || !_polling) return;

      setState(() {
        _wifiStatus = s1;
        if (dual) _secondWifiStatus = s2;
      });
      _pollCount++;

      bool terminal(WifiStatus? s) =>
          s != null && (s.state == 2 || s.state == 3);
      final done = terminal(s1) && (!dual || terminal(s2));

      if (done) {
        _cancelPollTimer();
        setState(() => _progress = _resultText(s1, s2, dual, timedOut: false));
        return;
      }

      if (_pollCount >= _maxPolls) {
        _cancelPollTimer();
        setState(() => _progress = _resultText(s1, s2, dual, timedOut: true));
      }
    } finally {
      _pollInFlight = false;
    }
  }

  // 汇总配网结果文案：成对模式下明确指出哪一台失败
  String _resultText(
    WifiStatus? s1,
    WifiStatus? s2,
    bool dual, {
    required bool timedOut,
  }) {
    if (!dual) {
      if (timedOut || s1 == null) return '配网超时，请确认设备在附近后重试';
      return s1.isConnected ? '配网成功' : '配网失败：请检查 Wi-Fi 密码或信号后重试';
    }

    final ok = <String>[];
    final failed = <String>[];
    void judge(String label, WifiStatus? s) {
      if (s != null && s.isConnected) {
        ok.add(label);
      } else {
        failed.add(label);
      }
    }

    judge(_primaryLabel, s1);
    judge(_secondLabel, s2);

    if (failed.isEmpty) return '两台设备均配网成功';
    if (ok.isEmpty) {
      // 优先展示设备上报的断开原因码提示，比笼统的“密码或信号”更可定位
      final hint = (s1?.reasonHint ?? s2?.reasonHint) ??
          '请检查 Wi-Fi 密码或信号后重试';
      return timedOut
          ? '两台设备均未连上（${failed.join('、')}）：$hint'
          : '配网失败（${failed.join('、')}）：$hint';
    }
    final hint = (s2?.reasonHint ?? s1?.reasonHint) ?? '请检查该设备的 Wi-Fi 密码或信号';
    return '配网部分成功：${ok.join('、')} 已连上；'
        '${failed.join('、')} 失败（$hint）';
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final busy = _busy;

    return Scaffold(
      appBar: AppBar(title: const Text('Wi-Fi 配网')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildDeviceCard(),
            if (_hasSecond) ...[
              const SizedBox(height: 16),
              _buildPairSwitchCard(),
            ],
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

  // 成对模式下的「同时配置另一台设备」开关
  Widget _buildPairSwitchCard() {
    return Card(
      child: SwitchListTile(
        value: _configSecond,
        onChanged: _busy
            ? null
            : (v) => setState(() => _configSecond = v),
        activeThumbColor: const Color(0xFFFF6B9D),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        secondary: const Icon(Icons.devices, color: Colors.grey),
        title: const Text('同时配置另一台设备',
            style: TextStyle(color: Colors.white, fontSize: 15)),
        // 开关打开时展示第二台设备名
        subtitle: Text(
          _configSecond
              ? '第二台设备：$_secondLabel'
              : '仅配置当前设备：$_primaryLabel',
          style: const TextStyle(color: Colors.grey, fontSize: 12),
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
            const SizedBox(height: 16),
            _buildScanSection(),
          ],
        ),
      ),
    );
  }

  // 扫描附近网络按钮 + 结果列表
  Widget _buildScanSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _busy ? null : _startScan,
            icon: _scanning
                ? const SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Color(0xFFFF6B9D),
                    ),
                  )
                : const Icon(Icons.search, size: 18),
            label: Text(_scanning ? '扫描中...' : '扫描附近网络',
                style: const TextStyle(fontSize: 14)),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFFFF6B9D),
              side: const BorderSide(color: Color(0xFFFF6B9D)),
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ),
        if (_scanProgress.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(_scanProgress,
              style: const TextStyle(color: Colors.grey, fontSize: 12)),
        ],
        // 扫描结束后才把结果渲染成可点击的列表
        if (!_scanning && _aps != null && _aps!.isNotEmpty) ...[
          const SizedBox(height: 8),
          ..._aps!.map(_buildApTile),
        ],
      ],
    );
  }

  // 单个扫描结果：显示 SSID 与信号强度，点击把 SSID 填入输入框
  Widget _buildApTile(WifiAp ap) {
    final color = _signalColor(ap.rssi);
    return InkWell(
      onTap: _busy
          ? null
          : () => setState(() => _ssidController.text = ap.ssid),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        child: Row(
          children: [
            Icon(Icons.wifi, color: color, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                ap.ssid,
                style: const TextStyle(color: Colors.white, fontSize: 14),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(
              '${ap.rssi} dBm · ${_signalLabel(ap.rssi)}',
              style: TextStyle(color: color, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  // 信号强弱文字标签
  String _signalLabel(int rssi) {
    if (rssi >= -60) return '强';
    if (rssi >= -75) return '中';
    return '弱';
  }

  // 信号强弱颜色：强=绿、中=橙、弱=红
  Color _signalColor(int rssi) {
    if (rssi >= -60) return Colors.green;
    if (rssi >= -75) return Colors.orange;
    return Colors.red;
  }

  Widget _buildStatusCard() {
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
                  if (_polling || _scanning)
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
            // 成对模式：分别展示两台设备的状态，便于看出是哪台失败
            if (_hasSecond) ...[
              _deviceStatusBlock(_wifiStatus, title: _primaryLabel),
              const Divider(color: Color(0xFF3A3A5E), height: 24),
              _deviceStatusBlock(_secondWifiStatus, title: _secondLabel),
            ] else
              _deviceStatusBlock(_wifiStatus),
          ],
        ),
      ),
    );
  }

  // 单台/分台状态行；单台时 title 为 null，保持既有样式
  Widget _deviceStatusBlock(WifiStatus? s, {String? title}) {
    final connected = s?.isConnected ?? false;
    final stateColor = connected
        ? Colors.green
        : (s?.state == 3 ? Colors.red : Colors.orange);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title != null) ...[
          Text(title,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
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
