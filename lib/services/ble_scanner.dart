import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../models/ble_device_info.dart';

class BLEScanner extends ChangeNotifier {
  static final BLEScanner _instance = BLEScanner._internal();
  factory BLEScanner() => _instance;
  BLEScanner._internal();

  final List<BLEDeviceInfo> _discoveredDevices = [];
  StreamSubscription<List<ScanResult>>? _scanSubscription;
  StreamSubscription<BluetoothConnectionState>? _connectionSubscription;
  Timer? _scanTimer;
  bool _isScanning = false;

  // Stream controller for discovered devices
  final StreamController<List<BLEDeviceInfo>> _devicesController =
      StreamController<List<BLEDeviceInfo>>.broadcast();

  Stream<List<BLEDeviceInfo>> get devicesStream => _devicesController.stream;
  List<BLEDeviceInfo> get discoveredDevices => List.unmodifiable(_discoveredDevices);
  bool get isScanning => _isScanning;

  // BMS specific service UUIDs (based on common BMS implementations)
  static const List<String> bmsServiceUuids = [
    "0000ff00-0000-1000-8000-00805f9b34fb", // Common BMS service
    "0000ffe0-0000-1000-8000-00805f9b34fb", // Alternative BMS service
    "6e400001-b5a3-f393-e0a9-e50e24dcca9e", // Nordic UART service
  ];


  Future<bool> initialize() async {
    try {
      // Check if Bluetooth is supported
      if (await FlutterBluePlus.isSupported == false) {
        return false;
      }

      // Check adapter state
      var adapterState = await FlutterBluePlus.adapterState.first;
      if (adapterState != BluetoothAdapterState.on) {
        return false;
      }

      return true;
    } catch (e) {
      return false;
    }
  }

  Future<void> startScan({Duration timeout = const Duration(seconds: 10)}) async {
    if (_isScanning) {
      await stopScan();
    }

    try {
      _isScanning = true;
      _discoveredDevices.clear();
      _devicesController.add(_discoveredDevices);
      notifyListeners();

      // Start scanning for BLE devices
      await FlutterBluePlus.startScan(
        withServices: [], // Scan for all services initially
        timeout: timeout,
        androidUsesFineLocation: true,
      );

      // Listen to scan results
      _scanSubscription = FlutterBluePlus.scanResults.listen(
        _onScanResult,
        onError: _onScanError,
      );

      // Auto-stop scanning after timeout
      _scanTimer = Timer(timeout, () {
        stopScan();
      });

    } catch (e) {
      // Scan start failed
      _isScanning = false;
      notifyListeners();
    }
  }

  void _onScanResult(List<ScanResult> results) {
    for (ScanResult result in results) {
      // Filter for BLE devices only and avoid duplicates
      if (_isBLEDevice(result) && !_deviceExists(result.device.remoteId.str)) {
        
        // Extract service UUIDs
        List<String> serviceUuids = result.advertisementData.serviceUuids
            .map((uuid) => uuid.toString().toLowerCase())
            .toList();

        // Only add devices that have ff00 service UUID
        bool hasFF00Service = serviceUuids.any((uuid) => uuid.contains('ff00'));
        
        if (hasFF00Service) {
          // Create device info
          BLEDeviceInfo deviceInfo = BLEDeviceInfo(
            name: result.advertisementData.advName.isNotEmpty 
                ? result.advertisementData.advName 
                : result.device.platformName.isNotEmpty
                    ? result.device.platformName
                    : "Unknown Device",
            deviceId: result.device.remoteId.str,
            macAddress: result.device.remoteId.str,
            rssi: result.rssi,
            serviceUuids: serviceUuids,
            device: result.device,
          );

          _discoveredDevices.add(deviceInfo);
          _devicesController.add(_discoveredDevices);
          notifyListeners();

        }
      }
    }
  }

  void _onScanError(error) {
  }

  bool _isBLEDevice(ScanResult result) {
    // Check if device has advertisement data (BLE characteristic)
    if (result.advertisementData.serviceUuids.isEmpty && 
        result.advertisementData.advName.isEmpty &&
        result.advertisementData.manufacturerData.isEmpty) {
      return false;
    }

    // Additional BLE validation can be added here
    return true;
  }

  bool _deviceExists(String deviceId) {
    return _discoveredDevices.any((device) => device.deviceId == deviceId);
  }


  Future<void> stopScan() async {
    try {
      await FlutterBluePlus.stopScan();
      _scanSubscription?.cancel();
      _scanTimer?.cancel();
      _isScanning = false;
      notifyListeners();
    } catch (e) {
      // Scan stop failed
    }
  }

  Future<bool> connectToDevice(BLEDeviceInfo deviceInfo) async {
    try {
      // Update device state
      deviceInfo.isConnecting = true;
      _updateDeviceList();

      // Connect to device
      await deviceInfo.device.connect(
        timeout: const Duration(seconds: 15),
        autoConnect: false,
      );

      // Listen to connection state
      _connectionSubscription = deviceInfo.device.connectionState.listen((state) {
        deviceInfo.isConnected = (state == BluetoothConnectionState.connected);
        deviceInfo.isConnecting = false;
        _updateDeviceList();
      });

      // Discover services after connection
      await _discoverServices(deviceInfo.device);

      deviceInfo.isConnected = true;
      deviceInfo.isConnecting = false;
      _updateDeviceList();

      return true;
    } catch (e) {
      deviceInfo.isConnecting = false;
      deviceInfo.isConnected = false;
      _updateDeviceList();
      return false;
    }
  }

  Future<void> _discoverServices(BluetoothDevice device) async {
    try {
      await device.discoverServices();
    } catch (e) {
      // Service discovery failed, but connection may still work
    }
  }

  Future<void> disconnectDevice(BLEDeviceInfo deviceInfo) async {
    try {
      await deviceInfo.device.disconnect();
      deviceInfo.isConnected = false;
      deviceInfo.isConnecting = false;
      _connectionSubscription?.cancel();
      _updateDeviceList();
    } catch (e) {
      // Disconnect failed, device may already be disconnected
    }
  }

  void _updateDeviceList() {
    _devicesController.add(_discoveredDevices);
    notifyListeners();
  }

  // Check if device is likely a BMS based on name or services
  bool isBMSDevice(BLEDeviceInfo deviceInfo) {
    String deviceName = deviceInfo.name.toLowerCase();
    
    // Common BMS device name patterns
    List<String> bmsKeywords = [
      'bms', 'battery', 'xiaoxiang', 'jk', 'daly', 'jbd', 'smart', 'lifepo4'
    ];

    // Check device name
    for (String keyword in bmsKeywords) {
      if (deviceName.contains(keyword)) {
        return true;
      }
    }

    // Check service UUIDs
    for (String serviceUuid in deviceInfo.serviceUuids) {
      if (bmsServiceUuids.contains(serviceUuid.toLowerCase())) {
        return true;
      }
    }

    return false;
  }

  // Filter devices to show only BMS devices
  List<BLEDeviceInfo> getBMSDevices() {
    return _discoveredDevices.where((device) => isBMSDevice(device)).toList();
  }


  @override
  void dispose() {
    _scanSubscription?.cancel();
    _connectionSubscription?.cancel();
    _scanTimer?.cancel();
    _devicesController.close();
    stopScan();
    super.dispose();
  }
}

// Usage example
class BLEScannerHelper {
  static Future<void> requestPermissions() async {
    // Request necessary permissions for BLE scanning
    // This should be implemented based on your permission handling package
    // For example, using permission_handler package
  }

  static String formatRSSI(int rssi) {
    if (rssi >= -50) return "Excellent";
    if (rssi >= -60) return "Good";
    if (rssi >= -70) return "Fair";
    return "Poor";
  }

  static String formatServiceUUIDs(List<String> uuids) {
    if (uuids.isEmpty) return "No services";
    return uuids.take(3).join(", ") + (uuids.length > 3 ? "..." : "");
  }
}