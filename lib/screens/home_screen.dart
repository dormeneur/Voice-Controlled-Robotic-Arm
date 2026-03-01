import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:permission_handler/permission_handler.dart';

import '../config/app_config.dart';
import '../services/bluetooth_service.dart';
import '../services/gemini_service.dart';
import '../services/speech_service.dart';
import '../utils/command_mapper.dart';

// ── Color constants ────────────────────────────────────────────────────
const _kCyan = Color(0xFF00E5FF);
const _kBg = Color(0xFF04060E);
const _kSurface = Color(0xFF0D111D);
const _kSurfaceLight = Color(0xFF161C2D);

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final BluetoothService _bluetoothService = BluetoothService();
  final SpeechService _speechService = SpeechService();

  String _connectionStatus = 'Disconnected';
  String _recognizedText = '';
  String _commandStatus = '';
  bool _isListening = false;
  int _selectedTab = 0; // 0: Control, 1: Camera
  bool _cameraRecording = false;

  // ── AI / Gemini state ──────────────────────────────────────────────
  final GeminiService _geminiService = GeminiService();
  bool _aiMode = true;
  bool _isProcessingAI = false;
  String _pendingSequence = '';
  int _activeSequenceIdx = -1;

  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _requestPermissions();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _pulseAnim = Tween(begin: 1.0, end: 1.18).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  // ── Permissions ──────────────────────────────────────────────────────

  Future<void> _requestPermissions() async {
    await [
      Permission.bluetooth,
      Permission.bluetoothConnect,
      Permission.bluetoothScan,
      Permission.location,
      Permission.microphone,
    ].request();
  }

  // ── Helpers ──────────────────────────────────────────────────────────

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(color: Colors.white)),
        backgroundColor: _kSurfaceLight,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  // ── Bluetooth ────────────────────────────────────────────────────────

  Future<void> _showDeviceList() async {
    try {
      final devices = await _bluetoothService.getPairedDevices();
      if (devices.isEmpty) {
        _showSnackBar('No paired devices found');
        return;
      }
      if (!mounted) return;
      showModalBottomSheet(
        context: context,
        backgroundColor: _kSurface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (context) {
          return SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 12),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Paired Devices',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      children: devices
                          .map(
                            (device) => ListTile(
                              leading: Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: _kCyan.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(
                                  Icons.bluetooth,
                                  color: _kCyan,
                                  size: 20,
                                ),
                              ),
                              title: Text(
                                device.name ?? 'Unknown',
                                style: const TextStyle(color: Colors.white),
                              ),
                              subtitle: Text(
                                device.address,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.5),
                                ),
                              ),
                              trailing: const Icon(
                                Icons.chevron_right,
                                color: Colors.white38,
                              ),
                              onTap: () {
                                Navigator.pop(context);
                                _connectToDevice(device);
                              },
                            ),
                          )
                          .toList(),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          );
        },
      );
    } catch (e) {
      _showSnackBar('Error: $e');
    }
  }

  Future<void> _connectToDevice(BluetoothDevice device) async {
    setState(() => _connectionStatus = 'Connecting...');
    try {
      await _bluetoothService.connectToDevice(device);
      setState(() => _connectionStatus = 'Connected to ${device.name}');
    } catch (e) {
      setState(() => _connectionStatus = 'Connection failed');
      final errorMessage = _parseBTError(e.toString());
      _showSnackBar(errorMessage);
    }
  }

  String _parseBTError(String error) {
    // Parse socket errors and show friendly messages
    if (error.contains('Connection refused')) {
      return 'Device not responding. Make sure HC-05 is powered and in range.';
    } else if (error.contains('Operation timed out')) {
      return 'Connection timed out. The device may be busy or out of range.';
    } else if (error.contains('Connection reset by peer')) {
      return 'Connection lost. Try turning the device off and on.';
    } else if (error.contains('No route to host')) {
      return 'Cannot reach device. Check if Bluetooth is enabled.';
    } else if (error.contains('Permission denied')) {
      return 'Bluetooth permission denied. Check app permissions.';
    } else if (error.contains('already connected')) {
      return 'Device is already connected.';
    } else {
      return 'Connection failed. Please try again.';
    }
  }

  Future<void> _disconnect() async {
    await _bluetoothService.disconnect();
    setState(() => _connectionStatus = 'Disconnected');
  }

  // ── Speech ───────────────────────────────────────────────────────────

  Future<void> _toggleListening() async {
    if (_isListening) {
      await _speechService.stopListening();
      setState(() => _isListening = false);
      return;
    }

    final available = await _speechService.initialize();
    if (!available) {
      _showSnackBar('Speech recognition not available');
      return;
    }

    setState(() {
      _isListening = true;
      _recognizedText = '';
      _commandStatus = '';
    });

    await _speechService.startListening((text, isFinal) {
      setState(() {
        _recognizedText = text;
        if (isFinal) _isListening = false;
      });
      if (isFinal) _processCommand(text);
    });
  }

  // ── Command Processing ───────────────────────────────────────────────

  void _processCommand(String text) {
    if (_aiMode) {
      _processWithAI(text);
    } else {
      final command = CommandMapper.mapCommand(text);
      if (command != null) {
        _sendCommand(command);
      } else {
        setState(() => _commandStatus = 'Command not recognized');
      }
    }
  }

  Future<void> _processWithAI(String text) async {
    if (AppConfig.effectiveApiKey.isEmpty) {
      _showSnackBar('Set your Gemini API key in Settings first.');
      _showApiKeyDialog();
      return;
    }
    setState(() {
      _isProcessingAI = true;
      _commandStatus = '';
      _pendingSequence = '';
      _activeSequenceIdx = -1;
    });
    try {
      final sequence = await _geminiService.parseSequence(text);
      setState(() {
        _pendingSequence = sequence;
        _isProcessingAI = false;
      });
      await _executeSequence(sequence);
    } catch (e) {
      setState(() {
        _isProcessingAI = false;
        _commandStatus = e.toString().replaceAll('Exception: ', '');
      });
    }
  }

  Future<void> _executeSequence(String sequence) async {
    for (int i = 0; i < sequence.length; i++) {
      setState(() => _activeSequenceIdx = i);
      await _sendCommand(sequence[i]);
      await Future.delayed(const Duration(milliseconds: 600));
    }
    setState(() {
      _activeSequenceIdx = -1;
      _commandStatus = 'Sequence complete';
    });
  }

  Future<void> _sendCommand(String command) async {
    if (!_bluetoothService.isConnected) {
      _showSnackBar('Not connected to any device');
      return;
    }
    try {
      await _bluetoothService.sendCommand(command);
      setState(() => _commandStatus = 'Sent: $command');
    } catch (e) {
      _showSnackBar('Failed to send command: $e');
    }
  }

  // ── Settings / API Key ───────────────────────────────────────────────

  void _showApiKeyDialog() {
    final keyConfigured = AppConfig.effectiveApiKey.isNotEmpty;
    final controller = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _kSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Gemini API Key',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  keyConfigured ? Icons.check_circle : Icons.info_outline,
                  size: 14,
                  color: keyConfigured
                      ? const Color(0xFF00E676)
                      : Colors.white38,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    keyConfigured
                        ? 'API key is configured'
                        : 'Add GEMINI_API_KEY to your .env file',
                    style: TextStyle(
                      color: keyConfigured
                          ? const Color(0xFF00E676)
                          : Colors.white54,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              obscureText: true,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Paste override key...',
                hintStyle: TextStyle(color: Colors.white24),
                filled: true,
                fillColor: _kBg,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: _kCyan.withValues(alpha: 0.3)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.white12),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: _kCyan),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: TextStyle(color: Colors.white38)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _kCyan,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () {
              final key = controller.text.trim();
              if (key.isNotEmpty) {
                AppConfig.geminiApiKey = key;
                _showSnackBar('API key override saved.');
              }
              Navigator.pop(ctx);
            },
            child: const Text(
              'Save',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  // ── Lifecycle ────────────────────────────────────────────────────────

  @override
  void dispose() {
    _pulseController.dispose();
    _speechService.stopListening();
    _bluetoothService.disconnect();
    super.dispose();
  }

  // ── Build ────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: _kBg,
      drawer: _buildDrawer(),
      drawerEdgeDragWidth: 40,
      body: Stack(
        children: [
          // Subtle ambient glow
          Positioned(
            top: -100,
            right: -100,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _kCyan.withValues(alpha: 0.1),
              ),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 80, sigmaY: 80),
                child: const SizedBox(),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                // Tab Navigation
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 10,
                  ),
                  child: _buildTabBar(),
                ),
                // Tab Content
                Expanded(
                  child: _selectedTab == 0
                      ? _buildControlView()
                      : _buildCameraView(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      decoration: BoxDecoration(
        color: _kSurface.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
          Expanded(child: _buildTabButton('CONTROL', 0)),
          Expanded(child: _buildTabButton('CAMERA', 1)),
        ],
      ),
    );
  }

  Widget _buildTabButton(String label, int index) {
    final isSelected = _selectedTab == index;
    return GestureDetector(
      onTap: () => setState(() => _selectedTab = index),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? _kCyan.withValues(alpha: 0.2)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: isSelected
              ? Border.all(color: _kCyan.withValues(alpha: 0.4))
              : null,
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: isSelected ? _kCyan : Colors.white54,
            letterSpacing: 1.5,
          ),
        ),
      ),
    );
  }

  Widget _buildControlView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(),
          const SizedBox(height: 14),
          _buildVoiceSection(),
          const SizedBox(height: 10),
          _buildCommandStatus(),
          const SizedBox(height: 14),
          _buildManualControls(),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildCameraView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildCameraFeed(),
          const SizedBox(height: 20),
          _buildCameraControls(),
          const SizedBox(height: 20),
          _buildCameraStats(),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildCameraFeed() {
    return Container(
      height: 320,
      decoration: BoxDecoration(
        color: _kSurface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _kCyan.withValues(alpha: 0.2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Stack(
        children: [
          // Dummy video feed
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFF0F1419),
                  const Color(0xFF1A2332),
                  const Color(0xFF0F1419),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.videocam,
                    size: 56,
                    color: _kCyan.withValues(alpha: 0.3),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'CAMERA FEED',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: _kCyan.withValues(alpha: 0.4),
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Ready for streaming',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.3),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Recording indicator
          Positioned(
            top: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: _cameraRecording
                    ? const Color(0xFFFF1744)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _cameraRecording
                      ? const Color(0xFFFF1744)
                      : Colors.white.withValues(alpha: 0.15),
                  width: 2,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_cameraRecording)
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                    ),
                  if (_cameraRecording) const SizedBox(width: 6),
                  Text(
                    _cameraRecording ? 'RECORDING' : 'STANDBY',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: _cameraRecording ? Colors.white : Colors.white54,
                      letterSpacing: 1,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Grid overlay
          Positioned.fill(
            child: IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: _kCyan.withValues(alpha: 0.1)),
                ),
                child: Column(
                  children: List.generate(
                    3,
                    (i) => Expanded(
                      child: Row(
                        children: List.generate(
                          3,
                          (j) => Expanded(
                            child: Container(
                              decoration: BoxDecoration(
                                border: Border(
                                  right: i < 2
                                      ? BorderSide(
                                          color: _kCyan.withValues(alpha: 0.05),
                                        )
                                      : BorderSide.none,
                                  bottom: j < 2
                                      ? BorderSide(
                                          color: _kCyan.withValues(alpha: 0.05),
                                        )
                                      : BorderSide.none,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCameraControls() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _kSurface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 12),
            child: Text(
              'CAMERA CONTROLS',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: Colors.white.withValues(alpha: 0.35),
                letterSpacing: 2,
              ),
            ),
          ),
          // Pan/Tilt controls
          Column(
            children: [
              _cameraControlButton(
                Icons.keyboard_arrow_up,
                'PAN UP',
                Colors.blue,
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: _cameraControlButton(
                      Icons.keyboard_arrow_left,
                      'LEFT',
                      Colors.blue,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _cameraControlButton(
                      Icons.center_focus_strong,
                      'CENTER',
                      _kCyan,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _cameraControlButton(
                      Icons.keyboard_arrow_right,
                      'RIGHT',
                      Colors.blue,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _cameraControlButton(
                Icons.keyboard_arrow_down,
                'PAN DOWN',
                Colors.blue,
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Zoom and recording controls
          Row(
            children: [
              Expanded(
                child: _cameraActionButton(
                  'ZOOM -',
                  Icons.zoom_out,
                  Colors.amber,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _cameraActionButton(
                  'ZOOM +',
                  Icons.zoom_in,
                  Colors.amber,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _cameraActionButton(
                  _cameraRecording ? 'STOP' : 'RECORD',
                  _cameraRecording
                      ? Icons.stop_circle
                      : Icons.fiber_manual_record,
                  _cameraRecording ? const Color(0xFFFF1744) : _kCyan,
                  onTap: () =>
                      setState(() => _cameraRecording = !_cameraRecording),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _cameraControlButton(IconData icon, String label, Color color) {
    return Container(
      height: 56,
      decoration: BoxDecoration(
        color: _kBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {},
          splashColor: color.withValues(alpha: 0.2),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 20, color: color),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: Colors.white54,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _cameraActionButton(
    String label,
    IconData icon,
    Color color, {
    VoidCallback? onTap,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: _kSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.15)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap ?? () {},
          splashColor: color.withValues(alpha: 0.2),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 20, color: color),
                const SizedBox(height: 4),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCameraStats() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: BoxDecoration(
        color: _kSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _statItem('RESOLUTION', '1920×1080', _kCyan),
          _statItem('FPS', '30', Colors.amber),
          _statItem('LATENCY', '~100ms', Colors.green),
        ],
      ),
    );
  }

  Widget _statItem(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: Colors.white.withValues(alpha: 0.4),
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
      ],
    );
  }

  // ── Header ───────────────────────────────────────────────────────────

  Widget _buildHeader() {
    final connected = _bluetoothService.isConnected;
    final connecting = _connectionStatus == 'Connecting...';
    final Color dotColor = connected
        ? const Color(0xFF00E676)
        : (connecting ? const Color(0xFFFFD600) : Colors.white24);

    return Row(
      children: [
        // Menu button
        Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => _scaffoldKey.currentState?.openDrawer(),
            child: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: _kSurface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: const Icon(
                Icons.menu_rounded,
                color: Colors.white70,
                size: 22,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Robotic Arm',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  letterSpacing: -0.5,
                ),
              ),
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: dotColor,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: dotColor.withValues(alpha: 0.6),
                          blurRadius: 6,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    connected
                        ? _connectionStatus.replaceFirst('Connected to ', '')
                        : (connecting ? 'Connecting...' : 'Not connected'),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: connected ? Colors.white54 : Colors.white38,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Side Drawer ──────────────────────────────────────────────────────

  Widget _buildDrawer() {
    final connected = _bluetoothService.isConnected;
    final connecting = _connectionStatus == 'Connecting...';
    final Color statusColor = connected
        ? const Color(0xFF00E676)
        : (connecting ? const Color(0xFFFFD600) : Colors.white24);
    final String statusLabel = connected
        ? 'CONNECTED'
        : (connecting ? 'CONNECTING...' : 'DISCONNECTED');
    final keyConfigured = AppConfig.effectiveApiKey.isNotEmpty;

    return Drawer(
      backgroundColor: _kBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(right: Radius.circular(24)),
      ),
      child: SafeArea(
        child: Column(
          children: [
            // Drawer header
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [_kCyan, Color(0xFF007A8C)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: _kCyan.withValues(alpha: 0.3),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.precision_manufacturing,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Settings',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            letterSpacing: -0.5,
                          ),
                        ),
                        Text(
                          'Connection & Config',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: Colors.white54,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Divider(color: Colors.white.withValues(alpha: 0.06), height: 1),
            const SizedBox(height: 16),

            // ── Bluetooth Section ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _drawerSectionLabel('BLUETOOTH'),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: _kSurface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: connected
                            ? const Color(0xFF00E676).withValues(alpha: 0.2)
                            : Colors.white.withValues(alpha: 0.05),
                      ),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                color: statusColor,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: statusColor.withValues(alpha: 0.6),
                                    blurRadius: 6,
                                    spreadRadius: 1,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    statusLabel,
                                    style: TextStyle(
                                      color: statusColor,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 1.5,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    connected
                                        ? _connectionStatus.replaceFirst(
                                            'Connected to ',
                                            '',
                                          )
                                        : 'HC-05 Target',
                                    style: TextStyle(
                                      color: connected
                                          ? Colors.white
                                          : Colors.white38,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        SizedBox(
                          width: double.infinity,
                          child: _drawerButton(
                            label: connected ? 'Disconnect' : 'Connect',
                            icon: connected
                                ? Icons.link_off
                                : Icons.bluetooth_searching,
                            color: connected ? const Color(0xFFFF1744) : _kCyan,
                            onTap: () {
                              Navigator.pop(context);
                              connected ? _disconnect() : _showDeviceList();
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // ── AI Settings Section ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _drawerSectionLabel('AI CONFIGURATION'),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: _kSurface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.05),
                      ),
                    ),
                    child: Column(
                      children: [
                        // API Key status
                        Row(
                          children: [
                            Icon(
                              keyConfigured
                                  ? Icons.check_circle
                                  : Icons.warning_amber_rounded,
                              size: 16,
                              color: keyConfigured
                                  ? const Color(0xFF00E676)
                                  : const Color(0xFFFF9100),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                keyConfigured
                                    ? 'Gemini API key configured'
                                    : 'API key not set',
                                style: TextStyle(
                                  color: keyConfigured
                                      ? Colors.white70
                                      : const Color(0xFFFF9100),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        SizedBox(
                          width: double.infinity,
                          child: _drawerButton(
                            label: 'Override API Key',
                            icon: Icons.key_rounded,
                            color: _kCyan,
                            onTap: () {
                              Navigator.pop(context);
                              _showApiKeyDialog();
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const Spacer(),

            // ── Footer ──
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: Column(
                children: [
                  Divider(
                    color: Colors.white.withValues(alpha: 0.06),
                    height: 1,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.precision_manufacturing,
                        size: 14,
                        color: Colors.white.withValues(alpha: 0.2),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Voice-Controlled Robotic Arm',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.white.withValues(alpha: 0.2),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _drawerSectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: Colors.white.withValues(alpha: 0.3),
          letterSpacing: 2,
        ),
      ),
    );
  }

  Widget _drawerButton({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        splashColor: color.withValues(alpha: 0.2),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.25)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Voice Section ────────────────────────────────────────────────────

  Widget _buildVoiceSection() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 20),
      decoration: BoxDecoration(
        color: _kSurface,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 15,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Column(
        children: [
          // AI Mode toggle row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.auto_awesome,
                    size: 16,
                    color: _aiMode ? _kCyan : Colors.white38,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'AI MODE',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: _aiMode ? _kCyan : Colors.white38,
                      letterSpacing: 1.5,
                    ),
                  ),
                ],
              ),
              Switch(
                value: _aiMode,
                onChanged: (v) => setState(() => _aiMode = v),
                activeThumbColor: _kCyan,
                activeTrackColor: _kCyan.withValues(alpha: 0.2),
                inactiveThumbColor: Colors.white38,
                inactiveTrackColor: Colors.white12,
              ),
            ],
          ),
          const SizedBox(height: 4),
          // Recognized text / processing indicator
          SizedBox(
            height: 44,
            child: Center(
              child: _isProcessingAI
                  ? Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 1,
                            color: _kCyan,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'Parsing with Gemini...',
                          style: TextStyle(
                            fontSize: 14,
                            color: _kCyan,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    )
                  : AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      child: Text(
                        _recognizedText.isEmpty
                            ? 'Awaiting command...'
                            : '"$_recognizedText"',
                        key: ValueKey(_recognizedText),
                        style: TextStyle(
                          fontSize: _recognizedText.isEmpty ? 16 : 18,
                          fontWeight: _recognizedText.isEmpty
                              ? FontWeight.w400
                              : FontWeight.w600,
                          color: _recognizedText.isEmpty
                              ? Colors.white38
                              : Colors.white,
                          letterSpacing: 0.3,
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 16),
          // Mic button with pulse animation
          GestureDetector(
            onTap: _toggleListening,
            child: AnimatedBuilder(
              animation: _pulseAnim,
              builder: (context, child) {
                final double scale = _isListening ? _pulseAnim.value : 1.0;
                return Transform.scale(
                  scale: scale,
                  child: Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: _isListening
                            ? [const Color(0xFFFF1744), const Color(0xFFD50000)]
                            : [_kCyan, const Color(0xFF00B8D4)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color:
                              (_isListening ? const Color(0xFFFF1744) : _kCyan)
                                  .withValues(alpha: 0.4),
                          blurRadius: _isListening ? 30 : 20,
                          spreadRadius: _isListening ? 4 : 0,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Icon(
                      _isListening ? Icons.graphic_eq : Icons.mic_rounded,
                      color: Colors.white,
                      size: 44,
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 10),
          Text(
            _isListening ? 'LISTENING' : 'TAP TO SPEAK',
            style: TextStyle(
              color: _isListening ? const Color(0xFFFF1744) : Colors.white38,
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 2,
            ),
          ),
        ],
      ),
    );
  }

  // ── Command Status ───────────────────────────────────────────────────

  static const Map<String, String> _cmdLabels = {
    'L': 'LEFT',
    'R': 'RIGHT',
    'U': 'UP',
    'D': 'DOWN',
    'P': 'PICK',
    'O': 'OPEN',
    'X': 'RESET',
  };

  Widget _buildCommandStatus() {
    // If we have a sequence, show the visual sequence player
    if (_pendingSequence.isNotEmpty) {
      return _buildSequenceDisplay();
    }
    if (_commandStatus.isEmpty) return const SizedBox.shrink();
    final bool ok =
        _commandStatus.contains('Sent') || _commandStatus.contains('complete');
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
      decoration: BoxDecoration(
        color: (ok ? const Color(0xFF00E676) : const Color(0xFFFF9100))
            .withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: (ok ? const Color(0xFF00E676) : const Color(0xFFFF9100))
              .withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            ok ? Icons.check_circle_outline : Icons.warning_amber_rounded,
            color: ok ? const Color(0xFF00E676) : const Color(0xFFFF9100),
            size: 20,
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              _commandStatus.toUpperCase(),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: ok ? const Color(0xFF00E676) : const Color(0xFFFF9100),
                letterSpacing: 1,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSequenceDisplay() {
    final bool done = _activeSequenceIdx == -1;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _kSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _kCyan.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.route_rounded, size: 16, color: _kCyan),
              const SizedBox(width: 8),
              Text(
                'AI SEQUENCE',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: _kCyan,
                  letterSpacing: 1.5,
                ),
              ),
              const Spacer(),
              Text(
                _pendingSequence,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: Colors.white24,
                  letterSpacing: 2,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Sequence chips
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: List.generate(_pendingSequence.length, (i) {
              final char = _pendingSequence[i];
              final isActive = i == _activeSequenceIdx;
              final isDone =
                  done || (_activeSequenceIdx != -1 && i < _activeSequenceIdx);
              return AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: isActive
                      ? _kCyan.withValues(alpha: 0.2)
                      : isDone
                      ? const Color(0xFF00E676).withValues(alpha: 0.1)
                      : _kBg,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isActive
                        ? _kCyan
                        : isDone
                        ? const Color(0xFF00E676).withValues(alpha: 0.5)
                        : Colors.white12,
                    width: isActive ? 2 : 1,
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      char,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: isActive
                            ? _kCyan
                            : isDone
                            ? const Color(0xFF00E676)
                            : Colors.white38,
                      ),
                    ),
                    Text(
                      _cmdLabels[char] ?? char,
                      style: TextStyle(
                        fontSize: 8,
                        fontWeight: FontWeight.w700,
                        color: isActive
                            ? _kCyan.withValues(alpha: 0.8)
                            : isDone
                            ? const Color(0xFF00E676).withValues(alpha: 0.7)
                            : Colors.white24,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ),
          if (done) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(
                  Icons.check_circle,
                  size: 14,
                  color: Color(0xFF00E676),
                ),
                const SizedBox(width: 6),
                Text(
                  'SEQUENCE COMPLETE',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF00E676),
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // ── Manual Controls ──────────────────────────────────────────────────

  Widget _buildManualControls() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section label
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 10),
          child: Text(
            'MANUAL OVERRIDE',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: Colors.white.withValues(alpha: 0.35),
              letterSpacing: 2,
            ),
          ),
        ),
        // D-Pad Wrapper
        Container(
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
          decoration: BoxDecoration(
            color: _kSurface,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: _kCyan.withValues(alpha: 0.06)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.4),
                blurRadius: 24,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Column(
            children: [
              // UP
              _dpadButton(Icons.expand_less_rounded, 'U'),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // LEFT
                  _dpadButton(Icons.chevron_left_rounded, 'L'),
                  // Center indicator
                  Container(
                    width: 56,
                    height: 56,
                    margin: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _kBg,
                      border: Border.all(
                        color: _kCyan.withValues(alpha: 0.12),
                        width: 2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: _kCyan.withValues(alpha: 0.08),
                          blurRadius: 12,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: Icon(
                      Icons.control_camera_rounded,
                      color: _kCyan.withValues(alpha: 0.35),
                      size: 24,
                    ),
                  ),
                  // RIGHT
                  _dpadButton(Icons.chevron_right_rounded, 'R'),
                ],
              ),
              const SizedBox(height: 10),
              // DOWN
              _dpadButton(Icons.expand_more_rounded, 'D'),
            ],
          ),
        ),
        const SizedBox(height: 14),
        // Action row
        Row(
          children: [
            Expanded(
              child: _actionButton(
                'PICK',
                'P',
                Icons.front_hand_rounded,
                _kCyan,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _actionButton(
                'RELEASE',
                'O',
                Icons.open_in_full_rounded,
                const Color(0xFFFFD600),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _actionButton(
                'RESET',
                'X',
                Icons.restart_alt_rounded,
                const Color(0xFFFF1744),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _dpadButton(IconData icon, String command) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: () => _sendCommand(command),
        splashColor: _kCyan.withValues(alpha: 0.15),
        highlightColor: _kCyan.withValues(alpha: 0.08),
        child: Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [_kSurfaceLight, _kBg],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: _kCyan.withValues(alpha: 0.10),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.6),
                blurRadius: 10,
                offset: const Offset(0, 5),
              ),
              BoxShadow(
                color: _kCyan.withValues(alpha: 0.04),
                blurRadius: 16,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Center(
            child: Icon(icon, color: _kCyan.withValues(alpha: 0.9), size: 40),
          ),
        ),
      ),
    );
  }

  Widget _actionButton(
    String label,
    String command,
    IconData icon,
    Color color,
  ) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: () => _sendCommand(command),
        splashColor: color.withValues(alpha: 0.15),
        highlightColor: color.withValues(alpha: 0.08),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [color.withValues(alpha: 0.08), _kSurface],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: color.withValues(alpha: 0.18),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 12,
                offset: const Offset(0, 6),
              ),
              BoxShadow(
                color: color.withValues(alpha: 0.06),
                blurRadius: 16,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 22),
            child: Column(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: color.withValues(alpha: 0.10),
                    border: Border.all(color: color.withValues(alpha: 0.15)),
                  ),
                  child: Icon(icon, color: color, size: 24),
                ),
                const SizedBox(height: 10),
                Text(
                  label,
                  style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
