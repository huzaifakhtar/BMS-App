import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import '../../../services/bluetooth/ble_service.dart';
import '../../cubits/theme_cubit.dart';

class FunctionSettingPage extends StatefulWidget {
  const FunctionSettingPage({super.key});

  @override
  State<FunctionSettingPage> createState() => _FunctionSettingPageState();
}

class _FunctionSettingPageState extends State<FunctionSettingPage> {
  BleService? bleService;
  Function(List<int>)? _originalCallback;
  
  // Response waiting
  Completer<List<int>>? _responseCompleter;
  Timer? _timeoutTimer;
  int _expectedRegister = 0;
  
  bool _isLoading = true;
  
  // Function switch states (Register 0x2D)
  bool _switchFunction = false;        // bit 0: switch
  bool _loadDetection = false;         // bit 1: load
  bool _balanceEnable = false;         // bit 2: balance_en
  bool _chgBalanceEnable = false;      // bit 3: chg_balance_en
  bool _ledEnable = false;             // bit 4: led_en
  bool _ledNum = false;                // bit 5: led_num
  bool _rtcEnable = false;             // bit 6: RTC
  bool _fccEnable = false;             // bit 7: FCC
  bool _chargingHandshake = false;     // bit 8: Charging Handshake
  bool _gpsEnable = false;             // bit 9: GPS
  bool _buzzerEnable = false;          // bit 10: Buzzer
  bool _carStart = false;              // bit 11: Car Start

  // Function settings data structure
  List<Map<String, dynamic>> get _functionSettings => [
    {'label': 'Switch Function', 'value': _switchFunction, 'bit': 0},
    {'label': 'Load Detection', 'value': _loadDetection, 'bit': 1},
    {'label': 'Balance Enable', 'value': _balanceEnable, 'bit': 2},
    {'label': 'Charge Balance Enable', 'value': _chgBalanceEnable, 'bit': 3},
    {'label': 'LED Enable', 'value': _ledEnable, 'bit': 4},
    {'label': 'LED Number', 'value': _ledNum, 'bit': 5},
    {'label': 'RTC', 'value': _rtcEnable, 'bit': 6},
    {'label': 'FCC', 'value': _fccEnable, 'bit': 7},
    {'label': 'Charging Handshake', 'value': _chargingHandshake, 'bit': 8},
    {'label': 'GPS', 'value': _gpsEnable, 'bit': 9},
    {'label': 'Buzzer', 'value': _buzzerEnable, 'bit': 10},
    {'label': 'Car Start', 'value': _carStart, 'bit': 11},
  ];

  @override
  void initState() {
    super.initState();
    debugPrint('[FUNCTION_SETTING] Screen initialized');
    _loadFunctionSettings();
  }

  Future<void> _loadFunctionSettings() async {
    try {
      bleService = context.read<BleService>();
      
      if (bleService?.isConnected != true) {
        setState(() {
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
      
      await _fetchAllFunctionSettings();
    } catch (e) {
      debugPrint('[FUNCTION_SETTING] Error: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  /// BLE data handler for function setting responses
  void _handleBleData(List<int> data) {
    if (data.length < 7) return;
    if (data[0] != 0xDD || data.last != 0x77) return;
    
    final register = data[1];
    final status = data[2];
    final dataLength = data[3];
    
    debugPrint('[FUNCTION_SETTING] 📦 Received response - Register: 0x${register.toRadixString(16)}, Status: 0x${status.toRadixString(16)}, Length: $dataLength');
    
    // Complete the response completer if waiting for this register
    if (_responseCompleter != null && !_responseCompleter!.isCompleted) {
      if (register == _expectedRegister && status == 0x00) {
        _responseCompleter!.complete(data);
        _timeoutTimer?.cancel();
        debugPrint('[FUNCTION_SETTING] ✅ Response completed for register 0x${register.toRadixString(16)}');
      }
    }
  }
  
  /// Wait for BLE response with timeout
  Future<List<int>?> _waitForResponse(Duration timeout) async {
    _responseCompleter = Completer<List<int>>();
    
    _timeoutTimer = Timer(timeout, () {
      if (!_responseCompleter!.isCompleted) {
        debugPrint('[FUNCTION_SETTING] ⏰ Response timeout for register 0x${_expectedRegister.toRadixString(16)}');
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
      debugPrint('[FUNCTION_SETTING] Reading register 0x${register.toRadixString(16)}...');
      
      // Set expected register for response matching
      _expectedRegister = register;
      
      // Send the command
      final checksum = (0x10000 - (register + 0x00)) & 0xFFFF;
      final checksumHigh = (checksum >> 8) & 0xFF;
      final checksumLow = checksum & 0xFF;
      
      final command = [0xDD, 0xA5, register, 0x00, checksumHigh, checksumLow, 0x77];
      debugPrint('[FUNCTION_SETTING] Sending command: ${command.map((b) => '0x${b.toRadixString(16).padLeft(2, '0')}').join(' ')}');
      
      await bleService?.writeData(command);
      
      // Wait for response
      final response = await _waitForResponse(const Duration(seconds: 3));
      
      if (response != null && response.length > 3 && response[2] == 0x00) {
        final dataLength = response[3];
        if (response.length >= 4 + dataLength) {
          final responseData = response.sublist(4, 4 + dataLength);
          onSuccess(responseData);
          debugPrint('[FUNCTION_SETTING] ✅ Successfully processed register 0x${register.toRadixString(16)}');
        } else {
          debugPrint('[FUNCTION_SETTING] ❌ Data length mismatch for register 0x${register.toRadixString(16)}');
        }
      } else {
        debugPrint('[FUNCTION_SETTING] ❌ Invalid response for register 0x${register.toRadixString(16)}');
      }
      
    } catch (e) {
      debugPrint('[FUNCTION_SETTING] ❌ Error reading register 0x${register.toRadixString(16)}: $e');
    }
  }

  /// Send factory mode command
  Future<bool> _sendFactoryModeCommand() async {
    try {
      debugPrint('[FUNCTION_SETTING] 🔑 Sending factory mode command...');
      
      // Factory mode command: DD 5A 00 02 56 78 FF 30 77
      final List<int> factoryModeCommand = [0xDD, 0x5A, 0x00, 0x02, 0x56, 0x78, 0xFF, 0x30, 0x77];
      final String hexCommand = factoryModeCommand.map((b) => '0x${b.toRadixString(16).padLeft(2, '0').toUpperCase()}').join(' ');
      
      debugPrint('[FUNCTION_SETTING] Factory Mode Command: $hexCommand');
      
      await bleService?.writeData(factoryModeCommand);
      
      debugPrint('[FUNCTION_SETTING] ✅ Factory mode command sent successfully');
      return true;
    } catch (e) {
      debugPrint('[FUNCTION_SETTING] ❌ Factory mode command failed: $e');
      return false;
    }
  }

  /// Fetch all function settings
  Future<void> _fetchAllFunctionSettings() async {
    try {
      debugPrint('[FUNCTION_SETTING] 🚀 Starting function settings fetch...');
      
      // Step 1: Send factory mode command FIRST
      debugPrint('[FUNCTION_SETTING] 🔑 Step 1: Factory Mode Command');
      bool factoryModeSuccess = await _sendFactoryModeCommand();
      if (!factoryModeSuccess) {
        debugPrint('[FUNCTION_SETTING] ⚠️ Factory mode failed, continuing anyway...');
      }
      
      // Wait a bit for factory mode to take effect
      await Future.delayed(const Duration(milliseconds: 500));
      
      // Step 2: Fetch function settings register 0x2D
      debugPrint('[FUNCTION_SETTING] 📊 Step 2: Fetching Function Settings');
      await _fetchFunctionBits();
      
      // Step 3: All data loaded, update UI
      setState(() {
        _isLoading = false;
      });
      
      debugPrint('[FUNCTION_SETTING] 🎉 All function settings loaded!');
      
    } catch (e) {
      debugPrint('[FUNCTION_SETTING] ❌ Error fetching function settings: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  /// Fetch function bits from register 0x2D
  Future<void> _fetchFunctionBits() async {
    await _readParameterWithWait(0x2D, (data) {
      if (data.length >= 2) {
        // Parse function bits from 2-byte value
        final functionBits = (data[0] << 8) | data[1];
        
        setState(() {
          _switchFunction = (functionBits & 0x0001) != 0;      // bit 0: switch
          _loadDetection = (functionBits & 0x0002) != 0;       // bit 1: load
          _balanceEnable = (functionBits & 0x0004) != 0;       // bit 2: balance_en
          _chgBalanceEnable = (functionBits & 0x0008) != 0;    // bit 3: chg_balance_en
          _ledEnable = (functionBits & 0x0010) != 0;           // bit 4: led_en
          _ledNum = (functionBits & 0x0020) != 0;              // bit 5: led_num
          _rtcEnable = (functionBits & 0x0040) != 0;           // bit 6: RTC
          _fccEnable = (functionBits & 0x0080) != 0;           // bit 7: FCC
          _chargingHandshake = (functionBits & 0x0100) != 0;   // bit 8: Charging Handshake
          _gpsEnable = (functionBits & 0x0200) != 0;           // bit 9: GPS
          _buzzerEnable = (functionBits & 0x0400) != 0;        // bit 10: Buzzer
          _carStart = (functionBits & 0x0800) != 0;            // bit 11: Car Start
        });
        
        debugPrint('[FUNCTION_SETTING] ✅ Function bits: 0x${functionBits.toRadixString(16).padLeft(4, '0')}');
        debugPrint('[FUNCTION_SETTING] Switch: $_switchFunction, Load: $_loadDetection, Balance: $_balanceEnable, CHG Balance: $_chgBalanceEnable');
        debugPrint('[FUNCTION_SETTING] LED: $_ledEnable, LED Num: $_ledNum, RTC: $_rtcEnable, FCC: $_fccEnable');
        debugPrint('[FUNCTION_SETTING] Handshake: $_chargingHandshake, GPS: $_gpsEnable, Buzzer: $_buzzerEnable, Car Start: $_carStart');
      }
    });
  }

  /// Write function setting bit using current UI state
  Future<void> _writeFunctionSetting(String settingName, bool value, int bitPosition) async {
    try {
      if (bleService?.isConnected != true) {
        _showErrorMessage('Device not connected');
        return;
      }

      debugPrint('[FUNCTION_SETTING] Writing $settingName = $value (bit $bitPosition)');

      // Get current function bits from UI state
      int currentBits = _getCurrentFunctionBits();
      int bitValue = 1 << bitPosition;
      int newBits;
      
      if (value) {
        // Add bit (turn ON)
        newBits = currentBits | bitValue;
        debugPrint('[FUNCTION_SETTING] Adding bit $bitPosition: 0x${currentBits.toRadixString(16)} + 0x${bitValue.toRadixString(16)} = 0x${newBits.toRadixString(16)}');
      } else {
        // Subtract bit (turn OFF)
        newBits = currentBits & ~bitValue;
        debugPrint('[FUNCTION_SETTING] Subtracting bit $bitPosition: 0x${currentBits.toRadixString(16)} - 0x${bitValue.toRadixString(16)} = 0x${newBits.toRadixString(16)}');
      }
      
      // Write new function bits back
      await _writeFunctionBits(newBits);
      
    } catch (e) {
      debugPrint('[FUNCTION_SETTING] Write error: $e');
      _showErrorMessage('Failed to write setting: $e');
    }
  }

  /// Get current function bits from UI state
  int _getCurrentFunctionBits() {
    int bits = 0;
    
    if (_switchFunction) bits |= 0x0001;      // bit 0
    if (_loadDetection) bits |= 0x0002;       // bit 1
    if (_balanceEnable) bits |= 0x0004;       // bit 2
    if (_chgBalanceEnable) bits |= 0x0008;    // bit 3
    if (_ledEnable) bits |= 0x0010;           // bit 4
    if (_ledNum) bits |= 0x0020;              // bit 5
    if (_rtcEnable) bits |= 0x0040;           // bit 6
    if (_fccEnable) bits |= 0x0080;           // bit 7
    if (_chargingHandshake) bits |= 0x0100;   // bit 8
    if (_gpsEnable) bits |= 0x0200;           // bit 9
    if (_buzzerEnable) bits |= 0x0400;        // bit 10
    if (_carStart) bits |= 0x0800;            // bit 11
    
    debugPrint('[FUNCTION_SETTING] Current UI state bits: 0x${bits.toRadixString(16).padLeft(4, '0')}');
    return bits;
  }

  /// Write function bits with BLE command
  Future<void> _writeFunctionBits(int functionBits) async {
    try {
      // Step 1: Send factory mode command before writing
      debugPrint('[FUNCTION_SETTING] 🔑 Sending factory mode command before write...');
      bool factoryModeSuccess = await _sendFactoryModeCommand();
      if (!factoryModeSuccess) {
        debugPrint('[FUNCTION_SETTING] ⚠️ Factory mode failed before write, continuing anyway...');
      }
      
      // Minimal wait for factory mode
      await Future.delayed(const Duration(milliseconds: 50));
      
      // Step 2: Build BLE write command: DD 5A [REG] 02 [DATA_HIGH] [DATA_LOW] [CHECKSUM_HIGH] [CHECKSUM_LOW] 77
      const register = 0x2D;
      final dataHigh = (functionBits >> 8) & 0xFF;
      final dataLow = functionBits & 0xFF;
      
      // Calculate checksum: 0x10000 - (register + length + dataHigh + dataLow)
      final checksumValue = 0x10000 - (register + 0x02 + dataHigh + dataLow);
      final checksumHigh = (checksumValue >> 8) & 0xFF;
      final checksumLow = checksumValue & 0xFF;
      
      final command = [0xDD, 0x5A, register, 0x02, dataHigh, dataLow, checksumHigh, checksumLow, 0x77];
      
      final hexCommand = command.map((b) => '0x${b.toRadixString(16).padLeft(2, '0').toUpperCase()}').join(' ');
      debugPrint('[FUNCTION_SETTING] Sending write command: $hexCommand');

      await bleService?.writeData(command);
      
      // Minimal wait for write completion
      await Future.delayed(const Duration(milliseconds: 20));
      
      // Quick re-read to verify
      await Future.delayed(const Duration(milliseconds: 30));
      await _fetchFunctionBits();
      
    } catch (e) {
      debugPrint('[FUNCTION_SETTING] Write command failed: $e');
      _showErrorMessage('Write command failed: $e');
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
        if (mounted && Navigator.canPop(context)) {
          Navigator.pop(context);
        }
      });
    });
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
              'Function Setting',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh, color: Colors.white),
                onPressed: () => _fetchAllFunctionSettings(),
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
                        _buildSectionHeader('Function Settings'),
                        Column(
                          children: <Widget>[
                            for (int i = 0; i < _functionSettings.length; i++)
                              ListTile(
                                title: Text(
                                  _functionSettings[i]['label'],
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: Colors.black,
                                    fontWeight: FontWeight.normal,
                                  ),
                                ),
                                trailing: _CustomRealSwitch(
                                  value: _functionSettings[i]['value'],
                                  onChanged: (bool value) {
                                    _writeFunctionSetting(
                                      _functionSettings[i]['label'],
                                      value,
                                      _functionSettings[i]['bit'],
                                    );
                                  },
                                  activeColor: themeProvider.primaryColor,
                                ),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
                              ),
                          ],
                        ),
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

  @override
  void dispose() {
    // Cancel timers
    _timeoutTimer?.cancel();
    
    // Restore original callback when leaving this page
    if (_originalCallback != null) {
      bleService?.addDataCallback(_originalCallback!);
    }
    super.dispose();
  }
}

/// Custom real button style switch with enhanced shadow
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
                'Loading Function Settings...',
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