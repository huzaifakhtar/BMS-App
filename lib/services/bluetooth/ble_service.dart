import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../core/cache/basic_info_cache.dart';
import '../../core/network/smart_mtu_negotiator.dart';
import '../../core/resilience/circuit_breaker.dart';

class BleService extends ChangeNotifier {
  BluetoothDevice? _connectedDevice;
  String _connectedDeviceName = '';
  BluetoothCharacteristic? _writeCharacteristic;
  BluetoothCharacteristic? _readCharacteristic;
  StreamSubscription<BluetoothConnectionState>? _connectionStateSubscription;
  StreamSubscription<List<int>>? _characteristicSubscription;
  
  // Memory leak fix: Track all subscriptions
  final List<StreamSubscription> _subscriptions = [];
  Timer? _connectionRetryTimer;
  Timer? _healthCheckTimer;
  
  // Circuit breakers for resilient BLE operations
  late final CircuitBreaker _connectionCircuitBreaker;
  late final CircuitBreaker _writeCircuitBreaker;
  // Note: _readCircuitBreaker reserved for future read operation protection
  
  final List<BluetoothDevice> _discoveredDevices = [];
  final List<ScanResult> _scanResults = [];
  bool _isScanning = false;
  bool _isConnected = false;
  String _statusMessage = 'Disconnected';
  final List<Function(List<int>)> _dataCallbacks = [];

  // Getters
  BluetoothDevice? get connectedDevice => _connectedDevice;
  String get connectedDeviceName => _connectedDeviceName;
  List<BluetoothDevice> get discoveredDevices => _discoveredDevices;
  List<ScanResult> get scanResults => _scanResults;
  bool get isScanning => _isScanning;
  bool get isConnected => _isConnected;
  String get statusMessage => _statusMessage;
  BluetoothCharacteristic? get writeCharacteristic => _writeCharacteristic;
  BluetoothCharacteristic? get readCharacteristic => _readCharacteristic;
  List<Function(List<int>)> get dataCallbacks => _dataCallbacks;
  
  // Keep the old getter for backward compatibility
  Function(List<int>)? get dataCallback => _dataCallbacks.isNotEmpty ? _dataCallbacks.first : null;

  // Constructor - Initialize circuit breakers
  BleService() {
    _connectionCircuitBreaker = CircuitBreakerManager.getCircuitBreaker(
      'BLE_Connection',
      failureThreshold: 3,
      resetTimeout: const Duration(seconds: 30),
    );
    
    _writeCircuitBreaker = CircuitBreakerManager.getCircuitBreaker(
      'BLE_Write',
      failureThreshold: 5,
      resetTimeout: const Duration(seconds: 15),
    );
    
    // Note: Read circuit breaker initialization reserved for future implementation
    
    debugPrint('[BLE_SERVICE] 🚀 Initialized with circuit breakers');
  }




  Future<bool> requestPermissions() async {
    debugPrint('[BLE] Requesting permissions for platform: ${Platform.operatingSystem}');
    
    // Let Flutter Blue Plus handle permissions directly on iOS
    if (Platform.isIOS) {
      debugPrint('[BLE] ✅ iOS permissions handled by FlutterBluePlus');
      return true;
    }
    
    // On Android, we still need to request permissions manually
    if (Platform.isAndroid) {
      try {
        debugPrint('[BLE] Requesting Android Bluetooth permissions...');
        Map<Permission, PermissionStatus> statuses = await [
          Permission.bluetoothScan,
          Permission.bluetoothConnect,
          Permission.locationWhenInUse,
        ].request();
        
        debugPrint('[BLE] Permission results:');
        for (var entry in statuses.entries) {
          debugPrint('[BLE]   ${entry.key}: ${entry.value}');
        }
        
        bool allGranted = statuses.values.every((status) => status.isGranted);
        debugPrint('[BLE] All permissions granted: $allGranted');
        return allGranted;
      } catch (e) {
        debugPrint('[BLE] ⚠️ Permission request error: $e, assuming granted');
        return true;
      }
    }
    
    debugPrint('[BLE] ✅ Unknown platform, assuming permissions granted');
    return true;
  }


  Future<void> startScan() async {
    if (_isScanning) return;

    _discoveredDevices.clear();
    _scanResults.clear();
    _isScanning = true;
    _updateStatus('Scanning for BLE devices...');
    notifyListeners();

    try {
      // Start BLE scan - show all devices
      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 15),
        androidUsesFineLocation: false,
      );
      
      FlutterBluePlus.scanResults.listen((results) {
        for (ScanResult result in results) {
          // Show only BLE devices (flutter_blue_plus already filters for BLE)
          if (!_discoveredDevices.contains(result.device)) {
            String deviceName = result.device.platformName;
            if (deviceName.isEmpty) {
              deviceName = result.advertisementData.advName;
            }
            if (deviceName.isEmpty) {
              deviceName = "Unknown BLE Device";
            }
            
            debugPrint('[BLE] Found BLE device: $deviceName (${result.device.remoteId}) RSSI: ${result.rssi}');
            
            _discoveredDevices.add(result.device);
            _scanResults.add(result);
            notifyListeners();
          }
        }
      });

      await Future.delayed(const Duration(seconds: 15));
      stopScan();
    } catch (e) {
      debugPrint('[BLE] Scan error: $e');
      _updateStatus('Scan error: $e');
      _isScanning = false;
      notifyListeners();
    }
  }

  void stopScan() {
    FlutterBluePlus.stopScan();
    _isScanning = false;
    _updateStatus('Scan complete');
    notifyListeners();
  }

  Future<bool> connectToDevice(BluetoothDevice device, {int maxRetries = 3}) async {
    // Store the device name from scan results before connecting
    _connectedDeviceName = _getDeviceNameFromScanResults(device) ?? 'BMS Device';
    debugPrint('[BLE] Starting connection to $_connectedDeviceName with circuit breaker protection...');
    
    try {
      return await _connectionCircuitBreaker.execute(() async {
        return await _performConnectionWithRetry(device, maxRetries);
      });
    } catch (e) {
      if (e is CircuitBreakerException) {
        debugPrint('[BLE] 🔒 Connection blocked by circuit breaker: ${e.message}');
        _updateStatus('Connection temporarily blocked due to repeated failures');
        return false;
      }
      rethrow;
    }
  }
  
  String? _getDeviceNameFromScanResults(BluetoothDevice device) {
    // Find the device in scan results to get its advertised name
    for (final scanResult in _scanResults) {
      if (scanResult.device.remoteId == device.remoteId) {
        String deviceName = scanResult.device.platformName;
        if (deviceName.isEmpty) {
          deviceName = scanResult.advertisementData.advName;
        }
        if (deviceName.isNotEmpty) {
          return deviceName;
        }
      }
    }
    return null;
  }

  Future<bool> _performConnectionWithRetry(BluetoothDevice device, int maxRetries) async {
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        debugPrint('[BLE] 📡 Connection attempt $attempt/$maxRetries to $_connectedDeviceName');
        _updateStatus('Connecting to $_connectedDeviceName... (attempt $attempt/$maxRetries)');
        
        // Progressive timeout increase
        final timeout = Duration(seconds: 10 + (attempt * 5));
        await device.connect(timeout: timeout);
        
        debugPrint('[BLE] ✅ Connection successful on attempt $attempt');
        return await _postConnectionSetup(device);
        
      } catch (e) {
        debugPrint('[BLE] ❌ Connection attempt $attempt failed: $e');
        
        if (attempt == maxRetries) {
          debugPrint('[BLE] 💀 All connection attempts exhausted');
          _updateStatus('Connection failed after $maxRetries attempts');
          throw Exception('Connection failed after $maxRetries attempts: $e');
        }
        
        // Exponential backoff
        final delay = Duration(seconds: (1 << attempt)); // 2^attempt seconds
        debugPrint('[BLE] ⏳ Waiting ${delay.inSeconds}s before retry...');
        await Future.delayed(delay);
      }
    }
    
    return false;
  }

  Future<bool> _postConnectionSetup(BluetoothDevice device) async {
    try {
      _connectedDevice = device;
      
      // Log device info for debugging
      debugPrint('[BLE] Connected device platform name: "${device.platformName}"');
      debugPrint('[BLE] Connected device remote ID: ${device.remoteId}');
      
      // Setup connection monitoring with proper subscription tracking
      final connectionSub = device.connectionState.listen(
        (state) => _handleConnectionStateChange(state),
        onError: (error) => _handleConnectionError(error),
        cancelOnError: false,
      );
      _subscriptions.add(connectionSub);
      _connectionStateSubscription = connectionSub;

      await _discoverServices();
      
      // Smart MTU negotiation with progressive fallback
      final mtuResult = await SmartMtuNegotiator.negotiateOptimalMtu(device);
      debugPrint('[BLE] 📡 MTU negotiation result: $mtuResult');
      
      if (mtuResult.isSuccess) {
        debugPrint('[BLE] ✅ Optimal MTU established: ${mtuResult.mtu} bytes (packet size: ${mtuResult.optimalPacketSize})');
      } else {
        debugPrint('[BLE] ⚠️ MTU negotiation not optimal: ${mtuResult.message}');
      }
      
      if (_writeCharacteristic != null && _readCharacteristic != null) {
        _isConnected = true;
        _updateStatus('Connected to $_connectedDeviceName');
        debugPrint('[BLE] 🔔 NOTIFYING LISTENERS - Connection SUCCESS');
        notifyListeners(); // Notify dashboard about connection
        return true;
      } else {
        _updateStatus('JBD BMS service not found');
        await disconnect();
        return false;
      }
    } catch (e) {
      _updateStatus('Connection failed: $e');
      return false;
    }
  }

  Future<void> _discoverServices() async {
    if (_connectedDevice == null) return;

    debugPrint('[BLE] Starting service discovery...');
    List<BluetoothService> services = await _connectedDevice!.discoverServices();
    debugPrint('[BLE] Found ${services.length} services');
    
    // Target UUIDs from PDF documentation
    const String targetServiceUuid = '0000ff00-0000-1000-8000-00805f9b34fb';
    const String targetWriteCharUuid = '0000ff02-0000-1000-8000-00805f9b34fb';
    const String targetReadCharUuid = '0000ff01-0000-1000-8000-00805f9b34fb';
    
    for (BluetoothService service in services) {
      String serviceUuid = service.uuid.toString().toLowerCase();
      debugPrint('[BLE] Service: $serviceUuid');
      
      // Look for exact JBD BMS service UUID from PDF
      if (serviceUuid == targetServiceUuid || serviceUuid.contains('ff00')) {
        debugPrint('[BLE] ✅ Found JBD BMS service: $serviceUuid');
        
        for (BluetoothCharacteristic characteristic in service.characteristics) {
          String charUuid = characteristic.uuid.toString().toLowerCase();
          debugPrint('[BLE]   Characteristic: $charUuid');
          debugPrint('[BLE]   Properties: read=${characteristic.properties.read}, write=${characteristic.properties.write}, notify=${characteristic.properties.notify}');
          
          // JBD write characteristic (0000ff02-0000-1000-8000-00805f9b34fb)
          if (charUuid == targetWriteCharUuid || charUuid.contains('ff02')) {
            _writeCharacteristic = characteristic;
            debugPrint('[BLE]   ✅ Set as WRITE characteristic (UUID: $charUuid)');
          }
          
          // JBD read/notify characteristic (0000ff01-0000-1000-8000-00805f9b34fb)
          if (charUuid == targetReadCharUuid || charUuid.contains('ff01')) {
            _readCharacteristic = characteristic;
            debugPrint('[BLE]   ✅ Set as READ characteristic (UUID: $charUuid)');
            
            if (characteristic.properties.notify) {
              await characteristic.setNotifyValue(true);
              debugPrint('[BLE]   ✅ Notifications enabled on read characteristic');
              _characteristicSubscription = characteristic.lastValueStream.listen((data) {
                debugPrint('[BLE] 📥 BLE NOTIFICATION: ${data.length} bytes received');
                debugPrint('[BLE] Data chunk: ${data.map((b) => '0x${b.toRadixString(16).padLeft(2, '0')}').join(' ')}');
                debugPrint('[BLE] ⚠️ This is likely a CHUNK - complete packet assembly needed');
                // Notify all registered callbacks
                for (var callback in _dataCallbacks) {
                  callback(data);
                }
              });
            }
          }
        }
        break;
      }
    }
    
    if (_writeCharacteristic == null || _readCharacteristic == null) {
      debugPrint('[BLE] ⚠️  Expected characteristics not found, trying fallback discovery...');
      // Fallback: look for any service with ff00 pattern
      for (BluetoothService service in services) {
        String serviceUuid = service.uuid.toString().toLowerCase();
        if (serviceUuid.contains('ff00')) {
          debugPrint('[BLE] 🔄 Fallback: trying service $serviceUuid');
          for (BluetoothCharacteristic characteristic in service.characteristics) {
            String charUuid = characteristic.uuid.toString().toLowerCase();
            if (charUuid.contains('ff02') && _writeCharacteristic == null) {
              _writeCharacteristic = characteristic;
              debugPrint('[BLE]   📝 Fallback write characteristic: $charUuid');
            }
            if (charUuid.contains('ff01') && _readCharacteristic == null) {
              _readCharacteristic = characteristic;
              debugPrint('[BLE]   📖 Fallback read characteristic: $charUuid');
              if (characteristic.properties.notify) {
                await characteristic.setNotifyValue(true);
                _characteristicSubscription = characteristic.lastValueStream.listen((data) {
                  // Notify all registered callbacks
                  for (var callback in _dataCallbacks) {
                    callback(data);
                  }
                });
              }
            }
          }
        }
      }
    }
    
    debugPrint('[BLE] Service discovery complete - Write: ${_writeCharacteristic != null}, Read: ${_readCharacteristic != null}');
    if (_writeCharacteristic != null) {
      debugPrint('[BLE] Write characteristic UUID: ${_writeCharacteristic!.uuid}');
    }
    if (_readCharacteristic != null) {
      debugPrint('[BLE] Read characteristic UUID: ${_readCharacteristic!.uuid}');
    }
  }

  Future<void> writeData(List<int> data) async {
    debugPrint('[BLE] Write attempt - Connected: $_isConnected, Write char: ${_writeCharacteristic != null}');
    debugPrint('[BLE] Writing ${data.length} bytes: ${data.map((b) => '0x${b.toRadixString(16).padLeft(2, '0')}').join(' ')}');
    
    if (_writeCharacteristic == null || !_isConnected) {
      String error = 'Device not connected or write characteristic not available';
      debugPrint('[BLE] Write failed: $error');
      throw Exception(error);
    }

    // Use circuit breaker for resilient write operations
    await _writeCircuitBreaker.execute(() async {
      await _writeCharacteristic!.write(data, withoutResponse: true);
      debugPrint('[BLE] ✅ Write successful through circuit breaker');
    });
  }

  void addDataCallback(Function(List<int>) callback) {
    if (!_dataCallbacks.contains(callback)) {
      _dataCallbacks.add(callback);
      debugPrint('[BLE] ✅ Added data callback (total: ${_dataCallbacks.length})');
    }
  }
  
  void removeDataCallback(Function(List<int>) callback) {
    _dataCallbacks.remove(callback);
    debugPrint('[BLE] ✅ Removed data callback (total: ${_dataCallbacks.length})');
  }
  
  void setDataCallback(Function(List<int>)? callback) {
    debugPrint('[BLE] ⚠️ setDataCallback is deprecated, use addDataCallback instead');
    if (callback != null) {
      addDataCallback(callback);
    }
  }
  
  void clearDataCallbacks() {
    _dataCallbacks.clear();
    debugPrint('[BLE] ✅ Cleared all data callbacks');
  }

  // Basic info callback
  Function(Map<String, String>)? _basicInfoCallback;
  
  void setBasicInfoCallback(Function(Map<String, String>)? callback) {
    _basicInfoCallback = callback;
  }

  Future<void> fetchBasicInfo() async {
    try {
      debugPrint('[BLE] Fetching basic info from BMS');
      
      // Set up parser for basic info responses
      addDataCallback((data) {
        _parseBasicInfoResponse(data);
      });
      
      // Send commands to BMS with proper delays
      debugPrint('[BLE] Sending manufacturer command');
      await writeData([0xDD, 0xA5, 0xA0, 0x00, 0xFF, 0x60, 0x77]); // Manufacturer
      await Future.delayed(const Duration(milliseconds: 500));
      
      debugPrint('[BLE] Sending barcode command');
      await writeData([0xDD, 0xA5, 0xA2, 0x00, 0xFF, 0x5E, 0x77]); // Barcode
      await Future.delayed(const Duration(milliseconds: 500));
      
      debugPrint('[BLE] Sending device model command');
      await writeData([0xDD, 0xA5, 0x05, 0x00, 0xFF, 0xFB, 0x77]); // Device model
      await Future.delayed(const Duration(milliseconds: 500));
      
      debugPrint('[BLE] All basic info commands sent');
      
    } catch (e) {
      debugPrint('[BLE] Error fetching basic info: $e');
    }
  }

  void _parseBasicInfoResponse(List<int> data) {
    debugPrint('[BLE] Parsing response: ${data.map((b) => '0x${b.toRadixString(16).padLeft(2, '0')}').join(' ')}');
    
    if (data.length >= 4) {
      int register = data[1];
      int status = data[2];
      int dataLength = data[3];
      
      debugPrint('[BLE] Register: 0x${register.toRadixString(16)}, Status: 0x${status.toRadixString(16)}, Length: $dataLength');
      
      if (status == 0x00 && data.length >= 4 + dataLength) {
        List<int> responseData = data.sublist(4, 4 + dataLength);
        debugPrint('[BLE] Response data: ${responseData.map((b) => '0x${b.toRadixString(16).padLeft(2, '0')}').join(' ')}');
        
        // Parse text data
        String text = '';
        for (int byte in responseData) {
          if (byte >= 32 && byte <= 126) {
            text += String.fromCharCode(byte);
          }
        }
        text = text.trim();
        
        // Clean manufacturer name
        if (text.contains('Humaya Power')) {
          text = 'Humaya Power';
        }
        
        if (text.isNotEmpty) {
          Map<String, String> result = {};
          
          switch (register) {
            case 0xA0: // Manufacturer
              result['manufacturer'] = text;
              debugPrint('[BLE] ✅ Parsed manufacturer: $text');
              break;
            case 0xA2: // Barcode
              result['barCode'] = text;
              debugPrint('[BLE] ✅ Parsed barcode: $text');
              break;
            case 0x05: // Device model  
              result['deviceModel'] = text;
              debugPrint('[BLE] ✅ Parsed device model: $text');
              break;
          }
          
          // Always add version and date from cache
          result['version'] = BasicInfoCache.version.isNotEmpty ? BasicInfoCache.version : '1.0';
          result['productionDate'] = BasicInfoCache.productionDate.isNotEmpty ? BasicInfoCache.productionDate : '2024-01-01';
          
          // Send to callback
          debugPrint('[BLE] Sending parsed data to callback: $result');
          _basicInfoCallback?.call(result);
        } else {
          debugPrint('[BLE] ⚠️ Empty text parsed from register 0x${register.toRadixString(16)}');
        }
      } else {
        debugPrint('[BLE] ⚠️ Invalid response - Status: 0x${status.toRadixString(16)}, Expected length: ${4 + dataLength}, Actual: ${data.length}');
      }
    } else {
      debugPrint('[BLE] ⚠️ Response too short: ${data.length} bytes');
    }
  }

  Future<void> disconnect() async {
    if (_connectedDevice != null) {
      await _connectedDevice!.disconnect();
    }
    _cleanup();
  }

  void _cleanup() {
    debugPrint('[BLE] 🧹 Starting comprehensive cleanup...');
    
    // Cancel all tracked subscriptions
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _subscriptions.clear();
    
    // Cancel specific subscriptions
    _connectionStateSubscription?.cancel();
    _characteristicSubscription?.cancel();
    
    // Cancel timers
    _connectionRetryTimer?.cancel();
    _healthCheckTimer?.cancel();
    
    // Reset state
    _connectedDevice = null;
    _connectedDeviceName = '';
    _writeCharacteristic = null;
    _readCharacteristic = null;
    _isConnected = false;
    _dataCallbacks.clear();
    
    // Clear cached basic info data
    BasicInfoCache.clear();
    debugPrint('[BLE] 🧹 BasicInfoCache cleared');
    
    debugPrint('[BLE] ✅ Cleanup complete - all resources released');
    debugPrint('[BLE] 🔔 NOTIFYING LISTENERS - CLEANUP/DISCONNECT');
    notifyListeners(); // Notify about disconnection
  }

  void _handleConnectionStateChange(BluetoothConnectionState state) {
    debugPrint('[BLE] 🔄 Connection state changed: $state');
    
    _isConnected = state == BluetoothConnectionState.connected;
    
    if (!_isConnected) {
      _updateStatus('Disconnected');
      
      // Start auto-reconnection if we have a device to reconnect to
      if (_connectedDevice != null) {
        _startAutoReconnection();
      } else {
        _cleanup();
      }
    } else {
      _updateStatus('Connected to $_connectedDeviceName');
      _stopAutoReconnection();
    }
    
    notifyListeners();
  }

  void _handleConnectionError(dynamic error) {
    debugPrint('[BLE] ❌ Connection error: $error');
    _updateStatus('Connection error: $error');
    
    // Trigger reconnection on error
    if (_connectedDevice != null) {
      _startAutoReconnection();
    }
  }

  void _startAutoReconnection() {
    if (_connectionRetryTimer?.isActive == true) {
      return; // Already trying to reconnect
    }
    
    debugPrint('[BLE] 🔄 Starting auto-reconnection...');
    
    _connectionRetryTimer = Timer.periodic(const Duration(seconds: 5), (timer) async {
      if (_isConnected || _connectedDevice == null) {
        timer.cancel();
        return;
      }
      
      debugPrint('[BLE] 🔄 Attempting auto-reconnection...');
      try {
        final success = await connectToDevice(_connectedDevice!, maxRetries: 1);
        if (success) {
          debugPrint('[BLE] ✅ Auto-reconnection successful');
          timer.cancel();
        }
      } catch (e) {
        debugPrint('[BLE] ❌ Auto-reconnection failed: $e');
      }
    });
  }

  void _stopAutoReconnection() {
    _connectionRetryTimer?.cancel();
    _connectionRetryTimer = null;
    debugPrint('[BLE] 🛑 Auto-reconnection stopped');
  }



  
  
  
  
  
  

  void _updateStatus(String message) {
    _statusMessage = message;
    notifyListeners();
  }

  @override
  void dispose() {
    disconnect();
    super.dispose();
  }
}