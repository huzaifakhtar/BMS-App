import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import '../../../services/bluetooth/ble_service.dart';
import '../../cubits/theme_cubit.dart';
import '../../../core/performance/screen_performance_optimizer.dart';

class TemperatureProtectionPage extends StatefulWidget {
  const TemperatureProtectionPage({super.key});

  @override
  State<TemperatureProtectionPage> createState() => _TemperatureProtectionPageState();
}

class _TemperatureProtectionPageState extends State<TemperatureProtectionPage> {
  BleService? bleService;
  Function(List<int>)? _originalCallback;
  
  // Response waiting
  Completer<List<int>>? _responseCompleter;
  Timer? _timeoutTimer;
  int _expectedRegister = 0;
  
  bool _isLoading = true;
  
  // Text controllers for displaying actual values
  late TextEditingController _chargeHighTempProtectController;
  late TextEditingController _chargeHighTempRecoverController;
  late TextEditingController _chargeLowTempProtectController;
  late TextEditingController _chargeLowTempRecoverController;
  late TextEditingController _dischargeHighTempProtectController;
  late TextEditingController _dischargeHighTempRecoverController;
  late TextEditingController _dischargeLowTempProtectController;
  late TextEditingController _dischargeLowTempRecoverController;
  late TextEditingController _chargeTempUnderDelayController;
  late TextEditingController _chargeTempOverDelayController;
  late TextEditingController _dischargeTempUnderDelayController;
  late TextEditingController _dischargeTempOverDelayController;
  
  // Placeholder controllers for user input
  final Map<String, TextEditingController> _placeholderControllers = {};

  @override
  void initState() {
    super.initState();
    debugPrint('[TEMPERATURE_PROTECTION] Screen initialized');
    
    // Initialize controllers with 0 values
    _chargeHighTempProtectController = TextEditingController(text: '0');
    _chargeHighTempRecoverController = TextEditingController(text: '0');
    _chargeLowTempProtectController = TextEditingController(text: '0');
    _chargeLowTempRecoverController = TextEditingController(text: '0');
    _dischargeHighTempProtectController = TextEditingController(text: '0');
    _dischargeHighTempRecoverController = TextEditingController(text: '0');
    _dischargeLowTempProtectController = TextEditingController(text: '0');
    _dischargeLowTempRecoverController = TextEditingController(text: '0');
    _chargeTempUnderDelayController = TextEditingController(text: '0');
    _chargeTempOverDelayController = TextEditingController(text: '0');
    _dischargeTempUnderDelayController = TextEditingController(text: '0');
    _dischargeTempOverDelayController = TextEditingController(text: '0');
    
    _loadTemperatureParameters();
  }

  Future<void> _loadTemperatureParameters() async {
    try {
      bleService = context.read<BleService>();
      
      if (bleService?.isConnected != true) {
        setState(() {
          _chargeHighTempProtectController.text = '0';
          _chargeHighTempRecoverController.text = '0';
          _chargeLowTempProtectController.text = '0';
          _chargeLowTempRecoverController.text = '0';
          _dischargeHighTempProtectController.text = '0';
          _dischargeHighTempRecoverController.text = '0';
          _dischargeLowTempProtectController.text = '0';
          _dischargeLowTempRecoverController.text = '0';
          _chargeTempUnderDelayController.text = '0';
          _chargeTempOverDelayController.text = '0';
          _dischargeTempUnderDelayController.text = '0';
          _dischargeTempOverDelayController.text = '0';
          _isLoading = false;
        });
        _showNotConnectedDialog();
        return;
      }

      setState(() {
        _isLoading = true;
      });

      _originalCallback = bleService?.dataCallback;
      bleService?.addDataCallback(_handleBleData);
      
      await _fetchAllTemperatureParameters();
    } catch (e) {
      debugPrint('[TEMPERATURE_PROTECTION] Error: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  /// Optimized BLE data handler for consistent performance
  void _handleBleData(List<int> data) {
    // Fast validation - check minimum length first
    final length = data.length;
    if (length < 7) return;
    
    // Fast header/footer validation - avoid data.last lookup
    if (data[0] != 0xDD || data[length - 1] != 0x77) return;
    
    // Extract response fields efficiently
    final register = data[1];
    final status = data[2];
    
    // Fast path: only process if we're waiting for a response
    final completer = _responseCompleter;
    if (completer != null && !completer.isCompleted) {
      // Check register match and success status in one condition
      if (register == _expectedRegister && status == 0x00) {
        completer.complete(data);
        _timeoutTimer?.cancel();
        // Minimal debug logging to reduce string operations
        if (kDebugMode) {
          debugPrint('[TEMPERATURE_PROTECTION] ✅ Response completed for register 0x${register.toRadixString(16)}');
        }
      }
    }
  }
  
  /// Wait for BLE response with timeout
  Future<List<int>?> _waitForResponse(Duration timeout) async {
    _responseCompleter = Completer<List<int>>();
    
    _timeoutTimer = Timer(timeout, () {
      if (!_responseCompleter!.isCompleted) {
        debugPrint('[TEMPERATURE_PROTECTION] ⏰ Response timeout for register 0x${_expectedRegister.toRadixString(16)}');
        _responseCompleter!.complete([]);
      }
    });
    
    final response = await _responseCompleter!.future;
    _timeoutTimer?.cancel();
    return response.isNotEmpty ? response : null;
  }
  
  /// Read parameter with wait system
  Future<void> _readParameterWithWait(int register, Function(List<int>) onSuccess) async {
    try {
      ScreenPerformanceOptimizer.startTiming('read_register_0x${register.toRadixString(16)}');
      debugPrint('[TEMPERATURE_PROTECTION] Reading register 0x${register.toRadixString(16)}...');
      
      // Set expected register for response matching
      _expectedRegister = register;
      
      // Send the command
      final checksum = (0x10000 - (register + 0x00)) & 0xFFFF;
      final checksumHigh = (checksum >> 8) & 0xFF;
      final checksumLow = checksum & 0xFF;
      
      final command = [0xDD, 0xA5, register, 0x00, checksumHigh, checksumLow, 0x77];
      debugPrint('[TEMPERATURE_PROTECTION] Sending command: ${command.map((b) => '0x${b.toRadixString(16).padLeft(2, '0')}').join(' ')}');
      
      await bleService?.writeData(command);
      
      // Wait for response with optimized timeout
      const timeout = Duration(milliseconds: 3000);
      final response = await _waitForResponse(timeout);
      
      if (response != null && response.length > 3 && response[2] == 0x00) {
        final dataLength = response[3];
        if (response.length >= 4 + dataLength) {
          final responseData = response.sublist(4, 4 + dataLength);
          onSuccess(responseData);
          ScreenPerformanceOptimizer.endTiming('read_register_0x${register.toRadixString(16)}');
          debugPrint('[TEMPERATURE_PROTECTION] ✅ Successfully processed register 0x${register.toRadixString(16)}');
        } else {
          ScreenPerformanceOptimizer.endTiming('read_register_0x${register.toRadixString(16)}');
          debugPrint('[TEMPERATURE_PROTECTION] ❌ Data length mismatch for register 0x${register.toRadixString(16)}');
        }
      } else {
        ScreenPerformanceOptimizer.endTiming('read_register_0x${register.toRadixString(16)}');
        debugPrint('[TEMPERATURE_PROTECTION] ❌ Invalid response for register 0x${register.toRadixString(16)}');
      }
      
    } catch (e) {
      ScreenPerformanceOptimizer.endTiming('read_register_0x${register.toRadixString(16)}');
      debugPrint('[TEMPERATURE_PROTECTION] ❌ Error reading register 0x${register.toRadixString(16)}: $e');
    }
  }

  /// Send factory mode command
  Future<bool> _sendFactoryModeCommand() async {
    try {
      debugPrint('[TEMPERATURE_PROTECTION] 🔑 Sending factory mode command...');
      
      // Factory mode command: DD 5A 00 02 56 78 FF 30 77
      final List<int> factoryModeCommand = [0xDD, 0x5A, 0x00, 0x02, 0x56, 0x78, 0xFF, 0x30, 0x77];
      final String hexCommand = factoryModeCommand.map((b) => '0x${b.toRadixString(16).padLeft(2, '0').toUpperCase()}').join(' ');
      
      debugPrint('[TEMPERATURE_PROTECTION] Factory Mode Command: $hexCommand');
      
      await bleService?.writeData(factoryModeCommand);
      
      debugPrint('[TEMPERATURE_PROTECTION] ✅ Factory mode command sent successfully');
      return true;
    } catch (e) {
      debugPrint('[TEMPERATURE_PROTECTION] ❌ Factory mode command failed: $e');
      return false;
    }
  }

  /// Fetch all temperature parameters
  Future<void> _fetchAllTemperatureParameters() async {
    try {
      debugPrint('[TEMPERATURE_PROTECTION] 🚀 Starting temperature parameters fetch...');
      
      // Step 1: Send factory mode command FIRST
      debugPrint('[TEMPERATURE_PROTECTION] 🔑 Step 1: Factory Mode Command');
      bool factoryModeSuccess = await _sendFactoryModeCommand();
      if (!factoryModeSuccess) {
        debugPrint('[TEMPERATURE_PROTECTION] ⚠️ Factory mode failed, continuing anyway...');
      }
      
      // Step 2: Fetch all temperature parameters using grouped approach
      debugPrint('[TEMPERATURE_PROTECTION] 🌡️ Step 2: Fetching All Temperature Parameters');
      
      // Fetch grouped temperature parameters
      final chargeParams = await _fetchChargeTemperatureParameters();
      final dischargeParams = await _fetchDischargeTemperatureParameters();
      final delayParams = await _fetchTemperatureDelays();
      
      // Step 3: Update UI with all collected data
      debugPrint('[TEMPERATURE_PROTECTION] 🎯 Step 3: Updating UI with all data');
      setState(() {
        _chargeHighTempProtectController.text = chargeParams['chargeHighTempProtect'] ?? '0';
        _chargeHighTempRecoverController.text = chargeParams['chargeHighTempRecover'] ?? '0';
        _chargeLowTempProtectController.text = chargeParams['chargeLowTempProtect'] ?? '0';
        _chargeLowTempRecoverController.text = chargeParams['chargeLowTempRecover'] ?? '0';
        _dischargeHighTempProtectController.text = dischargeParams['dischargeHighTempProtect'] ?? '0';
        _dischargeHighTempRecoverController.text = dischargeParams['dischargeHighTempRecover'] ?? '0';
        _dischargeLowTempProtectController.text = dischargeParams['dischargeLowTempProtect'] ?? '0';
        _dischargeLowTempRecoverController.text = dischargeParams['dischargeLowTempRecover'] ?? '0';
        _chargeTempUnderDelayController.text = delayParams['chargeTempUnderDelay'] ?? '0';
        _chargeTempOverDelayController.text = delayParams['chargeTempOverDelay'] ?? '0';
        _dischargeTempUnderDelayController.text = delayParams['dischargeTempUnderDelay'] ?? '0';
        _dischargeTempOverDelayController.text = delayParams['dischargeTempOverDelay'] ?? '0';
        _isLoading = false;
      });

      debugPrint('[TEMPERATURE_PROTECTION] ✅ All temperature parameters loaded successfully');

    } catch (e) {
      debugPrint('[TEMPERATURE_PROTECTION] ❌ Error loading temperature parameters: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  /// Fetch charge temperature parameters (0x18-0x1B)
  Future<Map<String, String>> _fetchChargeTemperatureParameters() async {
    Map<String, String> values = {
      'chargeHighTempProtect': '0',
      'chargeHighTempRecover': '0',
      'chargeLowTempProtect': '0',
      'chargeLowTempRecover': '0',
    };

    await _readParameterWithWait(0x18, (data) {
      if (data.length >= 2) {
        int value = (data[0] << 8) | data[1];
        double tempCelsius = (value / 10.0) - 273.15;
        values['chargeHighTempProtect'] = tempCelsius.toStringAsFixed(1);
        debugPrint('[TEMPERATURE_PROTECTION] ✅ Charge High Temp Protect: $tempCelsius°C');
      }
    });

    await _readParameterWithWait(0x19, (data) {
      if (data.length >= 2) {
        int value = (data[0] << 8) | data[1];
        double tempCelsius = (value / 10.0) - 273.15;
        values['chargeHighTempRecover'] = tempCelsius.toStringAsFixed(1);
        debugPrint('[TEMPERATURE_PROTECTION] ✅ Charge High Temp Recover: $tempCelsius°C');
      }
    });

    await _readParameterWithWait(0x1A, (data) {
      if (data.length >= 2) {
        int value = (data[0] << 8) | data[1];
        double tempCelsius = (value / 10.0) - 273.15;
        values['chargeLowTempProtect'] = tempCelsius.toStringAsFixed(1);
        debugPrint('[TEMPERATURE_PROTECTION] ✅ Charge Low Temp Protect: $tempCelsius°C');
      }
    });

    await _readParameterWithWait(0x1B, (data) {
      if (data.length >= 2) {
        int value = (data[0] << 8) | data[1];
        double tempCelsius = (value / 10.0) - 273.15;
        values['chargeLowTempRecover'] = tempCelsius.toStringAsFixed(1);
        debugPrint('[TEMPERATURE_PROTECTION] ✅ Charge Low Temp Recover: $tempCelsius°C');
      }
    });

    return values;
  }

  /// Fetch discharge temperature parameters (0x1C-0x1F)
  Future<Map<String, String>> _fetchDischargeTemperatureParameters() async {
    Map<String, String> values = {
      'dischargeHighTempProtect': '0',
      'dischargeHighTempRecover': '0',
      'dischargeLowTempProtect': '0',
      'dischargeLowTempRecover': '0',
    };

    await _readParameterWithWait(0x1C, (data) {
      if (data.length >= 2) {
        int value = (data[0] << 8) | data[1];
        double tempCelsius = (value / 10.0) - 273.15;
        values['dischargeHighTempProtect'] = tempCelsius.toStringAsFixed(1);
        debugPrint('[TEMPERATURE_PROTECTION] ✅ Discharge High Temp Protect: $tempCelsius°C');
      }
    });

    await _readParameterWithWait(0x1D, (data) {
      if (data.length >= 2) {
        int value = (data[0] << 8) | data[1];
        double tempCelsius = (value / 10.0) - 273.15;
        values['dischargeHighTempRecover'] = tempCelsius.toStringAsFixed(1);
        debugPrint('[TEMPERATURE_PROTECTION] ✅ Discharge High Temp Recover: $tempCelsius°C');
      }
    });

    await _readParameterWithWait(0x1E, (data) {
      if (data.length >= 2) {
        int value = (data[0] << 8) | data[1];
        double tempCelsius = (value / 10.0) - 273.15;
        values['dischargeLowTempProtect'] = tempCelsius.toStringAsFixed(1);
        debugPrint('[TEMPERATURE_PROTECTION] ✅ Discharge Low Temp Protect: $tempCelsius°C');
      }
    });

    await _readParameterWithWait(0x1F, (data) {
      if (data.length >= 2) {
        int value = (data[0] << 8) | data[1];
        double tempCelsius = (value / 10.0) - 273.15;
        values['dischargeLowTempRecover'] = tempCelsius.toStringAsFixed(1);
        debugPrint('[TEMPERATURE_PROTECTION] ✅ Discharge Low Temp Recover: $tempCelsius°C');
      }
    });

    return values;
  }

  /// Fetch temperature delays (0x3A, 0x3B)
  Future<Map<String, String>> _fetchTemperatureDelays() async {
    Map<String, String> values = {
      'chargeTempUnderDelay': '0',
      'chargeTempOverDelay': '0',
      'dischargeTempUnderDelay': '0',
      'dischargeTempOverDelay': '0',
    };

    await _readParameterWithWait(0x3A, (data) {
      if (data.length >= 2) {
        int underDelay = data[0];
        int overDelay = data[1];
        values['chargeTempUnderDelay'] = underDelay.toString();
        values['chargeTempOverDelay'] = overDelay.toString();
        debugPrint('[TEMPERATURE_PROTECTION] ✅ Charge Temp Delays: Under=${underDelay}s, Over=${overDelay}s');
      }
    });

    await _readParameterWithWait(0x3B, (data) {
      if (data.length >= 2) {
        int underDelay = data[0];
        int overDelay = data[1];
        values['dischargeTempUnderDelay'] = underDelay.toString();
        values['dischargeTempOverDelay'] = overDelay.toString();
        debugPrint('[TEMPERATURE_PROTECTION] ✅ Discharge Temp Delays: Under=${underDelay}s, Over=${overDelay}s');
      }
    });

    return values;
  }

  void _refreshBleCallback() {
    debugPrint('[TEMPERATURE_PROTECTION] 🔄 Refreshing BLE callback for write operation');
    bleService?.addDataCallback(_handleBleData);
  }

  /// Write parameter with factory mode
  Future<void> _writeParameterWithWait(int register, int value) async {
    try {
      // Build BLE write command: DD 5A [REG] 02 [DATA_HIGH] [DATA_LOW] [CHECKSUM_HIGH] [CHECKSUM_LOW] 77
      final dataHigh = (value >> 8) & 0xFF;
      final dataLow = value & 0xFF;
      
      // Calculate checksum: 0x10000 - (register + length + dataHigh + dataLow)
      final checksumValue = 0x10000 - (register + 0x02 + dataHigh + dataLow);
      final checksumHigh = (checksumValue >> 8) & 0xFF;
      final checksumLow = checksumValue & 0xFF;
      
      final command = [0xDD, 0x5A, register, 0x02, dataHigh, dataLow, checksumHigh, checksumLow, 0x77];
      
      final hexCommand = command.map((b) => '0x${b.toRadixString(16).padLeft(2, '0').toUpperCase()}').join(' ');
      debugPrint('[TEMPERATURE_PROTECTION] Sending write command: $hexCommand');

      // Send factory mode + write data
      await _writeDataWithFactory(command);
      
      _handleWriteSuccess(register);
      
    } catch (e) {
      debugPrint('[TEMPERATURE_PROTECTION] Write command failed: $e');
      _showErrorMessage('Write command failed: $e');
    }
  }

  /// Send factory mode then write data
  Future<void> _writeDataWithFactory(List<int> writeCommand) async {
    // Send factory mode command first
    debugPrint('[TEMPERATURE_PROTECTION] 🔑 Sending factory mode before write...');
    await _sendFactoryModeCommand();
    
    // Then send write command
    await bleService?.writeData(writeCommand);
  }

  void _handleWriteSuccess(int register) {
    debugPrint('[TEMPERATURE_PROTECTION] Write successful for register 0x${register.toRadixString(16)}');
    
    // Clear the placeholder field for this register
    _clearPlaceholderForRegister(register);
    
    // Wait a moment then read back to verify and update display
    Future.delayed(const Duration(milliseconds: 100), () {
      _refreshBleCallback(); // Ensure fresh callback
      _readParameterWithWait(register, (data) {
        if (data.length >= 2) {
          debugPrint('[TEMPERATURE_PROTECTION] ✅ Readback successful');
          _updateDisplayForRegister(register, data);
        } else {
          debugPrint('[TEMPERATURE_PROTECTION] ❌ Readback failed - invalid data length');
        }
      });
    });
  }

  void _clearPlaceholderForRegister(int register) {
    String? parameterKey;
    
    switch (register) {
      case 0x18:
        parameterKey = 'chargeHighTempProtect';
        break;
      case 0x19:
        parameterKey = 'chargeHighTempRecover';
        break;
      case 0x1A:
        parameterKey = 'chargeLowTempProtect';
        break;
      case 0x1B:
        parameterKey = 'chargeLowTempRecover';
        break;
      case 0x1C:
        parameterKey = 'dischargeHighTempProtect';
        break;
      case 0x1D:
        parameterKey = 'dischargeHighTempRecover';
        break;
      case 0x1E:
        parameterKey = 'dischargeLowTempProtect';
        break;
      case 0x1F:
        parameterKey = 'dischargeLowTempRecover';
        break;
      case 0x3A:
        parameterKey = 'chargeTempDelays';
        break;
      case 0x3B:
        parameterKey = 'dischargeTempDelays';
        break;
    }
    
    if (parameterKey != null && _placeholderControllers.containsKey(parameterKey)) {
      _placeholderControllers[parameterKey]!.clear();
    }
  }

  void _updateDisplayForRegister(int register, List<int> data) {
    if (data.length >= 2) {
      switch (register) {
        case 0x18:
          int value = (data[0] << 8) | data[1];
          double tempCelsius = (value / 10.0) - 273.15;
          _chargeHighTempProtectController.text = tempCelsius.toStringAsFixed(1);
          break;
        case 0x19:
          int value = (data[0] << 8) | data[1];
          double tempCelsius = (value / 10.0) - 273.15;
          _chargeHighTempRecoverController.text = tempCelsius.toStringAsFixed(1);
          break;
        case 0x1A:
          int value = (data[0] << 8) | data[1];
          double tempCelsius = (value / 10.0) - 273.15;
          _chargeLowTempProtectController.text = tempCelsius.toStringAsFixed(1);
          break;
        case 0x1B:
          int value = (data[0] << 8) | data[1];
          double tempCelsius = (value / 10.0) - 273.15;
          _chargeLowTempRecoverController.text = tempCelsius.toStringAsFixed(1);
          break;
        case 0x1C:
          int value = (data[0] << 8) | data[1];
          double tempCelsius = (value / 10.0) - 273.15;
          _dischargeHighTempProtectController.text = tempCelsius.toStringAsFixed(1);
          break;
        case 0x1D:
          int value = (data[0] << 8) | data[1];
          double tempCelsius = (value / 10.0) - 273.15;
          _dischargeHighTempRecoverController.text = tempCelsius.toStringAsFixed(1);
          break;
        case 0x1E:
          int value = (data[0] << 8) | data[1];
          double tempCelsius = (value / 10.0) - 273.15;
          _dischargeLowTempProtectController.text = tempCelsius.toStringAsFixed(1);
          break;
        case 0x1F:
          int value = (data[0] << 8) | data[1];
          double tempCelsius = (value / 10.0) - 273.15;
          _dischargeLowTempRecoverController.text = tempCelsius.toStringAsFixed(1);
          break;
        case 0x3A:
          if (data.length >= 2) {
            _chargeTempUnderDelayController.text = data[0].toString();
            _chargeTempOverDelayController.text = data[1].toString();
          }
          break;
        case 0x3B:
          if (data.length >= 2) {
            _dischargeTempUnderDelayController.text = data[0].toString();
            _dischargeTempOverDelayController.text = data[1].toString();
          }
          break;
      }
      setState(() {});
    }
  }

  Future<void> _writeParameterFromPlaceholder(String parameterKey, String placeholderValue) async {
    try {
      if (bleService?.isConnected != true) {
        _showErrorMessage('Device not connected');
        return;
      }

      if (placeholderValue.isEmpty) {
        _showErrorMessage('Please enter a value');
        return;
      }

      int register;
      int writeValue;
      
      switch (parameterKey) {
        // Temperature parameters - convert Celsius to 0.1K units
        case 'chargeHighTempProtect':
          register = 0x18;
          double tempCelsius = double.tryParse(placeholderValue) ?? -300;
          if (tempCelsius < -40 || tempCelsius > 85) {
            _showErrorMessage('Temperature must be between -40°C and 85°C');
            return;
          }
          writeValue = ((tempCelsius + 273.15) * 10).round();
          break;
        case 'chargeHighTempRecover':
          register = 0x19;
          double tempCelsius = double.tryParse(placeholderValue) ?? -300;
          if (tempCelsius < -40 || tempCelsius > 85) {
            _showErrorMessage('Temperature must be between -40°C and 85°C');
            return;
          }
          writeValue = ((tempCelsius + 273.15) * 10).round();
          break;
        case 'chargeLowTempProtect':
          register = 0x1A;
          double tempCelsius = double.tryParse(placeholderValue) ?? -300;
          if (tempCelsius < -40 || tempCelsius > 85) {
            _showErrorMessage('Temperature must be between -40°C and 85°C');
            return;
          }
          writeValue = ((tempCelsius + 273.15) * 10).round();
          break;
        case 'chargeLowTempRecover':
          register = 0x1B;
          double tempCelsius = double.tryParse(placeholderValue) ?? -300;
          if (tempCelsius < -40 || tempCelsius > 85) {
            _showErrorMessage('Temperature must be between -40°C and 85°C');
            return;
          }
          writeValue = ((tempCelsius + 273.15) * 10).round();
          break;
        case 'dischargeHighTempProtect':
          register = 0x1C;
          double tempCelsius = double.tryParse(placeholderValue) ?? -300;
          if (tempCelsius < -40 || tempCelsius > 85) {
            _showErrorMessage('Temperature must be between -40°C and 85°C');
            return;
          }
          writeValue = ((tempCelsius + 273.15) * 10).round();
          break;
        case 'dischargeHighTempRecover':
          register = 0x1D;
          double tempCelsius = double.tryParse(placeholderValue) ?? -300;
          if (tempCelsius < -40 || tempCelsius > 85) {
            _showErrorMessage('Temperature must be between -40°C and 85°C');
            return;
          }
          writeValue = ((tempCelsius + 273.15) * 10).round();
          break;
        case 'dischargeLowTempProtect':
          register = 0x1E;
          double tempCelsius = double.tryParse(placeholderValue) ?? -300;
          if (tempCelsius < -40 || tempCelsius > 85) {
            _showErrorMessage('Temperature must be between -40°C and 85°C');
            return;
          }
          writeValue = ((tempCelsius + 273.15) * 10).round();
          break;
        case 'dischargeLowTempRecover':
          register = 0x1F;
          double tempCelsius = double.tryParse(placeholderValue) ?? -300;
          if (tempCelsius < -40 || tempCelsius > 85) {
            _showErrorMessage('Temperature must be between -40°C and 85°C');
            return;
          }
          writeValue = ((tempCelsius + 273.15) * 10).round();
          break;
        default:
          _showErrorMessage('Unknown parameter: $parameterKey');
          return;
      }

      debugPrint('[TEMPERATURE_PROTECTION] Writing $placeholderValue to register 0x${register.toRadixString(16)} as value $writeValue');
      
      await _writeParameterWithWait(register, writeValue);
      
    } catch (e) {
      debugPrint('[TEMPERATURE_PROTECTION] Error in _writeParameterFromPlaceholder: $e');
      _showErrorMessage('Error: $e');
    }
  }

  void _showErrorMessage(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _showNotConnectedDialog() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      showDialog(
        context: context,
        barrierDismissible: true,
        barrierColor: Colors.transparent,
        builder: (context) => Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.5),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text(
              'You haven\'t connected any devices yet',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );

      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) {
          Navigator.of(context, rootNavigator: true).pop();
        }
      });
    });
  }

  String _getLabelKey(String label) {
    return label.toLowerCase().replaceAll(' ', '').replaceAll('°c', '').replaceAll('temp', 'temp');
  }


  Widget _buildParameterRow(String label, TextEditingController controller, String unit, ThemeProvider themeProvider) {
    // Create a unique key for this parameter based on label
    String parameterKey = _getLabelKey(label);
    
    // Create or get the placeholder controller for this parameter (always empty)
    if (!_placeholderControllers.containsKey(parameterKey)) {
      _placeholderControllers[parameterKey] = TextEditingController();
    }
    final placeholderController = _placeholderControllers[parameterKey]!;
    
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Colors.black,
                    fontWeight: FontWeight.normal,
                  ),
                ),
              ),
              // Value display  
              Container(
                margin: const EdgeInsets.only(left: 16),
                child: Text(
                  '${controller.text}$unit',
                  style: TextStyle(
                    fontSize: 13,
                    color: themeProvider.primaryColor,
                    fontWeight: FontWeight.normal,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Editable placeholder
              SizedBox(
                width: 60,
                height: 24,
                child: TextFormField(
                  controller: placeholderController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'^-?\d*\.?\d*')),
                  ],
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Colors.black,
                    fontWeight: FontWeight.normal,
                  ),
                  decoration: InputDecoration(
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide(color: themeProvider.borderColor),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide(color: themeProvider.borderColor),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide(color: themeProvider.primaryColor),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    fillColor: Colors.white,
                    filled: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: 24,
                width: 40,
                child: ElevatedButton(
                  onPressed: () {
                    final value = placeholderController.text.trim();
                    if (value.isNotEmpty) {
                      _writeParameterFromPlaceholder(parameterKey, value);
                    } else {
                      _showErrorMessage('Please enter a value first');
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: themeProvider.primaryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  child: const Text(
                    'SET',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
        Divider(
          height: 1,
          thickness: 0.5,
          color: themeProvider.borderColor.withOpacity(0.3),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, _) {
        return Scaffold(
          backgroundColor: themeProvider.backgroundColor,
          appBar: AppBar(
            backgroundColor: themeProvider.primaryColor,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
            title: const Text(
              'Temperature Settings',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh, color: Colors.white),
                onPressed: () => _fetchAllTemperatureParameters(),
              ),
            ],
          ),
          body: Stack(
            children: [
              // Main content
              SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 600),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildParameterRow('Charge High Temp Protect', _chargeHighTempProtectController, '°C', themeProvider),
                        _buildParameterRow('Charge High Temp Recover', _chargeHighTempRecoverController, '°C', themeProvider),
                        _buildParameterRow('Charge Temp Over Delay', _chargeTempOverDelayController, 's', themeProvider),
                        _buildParameterRow('Charge Low Temp Protect', _chargeLowTempProtectController, '°C', themeProvider),
                        _buildParameterRow('Charge Low Temp Recover', _chargeLowTempRecoverController, '°C', themeProvider),
                        _buildParameterRow('Charge Temp Under Delay', _chargeTempUnderDelayController, 's', themeProvider),
                        _buildParameterRow('Discharge High Temp Protect', _dischargeHighTempProtectController, '°C', themeProvider),
                        _buildParameterRow('Discharge High Temp Recover', _dischargeHighTempRecoverController, '°C', themeProvider),
                        _buildParameterRow('Discharge Temp Over Delay', _dischargeTempOverDelayController, 's', themeProvider),
                        _buildParameterRow('Discharge Low Temp Protect', _dischargeLowTempProtectController, '°C', themeProvider),
                        _buildParameterRow('Discharge Low Temp Recover', _dischargeLowTempRecoverController, '°C', themeProvider),
                        _buildParameterRow('Discharge Temp Under Delay', _dischargeTempUnderDelayController, 's', themeProvider),
                      ],
                    ),
                  ),
                ),
              ),
              
              // Loading overlay
              if (_isLoading)
                const _LoadingOverlay(),
            ],
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    // Restore original callback
    if (_originalCallback != null) {
      bleService?.addDataCallback(_originalCallback!);
    }
    
    // Cancel any pending operations
    _timeoutTimer?.cancel();
    
    // Dispose controllers
    _chargeHighTempProtectController.dispose();
    _chargeHighTempRecoverController.dispose();
    _chargeLowTempProtectController.dispose();
    _chargeLowTempRecoverController.dispose();
    _dischargeHighTempProtectController.dispose();
    _dischargeHighTempRecoverController.dispose();
    _dischargeLowTempProtectController.dispose();
    _dischargeLowTempRecoverController.dispose();
    _chargeTempUnderDelayController.dispose();
    _chargeTempOverDelayController.dispose();
    _dischargeTempUnderDelayController.dispose();
    _dischargeTempOverDelayController.dispose();
    
    // Dispose placeholder controllers
    for (var controller in _placeholderControllers.values) {
      controller.dispose();
    }
    
    super.dispose();
  }
}

/// Reusable loading overlay widget with 50% screen occupancy
class _LoadingOverlay extends StatelessWidget {
  const _LoadingOverlay();

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final overlaySize = screenSize.width * 0.5; // 50% screen occupancy
    
    return Container(
      color: Colors.transparent,
      width: double.infinity,
      height: double.infinity,
      child: Center(
        child: Container(
          width: overlaySize,
          height: overlaySize,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.7),
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                strokeWidth: 3,
              ),
              SizedBox(height: 20),
              Text(
                'Loading Temperature Settings...',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}