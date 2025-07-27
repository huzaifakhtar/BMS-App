import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import 'dart:math' as math;
import '../../../services/bluetooth/ble_service.dart';
import '../../../services/bluetooth/bms_service.dart';
import '../../cubits/theme_cubit.dart';
import '../devices/device_list_page.dart';
import '../../../core/constants/app_constants.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});
 
  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  
  Timer? _updateTimer;
  BleService? _bleService;
  bool _lastConnectionState = false;
  
  // Data variables
  double _voltage = 0.0;
  double _current = 0.0;
  double _power = 0.0;
  int _soc = 0;
  int _cycles = 0;
  List<double> _cellVoltages = [];
  List<double> _temperatures = [];
  int _protectionStatus = 0;
  int _balanceStatus = 0;
  bool _chargeFetOn = false;
  bool _dischargeFetOn = false;
  
  // Response waiting
  Completer<List<int>>? _responseCompleter;
  Timer? _timeoutTimer;
  int _expectedRegister = 0;
  
  // Packet assembly
  final List<int> _incomingBuffer = [];
  
  // Voltage calculations
  double? _cachedVolHigh;
  double? _cachedVolLow;
  double? _cachedVolDiff;
  double? _cachedAvgVol;


  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initialize());
  }


  @override
  void dispose() {
    _updateTimer?.cancel();
    _timeoutTimer?.cancel();
    _bleService?.removeListener(_onConnectionChanged);
    super.dispose();
  }

  void _initialize() {
    _bleService = context.read<BleService>();
    
    // Set up connection monitoring and BMS data flow
    _bleService?.addListener(_onConnectionChanged);
    
    if (_bleService != null) {
      // Dashboard gets its own copy of BLE data for manual parsing
      _bleService!.addDataCallback((data) {
        _handleBleData(data);
      });
    }
    
    // Check initial connection
    final isConnected = _bleService?.isConnected ?? false;
    _lastConnectionState = isConnected;
    
    if (isConnected) {
      _onConnectionEstablished();
    }
  }
  
  
  void _onConnectionChanged() {
    final currentConnectionState = _bleService?.isConnected ?? false;
    
    if (currentConnectionState != _lastConnectionState) {
      if (currentConnectionState) {
        _onConnectionEstablished();
      } else {
        _onConnectionLost();
      }
      _lastConnectionState = currentConnectionState;
    }
  }
  
  void _onConnectionEstablished() {
    final bmsService = context.read<BmsService>();
    bmsService.startReading();
    _startRealTimeUpdates();
  }
  
  void _onConnectionLost() {
    _updateTimer?.cancel();
    _updateTimer = null;
    _incomingBuffer.clear();
    
    setState(() {
      _voltage = 0.0;
      _current = 0.0;
      _power = 0.0;
      _soc = 0;
      _cycles = 0;
      _cellVoltages.clear();
      _temperatures.clear();
      _protectionStatus = 0;
      _balanceStatus = 0;
      _chargeFetOn = false;
      _dischargeFetOn = false;
      _cachedVolHigh = null;
      _cachedVolLow = null;
      _cachedVolDiff = null;
      _cachedAvgVol = null;
    });
  }



  void _startRealTimeUpdates() {
    _updateTimer?.cancel();
    
    if (_bleService?.isConnected == true) {
      // Immediate first fetch
      _fetchLatestData();
      
      // Set up periodic updates
      _updateTimer = Timer.periodic(AppConstants.updateInterval, (_) {
        if (_bleService?.isConnected == true && mounted) {
          _fetchLatestData();
        } else {
          _updateTimer?.cancel();
          _updateTimer = null;
        }
      });
    }
  }


  Future<void> _fetchLatestData() async {
    if (_bleService?.isConnected != true) {
      return;
    }
    
    try {
      // Step 1: Send 0x03 command and wait for response
      _expectedRegister = 0x03;
      await _bleService!.writeData(AppConstants.basicInfoCommand);
      final basicResponse = await _waitForResponse(AppConstants.responseTimeout);
      
      if (basicResponse != null) {
        _parseBasicData(basicResponse);
      }
      
      // Step 2: Send 0x04 command and wait for response
      _expectedRegister = 0x04;
      await _bleService!.writeData(AppConstants.cellVoltageCommand);
      final cellResponse = await _waitForResponse(AppConstants.responseTimeout);
      
      if (cellResponse != null) {
        _parseCellData(cellResponse);
      }
      
      // Force UI update after data fetch complete
      if (mounted) {
        setState(() {
          _updateVoltageCache();
        });
      }
      
    } catch (e) {
      // Handle data fetch error silently
    }
  }

  void _handleBleData(List<int> data) {
    _incomingBuffer.addAll(data);
    _processBuffer();
  }
  
  void _processBuffer() {
    while (_incomingBuffer.isNotEmpty) {
      int startIndex = _incomingBuffer.indexOf(0xDD);
      if (startIndex == -1) {
        _incomingBuffer.clear();
        return;
      }
      
      if (startIndex > 0) {
        _incomingBuffer.removeRange(0, startIndex);
      }
      
      if (_incomingBuffer.length < 7) return;
      
      int endIndex = -1;
      for (int i = 6; i < _incomingBuffer.length; i++) {
        if (_incomingBuffer[i] == 0x77) {
          endIndex = i;
          break;
        }
      }
      
      if (endIndex == -1) return;
      
      final packet = _incomingBuffer.sublist(0, endIndex + 1);
      _incomingBuffer.removeRange(0, endIndex + 1);
      
      _processCompletePacket(packet);
    }
  }
  
  void _processCompletePacket(List<int> packet) {
    if (packet.length < 7) return;
    
    final register = packet[1];
    final status = packet[2];
    
    final completer = _responseCompleter;
    if (completer != null && !completer.isCompleted) {
      if (register == _expectedRegister && status == 0x00) {
        completer.complete(packet);
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
  
  void _parseBasicData(List<int> data) {
    if (data.length < 7) return;
    final dataLength = data[3];
    if (data.length < 4 + dataLength) return;
    
    final actualData = data.sublist(4, 4 + dataLength);
    if (actualData.length < 21) return;
    
    if (mounted) {
      setState(() {
        _voltage = ((actualData[0] << 8) | actualData[1]) * 0.01;
        
        int currentRaw = (actualData[2] << 8) | actualData[3];
        if (currentRaw > 32767) currentRaw = currentRaw - 65536;
        _current = currentRaw * 0.01;
        _power = _voltage * _current;
        
        _cycles = (actualData[8] << 8) | actualData[9];
        _soc = actualData[19];
        
        if (actualData.length >= 18) {
          _protectionStatus = (actualData[16] << 8) | actualData[17];
        }
        
        if (actualData.length >= 14) {
          _balanceStatus = (actualData[12] << 8) | actualData[13];
        }
        
        if (actualData.length >= 21) {
          final fetStatus = actualData[20];
          _chargeFetOn = (fetStatus & 0x01) != 0;
          _dischargeFetOn = (fetStatus & 0x02) != 0;
        }
        
        _temperatures = [];
        if (actualData.length >= 23) {
          final ntcCount = actualData[22];
          int tempStartIndex = 23;
          for (int i = 0; i < ntcCount && (tempStartIndex + 1) < actualData.length; i++) {
            int tempRaw = (actualData[tempStartIndex] << 8) | actualData[tempStartIndex + 1];
            if (tempRaw > 0) {
              double tempCelsius = (tempRaw * 0.1) - 273.15;
              _temperatures.add(tempCelsius);
            }
            tempStartIndex += 2;
          }
        }
      });
    }
  }
  
  void _parseCellData(List<int> data) {
    if (data.length < 7) return;
    final dataLength = data[3];
    if (data.length < 4 + dataLength) return;
    
    final actualData = data.sublist(4, 4 + dataLength);
    final cellCount = actualData.length ~/ 2;
    
    if (mounted) {
      setState(() {
        _cellVoltages = [];
        for (int i = 0; i < cellCount; i++) {
          final voltage = ((actualData[i * 2] << 8) | actualData[i * 2 + 1]) / 1000.0;
          _cellVoltages.add(voltage);
        }
        _updateVoltageCache();
      });
    }
  }

  void _updateVoltageCache() {
    if (_cellVoltages.isNotEmpty) {
      _cachedVolHigh = _cellVoltages.reduce(math.max);
      _cachedVolLow = _cellVoltages.reduce(math.min);
      _cachedVolDiff = _cachedVolHigh! - _cachedVolLow!;
      _cachedAvgVol = _cellVoltages.reduce((a, b) => a + b) / _cellVoltages.length;
    } else {
      _cachedVolHigh = _cachedVolLow = _cachedVolDiff = _cachedAvgVol = 0.0;
    }
  }


  @override
  Widget build(BuildContext context) {
    
    return Consumer3<BleService, BmsService, ThemeProvider>(
      builder: (context, bleService, bmsService, themeProvider, _) {
        final isConnected = bleService.isConnected;
        
        // Dashboard uses its own direct data fetching
        final connectedDevice = bleService.connectedDevice;
        final storedDeviceName = bleService.connectedDeviceName;
        
        final deviceName = isConnected && connectedDevice != null 
          ? (storedDeviceName.isNotEmpty 
              ? storedDeviceName 
              : (connectedDevice.platformName.isNotEmpty 
                  ? connectedDevice.platformName 
                  : 'BMS Device')) 
          : 'Not Connected';
        final deviceId = isConnected ? 'Connected' : 'No Device ID';
        
        return Scaffold(
          backgroundColor: themeProvider.gaugeBackgroundColor,
          appBar: _buildAppBar(themeProvider),
          body: SafeArea(
            child: RefreshIndicator(
              onRefresh: () async {
                if (isConnected) {
                  await _fetchLatestData();
                }
              },
              color: themeProvider.primaryColor,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: Column(
                  children: [
                    _buildUpperSection(deviceName, deviceId, _soc, themeProvider, isConnected),
                    _buildLowerSection(themeProvider, isConnected),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }


  PreferredSizeWidget _buildAppBar(ThemeProvider themeProvider) {
    return AppBar(
      backgroundColor: themeProvider.gaugeBackgroundColor,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.cable, color: Colors.white),
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const DeviceListPage()),
        ),
      ),
      title: const Text(
        'Humaya Connect',
        style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh, color: Colors.white),
          onPressed: () {
            if (_bleService?.isConnected == true) {
              _fetchLatestData();
            }
          },
        ),
      ],
    );
  }

  Widget _buildUpperSection(String deviceName, String deviceId, int socValue, ThemeProvider themeProvider, bool isConnected) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            themeProvider.gaugeBackgroundColor,
            themeProvider.gaugeBackgroundColor.withOpacity(0.8),
          ],
        ),
      ),
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isConnected ? Colors.green : Colors.red,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                deviceName,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            deviceId,
            style: const TextStyle(fontSize: 14, color: Colors.white70),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 20),
          _SemiCircularGauge(socValue: socValue),
        ],
      ),
    );
  }

  Widget _buildLowerSection(ThemeProvider themeProvider, bool isConnected) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: themeProvider.cardColor,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: _StatusSection(
              chargeFetOn: _chargeFetOn,
              dischargeFetOn: _dischargeFetOn,
              balanceStatus: _balanceStatus,
              protectionStatus: _protectionStatus,
              themeProvider: themeProvider,
            ),
          ),
          const SizedBox(height: 24),
          _buildSectionDivider(themeProvider),
          const SizedBox(height: 20),
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: Padding(
                padding: const EdgeInsets.only(left: 12, right: 8),
                child: _MetricsGrid(
                  voltage: _voltage,
                  current: _current,
                  power: _power,
                  cycles: _cycles,
                  cachedVolHigh: _cachedVolHigh,
                  cachedVolLow: _cachedVolLow,
                  cachedVolDiff: _cachedVolDiff,
                  cachedAvgVol: _cachedAvgVol,
                  themeProvider: themeProvider,
                  isConnected: isConnected,
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          _buildSectionDivider(themeProvider),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: _TemperatureSection(temperatures: _temperatures, themeProvider: themeProvider, isConnected: isConnected),
          ),
          const SizedBox(height: 20),
          _buildSectionDivider(themeProvider),
          const SizedBox(height: 20),
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: _CellVoltageSection(cellVoltages: _cellVoltages, themeProvider: themeProvider),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildSectionDivider(ThemeProvider themeProvider) {
    return Container(
      height: 1,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.transparent,
            themeProvider.borderColor.withOpacity(0.3),
            Colors.transparent,
          ],
        ),
      ),
    );
  }



}

// All the remaining classes stay exactly the same...
// Status Section
class _StatusSection extends StatelessWidget {
  final bool chargeFetOn;
  final bool dischargeFetOn;
  final int balanceStatus;
  final int protectionStatus;
  final ThemeProvider themeProvider;

  const _StatusSection({
    required this.chargeFetOn,
    required this.dischargeFetOn,
    required this.balanceStatus,
    required this.protectionStatus,
    required this.themeProvider,
  });

  @override
  Widget build(BuildContext context) {
    final balanceOn = balanceStatus > 0;
    final protectionReason = _getProtectionReason(protectionStatus);
    
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildStatusItem('ChgMos', chargeFetOn ? 'ON' : 'OFF', chargeFetOn),
            const SizedBox(height: 8),
            _buildStatusItem('DisMos', dischargeFetOn ? 'ON' : 'OFF', dischargeFetOn),
          ],
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            _buildStatusItem('Balance', balanceOn ? 'ON' : 'OFF', balanceOn),
            const SizedBox(height: 8),
            _buildStatusItem('Protection', protectionReason, protectionReason != 'OFF'),
          ],
        ),
      ],
    );
  }

  Widget _buildStatusItem(String label, String status, bool isOn) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('$label : ', style: const TextStyle(fontSize: 14, color: Colors.black, fontWeight: FontWeight.w500)),
        Container(
          width: 10,
          height: 10,
          margin: const EdgeInsets.only(right: 6),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isOn ? themeProvider.primaryColor : Colors.grey,
          ),
        ),
        Text(status, style: TextStyle(fontSize: 14, color: isOn ? themeProvider.primaryColor : themeProvider.secondaryTextColor, fontWeight: FontWeight.w500)),
      ],
    );
  }

  String _getProtectionReason(int protectionStatus) {
    if (protectionStatus == 0) return 'OFF';
    
    const protections = [
      'Cell OV', 'Cell UV', 'Pack OV', 'Pack UV', 'Chg OT', 'Chg UT',
      'Dis OT', 'Dis UT', 'Chg OC', 'Dis OC', 'Short', 'IC Error', 'SW Lock'
    ];
    
    for (int i = 0; i < protections.length; i++) {
      if ((protectionStatus & (1 << i)) != 0) return protections[i];
    }
    
    return 'Unknown';
  }
}

// Metrics Grid
class _MetricsGrid extends StatelessWidget {
  final double voltage;
  final double current;
  final double power;
  final int cycles;
  final double? cachedVolHigh;
  final double? cachedVolLow;
  final double? cachedVolDiff;
  final double? cachedAvgVol;
  final ThemeProvider themeProvider;
  final bool isConnected;

  const _MetricsGrid({
    required this.voltage,
    required this.current,
    required this.power,
    required this.cycles,
    this.cachedVolHigh,
    this.cachedVolLow,
    this.cachedVolDiff,
    this.cachedAvgVol,
    required this.themeProvider,
    required this.isConnected,
  });

  @override
  Widget build(BuildContext context) {
    final metrics = _getMetrics();
    
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: _buildMetricItem(metrics[0])),
            const SizedBox(width: 16),
            Expanded(child: _buildMetricItem(metrics[1])),
            const SizedBox(width: 16),
            Expanded(child: _buildMetricItem(metrics[2])),
          ],
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(child: _buildMetricItem(metrics[3])),
            const SizedBox(width: 16),
            Expanded(child: _buildMetricItem(metrics[4])),
            const SizedBox(width: 16),
            Expanded(child: _buildMetricItem(metrics[5])),
          ],
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(child: _buildMetricItem(metrics[6])),
            const SizedBox(width: 16),
            Expanded(child: _buildMetricItem(metrics[7])),
            const SizedBox(width: 16),
            const Expanded(child: SizedBox()),
          ],
        ),
      ],
    );
  }

  List<_MetricData> _getMetrics() {
    final volHigh = cachedVolHigh ?? 0.0;
    final volLow = cachedVolLow ?? 0.0;
    final volDiff = cachedVolDiff ?? 0.0;
    final avgVol = cachedAvgVol ?? 0.0;
    
    final voltageDecimals = isConnected ? 2 : 1;
    final currentDecimals = isConnected ? 2 : 1;
    const powerDecimals = 1;
    final voltageDetailDecimals = isConnected ? 3 : 1;
    
    return [
      _MetricData(Icons.electrical_services, 'TotalVolt', '${voltage.toStringAsFixed(voltageDecimals)} V'),
      _MetricData(Icons.flash_on, 'Current', '${current.toStringAsFixed(currentDecimals)} A'),
      _MetricData(Icons.power, 'Power', '${power.toStringAsFixed(powerDecimals)} W'),
      _MetricData(Icons.keyboard_arrow_up, 'VolHigh', '${volHigh.toStringAsFixed(voltageDetailDecimals)} V'),
      _MetricData(Icons.keyboard_arrow_down, 'VolLow', '${volLow.toStringAsFixed(voltageDetailDecimals)} V'),
      _MetricData(Icons.height, 'VolDiff', '${volDiff.toStringAsFixed(voltageDetailDecimals)} V'),
      _MetricData(Icons.balance, 'AveVol', '${avgVol.toStringAsFixed(voltageDetailDecimals)} V'),
      _MetricData(Icons.autorenew, 'Cycles', '$cycles'),
    ];
  }

  Widget _buildMetricItem(_MetricData metric) {
    return Row(
      children: [
        _buildMetricIcon(metric.label),
        const SizedBox(width: 2),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                metric.value,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.normal, color: themeProvider.primaryColor),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
              const SizedBox(height: 2),
              Text(
                metric.label,
                style: const TextStyle(fontSize: 14, color: Colors.black, fontWeight: FontWeight.normal),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMetricIcon(String label) {
    if (['totalvolt', 'current', 'power'].contains(label.toLowerCase())) {
      String letter;
      switch (label.toLowerCase()) {
        case 'totalvolt': letter = 'V'; break;
        case 'current': letter = 'A'; break;
        case 'power': letter = 'W'; break;
        default: letter = '?'; break;
      }
      
      return _CustomMetricLogo(letter: letter, color: themeProvider.primaryColor, size: 28);
    }
    
    IconData iconData;
    switch (label.toLowerCase()) {
      case 'volhigh': iconData = Icons.keyboard_arrow_up; break;
      case 'vollow': iconData = Icons.keyboard_arrow_down; break;
      case 'voldiff': iconData = Icons.height; break;
      case 'avevol': iconData = Icons.analytics; break;
      case 'cycles': iconData = Icons.autorenew; break;
      default: iconData = Icons.analytics; break;
    }
    
    return Icon(iconData, color: themeProvider.primaryColor, size: 28);
  }
}

// Temperature Section
class _TemperatureSection extends StatelessWidget {
  final List<double> temperatures;
  final ThemeProvider themeProvider;
  final bool isConnected;

  const _TemperatureSection({
    required this.temperatures,
    required this.themeProvider,
    required this.isConnected,
  });

  @override
  Widget build(BuildContext context) {
    final displayTemperatures = temperatures.isNotEmpty ? temperatures.take(3).toList() : [0.0, 0.0, 0.0];
    
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: List.generate(3, (index) {
                final temp = index < displayTemperatures.length ? displayTemperatures[index] : 0.0;
                final sensorName = index == 0 ? 'MOS' : 'T$index';
                
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 35,
                        child: Text(
                          sensorName,
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Colors.black),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${temp.toStringAsFixed(1)}°C',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: themeProvider.primaryColor),
                      ),
                    ],
                  ),
                );
              }),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Icon(Icons.thermostat, color: themeProvider.primaryColor, size: 48),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: List.generate(3, (index) {
                final temp = index < displayTemperatures.length ? displayTemperatures[index] : 0.0;
                final tempF = (temp * 9/5) + 32;
                final sensorName = index == 0 ? 'MOS' : 'T$index';
                
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      SizedBox(
                        width: 35,
                        child: Text(
                          sensorName,
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Colors.black),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${tempF.toStringAsFixed(1)}°F',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: themeProvider.primaryColor),
                      ),
                    ],
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }
}

// Cell Voltage Section
class _CellVoltageSection extends StatelessWidget {
  final List<double> cellVoltages;
  final ThemeProvider themeProvider;

  const _CellVoltageSection({
    required this.cellVoltages,
    required this.themeProvider,
  });

  @override
  Widget build(BuildContext context) {
    if (cellVoltages.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(20),
        child: Column(
          children: [
            Text('Single voltage information', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.black), textAlign: TextAlign.center),
            SizedBox(height: 20),
            Text('No cell voltage data available', style: TextStyle(color: Colors.black, fontSize: 14), textAlign: TextAlign.center),
          ],
        ),
      );
    }

    final volHigh = cellVoltages.reduce(math.max);
    final volLow = cellVoltages.reduce(math.min);
    
    return Column(
      children: [
        const Text('Single voltage information', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.black), textAlign: TextAlign.center),
        const SizedBox(height: 20),
        ...List.generate((cellVoltages.length / 3).ceil(), (rowIndex) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: List.generate(3, (colIndex) {
                final cellIndex = rowIndex * 3 + colIndex;
                if (cellIndex >= cellVoltages.length) {
                  return const Expanded(child: SizedBox());
                }
                
                final voltage = cellVoltages[cellIndex];
                Color backgroundColor;
                
                if (voltage == volHigh) {
                  backgroundColor = Colors.green;
                } else if (voltage == volLow) {
                  backgroundColor = Colors.grey;
                } else {
                  backgroundColor = themeProvider.primaryColor;
                }
                
                return Expanded(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 20,
                        child: Text(
                          '${cellIndex + 1}',
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.black),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 75,
                            height: 36,
                            padding: const EdgeInsets.all(2),
                            decoration: BoxDecoration(
                              border: Border.all(color: themeProvider.borderColor, width: 2),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Container(
                              decoration: BoxDecoration(
                                color: backgroundColor,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Padding(
                                  padding: const EdgeInsets.only(left: 8),
                                  child: Text(
                                    voltage.toStringAsFixed(3),
                                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white),
                                    overflow: TextOverflow.visible,
                                    maxLines: 1,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 1),
                          Container(
                            width: 3,
                            height: 12,
                            decoration: BoxDecoration(
                              color: themeProvider.borderColor,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              }),
            ),
          );
        }),
      ],
    );
  }
}

// Semi Circular Gauge
class _SemiCircularGauge extends StatelessWidget {
  final int socValue;

  const _SemiCircularGauge({required this.socValue});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 120,
      width: 240,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: const Size(240, 90),
            painter: _SemiCircularGaugePainter(
              progress: socValue / 100.0,
              strokeWidth: 16,
              backgroundColor: Colors.white.withOpacity(0.2),
              progressColor: Colors.white,
            ),
          ),
          Positioned(
            bottom: 6,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  "SOC",
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.white70,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  "$socValue%",
                  style: const TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: -1,
                    shadows: [
                      Shadow(
                        color: Colors.black26,
                        offset: Offset(0, 2),
                        blurRadius: 4,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricData {
  final IconData icon;
  final String label;
  final String value;

  const _MetricData(this.icon, this.label, this.value);
}

class _SemiCircularGaugePainter extends CustomPainter {
  final double progress;
  final double strokeWidth;
  final Color backgroundColor;
  final Color progressColor;

  const _SemiCircularGaugePainter({
    required this.progress,
    required this.strokeWidth,
    required this.backgroundColor,
    required this.progressColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * 0.9);
    final radius = (size.width - strokeWidth) / 2.4;

    final backgroundPaint = Paint()
      ..color = backgroundColor
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final progressPaint = Paint()
      ..color = progressColor
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      math.pi,
      math.pi,
      false,
      backgroundPaint,
    );

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      math.pi,
      math.pi * progress,
      false,
      progressPaint,
    );
  }

  @override
  bool shouldRepaint(_SemiCircularGaugePainter oldDelegate) {
    return oldDelegate.progress != progress ||
           oldDelegate.strokeWidth != strokeWidth ||
           oldDelegate.backgroundColor != backgroundColor ||
           oldDelegate.progressColor != progressColor;
  }
}

class _CustomMetricLogo extends StatelessWidget {
  final String letter;
  final Color color;
  final double size;

  const _CustomMetricLogo({
    required this.letter,
    required this.color,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _MetricLogoPainter(
          letter: letter,
          color: color,
        ),
      ),
    );
  }
}

class _MetricLogoPainter extends CustomPainter {
  final String letter;
  final Color color;

  const _MetricLogoPainter({
    required this.letter,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withOpacity(0.8)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width * 0.35;

    canvas.drawArc(
      Rect.fromCenter(
        center: Offset(center.dx, center.dy - size.height * 0.05),
        width: radius * 2,
        height: radius * 2,
      ),
      -math.pi * 0.8,
      math.pi * 0.6,
      false,
      paint,
    );

    final textPainter = TextPainter(
      text: TextSpan(
        text: letter,
        style: TextStyle(
          color: color,
          fontSize: size.width * 0.65,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    );

    textPainter.layout();
    final textOffset = Offset(
      center.dx - textPainter.width / 2,
      center.dy - textPainter.height / 2 + size.height * 0.02,
    );
    
    textPainter.paint(canvas, textOffset);
  }

  @override
  bool shouldRepaint(_MetricLogoPainter oldDelegate) {
    return oldDelegate.letter != letter || oldDelegate.color != color;
  }
}