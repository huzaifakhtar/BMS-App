import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../cubits/theme_cubit.dart';
import '../../../services/bluetooth/ble_service.dart';

class CapacityVoltagePage extends StatefulWidget {
  const CapacityVoltagePage({super.key});

  @override
  State<CapacityVoltagePage> createState() => _CapacityVoltagePageState();
}

class _CapacityVoltagePageState extends State<CapacityVoltagePage> {
  final Map<String, TextEditingController> _controllers = {};
  final Map<String, TextEditingController> _placeholderControllers = {};
  final Map<String, int> _values = {};
  bool _isLoading = false;
  BleService? _bleService;
  
  // Response handling - event-driven approach
  Timer? _responseTimeout;
  
  // Missing variables for async operations
  int? _expectedRegister;
  Completer<List<int>>? _responseCompleter;
  Timer? _timeoutTimer;

  // Hex address mapping for each percentage
  final Map<String, int> _addressMap = {
    '10%': 0x46,
    '20%': 0x35,
    '30%': 0x45,
    '40%': 0x34,
    '50%': 0x44,
    '60%': 0x33,
    '70%': 0x43,
    '80%': 0x32,
    '90%': 0x42,
    '100%': 0x47,
    'Full Voltage': 0x12,
    'End of Voltage': 0x13,
  };

  final List<String> _percentageOptions = [
    '10%', '20%', '30%', '40%', '50%', '60%', '70%', '80%', '90%', '100%'
  ];

  final List<String> _voltageOptions = [
    'Full Voltage', 'End of Voltage'
  ];

  @override
  void initState() {
    super.initState();
    _initializeControllers();
    _initializeBleService();
  }

  void _initializeControllers() {
    for (String option in [..._percentageOptions, ..._voltageOptions]) {
      _controllers[option] = TextEditingController(text: '0');
      _placeholderControllers[option] = TextEditingController();
      _values[option] = 0;
    }
  }

  void _initializeBleService() {
    _bleService = Provider.of<BleService>(context, listen: false);
    
    // Set up data callback for responses
    _bleService?.addDataCallback(_handleBleData);
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_bleService?.isConnected == true) {
        _loadAllCapacityVoltages();
      } else {
        _showNotConnectedDialog();
      }
    });
  }

  @override
  void dispose() {
    _responseTimeout?.cancel();
    _timeoutTimer?.cancel();
    for (var controller in _controllers.values) {
      controller.dispose();
    }
    for (var controller in _placeholderControllers.values) {
      controller.dispose();
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
              'Capacity Voltage',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh, color: Colors.white),
                onPressed: () => _loadAllCapacityVoltages(),
              ),
            ],
          ),
          body: Stack(
            children: [
              SingleChildScrollView(
                padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 12),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 600),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildSectionHeader('Capacity Percentages', themeProvider),
                        ..._percentageOptions.map((option) => 
                          _buildParameterRow(option, _controllers[option]!, 'mV', themeProvider)
                        ),
                        _buildSectionHeader('Voltage Limits', themeProvider),
                        ..._voltageOptions.map((option) => 
                          _buildParameterRow(option, _controllers[option]!, 'mV', themeProvider)
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (_isLoading)
                const _LoadingOverlay(),
            ],
          ),
        );
      },
    );
  }

  void _handleBleData(List<int> data) {
    // Fast validation - check minimum length first
    final length = data.length;
    if (length < 7) return;
    
    // Fast header/footer validation
    if (data[0] != 0xDD || data[length - 1] != 0x77) return;
    
    // Extract response fields efficiently
    final register = data[1];
    final status = data[2];
    
    // Fast path: only process if we're waiting for a response
    final completer = _responseCompleter;
    if (completer != null && !completer.isCompleted) {
      if (register == _expectedRegister && status == 0x00) {
        completer.complete(data);
        _timeoutTimer?.cancel();
      }
    }
  }

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

  Future<bool> _sendFactoryModeCommand() async {
    try {
      final List<int> factoryModeCommand = [0xDD, 0x5A, 0x00, 0x02, 0x56, 0x78, 0xFF, 0x30, 0x77];
      await _bleService?.writeData(factoryModeCommand);
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<void> _loadAllCapacityVoltages() async {
    if (_bleService?.isConnected != true) return;

    setState(() {
      _isLoading = true;
    });

    try {
      // Send factory mode command first
      await _sendFactoryModeCommand();
      
      // Collect all data first
      final Map<String, int> allData = {};
      
      // Load percentage options
      for (String option in _percentageOptions) {
        final address = _addressMap[option];
        if (address != null) {
          final voltage = await _readCapacityVoltageValue(option, address);
          if (voltage != null) {
            allData[option] = voltage;
          }
        }
      }
      
      // Load voltage options
      for (String option in _voltageOptions) {
        final address = _addressMap[option];
        if (address != null) {
          final voltage = await _readCapacityVoltageValue(option, address);
          if (voltage != null) {
            allData[option] = voltage;
          }
        }
      }
      
      // Update all data at once
      if (mounted && allData.isNotEmpty) {
        setState(() {
          for (String option in allData.keys) {
            _controllers[option]!.text = allData[option].toString();
            _values[option] = allData[option]!;
          }
        });
      }
    } catch (e) {
      _showErrorMessage('Failed to load capacity voltages');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<int?> _readCapacityVoltageValue(String option, int address) async {
    if (_bleService?.isConnected != true) return null;

    try {
      _expectedRegister = address;
      
      // Calculate checksum: 0x10000 - (address + 0x00)
      final checksum = (0x10000 - (address + 0x00)) & 0xFFFF;
      final checksumHigh = (checksum >> 8) & 0xFF;
      final checksumLow = checksum & 0xFF;
      
      final command = [0xDD, 0xA5, address, 0x00, checksumHigh, checksumLow, 0x77];
      
      await _bleService!.writeData(command);
      
      final response = await _waitForResponse(const Duration(seconds: 2));
      
      if (response != null && response.length >= 7 && response[2] == 0x00) {
        // Seedha parse karo - high byte aur low byte se voltage
        final voltage = (response[4] << 8) + response[5];
        return voltage;
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  Future<void> _readCapacityVoltage(String option, int address) async {
    final voltage = await _readCapacityVoltageValue(option, address);
    if (voltage != null && mounted) {
      setState(() {
        _controllers[option]!.text = voltage.toString();
        _values[option] = voltage;
      });
    }
  }

  Future<void> _writeCapacityVoltage(String option, int voltage) async {
    if (_bleService?.isConnected != true) return;
    
    final address = _addressMap[option];
    if (address == null) return;

    try {
      // Send factory mode first
      await _sendFactoryModeCommand();
      
      final dataHigh = (voltage >> 8) & 0xFF;
      final dataLow = voltage & 0xFF;
      
      final checksumValue = 0x10000 - (address + 0x02 + dataHigh + dataLow);
      final checksumHigh = (checksumValue >> 8) & 0xFF;
      final checksumLow = checksumValue & 0xFF;
      
      final command = [0xDD, 0x5A, address, 0x02, dataHigh, dataLow, checksumHigh, checksumLow, 0x77];
      
      await _bleService!.writeData(command);
      
      // Read back to verify
      await _readCapacityVoltage(option, address);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$option set to ${voltage}mV'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
      
    } catch (e) {
      _showErrorMessage('Failed to write $option');
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

  Widget _buildParameterRow(String label, TextEditingController controller, String unit, ThemeProvider themeProvider) {
    final placeholderController = _placeholderControllers[label]!;
    
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Parameter label
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
              // Current value display
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
              // Input field for new value
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
              // SET button
              SizedBox(
                height: 24,
                width: 40,
                child: ElevatedButton(
                  onPressed: () {
                    final value = placeholderController.text.trim();
                    if (value.isNotEmpty) {
                      _setValue(label, value);
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
        // Divider between rows
        Divider(
          height: 1,
          thickness: 0.5,
          color: themeProvider.borderColor.withOpacity(0.3),
        ),
      ],
    );
  }

  void _setValue(String option, String value) async {
    final parsedValue = int.tryParse(value);
    if (parsedValue != null && parsedValue >= 0 && parsedValue <= 65535) {
      _placeholderControllers[option]!.clear();
      
      if (_addressMap.containsKey(option)) {
        // This is a percentage option with hex address
        await _writeCapacityVoltage(option, parsedValue);
      } else {
        // This is a voltage limit option (Full/End voltage)
        setState(() {
          _controllers[option]!.text = parsedValue.toString();
          _values[option] = parsedValue;
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$option set to ${parsedValue}mV'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } else {
      _showErrorMessage('Please enter a valid voltage value (0-65535 mV)');
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
}

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
                'Loading Capacity Voltage...',
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