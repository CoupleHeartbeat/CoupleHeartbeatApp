import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'ble_service.dart';
import 'foreground_service.dart';
import 'mimo_service.dart';
import 'storage_service.dart';

enum VoiceSessionState { idle, connecting, listening, thinking, replying, error }

// 语音链路：BLE 长连接接收设备录音 -> 云端 ASR -> 大模型 -> 0xFFEA 回传文本。
//
// 上行分包协议（couple_voice.h）：
//   [0]=type(1=BEGIN 2=DATA 3=END 4=CANCEL) [1]=保留
//   [2..3]=offset LE16  [4..5]=total LE16  [6..]=PCM
//   END 包的 offset 就是实际有效字节数，不补静音。
class VoiceSession {
  VoiceSession._();
  static final VoiceSession instance = VoiceSession._();

  static const int _sampleRate = 8000;
  static const int _replyTextMaxBytes = 400;

  final _stateController = StreamController<VoiceSessionState>.broadcast();
  Stream<VoiceSessionState> get states => _stateController.stream;

  VoiceSessionState _state = VoiceSessionState.idle;
  VoiceSessionState get state => _state;

  String _status = '未启用';
  String get status => _status;

  String _lastTranscript = '';
  String get lastTranscript => _lastTranscript;

  String _lastReply = '';
  String get lastReply => _lastReply;

  bool _enabled = false;
  bool get enabled => _enabled;

  BluetoothDevice? _device;
  BluetoothCharacteristic? _replyChar;
  BluetoothCharacteristic? _statusChar;
  BluetoothCharacteristic? _badgeChar;
  BluetoothCharacteristic? _timeChar;
  StreamSubscription<List<int>>? _notifySub;
  StreamSubscription<BluetoothConnectionState>? _connSub;
  Completer<void>? _disconnected;
  int _mtu = 23;

  BytesBuilder? _pcm;
  int _validBytes = 0;

  void _setState(VoiceSessionState s, String status) {
    _state = s;
    _status = status;
    if (!_stateController.isClosed) _stateController.add(s);
  }

  // 启用后台语音服务：连接本机所配设备并订阅 0xFFE9
  Future<void> enable() async {
    if (_enabled) return;
    _enabled = true;
    await BleService.ensurePermissions();
    await ForegroundService.start();
    unawaited(_run());
  }

  Future<void> disable() async {
    if (!_enabled) return;
    _enabled = false;
    await _notifySub?.cancel();
    _notifySub = null;
    await _connSub?.cancel();
    _connSub = null;
    final d = _device;
    _device = null;
    _replyChar = null;
    _statusChar = null;
    _badgeChar = null;
    _timeChar = null;
    try {
      await d?.disconnect();
    } catch (_) {}
    await ForegroundService.stop();
    _setState(VoiceSessionState.idle, '已停止');
  }

  Future<void> _run() async {
    while (_enabled) {
      try {
        await _connectOnce();
        // 保持连接，直到设备断开或用户关闭服务
        await _disconnected?.future;
      } catch (e) {
        _setState(VoiceSessionState.error, '连接失败：$e');
      }
      if (!_enabled) break;
      _setState(VoiceSessionState.connecting, '等待设备…');
      await Future.delayed(const Duration(seconds: 3));
    }
  }

  Future<void> _connectOnce() async {
    final address = await StorageService.getLocalAddress();
    if (address == null || address.isEmpty) {
      throw '尚未配对设备';
    }

    _setState(VoiceSessionState.connecting, '正在连接设备…');
    final device = BluetoothDevice.fromId(address);
    _device = device;
    _disconnected = Completer<void>();

    await device.connect(timeout: const Duration(seconds: 12));

    // 512 字节 MTU：整段回复文本可单包下发
    try {
      await device.requestMtu(512);
    } catch (_) {}
    _mtu = device.mtuNow;

    final services = await device.discoverServices();
    BluetoothService? svc;
    for (final s in services) {
      if (BleUuids.eq(s.uuid, BleUuids.service)) {
        svc = s;
        break;
      }
    }
    if (svc == null) throw '未找到设备服务(0xFFE0)';

    BluetoothCharacteristic? upChar;
    BluetoothCharacteristic? timeChar;
    _statusChar = null;
    _badgeChar = null;
    for (final c in svc.characteristics) {
      if (BleUuids.eq(c.uuid, BleUuids.voiceUp)) upChar = c;
      if (BleUuids.eq(c.uuid, BleUuids.voiceReply)) _replyChar = c;
      if (BleUuids.eq(c.uuid, BleUuids.timeSync)) timeChar = c;
      if (BleUuids.eq(c.uuid, BleUuids.deviceStatus)) _statusChar = c;
      if (BleUuids.eq(c.uuid, BleUuids.badgeInfo)) _badgeChar = c;
    }
    if (upChar == null || _replyChar == null) {
      throw '固件不支持语音链路，请升级固件';
    }

    await upChar.setNotifyValue(true);
    _notifySub = upChar.onValueReceived.listen(_onPacket);

    _connSub = device.connectionState.listen((s) {
      if (s == BluetoothConnectionState.disconnected) {
        final c = _disconnected;
        if (c != null && !c.isCompleted) c.complete();
      }
    });

    // 复用当前连接同步一次时间：设备没有 RTC 备用电池
    _timeChar = timeChar;
    if (timeChar != null) {
      final now = DateTime.now();
      final payload = jsonEncode({
        'unix': now.toUtc().millisecondsSinceEpoch ~/ 1000,
        'tz_offset': now.timeZoneOffset.inSeconds,
      });
      unawaited(timeChar
          .write(utf8.encode(payload), withoutResponse: false)
          .catchError((_) {}));
    }

    _setState(VoiceSessionState.idle, '已连接，等待设备录音');
  }

  // 复用常驻连接同步时间（手动点“同步时间”时调用）
  Future<void> syncTime() async {
    final char = _timeChar;
    if (char == null || _device?.isConnected != true) return;
    final now = DateTime.now();
    final payload = jsonEncode({
      'unix': now.toUtc().millisecondsSinceEpoch ~/ 1000,
      'tz_offset': now.timeZoneOffset.inSeconds,
    });
    await char.write(utf8.encode(payload), withoutResponse: false);
  }

  // 复用常驻连接读取设备状态，避免与语音会话抢占同一条 BLE 链路
  Future<DeviceStatus?> readDeviceStatus() async {
    if (_device == null || !_device!.isConnected) return null;
    bool paired = false;
    String? badgeName;
    if (_badgeChar != null) {
      try {
        final decoded = jsonDecode(utf8.decode(await _badgeChar!.read()));
        if (decoded is Map) {
          paired = decoded['paired'] == true;
          badgeName = decoded['badge_name'] as String?;
        }
      } catch (_) {}
    }
    int? battery, mode, volume, rssi;
    if (_statusChar != null) {
      try {
        final decoded = jsonDecode(utf8.decode(await _statusChar!.read()));
        if (decoded is Map) {
          battery = (decoded['battery'] as num?)?.toInt();
          mode = (decoded['mode'] as num?)?.toInt();
          volume = (decoded['volume'] as num?)?.toInt();
          rssi = (decoded['rssi'] as num?)?.toInt();
        }
      } catch (_) {}
    }
    return DeviceStatus(
      paired: paired,
      badgeName: badgeName,
      battery: battery,
      mode: mode,
      volume: volume,
      partnerRssi: rssi,
    );
  }

  void _onPacket(List<int> value) {
    if (value.length < 6) return;
    final type = value[0];
    final offset = value[2] | (value[3] << 8);
    final payload = value.sublist(6);

    switch (type) {
      case 1: // BEGIN
        _pcm = BytesBuilder(copy: false);
        _validBytes = 0;
        _pcm!.add(payload);
        _setState(VoiceSessionState.listening, '正在接收语音…');
        break;
      case 2: // DATA
        _pcm?.add(payload);
        break;
      case 3: // END：offset 即实际有效字节数
        _pcm?.add(payload);
        _validBytes = offset;
        unawaited(_finishTurn());
        break;
      case 4: // CANCEL
        _pcm = null;
        _validBytes = 0;
        _setState(VoiceSessionState.idle, '已取消');
        break;
    }
  }

  Future<void> _finishTurn() async {
    final builder = _pcm;
    _pcm = null;
    if (builder == null) return;

    final raw = builder.takeBytes();
    final valid = _validBytes > 0 ? min(_validBytes, raw.length) : raw.length;
    if (valid < _sampleRate) {
      // 不足 0.5 秒，按误触处理
      _setState(VoiceSessionState.idle, '录音太短');
      await _sendReply(1, '录音太短');
      return;
    }

    final wav = _buildWav(Uint8List.sublistView(raw, 0, valid));
    _setState(VoiceSessionState.thinking, '正在识别…');

    try {
      final apiKey = await StorageService.getApiKey();
      final text = await MimoService.transcribe(apiKey: apiKey ?? '', wav: wav);
      if (!_enabled) return;
      if (text.isEmpty) {
        await _sendReply(1, '没听清，再说一遍吧');
        _setState(VoiceSessionState.idle, '未识别到语音');
        return;
      }
      _lastTranscript = text;

      _setState(VoiceSessionState.replying, '正在生成回复…');
      final reply = await MimoService.chat(apiKey: apiKey ?? '', userText: text);
      if (!_enabled) return;

      _lastReply = reply.isEmpty ? '我在呢' : reply;
      await _sendReply(0, _lastReply);
      _setState(VoiceSessionState.idle, '回复已发送');
    } catch (e) {
      final msg = e is MimoException ? e.message : '$e';
      _setState(VoiceSessionState.error, msg);
      await _sendReply(1, msg);
    }
  }

  // 回复下行：单包 [status][UTF-8 文本]，长度不超过 MTU-3
  Future<void> _sendReply(int status, String text) async {
    final char = _replyChar;
    if (char == null) return;

    final maxText = max(1, _mtu - 3 - 1);
    final body = _truncateUtf8(text, min(_replyTextMaxBytes, maxText));
    final bytes = <int>[status, ...body];
    try {
      await char.write(bytes, withoutResponse: false);
    } catch (e) {
      _setState(VoiceSessionState.error, '回复下发失败：$e');
    }
  }

  // 按 UTF-8 字符边界截断，避免把多字节字符劈成两半
  static List<int> _truncateUtf8(String text, int maxBytes) {
    final out = <int>[];
    for (final rune in text.runes) {
      final encoded = utf8.encode(String.fromCharCode(rune));
      if (out.length + encoded.length > maxBytes) break;
      out.addAll(encoded);
    }
    return out;
  }

  // 8 kHz / 16 bit / 单声道 WAV 头 + PCM
  static Uint8List _buildWav(Uint8List pcm) {
    final header = ByteData(44);
    final dataSize = pcm.length;
    header.setUint8(0, 0x52); // R
    header.setUint8(1, 0x49); // I
    header.setUint8(2, 0x46); // F
    header.setUint8(3, 0x46); // F
    header.setUint32(4, 36 + dataSize, Endian.little);
    header.setUint8(8, 0x57); // W
    header.setUint8(9, 0x41); // A
    header.setUint8(10, 0x56); // V
    header.setUint8(11, 0x45); // E
    header.setUint8(12, 0x66); // f
    header.setUint8(13, 0x6d); // m
    header.setUint8(14, 0x74); // t
    header.setUint8(15, 0x20); // space
    header.setUint32(16, 16, Endian.little);
    header.setUint16(20, 1, Endian.little); // PCM
    header.setUint16(22, 1, Endian.little); // 单声道
    header.setUint32(24, _sampleRate, Endian.little);
    header.setUint32(28, _sampleRate * 2, Endian.little);
    header.setUint16(32, 2, Endian.little); // block align
    header.setUint16(34, 16, Endian.little); // 位宽
    header.setUint8(36, 0x64); // d
    header.setUint8(37, 0x61); // a
    header.setUint8(38, 0x74); // t
    header.setUint8(39, 0x61); // a
    header.setUint32(40, dataSize, Endian.little);

    final out = Uint8List(44 + dataSize);
    out.setRange(0, 44, header.buffer.asUint8List());
    out.setRange(44, out.length, pcm);
    return out;
  }
}
