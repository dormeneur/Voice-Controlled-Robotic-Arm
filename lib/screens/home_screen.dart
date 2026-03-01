import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:permission_handler/permission_handler.dart';

import '../services/bluetooth_service.dart';
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
  final BluetoothService _bluetoothService = BluetoothService();
  final SpeechService _speechService = SpeechService();

  String _connectionStatus = 'Disconnected';
  String _recognizedText = '';
  String _commandStatus = '';
  bool _isListening = false;

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
    final command = CommandMapper.mapCommand(text);
    if (command != null) {
      _sendCommand(command);
    } else {
      setState(() => _commandStatus = 'Command not recognized');
    }
  }

  Future<void> _sendCommand(String command) async {
    if (!_bluetoothService.isConnected) {
      _showSnackBar('Not connected to any device');
      return;
    }
    try {
      await _bluetoothService.sendCommand(command);
      setState(() => _commandStatus = 'Command Sent: $command');
    } catch (e) {
      _showSnackBar('Failed to send command: $e');
    }
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
      backgroundColor: _kBg,
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
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildHeader(),
                  const SizedBox(height: 32),
                  _buildConnectionBar(),
                  const SizedBox(height: 32),
                  _buildVoiceSection(),
                  const SizedBox(height: 16),
                  _buildCommandStatus(),
                  const SizedBox(height: 32),
                  _buildManualControls(),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Header ───────────────────────────────────────────────────────────

  Widget _buildHeader() {
    return Row(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [_kCyan, Color(0xFF007A8C)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(14),
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
            size: 26,
          ),
        ),
        const SizedBox(width: 16),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Robotic Arm',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  letterSpacing: -0.5,
                ),
              ),
              Text(
                'Voice & Manual Controller',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Colors.white54,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Connection Bar ───────────────────────────────────────────────────

  Widget _buildConnectionBar() {
    final connected = _bluetoothService.isConnected;
    final connecting = _connectionStatus == 'Connecting...';
    final Color statusColor = connected
        ? const Color(0xFF00E676)
        : (connecting ? const Color(0xFFFFD600) : Colors.white24);
    final String statusLabel = connected
        ? 'SYSTEM CONNECTED'
        : (connecting ? 'CONNECTING...' : 'DISCONNECTED');

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _kSurface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: connected
              ? const Color(0xFF00E676).withValues(alpha: 0.2)
              : Colors.white.withValues(alpha: 0.05),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          // Glowing status dot
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: statusColor,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: statusColor.withValues(alpha: 0.6),
                  blurRadius: 8,
                  spreadRadius: 2,
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  statusLabel,
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  connected
                      ? _connectionStatus.replaceFirst('Connected to ', '')
                      : 'HC-05 Target',
                  style: TextStyle(
                    color: connected ? Colors.white : Colors.white38,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          if (!connected)
            _pillButton(
              label: 'Connect',
              icon: Icons.bluetooth_searching,
              color: _kCyan,
              onTap: _showDeviceList,
            )
          else
            _pillButton(
              label: 'Disconnect',
              icon: Icons.link_off,
              color: const Color(0xFFFF1744),
              onTap: _disconnect,
            ),
        ],
      ),
    );
  }

  Widget _pillButton({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(30),
        onTap: onTap,
        splashColor: color.withValues(alpha: 0.2),
        highlightColor: color.withValues(alpha: 0.1),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 16),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
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
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
      decoration: BoxDecoration(
        color: _kSurface,
        borderRadius: BorderRadius.circular(32),
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
          // Recognized text
          SizedBox(
            height: 60,
            child: Center(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: Text(
                  _recognizedText.isEmpty
                      ? 'Awaiting command...'
                      : '"$_recognizedText"',
                  key: ValueKey(_recognizedText),
                  style: TextStyle(
                    fontSize: _recognizedText.isEmpty ? 16 : 22,
                    fontWeight: _recognizedText.isEmpty
                        ? FontWeight.w400
                        : FontWeight.w600,
                    color: _recognizedText.isEmpty
                        ? Colors.white38
                        : Colors.white,
                    letterSpacing: 0.5,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
          const SizedBox(height: 32),
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
                    width: 90,
                    height: 90,
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
                      size: 40,
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 24),
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

  Widget _buildCommandStatus() {
    if (_commandStatus.isEmpty) return const SizedBox.shrink();
    final bool sent = _commandStatus.contains('Sent');
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
      decoration: BoxDecoration(
        color: (sent ? const Color(0xFF00E676) : const Color(0xFFFF9100))
            .withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: (sent ? const Color(0xFF00E676) : const Color(0xFFFF9100))
              .withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            sent ? Icons.check_circle_outline : Icons.warning_amber_rounded,
            color: sent ? const Color(0xFF00E676) : const Color(0xFFFF9100),
            size: 20,
          ),
          const SizedBox(width: 10),
          Text(
            _commandStatus.toUpperCase(),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: sent ? const Color(0xFF00E676) : const Color(0xFFFF9100),
              letterSpacing: 1,
            ),
          ),
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
          padding: const EdgeInsets.only(left: 4, bottom: 16),
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
          padding: const EdgeInsets.symmetric(vertical: 24),
          decoration: BoxDecoration(
            color: _kSurface,
            borderRadius: BorderRadius.circular(32),
            border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            children: [
              _dpadButton(Icons.keyboard_arrow_up, 'U'),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _dpadButton(Icons.keyboard_arrow_left, 'L'),
                  const SizedBox(width: 64),
                  _dpadButton(Icons.keyboard_arrow_right, 'R'),
                ],
              ),
              const SizedBox(height: 8),
              _dpadButton(Icons.keyboard_arrow_down, 'D'),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // Action row
        Row(
          children: [
            Expanded(
              child: _actionButton(
                'PICK',
                'P',
                Icons.front_hand_outlined,
                _kCyan,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _actionButton(
                'RELEASE',
                'O',
                Icons.open_in_full,
                const Color(0xFFFFD600),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _actionButton(
                'RESET',
                'X',
                Icons.restart_alt,
                const Color(0xFFFF1744),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _dpadButton(IconData icon, String command) {
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        color: _kBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => _sendCommand(command),
          splashColor: _kCyan.withValues(alpha: 0.2),
          highlightColor: _kCyan.withValues(alpha: 0.1),
          child: Center(
            child: Icon(
              icon,
              color: Colors.white.withValues(alpha: 0.8),
              size: 30,
            ),
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
    return Container(
      decoration: BoxDecoration(
        color: _kSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.15)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => _sendCommand(command),
          splashColor: color.withValues(alpha: 0.2),
          highlightColor: color.withValues(alpha: 0.1),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: Column(
              children: [
                Icon(icon, color: color, size: 26),
                const SizedBox(height: 8),
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
