import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import '../../../services/bluetooth/ble_service.dart';
import '../../cubits/theme_cubit.dart';

class CurrentSettingsPage extends StatefulWidget {
  const CurrentSettingsPage({super.key});

  @override
  State<CurrentSettingsPage> createState() => _CurrentSettingsPageState();
}

class _CurrentSettingsPageState extends State<CurrentSettingsPage> {
  BleService? bleService;
  Function(List<int>)? _originalCallback;
  
  String chargeOvercurrentProtection = '0';
  String chargeOvercurrentDelay = '0';
  String dischargeOvercurrentProtection = '0';
  String dischargeOvercurrentDelay = '0';
  String shortCircuitProtection = '0';
  String shortCircuitDelay = '0';
  String secondaryOvercurrentProtection = '0';
  String secondaryOvercurrentDelay = '0';
  
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    debugPrint('[CURRENT_SETTINGS] Screen initialized');
    _loadCurrentSettings();
  }

  Future<void> _loadCurrentSettings() async {
    try {
      bleService = context.read<BleService>();
      
      if (bleService?.isConnected != true) {
        setState(() {
          chargeOvercurrentProtection = '0';
          chargeOvercurrentDelay = '0';
          dischargeOvercurrentProtection = '0';
          dischargeOvercurrentDelay = '0';
          shortCircuitProtection = '0';
          shortCircuitDelay = '0';
          secondaryOvercurrentProtection = '0';
          secondaryOvercurrentDelay = '0';
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
      
      await _fetchCurrentSettings();
    } catch (e) {
      debugPrint('[CURRENT_SETTINGS] Error: $e');
    }
  }

  void _handleBleData(List<int> data) {
    if (data.length < 3) return;
    
    if (data[0] == 0xDD && data[1] == 0x05) {
      _parseCurrentSettings(data);
    }
  }

  void _parseCurrentSettings(List<int> data) {
    if (data.length < 20) return;
    
    if (mounted) {
      setState(() {
        // Parse current protection settings
        final chargeOCP = data.length > 5 ? ((data[4] << 8) | data[5]) : 0;
        chargeOvercurrentProtection = '${chargeOCP / 100}';
        
        final chargeDelay = data.length > 7 ? ((data[6] << 8) | data[7]) : 0;
        chargeOvercurrentDelay = '$chargeDelay';
        
        final dischargeOCP = data.length > 9 ? ((data[8] << 8) | data[9]) : 0;
        dischargeOvercurrentProtection = '${dischargeOCP / 100}';
        
        final dischargeDelay = data.length > 11 ? ((data[10] << 8) | data[11]) : 0;
        dischargeOvercurrentDelay = '$dischargeDelay';
        
        final shortCircuit = data.length > 13 ? ((data[12] << 8) | data[13]) : 0;
        shortCircuitProtection = '${shortCircuit / 100}';
        
        final shortDelay = data.length > 15 ? ((data[14] << 8) | data[15]) : 0;
        shortCircuitDelay = '$shortDelay';
        
        final secondaryOCP = data.length > 17 ? ((data[16] << 8) | data[17]) : 0;
        secondaryOvercurrentProtection = '${secondaryOCP / 100}';
        
        final secondaryDelay = data.length > 19 ? ((data[18] << 8) | data[19]) : 0;
        secondaryOvercurrentDelay = '$secondaryDelay';
        
        _isLoading = false;
      });
    }
  }

  Future<void> _fetchCurrentSettings() async {
    try {
      await bleService?.writeData([0xDD, 0xA5, 0x05, 0x00, 0xFF, 0xFB, 0x77]);
    } catch (e) {
      debugPrint('[CURRENT_SETTINGS] Error: $e');
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

  @override
  void dispose() {
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
              'Current Settings',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh, color: Colors.white),
                onPressed: () => _fetchCurrentSettings(),
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
                        _buildSectionHeader('Current Protection Settings'),
                        _buildParameterSection([
                          _buildParameterRow('Charge Overcurrent Protection', chargeOvercurrentProtection, 'A'),
                          _buildParameterRow('Charge Overcurrent Delay', chargeOvercurrentDelay, 'sec'),
                          _buildParameterRow('Discharge Overcurrent Protection', dischargeOvercurrentProtection, 'A'),
                          _buildParameterRow('Discharge Overcurrent Delay', dischargeOvercurrentDelay, 'sec'),
                          _buildParameterRow('Short Circuit Protection', shortCircuitProtection, 'A'),
                          _buildParameterRow('Short Circuit Delay', shortCircuitDelay, 'ms'),
                          _buildParameterRow('Secondary Overcurrent Protection', secondaryOvercurrentProtection, 'A'),
                          _buildParameterRow('Secondary Overcurrent Delay', secondaryOvercurrentDelay, 'sec'),
                        ]),
                      ],
                    ),
                  ),
                ),
              ),
              
              // Transparent loader overlay
              if (_isLoading && bleService?.isConnected == true)
                Container(
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
                      child: const SizedBox(
                        width: 40,
                        height: 40,
                        child: CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          strokeWidth: 3,
                        ),
                      ),
                    ),
                  ),
                ),
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

  Widget _buildParameterRow(String label, String value, String unit) {
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
                      '$value$unit',
                      style: TextStyle(
                        fontSize: 13,
                        color: themeProvider.primaryColor,
                        fontWeight: FontWeight.normal,
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