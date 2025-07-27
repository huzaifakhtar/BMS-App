import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class BLEDeviceInfo {
  final String name;
  final String deviceId;
  final String macAddress;
  final int rssi;
  final List<String> serviceUuids;
  final BluetoothDevice device;
  bool isConnecting;
  bool isConnected;

  BLEDeviceInfo({
    required this.name,
    required this.deviceId,
    required this.macAddress,
    required this.rssi,
    required this.serviceUuids,
    required this.device,
    this.isConnecting = false,
    this.isConnected = false,
  });
}