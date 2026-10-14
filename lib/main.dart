import 'package:flutter/material.dart';
import 'pages/scan_page.dart';
import 'pages/home_page.dart';
import 'services/storage_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await StorageService.init();
  runApp(const AiPassportApp());
}

class AiPassportApp extends StatelessWidget {
  const AiPassportApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AI Passport 情侣版',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFFF6B9D),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFF1A1A2E),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF1A1A2E),
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        cardTheme: CardThemeData(
          color: const Color(0xFF252540),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      home: const AppRoot(),
    );
  }
}

class AppRoot extends StatefulWidget {
  const AppRoot({super.key});

  @override
  State<AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<AppRoot> {
  bool _isPaired = false;
  String? _mode;
  String? _deviceAName;
  String? _deviceBName;

  @override
  void initState() {
    super.initState();
    _loadPairStatus();
  }

  Future<void> _loadPairStatus() async {
    final paired = await StorageService.isPaired();
    final mode = await StorageService.getMode();
    final nameA = await StorageService.getDeviceName('A');
    final nameB = await StorageService.getDeviceName('B');
    if (!mounted) return;
    setState(() {
      _isPaired = paired;
      _mode = mode;
      _deviceAName = nameA;
      _deviceBName = nameB;
    });
  }

  void _onPaired(String nameA, String nameB) {
    setState(() {
      _isPaired = true;
      _mode = 'pair';
      _deviceAName = nameA;
      _deviceBName = nameB;
    });
  }

  void _onUnpaired() {
    setState(() {
      _isPaired = false;
      _mode = null;
      _deviceAName = null;
      _deviceBName = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final single = !_isPaired && _mode == 'single';
    // 已配对或单台模式均进入主页；单台模式下设备 B 允许为空
    if (_isPaired || single) {
      return HomePage(
        deviceAName: _deviceAName ?? '设备A',
        deviceBName: single ? null : (_deviceBName ?? '设备B'),
        onUnpair: _onUnpaired,
      );
    }
    return ScanPage(
      onPaired: _onPaired,
      onSingleConfigured: _loadPairStatus,
    );
  }
}
