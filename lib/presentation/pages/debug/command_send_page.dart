import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../services/bluetooth/bms_service.dart';
import '../../../services/bluetooth/ble_service.dart';
import '../../../data/models/bms_registers.dart';
import '../../cubits/theme_cubit.dart';

class CommandSendPage extends StatefulWidget {
  const CommandSendPage({super.key});

  @override
  State<CommandSendPage> createState() => _CommandSendPageState();
}

class _CommandSendPageState extends State<CommandSendPage> {
  final TextEditingController _customCommandController = TextEditingController();
  final TextEditingController _registerController = TextEditingController();
  final TextEditingController _dataController = TextEditingController();
  final ScrollController _responseScrollController = ScrollController();
  
  final List<String> _responseHistory = [];
  bool _isAutoScroll = true;
  String _selectedCommandType = 'read';
  String _selectedFormat = 'hex';

  @override
  void initState() {
    super.initState();
    // Set up response callback to capture BMS responses
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final bmsService = Provider.of<BmsService>(context, listen: false);
      bmsService.setSerialResponseCallback(_onBmsResponse);
    });
  }

  void _onBmsResponse(String response) {
    setState(() {
      _responseHistory.add(response);
      if (_responseHistory.length > 100) {
        _responseHistory.removeAt(0);
      }
    });
    
    if (_isAutoScroll && _responseScrollController.hasClients) {
      Future.delayed(const Duration(milliseconds: 100), () {
        _responseScrollController.animateTo(
          _responseScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      });
    }
  }

  void _sendCustomCommand() async {
    if (_customCommandController.text.trim().isEmpty) {
      _showErrorDialog('Please enter a command');
      return;
    }

    try {
      List<int> command = _parseCommand(_customCommandController.text.trim());
      if (command.isEmpty) {
        _showErrorDialog('Invalid command format');
        return;
      }

      final bleService = context.read<BleService>();
      if (!bleService.isConnected) {
        _showErrorDialog('Device not connected. Please connect to a BMS device first.');
        return;
      }

      String timestamp = DateTime.now().toString().substring(11, 19);
      String hexCommand = command.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join(' ');
      
      setState(() {
        _responseHistory.add('📤 [$timestamp] TX: $hexCommand (${command.length} bytes)');
      });

      await bleService.writeData(command);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Command sent successfully')),
        );
      }

    } catch (e) {
      _showErrorDialog('Error sending command: $e');
    }
  }

  void _sendRegisterCommand() async {
    if (_registerController.text.trim().isEmpty) {
      _showErrorDialog('Please enter a register address');
      return;
    }

    try {
      int registerAddress = int.parse(_registerController.text.trim(), radix: 16);
      final bmsService = Provider.of<BmsService>(context, listen: false);
      final bleService = context.read<BleService>();
      
      if (!bleService.isConnected) {
        _showErrorDialog('Device not connected. Please connect to a BMS device first.');
        return;
      }
      
      List<int> command;
      String timestamp = DateTime.now().toString().substring(11, 19);
      
      if (_selectedCommandType == 'read') {
        // Create a temporary register for the command
        JbdRegister tempRegister = JbdRegister.values.firstWhere(
          (reg) => reg.address == registerAddress,
          orElse: () => JbdRegister.basicInfo, // fallback
        );
        
        command = bmsService.createReadCommand(tempRegister);
        String hexCommand = command.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join(' ');
        
        setState(() {
          _responseHistory.add('📤 [$timestamp] READ 0x${registerAddress.toRadixString(16).padLeft(2, '0')}: $hexCommand');
        });
        
      } else if (_selectedCommandType == 'write') {
        if (_dataController.text.trim().isEmpty) {
          _showErrorDialog('Please enter data for write command');
          return;
        }
        
        List<int> data = _parseCommand(_dataController.text.trim());
        JbdRegister tempRegister = JbdRegister.values.firstWhere(
          (reg) => reg.address == registerAddress,
          orElse: () => JbdRegister.basicInfo,
        );
        
        command = bmsService.createWriteCommand(tempRegister, data);
        String hexCommand = command.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join(' ');
        
        setState(() {
          _responseHistory.add('📤 [$timestamp] WRITE 0x${registerAddress.toRadixString(16).padLeft(2, '0')}: $hexCommand');
        });
      } else {
        _showErrorDialog('Invalid command type');
        return;
      }

      await bleService.writeData(command);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Command sent successfully')),
        );
      }

    } catch (e) {
      _showErrorDialog('Error creating/sending command: $e');
    }
  }

  List<int> _parseCommand(String input) {
    List<int> bytes = [];
    
    if (_selectedFormat == 'hex') {
      // Parse hex format: "DD A5 03 00 FF FD 77" or "DDA50300FFFD77"
      String cleaned = input.replaceAll(RegExp(r'[^0-9A-Fa-f]'), '');
      if (cleaned.length % 2 != 0) throw Exception('Invalid hex length');
      
      for (int i = 0; i < cleaned.length; i += 2) {
        bytes.add(int.parse(cleaned.substring(i, i + 2), radix: 16));
      }
    } else {
      // Parse decimal format: "221 165 3 0 255 253 119"
      List<String> parts = input.split(RegExp(r'\s+'));
      for (String part in parts) {
        if (part.trim().isNotEmpty) {
          int value = int.parse(part.trim());
          if (value < 0 || value > 255) throw Exception('Byte value out of range: $value');
          bytes.add(value);
        }
      }
    }
    
    return bytes;
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Error'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _clearResponses() {
    setState(() {
      _responseHistory.clear();
    });
  }

  void _copyResponses() {
    Clipboard.setData(ClipboardData(text: _responseHistory.join('\n')));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Response history copied to clipboard')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, child) {
        return Scaffold(
          backgroundColor: themeProvider.backgroundColor,
          appBar: AppBar(
            title: const Text('BMS Command Interface'),
            backgroundColor: themeProvider.cardColor,
            foregroundColor: themeProvider.textColor,
            elevation: 0,
            actions: [
              IconButton(
                onPressed: _clearResponses,
                icon: const Icon(Icons.clear_all),
                tooltip: 'Clear Responses',
              ),
              IconButton(
                onPressed: _copyResponses,
                icon: const Icon(Icons.copy),
                tooltip: 'Copy Responses',
              ),
            ],
          ),
          body: Column(
            children: [
              // Command Input Section
              Container(
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: themeProvider.cardColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: themeProvider.borderColor),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Send Command',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: themeProvider.textColor,
                      ),
                    ),
                    const SizedBox(height: 16),
                    
                    // Format selector
                    Row(
                      children: [
                        Text(
                          'Format: ',
                          style: TextStyle(color: themeProvider.textColor),
                        ),
                        DropdownButton<String>(
                          value: _selectedFormat,
                          items: const [
                            DropdownMenuItem(value: 'hex', child: Text('Hex')),
                            DropdownMenuItem(value: 'decimal', child: Text('Decimal')),
                          ],
                          onChanged: (value) {
                            setState(() {
                              _selectedFormat = value!;
                            });
                          },
                        ),
                      ],
                    ),
                    
                    const SizedBox(height: 12),
                    
                    // Custom command input
                    TextField(
                      controller: _customCommandController,
                      decoration: InputDecoration(
                        labelText: _selectedFormat == 'hex' 
                          ? 'Custom Command (e.g., DD A5 03 00 FF FD 77)'
                          : 'Custom Command (e.g., 221 165 3 0 255 253 119)',
                        hintText: _selectedFormat == 'hex'
                          ? 'Enter hex bytes separated by spaces'
                          : 'Enter decimal values separated by spaces',
                        border: const OutlineInputBorder(),
                      ),
                      style: TextStyle(
                        fontFamily: 'monospace',
                        color: themeProvider.textColor,
                      ),
                    ),
                    
                    const SizedBox(height: 12),
                    
                    ElevatedButton.icon(
                      onPressed: _sendCustomCommand,
                      icon: const Icon(Icons.send),
                      label: const Text('Send Custom Command'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: themeProvider.primaryColor,
                        foregroundColor: Colors.white,
                      ),
                    ),
                    
                    const Divider(height: 32),
                    
                    // Register-based command builder
                    Text(
                      'Register Command Builder',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: themeProvider.textColor,
                      ),
                    ),
                    
                    const SizedBox(height: 12),
                    
                    Row(
                      children: [
                        Text(
                          'Type: ',
                          style: TextStyle(color: themeProvider.textColor),
                        ),
                        DropdownButton<String>(
                          value: _selectedCommandType,
                          items: const [
                            DropdownMenuItem(value: 'read', child: Text('Read')),
                            DropdownMenuItem(value: 'write', child: Text('Write')),
                          ],
                          onChanged: (value) {
                            setState(() {
                              _selectedCommandType = value!;
                            });
                          },
                        ),
                      ],
                    ),
                    
                    const SizedBox(height: 12),
                    
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _registerController,
                            decoration: const InputDecoration(
                              labelText: 'Register (hex)',
                              hintText: '03',
                              border: OutlineInputBorder(),
                            ),
                            style: TextStyle(
                              fontFamily: 'monospace',
                              color: themeProvider.textColor,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        if (_selectedCommandType == 'write')
                          Expanded(
                            child: TextField(
                              controller: _dataController,
                              decoration: InputDecoration(
                                labelText: 'Data ($_selectedFormat)',
                                hintText: _selectedFormat == 'hex' ? 'A0 B1' : '160 177',
                                border: const OutlineInputBorder(),
                              ),
                              style: TextStyle(
                                fontFamily: 'monospace',
                                color: themeProvider.textColor,
                              ),
                            ),
                          ),
                      ],
                    ),
                    
                    const SizedBox(height: 12),
                    
                    ElevatedButton.icon(
                      onPressed: _sendRegisterCommand,
                      icon: const Icon(Icons.settings),
                      label: Text('Send ${_selectedCommandType.toUpperCase()} Command'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: themeProvider.accentColor,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              
              // Response Display Section
              Expanded(
                child: Container(
                  margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: themeProvider.cardColor,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: themeProvider.borderColor),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            'BMS Responses',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: themeProvider.textColor,
                            ),
                          ),
                          const Spacer(),
                          Switch(
                            value: _isAutoScroll,
                            onChanged: (value) {
                              setState(() {
                                _isAutoScroll = value;
                              });
                            },
                            activeColor: themeProvider.primaryColor,
                          ),
                          Text(
                            'Auto-scroll',
                            style: TextStyle(color: themeProvider.textColor),
                          ),
                        ],
                      ),
                      
                      const SizedBox(height: 12),
                      
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: themeProvider.backgroundColor,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: themeProvider.borderColor),
                          ),
                          child: ListView.builder(
                            controller: _responseScrollController,
                            itemCount: _responseHistory.length,
                            itemBuilder: (context, index) {
                              String response = _responseHistory[index];
                              Color textColor = themeProvider.secondaryTextColor;
                              
                              if (response.contains('📤')) {
                                textColor = themeProvider.primaryColor;
                              } else if (response.contains('📥')) {
                                textColor = Colors.green;
                              } else if (response.contains('❌')) {
                                textColor = Colors.red;
                              } else if (response.contains('✅')) {
                                textColor = Colors.green;
                              }
                              
                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 2),
                                child: Text(
                                  response,
                                  style: TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 12,
                                    color: textColor,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _customCommandController.dispose();
    _registerController.dispose();
    _dataController.dispose();
    _responseScrollController.dispose();
    super.dispose();
  }
}