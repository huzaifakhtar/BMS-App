import 'dart:async';
import 'package:rxdart/rxdart.dart';
import 'package:flutter/foundation.dart';
import '../../data/models/bms_data_model.dart';

class BmsDataStream {
  // Main data streams
  final BehaviorSubject<JbdBmsData?> _bmsDataSubject = BehaviorSubject<JbdBmsData?>.seeded(null);
  final BehaviorSubject<List<double>?> _cellVoltagesSubject = BehaviorSubject<List<double>?>.seeded(null);
  final BehaviorSubject<bool> _connectionStateSubject = BehaviorSubject<bool>.seeded(false);
  final BehaviorSubject<String> _statusMessageSubject = BehaviorSubject<String>.seeded('Disconnected');
  
  // Performance streams
  final BehaviorSubject<double> _dataUpdateRateSubject = BehaviorSubject<double>.seeded(0.0);
  final BehaviorSubject<int> _packetCountSubject = BehaviorSubject<int>.seeded(0);
  
  // Error handling
  final PublishSubject<String> _errorSubject = PublishSubject<String>();
  
  // Combined data stream for dashboard
  late final Stream<DashboardData> _dashboardDataStream;
  
  // Update tracking
  DateTime? _lastUpdate;
  int _updateCount = 0;
  Timer? _rateCalculationTimer;

  BmsDataStream() {
    _initializeCombinedStreams();
    _startPerformanceTracking();
  }

  void _initializeCombinedStreams() {
    // Combine BMS data and cell voltages for dashboard
    _dashboardDataStream = Rx.combineLatest3(
      _bmsDataSubject.stream,
      _cellVoltagesSubject.stream,
      _connectionStateSubject.stream,
      (JbdBmsData? bmsData, List<double>? cellVoltages, bool isConnected) {
        return DashboardData(
          bmsData: bmsData,
          cellVoltages: cellVoltages ?? [],
          isConnected: isConnected,
          lastUpdate: DateTime.now(),
        );
      },
    ).distinct(); // Only emit when data actually changes
  }

  void _startPerformanceTracking() {
    _rateCalculationTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      double rate = _updateCount / 5.0; // Updates per second
      _dataUpdateRateSubject.add(rate);
      _updateCount = 0;
    });
  }

  // Getters for streams
  Stream<JbdBmsData?> get bmsDataStream => _bmsDataSubject.stream;
  Stream<List<double>?> get cellVoltagesStream => _cellVoltagesSubject.stream;
  Stream<bool> get connectionStateStream => _connectionStateSubject.stream;
  Stream<String> get statusMessageStream => _statusMessageSubject.stream;
  Stream<DashboardData> get dashboardDataStream => _dashboardDataStream;
  Stream<String> get errorStream => _errorSubject.stream;
  Stream<double> get dataUpdateRateStream => _dataUpdateRateSubject.stream;

  // Getters for latest values
  JbdBmsData? get latestBmsData => _bmsDataSubject.valueOrNull;
  List<double>? get latestCellVoltages => _cellVoltagesSubject.valueOrNull;
  bool get isConnected => _connectionStateSubject.value;
  String get statusMessage => _statusMessageSubject.value;
  double get currentUpdateRate => _dataUpdateRateSubject.value;

  // Data publishing methods
  void publishBmsData(JbdBmsData data) {
    debugPrint('[BMS_STREAM] 📊 Publishing BMS data: V=${data.totalVoltage}V, I=${data.current}A, SOC=${data.chargeLevel}%');
    _bmsDataSubject.add(data);
    _trackUpdate();
  }

  void publishCellVoltages(List<double> voltages) {
    debugPrint('[BMS_STREAM] 🔋 Publishing cell voltages: ${voltages.length} cells');
    _cellVoltagesSubject.add(voltages);
    _trackUpdate();
  }

  void publishConnectionState(bool isConnected) {
    debugPrint('[BMS_STREAM] 🔗 Connection state: $isConnected');
    _connectionStateSubject.add(isConnected);
    
    if (!isConnected) {
      // Clear data when disconnected
      _bmsDataSubject.add(null);
      _cellVoltagesSubject.add(null);
    }
  }

  void publishStatusMessage(String message) {
    debugPrint('[BMS_STREAM] 📝 Status: $message');
    _statusMessageSubject.add(message);
  }

  void publishError(String error) {
    debugPrint('[BMS_STREAM] ❌ Error: $error');
    _errorSubject.add(error);
  }

  void _trackUpdate() {
    _lastUpdate = DateTime.now();
    _updateCount++;
    _packetCountSubject.add(_packetCountSubject.value + 1);
  }

  // Utility methods for dashboard
  bool get hasValidData => latestBmsData != null;
  
  Duration? get timeSinceLastUpdate {
    if (_lastUpdate == null) return null;
    return DateTime.now().difference(_lastUpdate!);
  }

  // Performance metrics
  Map<String, dynamic> get performanceMetrics {
    return {
      'updateRate': currentUpdateRate,
      'totalPackets': _packetCountSubject.value,
      'lastUpdate': _lastUpdate?.toIso8601String(),
      'timeSinceUpdate': timeSinceLastUpdate?.inMilliseconds,
      'hasValidData': hasValidData,
    };
  }

  void printStats() {
    debugPrint('[BMS_STREAM] 📊 STREAM PERFORMANCE:');
    debugPrint('[BMS_STREAM] Update rate: ${currentUpdateRate.toStringAsFixed(2)} Hz');
    debugPrint('[BMS_STREAM] Total packets: ${_packetCountSubject.value}');
    debugPrint('[BMS_STREAM] Time since last update: ${timeSinceLastUpdate?.inMilliseconds ?? 'N/A'}ms');
    debugPrint('[BMS_STREAM] Has valid data: $hasValidData');
    debugPrint('[BMS_STREAM] Connection state: $isConnected');
  }

  void dispose() {
    _rateCalculationTimer?.cancel();
    _bmsDataSubject.close();
    _cellVoltagesSubject.close();
    _connectionStateSubject.close();
    _statusMessageSubject.close();
    _dataUpdateRateSubject.close();
    _packetCountSubject.close();
    _errorSubject.close();
  }
}

class DashboardData {
  final JbdBmsData? bmsData;
  final List<double> cellVoltages;
  final bool isConnected;
  final DateTime lastUpdate;

  DashboardData({
    required this.bmsData,
    required this.cellVoltages,
    required this.isConnected,
    required this.lastUpdate,
  });

  bool get hasValidData => bmsData != null;
  
  double get maxCellVoltage => cellVoltages.isEmpty ? 0.0 : cellVoltages.reduce((a, b) => a > b ? a : b);
  double get minCellVoltage => cellVoltages.isEmpty ? 0.0 : cellVoltages.reduce((a, b) => a < b ? a : b);
  double get cellVoltageDiff => maxCellVoltage - minCellVoltage;
  double get avgCellVoltage => cellVoltages.isEmpty ? 0.0 : cellVoltages.reduce((a, b) => a + b) / cellVoltages.length;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is DashboardData &&
        other.bmsData == bmsData &&
        other.cellVoltages.length == cellVoltages.length &&
        other.isConnected == isConnected;
  }

  @override
  int get hashCode {
    return Object.hash(bmsData, cellVoltages.length, isConnected);
  }

  @override
  String toString() {
    return 'DashboardData(hasData: $hasValidData, cells: ${cellVoltages.length}, connected: $isConnected)';
  }
}