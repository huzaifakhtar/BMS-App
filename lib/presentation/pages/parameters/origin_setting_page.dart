import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import '../../../services/bluetooth/ble_service.dart';
import '../../cubits/theme_cubit.dart';

class OriginSettingPage extends StatefulWidget {
  const OriginSettingPage({super.key});

  @override
  State<OriginSettingPage> createState() => _OriginSettingPageState();
}

class _OriginSettingPageState extends State<OriginSettingPage> {
  BleService? bleService;
  Function(List<int>)? _originalCallback;
  
  // Text controllers for displaying actual values (like protection parameter page)
  late TextEditingController _nominalCapacityController;
  late TextEditingController _cycleCapacityController;
  late TextEditingController _fullChargeCapacityController;
  late TextEditingController _cellNumController;
  
  // Placeholder controllers for user input
  final Map<String, TextEditingController> _placeholderControllers = {};
  
  // Response waiting
  Completer<List<int>>? _responseCompleter;
  Timer? _timeoutTimer;
  int _expectedRegister = 0;
  
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    debugPrint('[ORIGIN_SETTING] Screen initialized');
    
    // Initialize controllers with 0 values (like protection parameter page)
    _nominalCapacityController = TextEditingController(text: '0');
    _cycleCapacityController = TextEditingController(text: '0');
    _fullChargeCapacityController = TextEditingController(text: '0');
    _cellNumController = TextEditingController(text: '0');
    
    _loadOriginSetting();
  }

  Future<void> _loadOriginSetting() async {
    try {
      bleService = context.read<BleService>();
      
      if (bleService?.isConnected != true) {
        setState(() {
          _nominalCapacityController.text = '0';
          _cycleCapacityController.text = '0';
          _fullChargeCapacityController.text = '0';
          _cellNumController.text = '0';
          _isLoading = false;
        });
        _showNotConnectedDialog();
        return;
      }

      setState(() {
        _isLoading = true;
        // Keep showing 0 while loading, don't change the display values
      });

      _originalCallback = bleService?.dataCallback;
      bleService?.addDataCallback(_handleBleData);
      
      await _fetchAllOriginSettings();
    } catch (e) {
      debugPrint('[ORIGIN_SETTING] Error: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  /// BLE data handler for origin setting responses
  void _handleBleData(List<int> data) {
    if (data.length < 7) return;
    if (data[0] != 0xDD || data.last != 0x77) return;
    
    final register = data[1];
    final status = data[2];
    final dataLength = data[3];
    
    debugPrint('[ORIGIN_SETTING] 📦 Received response - Register: 0x${register.toRadixString(16)}, Status: 0x${status.toRadixString(16)}, Length: $dataLength');
    
    // Complete the response completer if waiting for this register
    if (_responseCompleter != null && !_responseCompleter!.isCompleted) {
      if (register == _expectedRegister && status == 0x00) {
        _responseCompleter!.complete(data);
        _timeoutTimer?.cancel();
        debugPrint('[ORIGIN_SETTING] ✅ Response completed for register 0x${register.toRadixString(16)}');
      }
    }
  }
  
  /// Wait for BLE response with timeout
  Future<List<int>?> _waitForResponse(Duration timeout) async {
    _responseCompleter = Completer<List<int>>();
    
    _timeoutTimer = Timer(timeout, () {
      if (!_responseCompleter!.isCompleted) {
        debugPrint('[ORIGIN_SETTING] ⏰ Response timeout for register 0x${_expectedRegister.toRadixString(16)}');
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
      debugPrint('[ORIGIN_SETTING] Reading register 0x${register.toRadixString(16)}...');
      
      // Set expected register for response matching
      _expectedRegister = register;
      
      // Send the command
      final checksum = (0x10000 - (register + 0x00)) & 0xFFFF;
      final checksumHigh = (checksum >> 8) & 0xFF;
      final checksumLow = checksum & 0xFF;
      
      final command = [0xDD, 0xA5, register, 0x00, checksumHigh, checksumLow, 0x77];
      debugPrint('[ORIGIN_SETTING] Sending command: ${command.map((b) => '0x${b.toRadixString(16).padLeft(2, '0')}').join(' ')}');
      
      await bleService?.writeData(command);
      
      // Wait for response
      final response = await _waitForResponse(const Duration(seconds: 3));
      
      if (response != null && response.length > 3 && response[2] == 0x00) {
        final dataLength = response[3];
        if (response.length >= 4 + dataLength) {
          final responseData = response.sublist(4, 4 + dataLength);
          onSuccess(responseData);
          debugPrint('[ORIGIN_SETTING] ✅ Successfully processed register 0x${register.toRadixString(16)}');
        } else {
          debugPrint('[ORIGIN_SETTING] ❌ Data length mismatch for register 0x${register.toRadixString(16)}');
          _setParameterError(register);
        }
      } else {
        debugPrint('[ORIGIN_SETTING] ❌ Invalid response for register 0x${register.toRadixString(16)}');
        _setParameterError(register);
      }
      
    } catch (e) {
      debugPrint('[ORIGIN_SETTING] ❌ Error reading register 0x${register.toRadixString(16)}: $e');
      _setParameterError(register);
    }
  }

  /// Set error state for specific parameter registers
  void _setParameterError(int register) {
    if (mounted) {
      setState(() {
        switch (register) {
          case 0x10: _nominalCapacityController.text = '0'; break;
          case 0x11: _cycleCapacityController.text = '0'; break;
          case 0x03: _fullChargeCapacityController.text = '0'; break;
          case 0x2F: _cellNumController.text = '0'; break;
        }
      });
    }
  }

  /// Send factory mode command with improved reliability
  Future<bool> _sendFactoryModeCommand() async {
    try {
      debugPrint('[ORIGIN_SETTING] 🔑 Sending factory mode command...');
      
      // Factory mode command: DD 5A 00 02 56 78 FF 30 77
      final List<int> factoryModeCommand = [0xDD, 0x5A, 0x00, 0x02, 0x56, 0x78, 0xFF, 0x30, 0x77];
      final String hexCommand = factoryModeCommand.map((b) => '0x${b.toRadixString(16).padLeft(2, '0').toUpperCase()}').join(' ');
      
      debugPrint('[ORIGIN_SETTING] Factory Mode Command: $hexCommand');
      
      await bleService?.writeData(factoryModeCommand);
      
      debugPrint('[ORIGIN_SETTING] ✅ Factory mode command sent successfully');
      return true;
    } catch (e) {
      debugPrint('[ORIGIN_SETTING] ❌ Factory mode command failed: $e');
      return false;
    }
  }

  /// Fetch all origin settings with individual register reads
  Future<void> _fetchAllOriginSettings() async {
    try {
      debugPrint('[ORIGIN_SETTING] 🚀 Starting origin settings fetch...');
      
      // Step 1: Send factory mode command FIRST - wait for response
      debugPrint('[ORIGIN_SETTING] 🔑 Step 1: Factory Mode Command');
      bool factoryModeSuccess = await _sendFactoryModeCommand();
      if (!factoryModeSuccess) {
        debugPrint('[ORIGIN_SETTING] ⚠️ Factory mode failed, continuing anyway...');
      }
      
      // Wait a bit for factory mode to take effect
      await Future.delayed(const Duration(milliseconds: 500));
      
      // Step 2: Sequential parameter fetching - wait for each response before next
      debugPrint('[ORIGIN_SETTING] 📊 Step 2: Response-Based Parameter Fetch');
      await _fetchNominalCapacity();    // 0x10
      await _fetchCycleCapacity();      // 0x11
      await _fetchFullChargeCapacity(); // 0x03
      await _fetchCellNumber();         // 0x2F
      
      // Step 3: All data loaded, update UI
      setState(() {
        _isLoading = false;
      });
      
      debugPrint('[ORIGIN_SETTING] 🎉 All origin settings loaded with factory mode!');
      
    } catch (e) {
      debugPrint('[ORIGIN_SETTING] ❌ Error fetching origin settings: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  /// Fetch nominal capacity (0x10)
  Future<void> _fetchNominalCapacity() async {
    await _readParameterWithWait(0x10, (data) {
      if (data.length >= 2) {
        final value = (data[0] << 8) | data[1];
        final capacityAh = value / 100.0; // Convert from 10mAh to Ah
        setState(() {
          _nominalCapacityController.text = capacityAh.toStringAsFixed(2);
        });
        debugPrint('[ORIGIN_SETTING] ✅ Nominal capacity: ${capacityAh}Ah');
      }
    });
  }

  /// Fetch cycle capacity (0x11)
  Future<void> _fetchCycleCapacity() async {
    await _readParameterWithWait(0x11, (data) {
      if (data.length >= 2) {
        final value = (data[0] << 8) | data[1];
        final capacityAh = value / 100.0; // Convert from 10mAh to Ah
        setState(() {
          _cycleCapacityController.text = capacityAh.toStringAsFixed(2);
        });
        debugPrint('[ORIGIN_SETTING] ✅ Cycle capacity: ${capacityAh}Ah');
      }
    });
  }

  /// Fetch full charge capacity - try multiple methods
  Future<void> _fetchFullChargeCapacity() async {
    debugPrint('[ORIGIN_SETTING] 🔍 Starting full charge capacity fetch...');
    
    // First try: Direct register 0xE0
    debugPrint('[ORIGIN_SETTING] 📊 Method 1: Trying direct register 0xE0...');
    await _readParameterWithWait(0xE0, (data) {
      debugPrint('[ORIGIN_SETTING] 📊 Register 0xE0 data: ${data.map((b) => '0x${b.toRadixString(16).padLeft(2, '0')}').join(' ')} (length: ${data.length})');
      
      if (data.length >= 2) {
        final value = (data[0] << 8) | data[1];
        if (value > 0) {
          final capacityAh = value / 100.0;
          debugPrint('[ORIGIN_SETTING] ✅ Method 1 SUCCESS - Register 0xE0: ${capacityAh}Ah');
          setState(() {
            _fullChargeCapacityController.text = capacityAh.toStringAsFixed(2);
          });
          return; // Success, exit
        } else {
          debugPrint('[ORIGIN_SETTING] ⚠️ Method 1 - Register 0xE0 returned zero, trying method 2...');
        }
      } else {
        debugPrint('[ORIGIN_SETTING] ❌ Method 1 - Register 0xE0 data too short, trying method 2...');
      }
      
      // Method 2: Try from basic info register 0x03
      _fetchFullChargeCapacityFromBasicInfo();
    });
  }

  /// Method 2: Get full charge capacity from basic info (0x03)
  Future<void> _fetchFullChargeCapacityFromBasicInfo() async {
    debugPrint('[ORIGIN_SETTING] 📊 Method 2: Trying basic info register 0x03...');
    
    await _readParameterWithWait(0x03, (data) {
      debugPrint('[ORIGIN_SETTING] 📊 Basic info raw data length: ${data.length}');
      debugPrint('[ORIGIN_SETTING] 📊 Basic info raw data: ${data.map((b) => '0x${b.toRadixString(16).padLeft(2, '0')}').join(' ')}');
      
      try {
        // Basic validation
        if (data.length < 7) {
          debugPrint('[ORIGIN_SETTING] ❌ Method 2 failed - Basic info data too short: ${data.length} bytes, trying method 3...');
          _fetchFullChargeCapacityFallback();
          return;
        }
        
        // Full charge capacity is at position: data.length - 6 (like version fetching)
        int capacityPosition = data.length - 6;
        debugPrint('[ORIGIN_SETTING] 📍 Full charge capacity position: $capacityPosition (data.length - 6 = ${data.length} - 6)');
        
        // Validate we have enough data
        if (capacityPosition < 0 || data.length < capacityPosition + 2) {
          debugPrint('[ORIGIN_SETTING] ❌ Method 2 failed - Invalid position for full charge capacity. Position: $capacityPosition, data length: ${data.length}, trying method 3...');
          _fetchFullChargeCapacityFallback();
          return;
        }
        
        // Read 2-byte value from calculated position
        final value = (data[capacityPosition] << 8) | data[capacityPosition + 1];
        final capacityAh = value / 100.0; // Convert from 10mAh to Ah
        
        debugPrint('[ORIGIN_SETTING] 🔢 Full charge capacity: raw=$value (bytes $capacityPosition-${capacityPosition + 1}), converted=${capacityAh}Ah');
        
        if (value > 0) {
          setState(() {
            _fullChargeCapacityController.text = capacityAh.toStringAsFixed(2);
          });
          debugPrint('[ORIGIN_SETTING] ✅ Method 2 SUCCESS - Full charge capacity: ${capacityAh}Ah');
        } else {
          debugPrint('[ORIGIN_SETTING] ⚠️ Method 2 returned zero value, trying method 3...');
          _fetchFullChargeCapacityFallback();
        }
        
      } catch (e) {
        debugPrint('[ORIGIN_SETTING] ❌ Method 2 error: $e, trying method 3...');
        _fetchFullChargeCapacityFallback();
      }
    });
  }

  /// Method 3: Fallback - use nominal capacity as estimate
  Future<void> _fetchFullChargeCapacityFallback() async {
    debugPrint('[ORIGIN_SETTING] 📊 Method 3: Using nominal capacity as fallback...');
    
    // Use nominal capacity as fallback (should already be loaded)
    final nominalValue = _nominalCapacityController.text;
    if (nominalValue != '0' && nominalValue.isNotEmpty) {
      setState(() {
        _fullChargeCapacityController.text = nominalValue;
      });
      debugPrint('[ORIGIN_SETTING] ✅ Method 3 SUCCESS - Using nominal capacity as fallback: ${nominalValue}Ah');
    } else {
      setState(() {
        _fullChargeCapacityController.text = '0';
      });
      debugPrint('[ORIGIN_SETTING] ❌ All methods failed - Setting full charge capacity to 0');
    }
  }
  

  /// Fetch cell number (0x2F)
  Future<void> _fetchCellNumber() async {
    await _readParameterWithWait(0x2F, (data) {
      if (data.length >= 2) {
        final value = (data[0] << 8) | data[1];
        setState(() {
          _cellNumController.text = value.toString();
        });
        debugPrint('[ORIGIN_SETTING] ✅ Cell number: $value');
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
              'Origin Setting',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh, color: Colors.white),
                onPressed: () => _fetchAllOriginSettings(),
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
                        _buildSectionHeader('Battery Origin Settings'),
                        _buildParameterSection([
                          _buildParameterRow('Nominal Capacity', _nominalCapacityController, 'Ah'),
                          _buildParameterRow('Cycle Capacity', _cycleCapacityController, 'Ah'),
                          _buildParameterRow('Full Charge Capacity', _fullChargeCapacityController, 'Ah'),
                          _buildParameterRow('Number of Cells', _cellNumController, ''),
                        ]),
                      ],
                    ),
                  ),
                ),
              ),
              
              // Loading overlay (same as basic info page)
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
                        FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
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

  String _getLabelKey(String label) {
    // Map UI labels to parameter keys
    switch (label) {
      case 'Nominal Capacity':
        return 'nominalCapacity';
      case 'Cycle Capacity':
        return 'cycleCapacity';
      case 'Full Charge Capacity':
        return 'fullChargeCapacity';
      case 'Cell Number':
        return 'cellNumber';
      default:
        return label.toLowerCase().replaceAll(' ', '');
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

      // Parse the input value based on parameter type
      double doubleValue = 0.0;
      int intValue = 0;
      
      // For cell number, expect integer input
      if (parameterKey == 'cellNumber') {
        intValue = int.tryParse(placeholderValue) ?? -1;
        if (intValue < 0 || intValue > 65535) {
          _showErrorMessage('Please enter a valid number (0-65535)');
          return;
        }
      } else {
        // For capacity fields, expect decimal input
        doubleValue = double.tryParse(placeholderValue) ?? -1.0;
        if (doubleValue < 0 || doubleValue > 655.35) {
          _showErrorMessage('Please enter a valid capacity (0-655.35 Ah)');
          return;
        }
      }

      // Map parameter to register and convert value
      int register;
      int scaledValue;
      
      switch (parameterKey) {
        case 'nominalCapacity': // 0x10 design_cap - 10mAh resolution
          register = 0x10;
          scaledValue = (doubleValue * 100).round(); // Convert Ah to 10mAh units
          break;
        case 'cycleCapacity': // 0x11 cycle_cap - 10mAh resolution  
          register = 0x11;
          scaledValue = (doubleValue * 100).round(); // Convert Ah to 10mAh units
          break;
        case 'fullChargeCapacity': // 0x03 full_cap - 10mAh resolution
          register = 0x03;
          scaledValue = (doubleValue * 100).round(); // Convert Ah to 10mAh units
          break;
        case 'cellNumber': // 0x2F cell_cnt - 1 cell resolution
          register = 0x2F;
          scaledValue = intValue; // Direct value, no scaling
          break;
        default:
          _showErrorMessage('Unknown parameter: $parameterKey');
          return;
      }


      // Validate scaled value range for U16
      if (scaledValue < 0 || scaledValue > 65535) {
        _showErrorMessage('Value out of range after scaling');
        return;
      }

      debugPrint('[ORIGIN_SETTING] Writing $parameterKey = $placeholderValue (scaled: $scaledValue) to register 0x${register.toRadixString(16)}');

      await _writeParameterWithWait(register, scaledValue);
      
    } catch (e) {
      debugPrint('[ORIGIN_SETTING] Write error: $e');
      _showErrorMessage('Failed to write parameter: $e');
    }
  }

  /// Write parameter with wait system (like protection parameter page)
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
      debugPrint('[ORIGIN_SETTING] Sending write command: $hexCommand');

      await bleService?.writeData(command);
      
      // Wait a bit for the write to complete
      await Future.delayed(const Duration(milliseconds: 200));
      
      _handleWriteSuccess(register);
      
    } catch (e) {
      debugPrint('[ORIGIN_SETTING] Write command failed: $e');
      _showErrorMessage('Write command failed: $e');
    }
  }

  void _handleWriteSuccess(int register) {
    debugPrint('[ORIGIN_SETTING] Write successful for register 0x${register.toRadixString(16)}, reading back...');
    
    // Clear the placeholder field for this register
    _clearPlaceholderForRegister(register);
    
    // Show success message
    _showSuccessMessage('Parameter written successfully');
    
    // Read back the parameter to update the display immediately
    Future.delayed(const Duration(milliseconds: 100), () {
      _readParameterWithWait(register, (data) {
        _updateDisplayForRegister(register, data);
      });
    });
  }

  void _clearPlaceholderForRegister(int register) {
    // Map register to parameter key and clear its placeholder
    String? parameterKey;
    
    switch (register) {
      case 0x10:
        parameterKey = 'nominalCapacity';
        break;
      case 0x11:
        parameterKey = 'cycleCapacity';
        break;
      case 0x03:
        parameterKey = 'fullChargeCapacity';
        break;
      case 0x2F:
        parameterKey = 'cellNumber';
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
          case 0x10: // Nominal capacity
            final capacityAh = value / 100.0;
            _nominalCapacityController.text = capacityAh.toStringAsFixed(2);
            break;
          case 0x11: // Cycle capacity
            final capacityAh = value / 100.0;
            _cycleCapacityController.text = capacityAh.toStringAsFixed(2);
            break;
          case 0x03: // Full charge capacity
            final capacityAh = value / 100.0;
            _fullChargeCapacityController.text = capacityAh.toStringAsFixed(2);
            break;
          case 0x2F: // Cell number
            _cellNumController.text = value.toString();
            break;
        }
      });
      
      debugPrint('[ORIGIN_SETTING] ✅ Updated display for register 0x${register.toRadixString(16)} with value: $value');
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

  void _showSuccessMessage(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  void dispose() {
    // Cancel timers
    _timeoutTimer?.cancel();
    
    // Dispose all controllers
    _nominalCapacityController.dispose();
    _cycleCapacityController.dispose();
    _fullChargeCapacityController.dispose();
    _cellNumController.dispose();
    
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
}

/// Reusable loading overlay widget for better performance
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
                'Loading Origin Settings...',
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