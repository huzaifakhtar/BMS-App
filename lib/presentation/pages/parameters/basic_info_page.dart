import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import '../../../services/bluetooth/ble_service.dart';
import '../../../services/bluetooth/bms_service.dart';
import '../../cubits/theme_cubit.dart';
import '../../../core/cache/basic_info_cache.dart';
import '../../../core/constants/app_constants.dart';

class BasicInfoPage extends StatefulWidget {
  const BasicInfoPage({super.key});

  @override
  State<BasicInfoPage> createState() => _BasicInfoPageState();
}

class _BasicInfoPageState extends State<BasicInfoPage> {
  static const int _paramBarcode = 88;
  static const int _paramManufacturer = 56;
  static const int _paramBmsModel = 176;
  static const int _paramBatteryModel = 72;
  static const int _paramProductionDate = 5;
  
  BleService? bleService;
  Function(List<int>)? _originalCallback;
  
  String bluetoothName = '';
  String barCode = '';
  String manufacturer = '';
  String version = '';
  String productionDate = '';
  String bmsModel = '';
  String batteryModel = '';
  
  bool _isLoading = true;
  
  Completer<List<int>>? _responseCompleter;
  Timer? _timeoutTimer;
  int _expectedRegister = 0;

  @override
  void initState() {
    super.initState();
    _loadDeviceInfo();
  }

  Future<void> _loadDeviceInfo() async {
    try {
      bleService = context.read<BleService>();
      
      if (bleService?.isConnected != true) {
        setState(() {
          _isLoading = false;
          bluetoothName = 'Not Connected';
          barCode = 'Not Connected';
          manufacturer = 'Not Connected';
          version = 'Not Connected';
          productionDate = 'Not Connected';
        });
        _showNotConnectedDialog();
        return;
      }

      // Set device name immediately
      final connectedDevice = bleService?.connectedDevice;
      bluetoothName = connectedDevice != null && connectedDevice.platformName.isNotEmpty 
        ? connectedDevice.platformName 
        : 'BMS Device';

      // Store original callback - dashboard uses BLE->BMS routing
      _originalCallback = bleService?.dataCallback;
      final bmsService = context.read<BmsService>();
      
      // Set up temporary BMS data callback for basic info page
      // This will temporarily override dashboard's callback, but we'll restore it
      bmsService.addDataCallback(_handleBleData);
      
      // Ensure BLE data flows to BMS service (same as dashboard)
      bleService?.addDataCallback((data) {
        bmsService.handleResponse(data);
      });
      
      // Start data fetching sequence
      await _fetchAllData();
      
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
    }
  }


  /// Optimized BLE data handler for consistent performance - now receives complete assembled packets
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
      }
    }
  }
  
  /// Wait for BLE response with timeout
  Future<List<int>?> _waitForResponse(Duration timeout) async {
    _responseCompleter = Completer<List<int>>();
    
    _timeoutTimer = Timer(timeout, () {
      if (!_responseCompleter!.isCompleted) {
        _responseCompleter!.complete([]);
      }
    });
    
    final response = await _responseCompleter!.future;
    _timeoutTimer?.cancel();
    return response.isNotEmpty ? response : null;
  }
  
  /// Read parameter mode with specific parameter number
  Future<void> _readParameterMode(int paramNumber, int expectedBytes, Function(List<int>) onSuccess) async {
    try {
      // Set expected register for response matching
      _expectedRegister = 0xFA;
      
      // Generate parameter reading command
      // Format: DD A5 FA 03 [PARAM_H] [PARAM_L] [BYTES] [CHECKSUM_H] [CHECKSUM_L] 77
      final paramHigh = (paramNumber >> 8) & 0xFF;
      final paramLow = paramNumber & 0xFF;
      
      final sum = 0xFA + 0x03 + paramHigh + paramLow + expectedBytes;
      final checksum = (0x10000 - sum) & 0xFFFF;
      final checksumHigh = (checksum >> 8) & 0xFF;
      final checksumLow = checksum & 0xFF;
      
      final command = [0xDD, 0xA5, 0xFA, 0x03, paramHigh, paramLow, expectedBytes, checksumHigh, checksumLow, 0x77];
      await bleService?.writeData(command);
      
      // Wait for response  
      final response = await _waitForResponse(AppConstants.responseTimeout);
      
      
      if (response != null && response[2] == 0x00) {
        final dataLength = response[3];
        if (response.length >= 4 + dataLength) {
          final responseData = response.sublist(4, 4 + dataLength);
          onSuccess(responseData);
        } else {
          _setParameterError(0xFA);
        }
      } 
      else if (response != null && response[2] == 0x80) {
        _setParameterError(0xFA);
      }
      else {
        _setParameterError(0xFA);
      }
      
    } catch (e) {
      _setParameterError(0xFA);
    }
  }

  /// Read parameter with wait system
  Future<void> _readParameterWithWait(int register, Function(List<int>) onSuccess) async {
    try {
      
      // Set expected register for response matching
      _expectedRegister = register;
      
      // For parameter reading mode (0xFA), use specific command structure
      List<int> command;
      if (register == 0xFA) {
        // This should not be called directly - use _readParameterMode instead
        throw Exception('Use _readParameterMode for 0xFA register');
      } else {
        // Standard register reading command
        final checksum = (0x10000 - (register + 0x00)) & 0xFFFF;
        final checksumHigh = (checksum >> 8) & 0xFF;
        final checksumLow = checksum & 0xFF;
        command = [0xDD, 0xA5, register, 0x00, checksumHigh, checksumLow, 0x77];
      }
      
      await bleService?.writeData(command);
      
      // Wait for response
      final response = await _waitForResponse(AppConstants.responseTimeout);
      
      if (response != null && response.length > 3 && response[2] == 0x00) {
        final dataLength = response[3];
        if (response.length >= 4 + dataLength) {
          final responseData = response.sublist(4, 4 + dataLength);
          onSuccess(responseData);
        } else {
          _setParameterError(register);
        }
      } else {
        _setParameterError(register);
      }
      
    } catch (e) {
      _setParameterError(register);
    }
  }

  /// Set error state for specific parameter registers
  void _setParameterError(int register) {
    switch (register) {
      case 0xA2: barCode = 'Not Available'; break;
      case 0xA0: manufacturer = 'Not Available'; break;
      case 0x03: version = 'Not Available'; break;
      case 0x15: productionDate = 'Not Available'; break;
    }
  }

  /// Fetch all data with response-based sequencing (no time delays)
  Future<void> _fetchAllData() async {
    try {
      setState(() {
        _isLoading = true;
      });
      // Step 1: Send factory mode command FIRST - wait for response
      await _sendFactoryModeCommand();
      // Get version from cache (no parameter mode available)
      await _fetchVersionFromCache(); // Get version from cache (wait for dashboard)
      
      await _fetchBmsModel();
      setState(() { _isLoading = false; });
      
      await _fetchProductionDateParam();
      await _fetchManufacturerParam();
      await _fetchBarcodeParam();
      await _fetchBatteryModel();
      
      setState(() {});
      
    } catch (e) {
      setState(() { _isLoading = false; });
    }
  }

  /// Send factory mode command with improved reliability
  Future<bool> _sendFactoryModeCommand() async {
    try {
      final List<int> factoryModeCommand = [0xDD, 0x5A, 0x00, 0x02, 0x56, 0x78, 0xFF, 0x30, 0x77];
      await bleService?.writeData(factoryModeCommand);
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<void> _fetchBarcodeParam() async {
    await _readParameterMode(_paramBarcode, 32, (data) {
      barCode = _extractStringFromParameterData(data, 'Barcode');
    });
  }

  Future<void> _fetchManufacturerParam() async {
    await _readParameterMode(_paramManufacturer, 32, (data) {
      manufacturer = _extractStringFromParameterData(data, 'Manufacturer');
    });
  }

 Future<void> _fetchVersionFromCache() async {
    if (BasicInfoCache.isLoaded && BasicInfoCache.version != 'Loading...') {
      version = BasicInfoCache.version;
      return;
    }
    
    for (int i = 0; i < 5; i++) {
      await Future.delayed(const Duration(milliseconds: 100));
      if (BasicInfoCache.isLoaded && BasicInfoCache.version != 'Loading...') {
        version = BasicInfoCache.version;
        return;
      }
    }
    
    try {
      await _readParameterWithWait(0x03, (data) {
        if (data.length > 18) {
          final versionByte = data[18];
          final major = (versionByte >> 4) & 0x0F;
          final minor = versionByte & 0x0F;
          version = '$major.$minor';
        } else {
          version = 'Not Available';
        }
      });
    } catch (e) {
      version = 'Not Available';
    }
  }



  Future<void> _fetchBmsModel() async {
    await _readParameterMode(_paramBmsModel, 8, (data) {
      bmsModel = _extractStringFromParameterData(data, 'BMS Model');
    });
  }

  Future<void> _fetchBatteryModel() async {
    await _readParameterMode(_paramBatteryModel, 32, (data) {
      batteryModel = _extractStringFromParameterData(data, 'Battery Model');
    });
  }

  Future<void> _fetchProductionDateParam() async {
    await _readParameterMode(_paramProductionDate, 2, (data) {
    final dateByteHigh = data[3];
    final dateByteLow = data[4];
    final dateValue = (dateByteHigh << 8) | dateByteLow;
    final day = dateValue & 0x1F;
    final month = (dateValue >> 5) & 0x0F;
    final year = 2000 + (dateValue >> 9);
    productionDate = '$year-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';  
    });
  }

  String _extractStringFromParameterData(List<int> data, String type) {
    if (data.length >= 4) {
      final stringLength = data[3];
      if (data.length >= 4 + stringLength && stringLength > 0 && stringLength <= 50) {
        final stringBytes = data.sublist(4, 4 + stringLength);
        final asciiData = stringBytes.where((b) => b >= 32 && b <= 126).map((b) => String.fromCharCode(b)).join('').trim();
        if (asciiData.isNotEmpty) return asciiData;
      }
    }
    
    if (data.length > 4) {
      final allPrintable = data.sublist(4).where((b) => b >= 32 && b <= 126).map((b) => String.fromCharCode(b)).join('').trim();
      if (allPrintable.isNotEmpty && allPrintable.length > 2) return allPrintable;
    }
    
    return 'Not Available';
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
  void dispose() {
    // Cancel timers
    _timeoutTimer?.cancel();
    
    // Restore original callbacks when leaving this page
    if (_originalCallback != null) {
      bleService?.addDataCallback(_originalCallback!);
    }
    
    // Clear our temporary BMS data callback to restore dashboard functionality
    try {
      final bmsService = context.read<BmsService>();
      bmsService.setDataCallback(null);
    } catch (e) {
      // Ignore error
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
              'Basic Information',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh, color: Colors.white),
                onPressed: () => _fetchAllData(),
              ),
            ],
          ),
          body: Stack(
            children: [
              // Main content (always present but may be hidden by loader)
              SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 600),
                    child: Column(
                      children: [
                        _buildEditableInfoRow('Bluetooth name', bluetoothName, true),
                        _buildInfoRow('Bar code', barCode),
                                        _buildInfoRow('Manufacturer', manufacturer),
                        _buildInfoRow('Version', version),
                        _buildInfoRow('BMS Model', bmsModel),
                        _buildInfoRow('Battery Model', batteryModel),
                                        _buildInfoRow('Production date', productionDate),
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

  Widget _buildInfoRow(String label, String value) {
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, _) {
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 2,
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 14,
                        color: themeProvider.textColor,
                        fontWeight: FontWeight.normal,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: Text(
                      value == 'Loading...' ? '--' : value,
                      style: TextStyle(
                        fontSize: 14,
                        color: themeProvider.primaryColor,
                        fontWeight: FontWeight.normal,
                      ),
                      textAlign: TextAlign.right,
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

  Widget _buildEditableInfoRow(String label, String value, bool isEditable) {
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
                    flex: 3,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label,
                          style: TextStyle(
                            fontSize: 14,
                            color: themeProvider.textColor,
                            fontWeight: FontWeight.normal,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          value,
                          style: TextStyle(
                            fontSize: 14,
                            color: themeProvider.primaryColor,
                            fontWeight: FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Container(
                      height: 36,
                      margin: const EdgeInsets.only(left: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        border: Border.all(color: themeProvider.borderColor),
                        borderRadius: BorderRadius.circular(8),
                        color: Colors.white,
                      ),
                      child: const Center(
                        child: Text(
                          '',
                          style: TextStyle(fontSize: 14),
                        ),
                      ),
                    ),
                  ),
                  if (isEditable) ...[
                    const SizedBox(width: 8),
                    SizedBox(
                      height: 36,
                      width: 45,
                      child: ElevatedButton(
                        onPressed: () {
                          _showEditDialog(label, value);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: themeProvider.primaryColor,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: const Text(
                          'SET',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
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

  void _showEditDialog(String label, String currentValue) {
    final TextEditingController controller = TextEditingController(text: currentValue);
    
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Consumer<ThemeProvider>(
          builder: (context, themeProvider, _) {
            return AlertDialog(
              title: Text('Edit $label'),
              content: TextField(
                controller: controller,
                decoration: InputDecoration(
                  hintText: 'Enter new $label',
                  border: const OutlineInputBorder(),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      bluetoothName = controller.text;
                    });
                    Navigator.pop(context);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: themeProvider.primaryColor,
                  ),
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
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
                'Loading Basic Information...',
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