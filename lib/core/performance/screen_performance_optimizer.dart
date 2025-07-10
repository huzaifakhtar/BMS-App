import 'package:flutter/foundation.dart';
import 'dart:async';

/// Screen-level performance optimizations
/// Reduces setState calls, optimizes data processing, and eliminates performance bottlenecks
class ScreenPerformanceOptimizer {
  
  /// Batch state updates to reduce flutter rebuilds
  static void batchStateUpdate(
    void Function(void Function()) setState,
    List<void Function()> updates,
  ) {
    // Apply all updates in a single setState call
    setState(() {
      for (final update in updates) {
        update();
      }
    });
  }
  
  /// Debounced state updates to prevent excessive rebuilds
  static Timer? _debounceTimer;
  static void debouncedStateUpdate(
    void Function(void Function()) setState,
    void Function() update, {
    Duration delay = const Duration(milliseconds: 50),
  }) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(delay, () {
      setState(update);
    });
  }
  
  /// Optimized timeout durations based on operation type
  static Duration getOptimalTimeout(String operationType, {int? register}) {
    switch (operationType) {
      case 'function_bits':
        return const Duration(milliseconds: 300);
      case 'cell_protection':
        return const Duration(milliseconds: 400);
      case 'total_voltage':
        return const Duration(milliseconds: 500);
      case 'text_data':
        return const Duration(milliseconds: 600);
      case 'hardware_protection':
        return const Duration(milliseconds: 400);
      case 'factory_mode':
        return const Duration(milliseconds: 200);
      default:
        return const Duration(milliseconds: 500);
    }
  }
  
  /// Memory-efficient value conversion utilities
  static String convertMvToDisplay(int rawValue, {bool is10mV = false}) {
    if (is10mV) {
      return (rawValue * 10).toString();
    }
    return rawValue.toString();
  }
  
  static int convertDisplayToMv(String displayValue, {bool is10mV = false}) {
    final intValue = int.tryParse(displayValue) ?? 0;
    if (is10mV) {
      return (intValue / 10).round();
    }
    return intValue;
  }
  
  /// Efficient register range checks
  static bool isTotalVoltageRegister(int register) {
    return register >= 0x20 && register <= 0x23;
  }
  
  static bool isCellProtectionRegister(int register) {
    return register >= 0x24 && register <= 0x27;
  }
  
  static bool isHardwareProtectionRegister(int register) {
    return register == 0x36 || register == 0x37;
  }
  
  /// Pre-compiled parameter key mappings for fast lookup
  static const Map<int, String> _registerToParameterKey = {
    // Cell protection
    0x24: 'cellHighVoltProtect',
    0x25: 'cellHighVoltRecover', 
    0x26: 'cellLowVoltProtect',
    0x27: 'cellLowVoltRecover',
    
    // Total voltage
    0x20: 'totalVoltHighProtect',
    0x21: 'totalVoltHighRecover',
    0x22: 'totalVoltLowProtect', 
    0x23: 'totalVoltLowRecover',
    
    // Hardware protection
    0x36: 'hwCellHighVoltProtect',
    0x37: 'hwCellLowVoltProtect',
    
    // Balance settings
    0x2A: 'balanceStartVoltage',
    0x2B: 'balanceAccuracy',
    
    // Origin settings
    0x10: 'nominalCapacity',
    0x11: 'cycleCapacity',
    0x03: 'fullChargeCapacity',
    0x2F: 'cellNumber',
  };
  
  static String? getParameterKey(int register) {
    return _registerToParameterKey[register];
  }
  
  /// Performance monitoring utilities
  static final Map<String, List<int>> _performanceMetrics = {};
  static final Map<String, Stopwatch> _activeStopwatches = {};
  
  static void startTiming(String operation) {
    if (kDebugMode) {
      final stopwatch = Stopwatch()..start();
      _activeStopwatches[operation] = stopwatch;
    }
  }
  
  static void endTiming(String operation) {
    if (kDebugMode) {
      final stopwatch = _activeStopwatches.remove(operation);
      if (stopwatch != null) {
        stopwatch.stop();
        final duration = stopwatch.elapsedMicroseconds;
        
        _performanceMetrics.putIfAbsent(operation, () => <int>[]);
        _performanceMetrics[operation]!.add(duration);
        
        // Report if operation is consistently slow
        final metrics = _performanceMetrics[operation]!;
        if (metrics.length >= 5) {
          final avg = metrics.reduce((a, b) => a + b) / metrics.length;
          final max = metrics.reduce((a, b) => a > b ? a : b);
          
          if (avg > 10000 || max > 50000) { // 10ms avg or 50ms max
            debugPrint('[PERFORMANCE] ⚠️ Slow operation: $operation - Avg: ${(avg/1000).toStringAsFixed(1)}ms, Max: ${(max/1000).toStringAsFixed(1)}ms');
          }
          
          // Keep only recent metrics
          if (metrics.length > 10) {
            metrics.removeRange(0, metrics.length - 10);
          }
        }
      }
    }
  }
  
  /// Efficient error message caching
  static const Map<String, String> _commonErrors = {
    'not_connected': 'Device not connected',
    'empty_value': 'Please enter a value',
    'invalid_range': 'Value out of valid range',
    'write_failed': 'Failed to write parameter',
    'timeout': 'Operation timed out',
    'invalid_response': 'Invalid response from device',
  };
  
  static String getErrorMessage(String errorKey, [String? customMessage]) {
    return customMessage ?? _commonErrors[errorKey] ?? 'Unknown error';
  }
}

/// Factory mode optimization singleton
class FactoryModeOptimizer {
  static bool _isInFactoryMode = false;
  static DateTime? _lastFactoryModeTime;
  static const Duration _factoryModeTimeout = Duration(minutes: 5);
  
  /// Check if factory mode is still active
  static bool get isActive {
    if (!_isInFactoryMode || _lastFactoryModeTime == null) return false;
    
    final elapsed = DateTime.now().difference(_lastFactoryModeTime!);
    if (elapsed > _factoryModeTimeout) {
      _isInFactoryMode = false;
      return false;
    }
    
    return true;
  }
  
  /// Mark factory mode as active
  static void markActive() {
    _isInFactoryMode = true;
    _lastFactoryModeTime = DateTime.now();
  }
  
  /// Force factory mode refresh
  static void forceRefresh() {
    _isInFactoryMode = false;
    _lastFactoryModeTime = null;
  }
  
  /// Get optimal factory mode command
  static List<int> getFactoryModeCommand() {
    return const [0xDD, 0x5A, 0x00, 0x02, 0x56, 0x78, 0xFF, 0x30, 0x77];
  }
}