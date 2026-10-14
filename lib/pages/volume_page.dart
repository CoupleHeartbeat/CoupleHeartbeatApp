import 'package:flutter/material.dart';
import '../services/storage_service.dart';

class VolumePage extends StatefulWidget {
  const VolumePage({super.key});

  @override
  State<VolumePage> createState() => _VolumePageState();
}

class _VolumePageState extends State<VolumePage> {
  double _volume = 60;
  bool _muted = false;
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    _loadVolume();
  }

  Future<void> _loadVolume() async {
    // TODO: 从设备读取音量，先用本地缓存
    final saved = await StorageService.getVolume();
    if (saved != null) {
      setState(() => _volume = saved.toDouble());
    }
  }

  Future<void> _syncVolume() async {
    // TODO: 通过 BLE 写入音量到设备
    await StorageService.setVolume(_volume.round());
    setState(() => _syncing = true);
    await Future.delayed(const Duration(milliseconds: 500));
    if (mounted) setState(() => _syncing = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('心跳音量')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 心形图标 + 音量指示
            Center(
              child: Column(
                children: [
                  Icon(
                    _muted ? Icons.volume_off : Icons.favorite,
                    size: 80,
                    color: const Color(0xFFFF6B9D),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _muted ? '已静音' : '${_volume.round()}%',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 36,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 40),

            // 音量滑块
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('心跳音量',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    const Text('恋人越近，心跳声越快越响',
                        style: TextStyle(color: Colors.grey, fontSize: 13)),
                    const SizedBox(height: 16),
                    Slider(
                      value: _volume,
                      min: 0,
                      max: 100,
                      divisions: 20,
                      activeColor: const Color(0xFFFF6B9D),
                      inactiveColor: const Color(0xFF3A3A5E),
                      onChanged: (v) => setState(() {
                        _volume = v;
                        _muted = v == 0;
                      }),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: const [
                        Text('静音', style: TextStyle(color: Colors.grey)),
                        Text('最大', style: TextStyle(color: Colors.grey)),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // 静音开关
            Card(
              child: SwitchListTile(
                title: const Text('静音模式',
                    style: TextStyle(color: Colors.white)),
                subtitle: const Text('关闭后完全无声',
                    style: TextStyle(color: Colors.grey)),
                value: _muted,
                activeColor: const Color(0xFFFF6B9D),
                onChanged: (v) {
                  setState(() {
                    _muted = v;
                    if (v && _volume > 0) {
                      _volume = 0;
                    } else if (!v && _volume == 0) {
                      _volume = 50;
                    }
                  });
                },
              ),
            ),

            const Spacer(),

            // 同步按钮
            ElevatedButton(
              onPressed: _syncing ? null : _syncVolume,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF6B9D),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _syncing
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('同步到设备', style: TextStyle(fontSize: 16)),
            ),
          ],
        ),
      ),
    );
  }
}
