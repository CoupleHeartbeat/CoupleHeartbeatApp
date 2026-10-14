import 'package:flutter/material.dart';

class BadgeConfigPage extends StatefulWidget {
  final String deviceAName;
  final String deviceBName;

  const BadgeConfigPage({
    super.key,
    required this.deviceAName,
    required this.deviceBName,
  });

  @override
  State<BadgeConfigPage> createState() => _BadgeConfigPageState();
}

class _BadgeConfigPageState extends State<BadgeConfigPage> {
  late TextEditingController _nameAController;
  late TextEditingController _nameBController;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameAController = TextEditingController(text: widget.deviceAName);
    _nameBController = TextEditingController(text: widget.deviceBName);
  }

  @override
  void dispose() {
    _nameAController.dispose();
    _nameBController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);

    // TODO: 通过 BLE 写入设备
    await Future.delayed(const Duration(seconds: 1));

    setState(() => _saving = false);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('昵称已更新')),
      );
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('修改昵称')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildNameCard('A', _nameAController, const Color(0xFFFF6B9D)),
            const SizedBox(height: 16),
            _buildNameCard('B', _nameBController, const Color(0xFF6BB5FF)),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: _saving ? null : _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF6B9D),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
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
                  : const Text('保存', style: TextStyle(fontSize: 16)),
            ),
            const SizedBox(height: 12),
            const Text(
              '昵称将同步显示在设备的工牌模式中',
              style: TextStyle(color: Colors.grey, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNameCard(
      String role, TextEditingController controller, Color color) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: color,
                  child: Text(role,
                      style: const TextStyle(color: Colors.white)),
                ),
                const SizedBox(width: 12),
                Text('设备 $role',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
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
          ],
        ),
      ),
    );
  }
}
