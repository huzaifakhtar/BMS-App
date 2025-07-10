import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'dart:async';
import '../../../services/bluetooth/ble_service.dart';
import '../../../services/bluetooth/bms_service.dart';
import '../../cubits/theme_cubit.dart';

class DeviceListPage extends StatefulWidget {
  const DeviceListPage({super.key});

  @override
  State<DeviceListPage> createState() => _DeviceListPageState();
}

class _DeviceListPageState extends State<DeviceListPage> with AutomaticKeepAliveClientMixin {
  bool _isScanning = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initialize());
  }

  void _initialize() {
    _checkBluetoothState();
    _startAutomaticScan();
  }

  Future<void> _startAutomaticScan() async {
    final bleService = context.read<BleService>();
    
    await Future.delayed(const Duration(milliseconds: 300));
    
    if (mounted) {
      setState(() => _isScanning = true);
      
      try {
        await bleService.startScan();
        await Future.delayed(const Duration(seconds: 3));
        bleService.stopScan();
      } finally {
        if (mounted) setState(() => _isScanning = false);
      }
    }
  }

  Future<void> _checkBluetoothState() async {
    FlutterBluePlus.adapterState.listen((state) {
      if (state != BluetoothAdapterState.on && mounted) {
        _showBluetoothAlert();
      }
    });
  }

  void _showBluetoothAlert() {
    final themeProvider = context.read<ThemeProvider>();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Row(
          children: [
            Icon(Icons.bluetooth_disabled, color: Colors.white),
            SizedBox(width: 12),
            Text('Please enable Bluetooth', style: TextStyle(fontWeight: FontWeight.w500)),
          ],
        ),
        backgroundColor: themeProvider.errorColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 3),
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    super.build(context);
    
    return Consumer2<ThemeProvider, BleService>(
      builder: (context, themeProvider, bleService, _) {
        return Scaffold(
          backgroundColor: themeProvider.backgroundColor,
          appBar: _buildAppBar(themeProvider),
          body: Consumer<BleService>(
            builder: (context, bleService, _) {
              return RefreshIndicator(
                onRefresh: _performScan,
                color: themeProvider.primaryColor,
                backgroundColor: themeProvider.cardColor,
                child: _buildDeviceList(bleService, themeProvider),
              );
            },
          ),
        );
      },
    );
  }

  PreferredSizeWidget _buildAppBar(ThemeProvider themeProvider) {
    return AppBar(
      title: const Text(
        'Connect Device',
        style: TextStyle(fontWeight: FontWeight.w600, letterSpacing: 0.5),
      ),
      backgroundColor: themeProvider.gaugeBackgroundColor,
      foregroundColor: Colors.white,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
        onPressed: () => Navigator.pop(context),
      ),
      actions: [
        IconButton(
          icon: Icon(
            _isScanning ? Icons.bluetooth_searching : Icons.refresh,
            color: Colors.white,
          ),
          onPressed: _isScanning ? null : _performScan,
        ),
      ],
    );
  }

  Future<void> _performScan() async {
    setState(() => _isScanning = true);
    final bleService = context.read<BleService>();
    
    try {
      await bleService.startScan();
      await Future.delayed(const Duration(seconds: 3));
      bleService.stopScan();
    } finally {
      if (mounted) setState(() => _isScanning = false);
    }
  }

  Widget _buildDeviceList(BleService bleService, ThemeProvider themeProvider) {
    final isConnected = bleService.isConnected;
    final connectedDevice = bleService.connectedDevice;
    final discoveredDevices = bleService.scanResults;
    
    if (!isConnected && discoveredDevices.isEmpty) {
      return _EmptyDeviceList(isScanning: _isScanning, onScan: _performScan, themeProvider: themeProvider);
    }

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        if (isConnected && connectedDevice != null) ...[
          Text(
            'Connected Device',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: themeProvider.textColor,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 16),
          _ConnectedDeviceCard(
            device: connectedDevice,
            bleService: bleService,
            themeProvider: themeProvider,
            onDisconnect: _disconnectDevice,
          ),
          const SizedBox(height: 24),
        ],
        
        if (discoveredDevices.isNotEmpty) ...[
          Text(
            'Available Devices',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: themeProvider.textColor,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 16),
          ...discoveredDevices.map((scanResult) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _AvailableDeviceCard(
              scanResult: scanResult,
              bleService: bleService,
              themeProvider: themeProvider,
              onConnect: _connectToDevice,
            ),
          )),
        ],
      ],
    );
  }

  Future<void> _disconnectDevice() async {
    final bleService = context.read<BleService>();
    final themeProvider = context.read<ThemeProvider>();
    
    try {
      await bleService.disconnect();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.bluetooth_disabled, color: Colors.white),
                SizedBox(width: 12),
                Text('Device disconnected', style: TextStyle(fontWeight: FontWeight.w500)),
              ],
            ),
            backgroundColor: themeProvider.warningColor,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.all(16),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Disconnect error: $e',
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
            backgroundColor: themeProvider.errorColor,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.all(16),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  Future<void> _connectToDevice(BluetoothDevice device) async {
    final bleService = context.read<BleService>();
    final bmsService = context.read<BmsService>();
    
    Navigator.pop(context);
    
    await Future.delayed(const Duration(milliseconds: 100));
    
    if (!mounted) return;

    try {
      final connected = await bleService.connectToDevice(device);
      
      if (connected) {
        bleService.addDataCallback((data) async => await bmsService.handleResponse(data));
        await _fetchInitialBatteryData();
      } else {
        if (mounted) _showConnectionFailedAlert();
      }
    } catch (e) {
      if (mounted) _showConnectionFailedAlert();
    }
  }

  void _showConnectionFailedAlert() {
    final themeProvider = context.read<ThemeProvider>();
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: themeProvider.cardColor,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: themeProvider.errorColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.error_outline,
                color: themeProvider.errorColor,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              'Connection Failed',
              style: TextStyle(
                color: themeProvider.textColor,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ],
        ),
        content: Text(
          'Failed to connect to device. Please try again.',
          style: TextStyle(
            color: themeProvider.secondaryTextColor,
            fontSize: 14,
          ),
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );

    Timer(const Duration(seconds: 2), () {
      if (mounted && Navigator.canPop(context)) {
        Navigator.of(context).pop();
      }
    });
  }

  Future<void> _fetchInitialBatteryData() async {
    try {
      final bmsService = context.read<BmsService>();
      final bleService = context.read<BleService>();
      
      bmsService.startReading();
      bmsService.clearValues();
      
      await bleService.writeData([0xDD, 0xA5, 0x03, 0x00, 0xFF, 0xFD, 0x77]);
      await Future.delayed(const Duration(milliseconds: 1000));
    } catch (_) {}
  }
}

class _EmptyDeviceList extends StatelessWidget {
  final bool isScanning;
  final VoidCallback onScan;
  final ThemeProvider themeProvider;

  const _EmptyDeviceList({
    required this.isScanning,
    required this.onScan,
    required this.themeProvider,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    themeProvider.primaryColor.withOpacity(0.2),
                    themeProvider.primaryColor.withOpacity(0.05),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
                border: Border.all(
                  color: themeProvider.primaryColor.withOpacity(0.3),
                  width: 2,
                ),
              ),
              child: isScanning
                  ? Center(
                      child: SizedBox(
                        width: 40,
                        height: 40,
                        child: CircularProgressIndicator(
                          strokeWidth: 3,
                          valueColor: AlwaysStoppedAnimation<Color>(themeProvider.primaryColor),
                        ),
                      ),
                    )
                  : Icon(
                      Icons.bluetooth_searching,
                      size: 48,
                      color: themeProvider.primaryColor,
                    ),
            ),
            const SizedBox(height: 24),
            Text(
              isScanning ? 'Scanning for devices...' : 'No devices found',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: themeProvider.textColor,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              isScanning 
                  ? 'Please wait while we search for available devices'
                  : 'Pull down to refresh and scan for devices',
              style: TextStyle(
                fontSize: 14,
                color: themeProvider.secondaryTextColor,
              ),
              textAlign: TextAlign.center,
            ),
            if (!isScanning) ...[
              const SizedBox(height: 32),
              ElevatedButton.icon(
                onPressed: onScan,
                icon: const Icon(Icons.refresh),
                label: const Text('Scan Again'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: themeProvider.primaryColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ConnectedDeviceCard extends StatelessWidget {
  final BluetoothDevice device;
  final BleService bleService;
  final ThemeProvider themeProvider;
  final VoidCallback onDisconnect;

  const _ConnectedDeviceCard({
    required this.device,
    required this.bleService,
    required this.themeProvider,
    required this.onDisconnect,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      decoration: BoxDecoration(
        color: themeProvider.cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: themeProvider.primaryColor.withOpacity(0.3),
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: themeProvider.primaryColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: themeProvider.primaryColor.withOpacity(0.3),
              width: 1,
            ),
          ),
          child: Icon(
            Icons.bluetooth_connected,
            color: themeProvider.primaryColor,
            size: 28,
          ),
        ),
        title: Text(
          device.platformName.isNotEmpty ? device.platformName : 'Unknown Device',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 14,
            color: themeProvider.textColor,
            letterSpacing: 0.5,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            _formatDeviceId(device, bleService),
            style: TextStyle(
              color: themeProvider.secondaryTextColor,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: themeProvider.errorColor,
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Text(
            'DISCONNECT',
            style: TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
        ),
        onTap: onDisconnect,
      ),
    );
  }

  String _formatDeviceId(BluetoothDevice device, BleService bleService) {
    return device.remoteId.toString();
  }
}

class _AvailableDeviceCard extends StatelessWidget {
  final ScanResult scanResult;
  final BleService bleService;
  final ThemeProvider themeProvider;
  final Function(BluetoothDevice) onConnect;

  const _AvailableDeviceCard({
    required this.scanResult,
    required this.bleService,
    required this.themeProvider,
    required this.onConnect,
  });

  @override
  Widget build(BuildContext context) {
    final device = scanResult.device;
    final rssi = scanResult.rssi;
    
    return Container(
      decoration: BoxDecoration(
        color: themeProvider.cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: themeProvider.borderColor.withOpacity(0.5),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                themeProvider.primaryColor.withOpacity(0.15),
                themeProvider.primaryColor.withOpacity(0.05),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: themeProvider.primaryColor.withOpacity(0.2),
              width: 1,
            ),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Icon(
                Icons.bluetooth,
                color: themeProvider.primaryColor,
                size: 28,
              ),
              Positioned(
                bottom: 4,
                right: 4,
                child: _buildSignalStrengthIcon(rssi),
              ),
            ],
          ),
        ),
        title: Text(
          device.platformName.isNotEmpty ? device.platformName : 'Unknown Device',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 14,
            color: themeProvider.textColor,
            letterSpacing: 0.3,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _formatDeviceId(device, bleService),
                      style: TextStyle(
                        color: themeProvider.secondaryTextColor,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  _buildRssiIndicator(rssi),
                  const SizedBox(width: 8),
                  Text(
                    '$rssi dBm',
                    style: TextStyle(
                      color: _getRssiColor(rssi),
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _getSignalStrength(rssi),
                    style: TextStyle(
                      color: _getRssiColor(rssi),
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        trailing: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: themeProvider.primaryColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: themeProvider.primaryColor.withOpacity(0.2),
              width: 1,
            ),
          ),
          child: Icon(
            Icons.arrow_forward_ios,
            color: themeProvider.primaryColor,
            size: 18,
          ),
        ),
        onTap: () => onConnect(device),
      ),
    );
  }

  Widget _buildSignalStrengthIcon(int rssi) {
    final color = _getRssiColor(rssi);
    IconData icon;
    
    if (rssi >= -50) {
      icon = Icons.bluetooth;
    } else if (rssi >= -80) {
      icon = Icons.bluetooth_searching;
    } else {
      icon = Icons.bluetooth_disabled;
    }
    
    return Container(
      width: 16,
      height: 16,
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Icon(icon, size: 10, color: color),
    );
  }

  Widget _buildRssiIndicator(int rssi) {
    final strength = _getSignalStrengthLevel(rssi);
    final color = _getRssiColor(rssi);
    
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(4, (index) {
        return Container(
          width: 3,
          height: 4 + (index * 2).toDouble(),
          margin: const EdgeInsets.only(right: 1),
          decoration: BoxDecoration(
            color: index < strength ? color : color.withOpacity(0.3),
            borderRadius: BorderRadius.circular(1),
          ),
        );
      }),
    );
  }



  String _formatDeviceId(BluetoothDevice device, BleService bleService) {
    return device.remoteId.toString();
  }

  Color _getRssiColor(int rssi) {
    if (rssi >= -50) {
      return themeProvider.accentColor;
    } else if (rssi >= -60) {
      return themeProvider.accentColor;
    } else if (rssi >= -70) {
      return themeProvider.warningColor;
    } else {
      return themeProvider.errorColor;
    }
  }

  String _getSignalStrength(int rssi) {
    if (rssi >= -50) return 'Excellent';
    if (rssi >= -60) return 'Good';
    if (rssi >= -70) return 'Fair';
    if (rssi >= -80) return 'Poor';
    return 'Very Poor';
  }

  int _getSignalStrengthLevel(int rssi) {
    if (rssi >= -50) return 4;
    if (rssi >= -60) return 3;
    if (rssi >= -70) return 2;
    if (rssi >= -80) return 1;
    return 0;
  }
}