import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import '../../../services/bluetooth/ble_service.dart';
import '../../cubits/theme_cubit.dart';

class BalanceSettingsPage extends StatefulWidget {
  const BalanceSettingsPage({super.key});

  @override
  State<BalanceSettingsPage> createState() => _BalanceSettingsPageState();
}

class _BalanceSettingsPageState extends State<BalanceSettingsPage> {
  BleService? bleService;
  Function(List<int>)? _originalCallback;
  
  // Response waiting
  Completer<List<int>>? _responseCompleter;
  Timer? _timeoutTimer;
  int _expectedRegister = 0;
  
  bool _isLoading = true;
  
  // Text controllers for displaying actual values
  late TextEditingController _balanceStartVoltageController;
  late TextEditingController _balanceAccuracyController;
  
  // Switch states
  bool _balanceEnable = false;        // Balance enable switch
  bool _chargeBalance = false;        // Charge balance switch
  
  // Placeholder controllers for user input
  final Map<String, TextEditingController> _placeholderControllers = {};

  @override
  void initState() {
    super.initState();
    debugPrint('[BALANCE_SETTINGS] Screen initialized');
    
    // Initialize controllers with 0 values
    _balanceStartVoltageController = TextEditingController(text: '0');
    _balanceAccuracyController = TextEditingController(text: '0');
    
    _loadBalanceSettings();
  }

  Future<void> _loadBalanceSettings() async {
    try {
      bleService = context.read<BleService>();
      
      if (bleService?.isConnected != true) {
        setState(() {
          _balanceStartVoltageController.text = '0';
          _balanceAccuracyController.text = '0';
          _balanceEnable = false;
          _chargeBalance = false;
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
      
      await _fetchAllBalanceSettings();
    } catch (e) {
      debugPrint('[BALANCE_SETTINGS] Error: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  /// BLE data handler for balance setting responses
  void _handleBleData(List<int> data) {
    if (data.length < 7) return;
    if (data[0] != 0xDD || data.last != 0x77) return;
    
    final register = data[1];
    final status = data[2];
    final dataLength = data[3];
    
    debugPrint('[BALANCE_SETTINGS] 📦 Received response - Register: 0x${register.toRadixString(16)}, Status: 0x${status.toRadixString(16)}, Length: $dataLength');
    
    // Complete the response completer if waiting for this register
    if (_responseCompleter != null && !_responseCompleter!.isCompleted) {
      if (register == _expectedRegister && status == 0x00) {
        _responseCompleter!.complete(data);
        _timeoutTimer?.cancel();
        debugPrint('[BALANCE_SETTINGS] ✅ Response completed for register 0x${register.toRadixString(16)}');
      }
    }
  }
  
  /// Wait for BLE response with timeout
  Future<List<int>?> _waitForResponse(Duration timeout) async {
    _responseCompleter = Completer<List<int>>();
    
    _timeoutTimer = Timer(timeout, () {
      if (!_responseCompleter!.isCompleted) {
        debugPrint('[BALANCE_SETTINGS] ⏰ Response timeout for register 0x${_expectedRegister.toRadixString(16)}');
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
      debugPrint('[BALANCE_SETTINGS] Reading register 0x${register.toRadixString(16)}...');
      
      // Set expected register for response matching
      _expectedRegister = register;
      
      // Send the command
      final checksum = (0x10000 - (register + 0x00)) & 0xFFFF;
      final checksumHigh = (checksum >> 8) & 0xFF;
      final checksumLow = checksum & 0xFF;
      
      final command = [0xDD, 0xA5, register, 0x00, checksumHigh, checksumLow, 0x77];
      debugPrint('[BALANCE_SETTINGS] Sending command: ${command.map((b) => '0x${b.toRadixString(16).padLeft(2, '0')}').join(' ')}');
      
      await bleService?.writeData(command);
      
      // Wait for response
      final response = await _waitForResponse(const Duration(seconds: 3));
      
      if (response != null && response.length > 3 && response[2] == 0x00) {
        final dataLength = response[3];
        if (response.length >= 4 + dataLength) {
          final responseData = response.sublist(4, 4 + dataLength);
          onSuccess(responseData);
          debugPrint('[BALANCE_SETTINGS] ✅ Successfully processed register 0x${register.toRadixString(16)}');
        } else {
          debugPrint('[BALANCE_SETTINGS] ❌ Data length mismatch for register 0x${register.toRadixString(16)}');
        }
      } else {
        debugPrint('[BALANCE_SETTINGS] ❌ Invalid response for register 0x${register.toRadixString(16)}');
      }
      
    } catch (e) {
      debugPrint('[BALANCE_SETTINGS] ❌ Error reading register 0x${register.toRadixString(16)}: $e');
    }
  }

  /// Send factory mode command
  Future<bool> _sendFactoryModeCommand() async {
    try {
      debugPrint('[BALANCE_SETTINGS] 🔑 Sending factory mode command...');
      
      // Factory mode command: DD 5A 00 02 56 78 FF 30 77
      final List<int> factoryModeCommand = [0xDD, 0x5A, 0x00, 0x02, 0x56, 0x78, 0xFF, 0x30, 0x77];
      final String hexCommand = factoryModeCommand.map((b) => '0x${b.toRadixString(16).padLeft(2, '0').toUpperCase()}').join(' ');
      
      debugPrint('[BALANCE_SETTINGS] Factory Mode Command: $hexCommand');
      
      await bleService?.writeData(factoryModeCommand);
      
      debugPrint('[BALANCE_SETTINGS] ✅ Factory mode command sent successfully');
      return true;
    } catch (e) {
      debugPrint('[BALANCE_SETTINGS] ❌ Factory mode command failed: $e');
      return false;
    }
  }

  /// Fetch all balance settings
  Future<void> _fetchAllBalanceSettings() async {
    try {
      debugPrint('[BALANCE_SETTINGS] 🚀 Starting balance settings fetch...');
      
      // Step 1: Send factory mode command FIRST
      debugPrint('[BALANCE_SETTINGS] 🔑 Step 1: Factory Mode Command');
      bool factoryModeSuccess = await _sendFactoryModeCommand();
      if (!factoryModeSuccess) {
        debugPrint('[BALANCE_SETTINGS] ⚠️ Factory mode failed, continuing anyway...');
      }
      
      // Wait a bit for factory mode to take effect
      await Future.delayed(const Duration(milliseconds: 30));
      
      // Step 2: Fetch balance parameters and function switches
      debugPrint('[BALANCE_SETTINGS] 📊 Step 2: Fetching Balance Settings');
      await _fetchBalanceStartVoltage();  // 0x2A
      await _fetchBalanceAccuracy();      // 0x2B  
      await _fetchBalanceSwitches();       // 0x2D (function settings)
      
      // Step 3: All data loaded, update UI
      setState(() {
        _isLoading = false;
      });
      
      debugPrint('[BALANCE_SETTINGS] 🎉 All balance settings loaded!');
      
    } catch (e) {
      debugPrint('[BALANCE_SETTINGS] ❌ Error fetching balance settings: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  /// Fetch balance start voltage (0x2A)
  Future<void> _fetchBalanceStartVoltage() async {
    await _readParameterWithWait(0x2A, (data) {
      if (data.length >= 2) {
        final value = (data[0] << 8) | data[1];
        setState(() {
          _balanceStartVoltageController.text = value.toString();
        });
        debugPrint('[BALANCE_SETTINGS] ✅ Balance start voltage: ${value}mV');
      }
    });
  }

  /// Fetch balance accuracy (0x2B)
  Future<void> _fetchBalanceAccuracy() async {
    await _readParameterWithWait(0x2B, (data) {
      if (data.length >= 2) {
        final value = (data[0] << 8) | data[1];
        setState(() {
          _balanceAccuracyController.text = value.toString();
        });
        debugPrint('[BALANCE_SETTINGS] ✅ Balance accuracy: ${value}mV');
      }
    });
  }

  /// Fetch balance switches from function settings (0x2D)
  Future<void> _fetchBalanceSwitches() async {
    await _readParameterWithWait(0x2D, (data) {
      if (data.length >= 2) {
        // Parse function bits from 2-byte value
        final functionBits = (data[0] << 8) | data[1];
        
        setState(() {
          _balanceEnable = (functionBits & 0x0004) != 0;       // bit 2: balance_en
          _chargeBalance = (functionBits & 0x0008) != 0;       // bit 3: chg_balance_en
        });
        
        debugPrint('[BALANCE_SETTINGS] ✅ Balance switches - Balance Enable: $_balanceEnable, Charge Balance: $_chargeBalance');
      }
    });
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

      // Parse the input value as mV directly
      int mvValue = int.tryParse(placeholderValue) ?? -1;
      if (mvValue < 0 || mvValue > 65535) {
        _showErrorMessage('Please enter a valid voltage (0-65535 mV)');
        return;
      }

      // Map parameter to register - value already in mV
      int register;
      int scaledValue;
      
      switch (parameterKey) {
        case 'balanceStartVoltage': // 0x2A balance start voltage - mV resolution
          register = 0x2A;
          scaledValue = mvValue; // Direct mV value, no conversion needed
          break;
        case 'balanceAccuracy': // 0x2B balance accuracy - mV resolution  
          register = 0x2B;
          scaledValue = mvValue; // Direct mV value, no conversion needed
          break;
        default:
          _showErrorMessage('Unknown parameter: $parameterKey');
          return;
      }

      debugPrint('[BALANCE_SETTINGS] Writing $parameterKey = ${placeholderValue}mV (value: $scaledValue) to register 0x${register.toRadixString(16)}');

      await _writeParameterWithWait(register, scaledValue);
      
    } catch (e) {
      debugPrint('[BALANCE_SETTINGS] Write error: $e');
      _showErrorMessage('Failed to write parameter: $e');
    }
  }

  /// Write parameter with factory mode
  Future<void> _writeParameterWithWait(int register, int value) async {
    try {
      // Step 1: Send factory mode command before writing
      debugPrint('[BALANCE_SETTINGS] 🔑 Sending factory mode command before write...');
      bool factoryModeSuccess = await _sendFactoryModeCommand();
      if (!factoryModeSuccess) {
        debugPrint('[BALANCE_SETTINGS] ⚠️ Factory mode failed before write, continuing anyway...');
      }
      
      // Minimal wait for factory mode
      await Future.delayed(const Duration(milliseconds: 50));
      
      // Step 2: Build BLE write command: DD 5A [REG] 02 [DATA_HIGH] [DATA_LOW] [CHECKSUM_HIGH] [CHECKSUM_LOW] 77
      final dataHigh = (value >> 8) & 0xFF;
      final dataLow = value & 0xFF;
      
      // Calculate checksum: 0x10000 - (register + length + dataHigh + dataLow)
      final checksumValue = 0x10000 - (register + 0x02 + dataHigh + dataLow);
      final checksumHigh = (checksumValue >> 8) & 0xFF;
      final checksumLow = checksumValue & 0xFF;
      
      final command = [0xDD, 0x5A, register, 0x02, dataHigh, dataLow, checksumHigh, checksumLow, 0x77];
      
      final hexCommand = command.map((b) => '0x${b.toRadixString(16).padLeft(2, '0').toUpperCase()}').join(' ');
      debugPrint('[BALANCE_SETTINGS] Sending write command: $hexCommand');

      await bleService?.writeData(command);
      
      // Minimal wait for write completion
      await Future.delayed(const Duration(milliseconds: 10));
      
      _handleWriteSuccess(register);
      
    } catch (e) {
      debugPrint('[BALANCE_SETTINGS] Write command failed: $e');
      _showErrorMessage('Write command failed: $e');
    }
  }

  void _handleWriteSuccess(int register) {
    debugPrint('[BALANCE_SETTINGS] Write successful for register 0x${register.toRadixString(16)}, reading back...');
    
    // Clear the placeholder field for this register
    _clearPlaceholderForRegister(register);
    
    // Read back the parameter to update the display immediately
    Future.delayed(const Duration(milliseconds: 10), () {
      _readParameterWithWait(register, (data) {
        _updateDisplayForRegister(register, data);
      });
    });
  }

  void _clearPlaceholderForRegister(int register) {
    // Map register to parameter key and clear its placeholder
    String? parameterKey;
    
    switch (register) {
      case 0x2A:
        parameterKey = 'balanceStartVoltage';
        break;
      case 0x2B:
        parameterKey = 'balanceAccuracy';
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
          case 0x2A: // Balance start voltage
            _balanceStartVoltageController.text = value.toString();
            break;
          case 0x2B: // Balance accuracy
            _balanceAccuracyController.text = value.toString();
            break;
        }
      });
      
      debugPrint('[BALANCE_SETTINGS] ✅ Updated display for register 0x${register.toRadixString(16)} with value: $value');
    }
  }

  /// Write balance switch setting
  Future<void> _writeBalanceSwitch(String settingName, bool value, int bitPosition) async {
    try {
      if (bleService?.isConnected != true) {
        _showErrorMessage('Device not connected');
        return;
      }

      debugPrint('[BALANCE_SETTINGS] Writing $settingName = $value (bit $bitPosition)');

      // Get current function bits from UI state (include both balance switches)
      int currentBits = 0;
      if (_balanceEnable) currentBits |= 0x0004;    // bit 2
      if (_chargeBalance) currentBits |= 0x0008;    // bit 3
      
      int bitValue = 1 << bitPosition;
      int newBits;
      
      if (value) {
        // Add bit (turn ON)
        newBits = currentBits | bitValue;
        debugPrint('[BALANCE_SETTINGS] Adding bit $bitPosition: 0x${currentBits.toRadixString(16)} + 0x${bitValue.toRadixString(16)} = 0x${newBits.toRadixString(16)}');
      } else {
        // Subtract bit (turn OFF)
        newBits = currentBits & ~bitValue;
        debugPrint('[BALANCE_SETTINGS] Subtracting bit $bitPosition: 0x${currentBits.toRadixString(16)} - 0x${bitValue.toRadixString(16)} = 0x${newBits.toRadixString(16)}');
      }
      
      // Write new function bits back to register 0x2D
      await _writeFunctionBits(newBits);
      
    } catch (e) {
      debugPrint('[BALANCE_SETTINGS] Write error: $e');
      _showErrorMessage('Failed to write setting: $e');
    }
  }

  /// Write function bits to register 0x2D
  Future<void> _writeFunctionBits(int functionBits) async {
    try {
      // Step 1: Send factory mode command before writing
      debugPrint('[BALANCE_SETTINGS] 🔑 Sending factory mode command before switch write...');
      bool factoryModeSuccess = await _sendFactoryModeCommand();
      if (!factoryModeSuccess) {
        debugPrint('[BALANCE_SETTINGS] ⚠️ Factory mode failed before write, continuing anyway...');
      }
      
      // Minimal wait for factory mode
      await Future.delayed(const Duration(milliseconds: 20));
      
      // Step 2: Build BLE write command for register 0x2D
      const register = 0x2D;
      final dataHigh = (functionBits >> 8) & 0xFF;
      final dataLow = functionBits & 0xFF;
      
      // Calculate checksum: 0x10000 - (register + length + dataHigh + dataLow)
      final checksumValue = 0x10000 - (register + 0x02 + dataHigh + dataLow);
      final checksumHigh = (checksumValue >> 8) & 0xFF;
      final checksumLow = checksumValue & 0xFF;
      
      final command = [0xDD, 0x5A, register, 0x02, dataHigh, dataLow, checksumHigh, checksumLow, 0x77];
      
      final hexCommand = command.map((b) => '0x${b.toRadixString(16).padLeft(2, '0').toUpperCase()}').join(' ');
      debugPrint('[BALANCE_SETTINGS] Sending function bits write command: $hexCommand');

      await bleService?.writeData(command);
      
      // Minimal wait for write completion
      await Future.delayed(const Duration(milliseconds: 10));
      
      // Quick re-read to verify
      await Future.delayed(const Duration(milliseconds: 10));
      await _fetchBalanceSwitches();
      
    } catch (e) {
      debugPrint('[BALANCE_SETTINGS] Function bits write command failed: $e');
      _showErrorMessage('Write command failed: $e');
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
      case 'Balance Start Voltage':
        return 'balanceStartVoltage';
      case 'Balance Accuracy':
        return 'balanceAccuracy';
      default:
        return label.toLowerCase().replaceAll(' ', '');
    }
  }

  @override
  void dispose() {
    // Cancel timers
    _timeoutTimer?.cancel();
    
    // Dispose all controllers
    _balanceStartVoltageController.dispose();
    _balanceAccuracyController.dispose();
    
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
              'Balance Settings',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh, color: Colors.white),
                onPressed: () => _fetchAllBalanceSettings(),
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
                        _buildSectionHeader('Balance Parameters'),
                        _buildParameterSection([
                          _buildParameterRow('Balance Start Voltage', _balanceStartVoltageController, 'mV'),
                          _buildParameterRow('Balance Accuracy', _balanceAccuracyController, 'mV'),
                          _buildSwitchRow('Balance Enable', _balanceEnable, (value) => _writeBalanceSwitch('Balance Enable', value, 2), themeProvider),
                          _buildSwitchRow('Charge Balance', _chargeBalance, (value) => _writeBalanceSwitch('Charge Balance', value, 3), themeProvider),
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

  Widget _buildSectionHeader(String title) {
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, _) {
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
      },
    );
  }

  Widget _buildParameterSection(List<Widget> children) {
    return Column(children: children);
  }

  Widget _buildSwitchRow(String label, bool value, Function(bool) onChanged, ThemeProvider themeProvider) {
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
              _CustomRealSwitch(
                value: value,
                onChanged: onChanged,
                activeColor: themeProvider.primaryColor,
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

  Widget _buildParameterRow(String label, TextEditingController controller, String unit) {
    // Create a unique key for this parameter based on label
    String parameterKey = _getLabelKey(label);
    
    // Create or get the placeholder controller for this parameter (always empty)
    if (!_placeholderControllers.containsKey(parameterKey)) {
      _placeholderControllers[parameterKey] = TextEditingController();
    }
    final placeholderController = _placeholderControllers[parameterKey]!;
    
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, _) {
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
      },
    );
  }
}

/// Custom real button style switch (same as function settings)
class _CustomRealSwitch extends StatelessWidget {
  final bool value;
  final Function(bool) onChanged;
  final Color activeColor;

  const _CustomRealSwitch({
    required this.value,
    required this.onChanged,
    required this.activeColor,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 44,
        height: 22,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(11),
          color: value ? activeColor : Colors.grey.shade400,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 3,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Stack(
          children: [
            AnimatedPositioned(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeInOut,
              left: value ? 22 : 2,
              top: 1,
              child: Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.08),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                      spreadRadius: 0,
                    ),
                    BoxShadow(
                      color: Colors.black.withOpacity(0.04),
                      blurRadius: 1,
                      offset: const Offset(0, 0.5),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Reusable loading overlay widget
class _LoadingOverlay extends StatelessWidget {
  const _LoadingOverlay();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.transparent,
      width: double.infinity,
      height: double.infinity,
      child: Center(
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.5),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
              SizedBox(height: 16),
              Text(
                'Loading Balance Settings...',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}