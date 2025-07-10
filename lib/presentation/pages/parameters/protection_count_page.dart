import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import '../../../services/bluetooth/ble_service.dart';
import '../../cubits/theme_cubit.dart';

class ProtectionCountPage extends StatefulWidget {
  const ProtectionCountPage({super.key});

  @override
  State<ProtectionCountPage> createState() => _ProtectionCountPageState();
}

class _ProtectionCountPageState extends State<ProtectionCountPage> {
  BleService? bleService;
  Function(List<int>)? _originalCallback;
  
  String shortCircuitCount = '0';
  String chargeOvercurrentCount = '0';
  String dischargeOvercurrentCount = '0';
  String cellOvervoltageCount = '0';
  String cellUndervoltageCount = '0';
  String chargeOvertempCount = '0';
  String chargeUndertempCount = '0';
  String dischargeOvertempCount = '0';
  String dischargeUndertempCount = '0';
  String packOvervoltageCount = '0';
  String packUndervoltageCount = '0';
  String systemRestartCount = '0';
  
  bool _dataReceived = false;
  Timer? _timeoutTimer;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    debugPrint('[PROTECTION_COUNT] Screen initialized');
    _loadProtectionCount();
  }

  Future<void> _loadProtectionCount() async {
    try {
      bleService = context.read<BleService>();
      
      if (bleService?.isConnected != true) {
        setState(() {
          shortCircuitCount = '0';
          chargeOvercurrentCount = '0';
          dischargeOvercurrentCount = '0';
          cellOvervoltageCount = '0';
          cellUndervoltageCount = '0';
          chargeOvertempCount = '0';
          chargeUndertempCount = '0';
          dischargeOvertempCount = '0';
          dischargeUndertempCount = '0';
          packOvervoltageCount = '0';
          packUndervoltageCount = '0';
          systemRestartCount = '0';
          _isLoading = false;
        });
        _showNotConnectedDialog();
        return;
      }

      setState(() {
        _isLoading = true;
        _dataReceived = false;
      });

      // Store original callback and set up combo callback
      _originalCallback = bleService?.dataCallback;
      bleService?.addDataCallback((data) {
        debugPrint('[PROTECTION_COUNT] Received BLE data: ${data.map((b) => '0x${b.toRadixString(16).padLeft(2, '0')}').join(' ')}');
        _handleBleData(data);
        // Also forward to original callback if it exists (for dashboard)
        if (_originalCallback != null) {
          _originalCallback!(data);
        }
      });
      
      // Wait a bit before sending command
      await Future.delayed(const Duration(milliseconds: 500));
      await _fetchProtectionCount();
    } catch (e) {
      debugPrint('[PROTECTION_COUNT] Error: $e');
    }
  }

  void _handleBleData(List<int> data) {
    debugPrint('[PROTECTION_COUNT] Processing data: ${data.map((b) => '0x${b.toRadixString(16).padLeft(2, '0')}').join(' ')}');
    
    if (data.length < 7) {
      debugPrint('[PROTECTION_COUNT] Data too short: ${data.length}');
      return;
    }
    
    if (data[0] != 0xDD || data.last != 0x77) {
      debugPrint('[PROTECTION_COUNT] Invalid frame format');
      return;
    }
    
    final register = data[1];
    final status = data[2];
    final dataLength = data[3];
    
    debugPrint('[PROTECTION_COUNT] Register: 0x${register.toRadixString(16)}, Status: 0x${status.toRadixString(16)}, Length: $dataLength');
    
    if (status != 0x00) {
      debugPrint('[PROTECTION_COUNT] Error status: 0x${status.toRadixString(16)}');
      return;
    }
    
    if (data.length < 4 + dataLength + 3) { // +3 for checksum and end byte
      debugPrint('[PROTECTION_COUNT] Insufficient data length');
      return;
    }
    
    if (register == 0xAA) {
      debugPrint('[PROTECTION_COUNT] Found register 0xAA response');
      final responseData = data.sublist(4, 4 + dataLength);
      _parseProtectionCount(responseData);
    } else {
      debugPrint('[PROTECTION_COUNT] Ignoring register: 0x${register.toRadixString(16)}');
    }
  }

  void _parseProtectionCount(List<int> data) {
    if (mounted) {
      setState(() {
        debugPrint('[PROTECTION_COUNT] Parsing error counts data: ${data.map((b) => '0x${b.toRadixString(16).padLeft(2, '0')}').join(' ')}');
        
        // Parse protection count data (11 U16 values, each count is 2 bytes)
        // sc_err_cnt, chgoc_err_cnt, dsgoc_err_cnt, covp_err_cnt, cuvp_err_cnt, 
        // chgot_err_cnt, chgut_err_cnt, dsgot_err_cnt, dsgut_err_cnt, povp_err_cnt, puvp_err_cnt
        
        // Safe parsing with bounds checking
        final scCount = data.length >= 2 ? (data[0] << 8) | data[1] : 0;
        shortCircuitCount = '$scCount';
        debugPrint('[PROTECTION_COUNT] Short Circuit: $scCount');
        
        final chgocCount = data.length >= 4 ? (data[2] << 8) | data[3] : 0;
        chargeOvercurrentCount = '$chgocCount';
        debugPrint('[PROTECTION_COUNT] Charge Overcurrent: $chgocCount');
        
        final dsgocCount = data.length >= 6 ? (data[4] << 8) | data[5] : 0;
        dischargeOvercurrentCount = '$dsgocCount';
        debugPrint('[PROTECTION_COUNT] Discharge Overcurrent: $dsgocCount');
        
        final covpCount = data.length >= 8 ? (data[6] << 8) | data[7] : 0;
        cellOvervoltageCount = '$covpCount';
        debugPrint('[PROTECTION_COUNT] Cell Overvoltage: $covpCount');
        
        final cuvpCount = data.length >= 10 ? (data[8] << 8) | data[9] : 0;
        cellUndervoltageCount = '$cuvpCount';
        debugPrint('[PROTECTION_COUNT] Cell Undervoltage: $cuvpCount');
        
        final chgotCount = data.length >= 12 ? (data[10] << 8) | data[11] : 0;
        chargeOvertempCount = '$chgotCount';
        debugPrint('[PROTECTION_COUNT] Charge Overtemperature: $chgotCount');
        
        final chgutCount = data.length >= 14 ? (data[12] << 8) | data[13] : 0;
        chargeUndertempCount = '$chgutCount';
        debugPrint('[PROTECTION_COUNT] Charge Undertemperature: $chgutCount');
        
        final dsgotCount = data.length >= 16 ? (data[14] << 8) | data[15] : 0;
        dischargeOvertempCount = '$dsgotCount';
        debugPrint('[PROTECTION_COUNT] Discharge Overtemperature: $dsgotCount');
        
        final dsgutCount = data.length >= 18 ? (data[16] << 8) | data[17] : 0;
        dischargeUndertempCount = '$dsgutCount';
        debugPrint('[PROTECTION_COUNT] Discharge Undertemperature: $dsgutCount');
        
        final povpCount = data.length >= 20 ? (data[18] << 8) | data[19] : 0;
        packOvervoltageCount = '$povpCount';
        debugPrint('[PROTECTION_COUNT] Pack Overvoltage: $povpCount');
        
        final puvpCount = data.length >= 22 ? (data[20] << 8) | data[21] : 0;
        packUndervoltageCount = '$puvpCount';
        debugPrint('[PROTECTION_COUNT] Pack Undervoltage: $puvpCount');
        
        // Note: Original code had systemRestartCount but the spec only shows 11 counts
        // Setting it to 0 as it's not in the register specification
        systemRestartCount = '0';
        
        // Mark data as received and cancel timeout
        _dataReceived = true;
        _timeoutTimer?.cancel();
        _isLoading = false;
        
        debugPrint('[PROTECTION_COUNT] Successfully parsed all protection counts');
      });
    }
  }

  Future<void> _fetchProtectionCount() async {
    try {
      _dataReceived = false;
      
      // Set up timeout timer
      _timeoutTimer?.cancel();
      _timeoutTimer = Timer(const Duration(seconds: 5), () {
        if (!_dataReceived && mounted) {
          debugPrint('[PROTECTION_COUNT] Timeout - no response received');
          setState(() {
            shortCircuitCount = 'Timeout';
            chargeOvercurrentCount = 'Timeout';
            dischargeOvercurrentCount = 'Timeout';
            cellOvervoltageCount = 'Timeout';
            cellUndervoltageCount = 'Timeout';
            chargeOvertempCount = 'Timeout';
            chargeUndertempCount = 'Timeout';
            dischargeOvertempCount = 'Timeout';
            dischargeUndertempCount = 'Timeout';
            packOvervoltageCount = 'Timeout';
            packUndervoltageCount = 'Timeout';
            systemRestartCount = 'Timeout';
          });
        }
      });
      
      // Send command to read protection counts from register 0xAA
      const checksum = (0x10000 - (0xAA + 0x00)) & 0xFFFF;
      const checksumHigh = (checksum >> 8) & 0xFF;
      const checksumLow = checksum & 0xFF;
      
      const command = [0xDD, 0xA5, 0xAA, 0x00, checksumHigh, checksumLow, 0x77];
      debugPrint('[PROTECTION_COUNT] Sending command: ${command.map((b) => '0x${b.toRadixString(16).padLeft(2, '0')}').join(' ')}');
      
      await bleService?.writeData(command);
    } catch (e) {
      debugPrint('[PROTECTION_COUNT] Error: $e');
      _timeoutTimer?.cancel();
      // Set default values on error
      if (mounted) {
        setState(() {
          shortCircuitCount = 'Error';
          chargeOvercurrentCount = 'Error';
          dischargeOvercurrentCount = 'Error';
          cellOvervoltageCount = 'Error';
          cellUndervoltageCount = 'Error';
          chargeOvertempCount = 'Error';
          chargeUndertempCount = 'Error';
          dischargeOvertempCount = 'Error';
          dischargeUndertempCount = 'Error';
          packOvervoltageCount = 'Error';
          packUndervoltageCount = 'Error';
          systemRestartCount = 'Error';
        });
      }
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
    _timeoutTimer?.cancel();
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
              'Protection Counts',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh, color: Colors.white),
                onPressed: () => _fetchProtectionCount(),
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
                        _buildSectionHeader('Protection Event Counts'),
                        _buildParameterSection([
                          _buildParameterRow('Short Circuit Protection', shortCircuitCount, 'times'),
                          _buildParameterRow('Charge Overcurrent', chargeOvercurrentCount, 'times'),
                          _buildParameterRow('Discharge Overcurrent', dischargeOvercurrentCount, 'times'),
                          _buildParameterRow('Cell Overvoltage', cellOvervoltageCount, 'times'),
                          _buildParameterRow('Cell Undervoltage', cellUndervoltageCount, 'times'),
                          _buildParameterRow('Charge Overtemperature', chargeOvertempCount, 'times'),
                          _buildParameterRow('Charge Undertemperature', chargeUndertempCount, 'times'),
                          _buildParameterRow('Discharge Overtemperature', dischargeOvertempCount, 'times'),
                          _buildParameterRow('Discharge Undertemperature', dischargeUndertempCount, 'times'),
                          _buildParameterRow('Pack Overvoltage', packOvervoltageCount, 'times'),
                          _buildParameterRow('Pack Undervoltage', packUndervoltageCount, 'times'),
                          _buildParameterRow('System Restart', systemRestartCount, 'times'),
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
                      '$value $unit',
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