import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:qr/qr.dart';
import '../services/ble_service.dart';
import '../services/storage_service.dart';
import 'scan_qr_page.dart';

// 两台手机串联配对的数据（放在二维码里）
// type 'a'：A 手机发起，携带 pair_id/pair_key 与自己的设备地址
// type 'b'：B 手机回执，携带自己的设备地址
class PairQr {
  final String type; // 'a' | 'b'
  final String pairId;
  final String pairKey;
  final String role;
  final String address;
  final String name;

  const PairQr({
    required this.type,
    required this.pairId,
    required this.pairKey,
    required this.role,
    required this.address,
    required this.name,
  });

  String encode() => jsonEncode({
        'v': 1,
        't': type,
        'pid': pairId,
        'pk': pairKey,
        'role': role,
        'addr': address,
        'name': name,
      });

  static PairQr? decode(String raw) {
    try {
      final map = jsonDecode(raw);
      if (map is! Map) return null;
      if (map['v'] != 1) return null;
      final type = map['t'];
      final pid = map['pid'];
      final pk = map['pk'];
      final role = map['role'];
      final addr = map['addr'];
      final name = map['name'];
      if (type is! String || pid is! String || addr is! String) return null;
      if (pk is! String || role is! String || name is! String) return null;
      if (pid.length < 16 || addr.isEmpty) return null;
      return PairQr(
        type: type,
        pairId: pid,
        pairKey: pk,
        role: role,
        address: addr,
        name: name,
      );
    } catch (_) {
      return null;
    }
  }
}

// 两台串联：两台手机已各自绑定一台设备（首页配对），
// 从设置进入本页，用二维码交换 pair_id / pair_key / 对方地址，
// 分别写入各自的设备后，两台设备即串联成一对。
class PhonePairPage extends StatefulWidget {
  final Function(String nameA, String nameB) onLinked;

  const PhonePairPage({
    super.key,
    required this.onLinked,
  });

  @override
  State<PhonePairPage> createState() => _PhonePairPageState();
}

class _PhonePairPageState extends State<PhonePairPage> {
  final _nameController = TextEditingController(text: '亲爱的');
  final _codeController = TextEditingController();

  String _role = 'A';
  bool _busy = false;
  String _status = '';

  String? _pairId;
  String? _pairKey;
  PairQr? _remote; // A 扫到的 B 回执，或 B 扫到的 A 邀请

  // 本机绑定的设备（首页配对时保存的地址与昵称）
  String? _ownAddr;
  String? _ownName;
  bool _ready = false;
  bool _loadFailed = false;

  String get _address => _ownAddr ?? '';

  @override
  void initState() {
    super.initState();
    _loadOwnDevice();
  }

  Future<void> _loadOwnDevice() async {
    final role = await StorageService.getLocalRole();
    final address =
        await StorageService.getLocalAddress() ??
            await StorageService.getDeviceAddress('A');
    final name = await StorageService.getDeviceName(role ?? 'A');
    if (!mounted) return;
    if (address == null || address.isEmpty) {
      setState(() => _loadFailed = true);
      return;
    }
    _ownAddr = address;
    _ownName = name;
    if (name != null && name.isNotEmpty) {
      _nameController.text = name;
    }
    setState(() => _ready = true);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  Future<String?> _scan() async {
    final status = await Permission.camera.request();
    if (!status.isGranted) {
      if (mounted) _snack('需要相机权限才能扫描二维码');
      return null;
    }
    if (!mounted) return null;
    return Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (context) => const ScanQrPage()),
    );
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  String _validatedName() {
    final name = _nameController.text.trim();
    return name.isEmpty ? '亲爱的' : name;
  }

  bool _validCode() => RegExp(r'^\d{4}$').hasMatch(_codeController.text.trim());

  // A：生成邀请二维码
  void _generateInvite() {
    if (!_validCode()) {
      _snack('请输入设备屏幕上的 4 位配对码');
      return;
    }
    setState(() {
      _pairId = BleService.generatePairId();
      _pairKey = BleService.generatePairKey();
      _status = '让对方手机扫描你的二维码';
    });
  }

  // A：扫描 B 的回执后写入自己的设备，完成串联
  Future<void> _scanPartnerAndWrite() async {
    final raw = await _scan();
    if (raw == null) return;
    final qr = PairQr.decode(raw);
    if (qr == null || qr.type != 'b') {
      _snack('这不是对方的配对回执');
      return;
    }
    if (qr.pairId != _pairId) {
      _snack('配对信息不匹配，请确认双方扫描的是同一次配对的二维码');
      return;
    }
    setState(() {
      _busy = true;
      _status = '正在写入设备 A…';
    });

    final nameA = _validatedName();
    final err = await BleService.pairDevice(
      device: BluetoothDevice.fromId(_address),
      role: 'A',
      pairId: _pairId!,
      pairKey: _pairKey!,
      partnerAddress: qr.address,
      badgeName: nameA,
      pairCode: _codeController.text.trim(),
    );
    if (!mounted) return;
    if (err != null) {
      setState(() {
        _busy = false;
        _status = '配对失败：$err';
      });
      return;
    }

    await StorageService.setPaired(true);
    await StorageService.setMode('pair');
    await StorageService.setPairId(_pairId!);
    await StorageService.setLocalRole('A');
    await StorageService.setDeviceName('A', nameA);
    await StorageService.setDeviceName('B', qr.name);
    await StorageService.setDeviceAddress('A', _address);
    await StorageService.setDeviceAddress('B', qr.address);

    if (!mounted) return;
    setState(() {
      _busy = false;
      _status = '配对成功！';
    });
    await Future.delayed(const Duration(milliseconds: 700));
    if (!mounted) return;
    widget.onLinked(nameA, qr.name);
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  // B：扫描 A 的邀请
  Future<void> _scanInvite() async {
    final raw = await _scan();
    if (raw == null) return;
    final qr = PairQr.decode(raw);
    if (qr == null || qr.type != 'a') {
      _snack('这不是 A 手机的配对二维码');
      return;
    }
    setState(() {
      _remote = qr;
      _pairId = qr.pairId;
      _pairKey = qr.pairKey;
      _status = '已读取 A 的配对信息，请填写昵称与配对码';
    });
  }

  // B：写入自己的设备，随后展示回执二维码
  Future<void> _writeAsPartner() async {
    final remote = _remote;
    if (remote == null) {
      _snack('请先扫描 A 手机的二维码');
      return;
    }
    if (!_validCode()) {
      _snack('请输入设备屏幕上的 4 位配对码');
      return;
    }

    setState(() {
      _busy = true;
      _status = '正在写入设备 B…';
    });

    final nameB = _validatedName();
    final err = await BleService.pairDevice(
      device: BluetoothDevice.fromId(_address),
      role: 'B',
      pairId: remote.pairId,
      pairKey: remote.pairKey,
      partnerAddress: remote.address,
      badgeName: nameB,
      pairCode: _codeController.text.trim(),
    );
    if (!mounted) return;
    if (err != null) {
      setState(() {
        _busy = false;
        _status = '配对失败：$err';
      });
      return;
    }

    await StorageService.setPaired(true);
    await StorageService.setMode('pair');
    await StorageService.setPairId(remote.pairId);
    await StorageService.setLocalRole('B');
    await StorageService.setDeviceName('A', remote.name);
    await StorageService.setDeviceName('B', nameB);
    await StorageService.setDeviceAddress('A', remote.address);
    await StorageService.setDeviceAddress('B', _address);

    if (!mounted) return;
    setState(() {
      _busy = false;
      _status = '设备 B 已配置，请让 A 手机扫描下方二维码';
    });
  }

  void _finishAsPartner() {
    final nameB = _validatedName();
    final remote = _remote;
    widget.onLinked(remote?.name ?? '设备A', nameB);
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    if (_loadFailed) {
      return Scaffold(
        appBar: AppBar(title: const Text('两台串联')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.link_off, size: 64, color: Colors.grey),
              const SizedBox(height: 16),
              const Text('本机尚未绑定设备',
                  style: TextStyle(color: Colors.grey)),
              const SizedBox(height: 8),
              const Text('请先返回首页，配对绑定一台设备',
                  style: TextStyle(color: Colors.grey, fontSize: 12)),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('返回'),
              ),
            ],
          ),
        ),
      );
    }
    if (!_ready) {
      return Scaffold(
        appBar: AppBar(title: const Text('两台串联')),
        body: const Center(
          child: CircularProgressIndicator(color: Color(0xFFFF6B9D)),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('两台串联')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
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
                          const Text('本机已绑定设备',
                              style:
                                  TextStyle(color: Colors.grey, fontSize: 12)),
                          Text(_ownName ?? '未命名设备',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold)),
                          Text(_address,
                              style: const TextStyle(
                                  color: Colors.grey, fontSize: 11)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment<String>(
                  value: 'A',
                  label: Text('我是 A（发起）'),
                  icon: Icon(Icons.first_page),
                ),
                ButtonSegment<String>(
                  value: 'B',
                  label: Text('我是 B（加入）'),
                  icon: Icon(Icons.last_page),
                ),
              ],
              selected: {_role},
              onSelectionChanged: (s) => setState(() {
                _role = s.first;
                _remote = null;
                _pairId = null;
                _pairKey = null;
                _status = '';
              }),
            ),
            const SizedBox(height: 16),
            _buildNameField(),
            const SizedBox(height: 12),
            _buildCodeField(),
            const SizedBox(height: 8),
            const Text(
              '配对码显示在设备屏幕上（设备未串联时显示）；\n串联过的设备请先短按 OK 键进入设置菜单，选择"恢复出厂设置"。',
              style: TextStyle(color: Colors.grey, fontSize: 12),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            if (_role == 'A') ..._buildARole() else ..._buildBRole(),
            if (_status.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(_status,
                  style: const TextStyle(color: Colors.grey),
                  textAlign: TextAlign.center),
            ],
          ],
        ),
      ),
    );
  }

  List<Widget> _buildARole() {
    final invite = _pairId == null
        ? null
        : PairQr(
            type: 'a',
            pairId: _pairId!,
            pairKey: _pairKey!,
            role: 'A',
            address: _address,
            name: _validatedName(),
          ).encode();
    return [
      _primaryButton(
        label: _pairId == null ? '生成配对二维码' : '重新生成二维码',
        onPressed: _busy ? null : _generateInvite,
      ),
      if (invite != null) ...[
        const SizedBox(height: 16),
        Center(child: QrView(data: invite)),
        const SizedBox(height: 12),
        const Text('让对方手机扫描上面的二维码',
            style: TextStyle(color: Colors.grey, fontSize: 12),
            textAlign: TextAlign.center),
        const SizedBox(height: 16),
        _primaryButton(
          label: '扫描对方回执并写入设备',
          onPressed: _busy ? null : _scanPartnerAndWrite,
          busy: _busy,
        ),
      ],
    ];
  }

  List<Widget> _buildBRole() {
    final confirm = _remote == null
        ? null
        : PairQr(
            type: 'b',
            pairId: _remote!.pairId,
            pairKey: _remote!.pairKey,
            role: 'B',
            address: _address,
            name: _validatedName(),
          ).encode();
    final written = _status.startsWith('设备 B 已配置');
    return [
      if (_remote == null)
        _primaryButton(label: '扫描 A 手机的二维码', onPressed: _scanInvite)
      else
        _primaryButton(
          label: written ? '重新写入设备' : '配置我的设备',
          onPressed: _busy ? null : _writeAsPartner,
          busy: _busy,
        ),
      if (written && confirm != null) ...[
        const SizedBox(height: 16),
        Center(child: QrView(data: confirm)),
        const SizedBox(height: 12),
        const Text('请让 A 手机扫描上面的回执二维码，完成串联',
            style: TextStyle(color: Colors.grey, fontSize: 12),
            textAlign: TextAlign.center),
        const SizedBox(height: 16),
        _primaryButton(label: '完成', onPressed: _finishAsPartner),
      ],
    ];
  }

  Widget _primaryButton({
    required String label,
    VoidCallback? onPressed,
    bool busy = false,
  }) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFFFF6B9D),
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      child: busy
          ? const SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : Text(label, style: const TextStyle(fontSize: 16)),
    );
  }

  Widget _buildNameField() {
    return TextField(
      controller: _nameController,
      style: const TextStyle(color: Colors.white),
      maxLength: 10,
      decoration: InputDecoration(
        counterText: '',
        labelText: '设备昵称',
        labelStyle: const TextStyle(color: Colors.grey),
        filled: true,
        fillColor: const Color(0xFF252540),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  Widget _buildCodeField() {
    return TextField(
      controller: _codeController,
      keyboardType: TextInputType.number,
      maxLength: 4,
      style: const TextStyle(color: Colors.white, letterSpacing: 8),
      decoration: InputDecoration(
        counterText: '',
        labelText: '配对码（设备屏幕 4 位数字）',
        labelStyle: const TextStyle(color: Colors.grey),
        hintText: '0000',
        hintStyle: const TextStyle(color: Colors.grey, letterSpacing: 8),
        filled: true,
        fillColor: const Color(0xFF252540),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }
}

// 二维码绘制（qr 包生成矩阵，白底黑码便于相机识别）
class QrView extends StatelessWidget {
  final String data;
  final double size;
  const QrView({super.key, required this.data, this.size = 240});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(12),
      child: CustomPaint(
        size: Size.square(size),
        painter: _QrPainter(data),
      ),
    );
  }
}

class _QrPainter extends CustomPainter {
  final String data;
  _QrPainter(this.data);

  @override
  void paint(Canvas canvas, Size size) {
    final code = QrCode.fromData(
      data: data,
      errorCorrectLevel: QrErrorCorrectLevel.M,
    );
    final image = QrImage(code);
    final n = image.moduleCount;
    final cell = size.width / n;
    final paint = Paint()..color = Colors.black;
    for (var row = 0; row < n; row++) {
      for (var col = 0; col < n; col++) {
        if (image.isDark(row, col)) {
          canvas.drawRect(
            Rect.fromLTWH(col * cell, row * cell, cell, cell),
            paint,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _QrPainter oldDelegate) =>
      oldDelegate.data != data;
}
