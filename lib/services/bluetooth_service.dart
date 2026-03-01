import 'dart:typed_data';

import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';

class BluetoothService {
  BluetoothConnection? _connection;

  bool get isConnected => _connection != null && _connection!.isConnected;

  /// Returns a list of already-paired Bluetooth devices.
  Future<List<BluetoothDevice>> getPairedDevices() async {
    return await FlutterBluetoothSerial.instance.getBondedDevices();
  }

  /// Connects to the given Bluetooth device via SPP.
  Future<void> connectToDevice(BluetoothDevice device) async {
    _connection = await BluetoothConnection.toAddress(device.address);
  }

  /// Sends a single-character ASCII command over the Bluetooth connection.
  Future<void> sendCommand(String command) async {
    if (_connection == null || !_connection!.isConnected) {
      throw Exception('Not connected to any device');
    }
    _connection!.output.add(Uint8List.fromList(command.codeUnits));
    await _connection!.output.allSent;
  }

  /// Gracefully closes the Bluetooth connection.
  Future<void> disconnect() async {
    await _connection?.finish();
    _connection = null;
  }
}
