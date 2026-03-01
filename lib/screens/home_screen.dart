import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:permission_handler/permission_handler.dart';

import '../services/bluetooth_service.dart';
import '../services/speech_service.dart';
import '../utils/command_mapper.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final BluetoothService _bluetoothService = BluetoothService();
  final SpeechService _speechService = SpeechService();

  String _connectionStatus = 'Disconnected';
  String _recognizedText = '';
  String _commandStatus = '';
  bool _isListening = false;

  @override
  void initState() {
    super.initState();
    _requestPermissions();
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
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
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
        builder: (context) {
          return ListView.builder(
            shrinkWrap: true,
            itemCount: devices.length,
            itemBuilder: (context, index) {
              final device = devices[index];
              return ListTile(
                leading: const Icon(Icons.bluetooth),
                title: Text(device.name ?? 'Unknown Device'),
                subtitle: Text(device.address),
                onTap: () {
                  Navigator.pop(context);
                  _connectToDevice(device);
                },
              );
            },
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
      setState(() {
        _connectionStatus = 'Connected to ${device.name}';
      });
    } catch (e) {
      setState(() => _connectionStatus = 'Connection failed');
      _showSnackBar('Failed to connect: $e');
    }
  }

  Future<void> _disconnect() async {
    await _bluetoothService.disconnect();
    setState(() {
      _connectionStatus = 'Disconnected';
    });
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
        if (isFinal) {
          _isListening = false;
        }
      });
      if (isFinal) {
        _processCommand(text);
      }
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
    _speechService.stopListening();
    _bluetoothService.disconnect();
    super.dispose();
  }

  // ── Build ────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Robotic Arm Controller'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildConnectionCard(),
            const SizedBox(height: 16),
            _buildVoiceCard(),
            const SizedBox(height: 8),
            _buildCommandStatus(),
            const SizedBox(height: 16),
            _buildManualControls(),
          ],
        ),
      ),
    );
  }

  // ── Connection Card ──────────────────────────────────────────────────

  Widget _buildConnectionCard() {
    final connected = _bluetoothService.isConnected;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                Icon(
                  connected
                      ? Icons.bluetooth_connected
                      : Icons.bluetooth_disabled,
                  color: connected ? Colors.blue : Colors.grey,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _connectionStatus,
                    style: const TextStyle(fontSize: 16),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: connected ? null : _showDeviceList,
                    icon: const Icon(Icons.bluetooth_searching),
                    label: const Text('Connect'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: connected ? _disconnect : null,
                    icon: const Icon(Icons.bluetooth_disabled),
                    label: const Text('Disconnect'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red.shade100,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── Voice Card ───────────────────────────────────────────────────────

  Widget _buildVoiceCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Text(
              _recognizedText.isEmpty
                  ? 'Tap the mic and speak a command'
                  : _recognizedText,
              style: TextStyle(
                fontSize: 18,
                color: _recognizedText.isEmpty ? Colors.grey : null,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            GestureDetector(
              onTap: _toggleListening,
              child: CircleAvatar(
                radius: 36,
                backgroundColor: _isListening ? Colors.red : Colors.blue,
                child: Icon(
                  _isListening ? Icons.mic_off : Icons.mic,
                  color: Colors.white,
                  size: 32,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _isListening ? 'Listening...' : 'Tap to speak',
              style: TextStyle(color: _isListening ? Colors.red : Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  // ── Command Status ───────────────────────────────────────────────────

  Widget _buildCommandStatus() {
    if (_commandStatus.isEmpty) return const SizedBox.shrink();
    return Text(
      _commandStatus,
      style: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.bold,
        color: _commandStatus.contains('Sent') ? Colors.green : Colors.orange,
      ),
      textAlign: TextAlign.center,
    );
  }

  // ── Manual Controls ──────────────────────────────────────────────────

  Widget _buildManualControls() {
    return Column(
      children: [
        const Text(
          'Manual Controls',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        // Up
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [_controlButton('Up', 'U', Icons.arrow_upward)],
        ),
        // Left / Right
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _controlButton('Left', 'L', Icons.arrow_back),
            const SizedBox(width: 56),
            _controlButton('Right', 'R', Icons.arrow_forward),
          ],
        ),
        // Down
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [_controlButton('Down', 'D', Icons.arrow_downward)],
        ),
        const SizedBox(height: 8),
        // Action buttons
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _controlButton('Pick', 'P', Icons.pan_tool),
            _controlButton('Release', 'O', Icons.open_with),
            _controlButton('Reset', 'X', Icons.restart_alt),
          ],
        ),
      ],
    );
  }

  Widget _controlButton(String label, String command, IconData icon) {
    return Padding(
      padding: const EdgeInsets.all(4),
      child: ElevatedButton(
        onPressed: () => _sendCommand(command),
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 24),
            const SizedBox(height: 4),
            Text(label, style: const TextStyle(fontSize: 12)),
          ],
        ),
      ),
    );
  }
}
