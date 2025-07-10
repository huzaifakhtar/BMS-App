import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import '../../../services/bluetooth/ble_service.dart';
import '../../cubits/theme_cubit.dart';
import '../../../core/performance/screen_performance_optimizer.dart';

class ProtectionParameterPage extends StatefulWidget {
  const ProtectionParameterPage({super.key});

  @override
  State<ProtectionParameterPage> createState() => _ProtectionParameterPageState();
}

class _ProtectionParameterPageState extends State<ProtectionParameterPage> {
  BleService? bleService;
  Function(List<int>)? _originalCallback;
  
  // Response waiting
  Completer<List<int>>? _responseCompleter;
  Timer? _timeoutTimer;
  int _expectedRegister = 0;
  
  bool _isLoading = true;
  
  // Text controllers for displaying actual values
  late TextEditingController _cellHighVoltProtectController;
  late TextEditingController _cellHighVoltRecoverController;
  late TextEditingController _cellHighVoltDelayController;
  late TextEditingController _cellLowVoltProtectController;
  late TextEditingController _cellLowVoltRecoverController;
  late TextEditingController _cellLowVoltDelayController;
  late TextEditingController _totalVoltHighProtectController;
  late TextEditingController _totalVoltHighRecoverController;
  late TextEditingController _totalVoltHighDelayController;
  late TextEditingController _totalVoltLowProtectController;
  late TextEditingController _totalVoltLowRecoverController;
  late TextEditingController _totalVoltLowDelayController;
  late TextEditingController _hwCellHighVoltProtectController;
  late TextEditingController _hwCellLowVoltProtectController;
  
  // Placeholder controllers for user input
  final Map<String, TextEditingController> _placeholderControllers = {};

  @override
  void initState() {
    super.initState();
    debugPrint('[PROTECTION_PARAMETER] Screen initialized');
    
    // Initialize controllers with 0 values
    _cellHighVoltProtectController = TextEditingController(text: '0');
    _cellHighVoltRecoverController = TextEditingController(text: '0');
    _cellHighVoltDelayController = TextEditingController(text: '0');
    _cellLowVoltProtectController = TextEditingController(text: '0');
    _cellLowVoltRecoverController = TextEditingController(text: '0');
    _cellLowVoltDelayController = TextEditingController(text: '0');
    _totalVoltHighProtectController = TextEditingController(text: '0');
    _totalVoltHighRecoverController = TextEditingController(text: '0');
    _totalVoltHighDelayController = TextEditingController(text: '0');
    _totalVoltLowProtectController = TextEditingController(text: '0');
    _totalVoltLowRecoverController = TextEditingController(text: '0');
    _totalVoltLowDelayController = TextEditingController(text: '0');
    _hwCellHighVoltProtectController = TextEditingController(text: '0');
    _hwCellLowVoltProtectController = TextEditingController(text: '0');
    
    _loadProtectionParameters();
  }

  Future<void> _loadProtectionParameters() async {
    try {
      bleService = context.read<BleService>();
      
      if (bleService?.isConnected != true) {
        setState(() {
          _cellHighVoltProtectController.text = '0';
          _cellHighVoltRecoverController.text = '0';
          _cellHighVoltDelayController.text = '0';
          _cellLowVoltProtectController.text = '0';
          _cellLowVoltRecoverController.text = '0';
          _cellLowVoltDelayController.text = '0';
          _totalVoltHighProtectController.text = '0';
          _totalVoltHighRecoverController.text = '0';
          _totalVoltHighDelayController.text = '0';
          _totalVoltLowProtectController.text = '0';
          _totalVoltLowRecoverController.text = '0';
          _totalVoltLowDelayController.text = '0';
          _hwCellHighVoltProtectController.text = '0';
          _hwCellLowVoltProtectController.text = '0';
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
      
      await _fetchAllProtectionParameters();
    } catch (e) {
      debugPrint('[PROTECTION_PARAMETER] Error: $e');
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
          debugPrint('[PROTECTION_PARAMETER] ✅ Response completed for register 0x${register.toRadixString(16)}');
        }
      }
    }
  }
  
  /// Wait for BLE response with timeout
  Future<List<int>?> _waitForResponse(Duration timeout) async {
    _responseCompleter = Completer<List<int>>();
    
    _timeoutTimer = Timer(timeout, () {
      if (!_responseCompleter!.isCompleted) {
        debugPrint('[PROTECTION_PARAMETER] ⏰ Response timeout for register 0x${_expectedRegister.toRadixString(16)}');
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
      debugPrint('[PROTECTION_PARAMETER] Reading register 0x${register.toRadixString(16)}...');
      
      // Set expected register for response matching
      _expectedRegister = register;
      
      // Send the command
      final checksum = (0x10000 - (register + 0x00)) & 0xFFFF;
      final checksumHigh = (checksum >> 8) & 0xFF;
      final checksumLow = checksum & 0xFF;
      
      final command = [0xDD, 0xA5, register, 0x00, checksumHigh, checksumLow, 0x77];
      debugPrint('[PROTECTION_PARAMETER] Sending command: ${command.map((b) => '0x${b.toRadixString(16).padLeft(2, '0')}').join(' ')}');
      
      await bleService?.writeData(command);
      
      // Wait for response with optimized timeout based on register type
      final timeout = ScreenPerformanceOptimizer.isTotalVoltageRegister(register) 
          ? ScreenPerformanceOptimizer.getOptimalTimeout('total_voltage')
          : ScreenPerformanceOptimizer.isCellProtectionRegister(register)
              ? ScreenPerformanceOptimizer.getOptimalTimeout('cell_protection')
              : ScreenPerformanceOptimizer.getOptimalTimeout('hardware_protection');
      
      final response = await _waitForResponse(timeout);
      
      if (response != null && response.length > 3 && response[2] == 0x00) {
        final dataLength = response[3];
        if (response.length >= 4 + dataLength) {
          final responseData = response.sublist(4, 4 + dataLength);
          onSuccess(responseData);
          ScreenPerformanceOptimizer.endTiming('read_register_0x${register.toRadixString(16)}');
          debugPrint('[PROTECTION_PARAMETER] ✅ Successfully processed register 0x${register.toRadixString(16)}');
        } else {
          ScreenPerformanceOptimizer.endTiming('read_register_0x${register.toRadixString(16)}');
          debugPrint('[PROTECTION_PARAMETER] ❌ Data length mismatch for register 0x${register.toRadixString(16)}');
        }
      } else {
        ScreenPerformanceOptimizer.endTiming('read_register_0x${register.toRadixString(16)}');
        debugPrint('[PROTECTION_PARAMETER] ❌ Invalid response for register 0x${register.toRadixString(16)}');
      }
      
    } catch (e) {
      ScreenPerformanceOptimizer.endTiming('read_register_0x${register.toRadixString(16)}');
      debugPrint('[PROTECTION_PARAMETER] ❌ Error reading register 0x${register.toRadixString(16)}: $e');
    }
  }

  /// Send factory mode command
  Future<bool> _sendFactoryModeCommand() async {
    try {
      debugPrint('[PROTECTION_PARAMETER] 🔑 Sending factory mode command...');
      
      // Factory mode command: DD 5A 00 02 56 78 FF 30 77
      final List<int> factoryModeCommand = [0xDD, 0x5A, 0x00, 0x02, 0x56, 0x78, 0xFF, 0x30, 0x77];
      final String hexCommand = factoryModeCommand.map((b) => '0x${b.toRadixString(16).padLeft(2, '0').toUpperCase()}').join(' ');
      
      debugPrint('[PROTECTION_PARAMETER] Factory Mode Command: $hexCommand');
      
      await bleService?.writeData(factoryModeCommand);
      
      debugPrint('[PROTECTION_PARAMETER] ✅ Factory mode command sent successfully');
      return true;
    } catch (e) {
      debugPrint('[PROTECTION_PARAMETER] ❌ Factory mode command failed: $e');
      return false;
    }
  }

  /// Fetch all protection parameters
  Future<void> _fetchAllProtectionParameters() async {
    try {
      debugPrint('[PROTECTION_PARAMETER] 🚀 Starting protection parameters fetch...');
      
      // Step 1: Send factory mode command FIRST
      debugPrint('[PROTECTION_PARAMETER] 🔑 Step 1: Factory Mode Command');
      bool factoryModeSuccess = await _sendFactoryModeCommand();
      if (!factoryModeSuccess) {
        debugPrint('[PROTECTION_PARAMETER] ⚠️ Factory mode failed, continuing anyway...');
      }
      
      // No delay - proceed immediately
      
      // Step 2: Fetch all protection parameters (store in temp variables)
      debugPrint('[PROTECTION_PARAMETER] 📊 Step 2: Fetching All Protection Parameters');
      
      // Temporary storage for all parameters
      String cellHighVoltProtect = '0';
      String cellHighVoltRecover = '0';
      String cellLowVoltProtect = '0';
      String cellLowVoltRecover = '0';
      String cellHighVoltDelay = '0';
      String cellLowVoltDelay = '0';
      String totalVoltHighProtect = '0';
      String totalVoltHighRecover = '0';
      String totalVoltLowProtect = '0';
      String totalVoltLowRecover = '0';
      String totalVoltHighDelay = '0';
      String totalVoltLowDelay = '0';
      String hwCellHighVoltProtect = '0';
      String hwCellLowVoltProtect = '0';

      // Fetch all data sequentially
      final cellParams = await _fetchCellProtectionParameters();
      final cellDelays = await _fetchCellProtectionDelays();
      final totalParams = await _fetchTotalVoltageParameters();
      final totalDelays = await _fetchTotalVoltageDelays();
      final hwParams = await _fetchHardwareProtection();
      
      // Extract values from returned maps
      cellHighVoltProtect = cellParams['cellHighVoltProtect'] ?? '0';
      cellHighVoltRecover = cellParams['cellHighVoltRecover'] ?? '0';
      cellLowVoltProtect = cellParams['cellLowVoltProtect'] ?? '0';
      cellLowVoltRecover = cellParams['cellLowVoltRecover'] ?? '0';
      cellHighVoltDelay = cellDelays['cellHighVoltDelay'] ?? '0';
      cellLowVoltDelay = cellDelays['cellLowVoltDelay'] ?? '0';
      totalVoltHighProtect = totalParams['totalVoltHighProtect'] ?? '0';
      totalVoltHighRecover = totalParams['totalVoltHighRecover'] ?? '0';
      totalVoltLowProtect = totalParams['totalVoltLowProtect'] ?? '0';
      totalVoltLowRecover = totalParams['totalVoltLowRecover'] ?? '0';
      totalVoltHighDelay = totalDelays['totalVoltHighDelay'] ?? '0';
      totalVoltLowDelay = totalDelays['totalVoltLowDelay'] ?? '0';
      hwCellHighVoltProtect = hwParams['hwCellHighVoltProtect'] ?? '0';
      hwCellLowVoltProtect = hwParams['hwCellLowVoltProtect'] ?? '0';
      
      // Step 3: Update ALL data at once with single setState
      setState(() {
        _cellHighVoltProtectController.text = cellHighVoltProtect;
        _cellHighVoltRecoverController.text = cellHighVoltRecover;
        _cellLowVoltProtectController.text = cellLowVoltProtect;
        _cellLowVoltRecoverController.text = cellLowVoltRecover;
        _cellHighVoltDelayController.text = cellHighVoltDelay;
        _cellLowVoltDelayController.text = cellLowVoltDelay;
        _totalVoltHighProtectController.text = totalVoltHighProtect;
        _totalVoltHighRecoverController.text = totalVoltHighRecover;
        _totalVoltLowProtectController.text = totalVoltLowProtect;
        _totalVoltLowRecoverController.text = totalVoltLowRecover;
        _totalVoltHighDelayController.text = totalVoltHighDelay;
        _totalVoltLowDelayController.text = totalVoltLowDelay;
        _hwCellHighVoltProtectController.text = hwCellHighVoltProtect;
        _hwCellLowVoltProtectController.text = hwCellLowVoltProtect;
        _isLoading = false;
      });
      
      debugPrint('[PROTECTION_PARAMETER] 🎉 All protection parameters loaded in single update!');
      
    } catch (e) {
      debugPrint('[PROTECTION_PARAMETER] ❌ Error fetching protection parameters: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  /// Fetch cell protection parameters (0x24-0x27) - returns Map with values
  Future<Map<String, String>> _fetchCellProtectionParameters() async {
    Map<String, String> values = {
      'cellHighVoltProtect': '0',
      'cellHighVoltRecover': '0',
      'cellLowVoltProtect': '0',
      'cellLowVoltRecover': '0',
    };

    await _readParameterWithWait(0x24, (data) {
      if (data.length >= 2) {
        final value = (data[0] << 8) | data[1];
        values['cellHighVoltProtect'] = value.toString();
        debugPrint('[PROTECTION_PARAMETER] ✅ Cell High Volt Protect: ${value}mV');
      }
    });

    await _readParameterWithWait(0x25, (data) {
      if (data.length >= 2) {
        final value = (data[0] << 8) | data[1];
        values['cellHighVoltRecover'] = value.toString();
        debugPrint('[PROTECTION_PARAMETER] ✅ Cell High Volt Recover: ${value}mV');
      }
    });

    await _readParameterWithWait(0x26, (data) {
      if (data.length >= 2) {
        final value = (data[0] << 8) | data[1];
        values['cellLowVoltProtect'] = value.toString();
        debugPrint('[PROTECTION_PARAMETER] ✅ Cell Low Volt Protect: ${value}mV');
      }
    });

    await _readParameterWithWait(0x27, (data) {
      if (data.length >= 2) {
        final value = (data[0] << 8) | data[1];
        values['cellLowVoltRecover'] = value.toString();
        debugPrint('[PROTECTION_PARAMETER] ✅ Cell Low Volt Recover: ${value}mV');
      }
    });

    return values;
  }

  /// Fetch cell protection delays (0x3D)
  Future<Map<String, String>> _fetchCellProtectionDelays() async {
    Map<String, String> values = {
      'cellHighVoltDelay': '0',
      'cellLowVoltDelay': '0',
    };

    await _readParameterWithWait(0x3D, (data) {
      if (data.length >= 4) {
        final highDelay = (data[0] << 8) | data[1];
        final lowDelay = (data[2] << 8) | data[3];
        values['cellHighVoltDelay'] = highDelay.toString();
        values['cellLowVoltDelay'] = lowDelay.toString();
        debugPrint('[PROTECTION_PARAMETER] ✅ Cell Delays - High: ${highDelay}s, Low: ${lowDelay}s');
      }
    });

    return values;
  }

  /// Fetch total voltage parameters (0x20-0x23)
  Future<Map<String, String>> _fetchTotalVoltageParameters() async {
    Map<String, String> values = {
      'totalVoltHighProtect': '0',
      'totalVoltHighRecover': '0',
      'totalVoltLowProtect': '0',
      'totalVoltLowRecover': '0',
    };

    await _readParameterWithWait(0x20, (data) {
      if (data.length >= 2) {
        final rawValue = (data[0] << 8) | data[1];
        final valueIn10mV = rawValue * 10; // Convert to 10mV display
        values['totalVoltHighProtect'] = valueIn10mV.toString();
        debugPrint('[PROTECTION_PARAMETER] ✅ Total High Volt Protect: ${valueIn10mV}mV (raw: $rawValue)');
      }
    });

    await _readParameterWithWait(0x21, (data) {
      if (data.length >= 2) {
        final rawValue = (data[0] << 8) | data[1];
        final valueIn10mV = rawValue * 10; // Convert to 10mV display
        values['totalVoltHighRecover'] = valueIn10mV.toString();
        debugPrint('[PROTECTION_PARAMETER] ✅ Total High Volt Recover: ${valueIn10mV}mV (raw: $rawValue)');
      }
    });

    await _readParameterWithWait(0x22, (data) {
      if (data.length >= 2) {
        final rawValue = (data[0] << 8) | data[1];
        final valueIn10mV = rawValue * 10; // Convert to 10mV display
        values['totalVoltLowProtect'] = valueIn10mV.toString();
        debugPrint('[PROTECTION_PARAMETER] ✅ Total Low Volt Protect: ${valueIn10mV}mV (raw: $rawValue)');
      }
    });

    await _readParameterWithWait(0x23, (data) {
      if (data.length >= 2) {
        final rawValue = (data[0] << 8) | data[1];
        final valueIn10mV = rawValue * 10; // Convert to 10mV display
        values['totalVoltLowRecover'] = valueIn10mV.toString();
        debugPrint('[PROTECTION_PARAMETER] ✅ Total Low Volt Recover: ${valueIn10mV}mV (raw: $rawValue)');
      }
    });

    return values;
  }

  /// Fetch total voltage delays (0x3C)
  Future<Map<String, String>> _fetchTotalVoltageDelays() async {
    Map<String, String> values = {
      'totalVoltHighDelay': '0',
      'totalVoltLowDelay': '0',
    };

    await _readParameterWithWait(0x3C, (data) {
      if (data.length >= 4) {
        final highDelay = (data[0] << 8) | data[1];
        final lowDelay = (data[2] << 8) | data[3];
        values['totalVoltHighDelay'] = highDelay.toString();
        values['totalVoltLowDelay'] = lowDelay.toString();
        debugPrint('[PROTECTION_PARAMETER] ✅ Total Voltage Delays - High: ${highDelay}s, Low: ${lowDelay}s');
      }
    });

    return values;
  }

  /// Fetch hardware protection (0x36, 0x37)
  Future<Map<String, String>> _fetchHardwareProtection() async {
    Map<String, String> values = {
      'hwCellHighVoltProtect': '0',
      'hwCellLowVoltProtect': '0',
    };

    await _readParameterWithWait(0x36, (data) {
      if (data.length >= 2) {
        final value = (data[0] << 8) | data[1];
        values['hwCellHighVoltProtect'] = value.toString();
        debugPrint('[PROTECTION_PARAMETER] ✅ HW Cell High Volt Protect: ${value}mV');
      }
    });

    await _readParameterWithWait(0x37, (data) {
      if (data.length >= 2) {
        final value = (data[0] << 8) | data[1];
        values['hwCellLowVoltProtect'] = value.toString();
        debugPrint('[PROTECTION_PARAMETER] ✅ HW Cell Low Volt Protect: ${value}mV');
      }
    });

    return values;
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
        if (mounted && Navigator.canPop(context)) {
          Navigator.pop(context);
        }
      });
    });
  }

  /// Write parameter from placeholder
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

      // Parse the input value and map to register
      int inputValue = int.tryParse(placeholderValue) ?? -1;
      if (inputValue < 0 || inputValue > 655350) {
        _showErrorMessage('Please enter a valid value (0-655350)');
        return;
      }

      int register;
      int writeValue;
      
      switch (parameterKey) {
        // Cell protection parameters - 1mV resolution
        case 'cellHighVoltProtect':
          register = 0x24;
          writeValue = inputValue; // Direct mV value
          break;
        case 'cellHighVoltRecover':
          register = 0x25;
          writeValue = inputValue; // Direct mV value
          break;
        case 'cellLowVoltProtect':
          register = 0x26;
          writeValue = inputValue; // Direct mV value
          break;
        case 'cellLowVoltRecover':
          register = 0x27;
          writeValue = inputValue; // Direct mV value
          break;
        
        // Total voltage parameters - 10mV resolution  
        case 'totalVoltHighProtect':
          register = 0x20;
          writeValue = (inputValue / 10).round(); // Convert mV input to 10mV units
          break;
        case 'totalVoltHighRecover':
          register = 0x21;
          writeValue = (inputValue / 10).round(); // Convert mV input to 10mV units
          break;
        case 'totalVoltLowProtect':
          register = 0x22;
          writeValue = (inputValue / 10).round(); // Convert mV input to 10mV units
          break;
        case 'totalVoltLowRecover':
          register = 0x23;
          writeValue = (inputValue / 10).round(); // Convert mV input to 10mV units
          break;
          
        // Hardware protection parameters - 1mV resolution
        case 'hwCellHighVoltProtect':
          register = 0x36;
          writeValue = inputValue; // Direct mV value
          break;
        case 'hwCellLowVoltProtect':
          register = 0x37;
          writeValue = inputValue; // Direct mV value
          break;
        default:
          _showErrorMessage('Unknown parameter: $parameterKey');
          return;
      }

      if (writeValue < 0 || writeValue > 65535) {
        _showErrorMessage('Value out of range after conversion');
        return;
      }

      debugPrint('[PROTECTION_PARAMETER] Writing $parameterKey = $placeholderValue to register 0x${register.toRadixString(16)}');

      // Reset BLE callback before writing (in case screen was open for long time)
      _refreshBleCallback();
      
      await _writeParameterWithWait(register, writeValue);
      
    } catch (e) {
      debugPrint('[PROTECTION_PARAMETER] Write error: $e');
      _showErrorMessage('Failed to write parameter: $e');
    }
  }

  /// Refresh BLE callback to ensure we receive responses after long idle time
  void _refreshBleCallback() {
    debugPrint('[PROTECTION_PARAMETER] 🔄 Refreshing BLE callback for write operation');
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
      debugPrint('[PROTECTION_PARAMETER] Sending write command: $hexCommand');

      // Send factory mode + write data
      await _writeDataWithFactory(command);
      
      _handleWriteSuccess(register);
      
    } catch (e) {
      debugPrint('[PROTECTION_PARAMETER] Write command failed: $e');
      _showErrorMessage('Write command failed: $e');
    }
  }

  /// Send factory mode then write data
  Future<void> _writeDataWithFactory(List<int> writeCommand) async {
    // Send factory mode command first
    debugPrint('[PROTECTION_PARAMETER] 🔑 Sending factory mode before write...');
    await _sendFactoryModeCommand();
    
    // Then send write command
    await bleService?.writeData(writeCommand);
  }

  void _handleWriteSuccess(int register) {
    debugPrint('[PROTECTION_PARAMETER] Write successful for register 0x${register.toRadixString(16)}');
    
    // Clear the placeholder field for this register
    _clearPlaceholderForRegister(register);
    
    // Wait a moment then read back to verify and update display
    Future.delayed(const Duration(milliseconds: 100), () {
      _refreshBleCallback(); // Ensure fresh callback
      _readParameterWithWait(register, (data) {
        if (data.length >= 2) {
          final value = (data[0] << 8) | data[1];
          debugPrint('[PROTECTION_PARAMETER] ✅ Readback successful: $value');
          _updateDisplayForRegister(register, data);
        } else {
          debugPrint('[PROTECTION_PARAMETER] ❌ Readback failed - invalid data length');
        }
      });
    });
  }

  void _clearPlaceholderForRegister(int register) {
    // Map register to parameter key and clear its placeholder
    String? parameterKey;
    
    switch (register) {
      case 0x24:
        parameterKey = 'cellHighVoltProtect';
        break;
      case 0x25:
        parameterKey = 'cellHighVoltRecover';
        break;
      case 0x26:
        parameterKey = 'cellLowVoltProtect';
        break;
      case 0x27:
        parameterKey = 'cellLowVoltRecover';
        break;
      case 0x20:
        parameterKey = 'totalVoltHighProtect';
        break;
      case 0x21:
        parameterKey = 'totalVoltHighRecover';
        break;
      case 0x22:
        parameterKey = 'totalVoltLowProtect';
        break;
      case 0x23:
        parameterKey = 'totalVoltLowRecover';
        break;
      case 0x36:
        parameterKey = 'hwCellHighVoltProtect';
        break;
      case 0x37:
        parameterKey = 'hwCellLowVoltProtect';
        break;
    } 
    
    if (parameterKey != null) {
      _placeholderControllers[parameterKey]?.clear();
    }
  }

  void _updateDisplayForRegister(int register, List<int> data) {
    if (data.length >= 2) {
      final value = (data[0] << 8) | data[1];
      
      setState(() {
        switch (register) {
          case 0x24:
            _cellHighVoltProtectController.text = value.toString();
            break;
          case 0x25:
            _cellHighVoltRecoverController.text = value.toString();
            break;
          case 0x26:
            _cellLowVoltProtectController.text = value.toString();
            break;
          case 0x27:
            _cellLowVoltRecoverController.text = value.toString();
            break;
          case 0x20:
            _totalVoltHighProtectController.text = value.toString();
            break;
          case 0x21:
            _totalVoltHighRecoverController.text = value.toString();
            break;
          case 0x22:
            _totalVoltLowProtectController.text = value.toString();
            break;
          case 0x23:
            _totalVoltLowRecoverController.text = value.toString();
            break;
          case 0x36:
            _hwCellHighVoltProtectController.text = value.toString();
            break;
          case 0x37:
            _hwCellLowVoltProtectController.text = value.toString();
            break;
        }
      });
      
      debugPrint('[PROTECTION_PARAMETER] ✅ Updated display for register 0x${register.toRadixString(16)} with value: $value');
    }
  }

  void _showErrorMessage(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  String _getLabelKey(String label) {
    // Map UI labels to parameter keys
    switch (label) {
      case 'Cell High Volt Protect':
        return 'cellHighVoltProtect';
      case 'Cell High Volt Recover':
        return 'cellHighVoltRecover';
      case 'Cell High Volt Delay':
        return 'cellHighVoltDelay';
      case 'Cell Low Volt Protect':
        return 'cellLowVoltProtect';
      case 'Cell Low Volt Recover':
        return 'cellLowVoltRecover';
      case 'Cell Low Volt Delay':
        return 'cellLowVoltDelay';
      case 'Total High Volt Protect':
        return 'totalVoltHighProtect';
      case 'Total High Volt Recover':
        return 'totalVoltHighRecover';
      case 'Total High Volt Delay':
        return 'totalVoltHighDelay';
      case 'Total Low Volt Protect':
        return 'totalVoltLowProtect';
      case 'Total Low Volt Recover':
        return 'totalVoltLowRecover';
      case 'Total Low Volt Delay':
        return 'totalVoltLowDelay';
      case 'HW Cell High Volt Protect':
        return 'hwCellHighVoltProtect';
      case 'HW Cell Low Volt Protect':
        return 'hwCellLowVoltProtect';
      default:
        return label.toLowerCase().replaceAll(' ', '');
    }
  }

  @override
  void dispose() {
    // Cancel timers
    _timeoutTimer?.cancel();
    
    // Dispose all controllers
    _cellHighVoltProtectController.dispose();
    _cellHighVoltRecoverController.dispose();
    _cellHighVoltDelayController.dispose();
    _cellLowVoltProtectController.dispose();
    _cellLowVoltRecoverController.dispose();
    _cellLowVoltDelayController.dispose();
    _totalVoltHighProtectController.dispose();
    _totalVoltHighRecoverController.dispose();
    _totalVoltHighDelayController.dispose();
    _totalVoltLowProtectController.dispose();
    _totalVoltLowRecoverController.dispose();
    _totalVoltLowDelayController.dispose();
    _hwCellHighVoltProtectController.dispose();
    _hwCellLowVoltProtectController.dispose();
    
    // Dispose all placeholder controllers
    for (var controller in _placeholderControllers.values) {
      controller.dispose();
    }
    
    // Restore original callback when leaving this page
    if (_originalCallback != null) {
      bleService?.addDataCallback(_originalCallback!);
    }
    super.dispose();
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
              'Protection Parameters',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh, color: Colors.white),
                onPressed: () => _fetchAllProtectionParameters(),
              ),
            ],
          ),
          body: Stack(
            children: [
              // Main content
              SingleChildScrollView(
                padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 12),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 600),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildSectionHeader('Cell Protection', themeProvider),
                        _buildParameterSection([
                          _buildParameterRow('Cell High Volt Protect', _cellHighVoltProtectController, 'mV', themeProvider),
                          _buildParameterRow('Cell High Volt Recover', _cellHighVoltRecoverController, 'mV', themeProvider),
                          _buildParameterRow('Cell High Volt Delay', _cellHighVoltDelayController, 's', themeProvider),
                          _buildParameterRow('Cell Low Volt Protect', _cellLowVoltProtectController, 'mV', themeProvider),
                          _buildParameterRow('Cell Low Volt Recover', _cellLowVoltRecoverController, 'mV', themeProvider),
                          _buildParameterRow('Cell Low Volt Delay', _cellLowVoltDelayController, 's', themeProvider),
                        ]),
                        const SizedBox(height: 24),
                        _buildSectionHeader('Total Voltage Protection', themeProvider),
                        _buildParameterSection([
                          _buildParameterRow('Total High Volt Protect', _totalVoltHighProtectController, 'mV', themeProvider),
                          _buildParameterRow('Total High Volt Recover', _totalVoltHighRecoverController, 'mV', themeProvider),
                          _buildParameterRow('Total High Volt Delay', _totalVoltHighDelayController, 's', themeProvider),
                          _buildParameterRow('Total Low Volt Protect', _totalVoltLowProtectController, 'mV', themeProvider),
                          _buildParameterRow('Total Low Volt Recover', _totalVoltLowRecoverController, 'mV', themeProvider),
                          _buildParameterRow('Total Low Volt Delay', _totalVoltLowDelayController, 's', themeProvider),
                        ]),
                        const SizedBox(height: 24),
                        _buildSectionHeader('Hardware Protection', themeProvider),
                        _buildParameterSection([
                          _buildParameterRow('HW Cell High Volt Protect', _hwCellHighVoltProtectController, 'mV', themeProvider),
                          _buildParameterRow('HW Cell Low Volt Protect', _hwCellLowVoltProtectController, 'mV', themeProvider),
                        ]),
                      ],
                    ),
                  ),
                ),
              ),
              
              // Loading overlay
              if (_isLoading && bleService?.isConnected == true)
                const _LoadingOverlay(),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSectionHeader(String title, ThemeProvider themeProvider) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 16),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: themeProvider.primaryColor,
        ),
      ),
    );
  }

  Widget _buildParameterSection(List<Widget> children) {
    return Column(children: children);
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
                    FilteringTextInputFormatter.digitsOnly,
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
                'Loading Protection Parameters...',
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