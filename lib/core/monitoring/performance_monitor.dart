import 'dart:async';
import 'dart:math';
import 'dart:collection';
import 'package:flutter/foundation.dart';

/// Performance monitoring system for BMS operations
class PerformanceMonitor {
  static final PerformanceMonitor _instance = PerformanceMonitor._internal();
  factory PerformanceMonitor() => _instance;
  PerformanceMonitor._internal();
  
  final Map<String, OperationMetrics> _operationMetrics = {};
  final List<PerformanceEvent> _recentEvents = [];
  final int _maxRecentEvents = 100;
  Timer? _reportingTimer;
  
  /// Start monitoring with periodic reporting
  void startMonitoring({Duration reportInterval = const Duration(minutes: 5)}) {
    _reportingTimer?.cancel();
    _reportingTimer = Timer.periodic(reportInterval, (_) => _generatePerformanceReport());
    debugPrint('[PERFORMANCE_MONITOR] 🚀 Started monitoring with ${reportInterval.inMinutes}min intervals');
  }
  
  /// Stop monitoring
  void stopMonitoring() {
    _reportingTimer?.cancel();
    _reportingTimer = null;
    debugPrint('[PERFORMANCE_MONITOR] 🛑 Stopped monitoring');
  }
  
  /// Record operation start
  OperationTracker trackOperation(String operationName, {Map<String, dynamic>? metadata}) {
    return OperationTracker(operationName, this, metadata: metadata);
  }
  
  /// Record completed operation
  void recordOperation(String operationName, Duration duration, bool success, {
    String? errorMessage,
    Map<String, dynamic>? metadata,
  }) {
    // Update operation metrics
    final metrics = _operationMetrics.putIfAbsent(
      operationName, 
      () => OperationMetrics(operationName),
    );
    
    metrics.recordOperation(duration, success, errorMessage: errorMessage);
    
    // Add to recent events
    final event = PerformanceEvent(
      operationName: operationName,
      duration: duration,
      success: success,
      timestamp: DateTime.now(),
      errorMessage: errorMessage,
      metadata: metadata,
    );
    
    _recentEvents.add(event);
    if (_recentEvents.length > _maxRecentEvents) {
      _recentEvents.removeAt(0);
    }
    
    // Log slow operations
    if (duration > const Duration(seconds: 5)) {
      debugPrint('[PERFORMANCE_MONITOR] 🐌 Slow operation: $operationName took ${duration.inMilliseconds}ms');
    }
    
    // Log failures
    if (!success) {
      debugPrint('[PERFORMANCE_MONITOR] ❌ Failed operation: $operationName - $errorMessage');
    }
  }
  
  /// Get metrics for specific operation
  OperationMetrics? getOperationMetrics(String operationName) {
    return _operationMetrics[operationName];
  }
  
  /// Get all operation metrics
  Map<String, OperationMetrics> getAllMetrics() {
    return UnmodifiableMapView(_operationMetrics);
  }
  
  /// Get recent events
  List<PerformanceEvent> getRecentEvents({int? limit}) {
    final events = List<PerformanceEvent>.from(_recentEvents.reversed);
    return limit != null ? events.take(limit).toList() : events;
  }
  
  /// Generate performance report
  void _generatePerformanceReport() {
    debugPrint('[PERFORMANCE_MONITOR] 📊 PERFORMANCE REPORT:');
    debugPrint('[PERFORMANCE_MONITOR] Total operations tracked: ${_operationMetrics.length}');
    debugPrint('[PERFORMANCE_MONITOR] Recent events: ${_recentEvents.length}');
    
    // Sort operations by total count
    final sortedOps = _operationMetrics.values.toList()
      ..sort((a, b) => b.totalCount.compareTo(a.totalCount));
    
    for (final metrics in sortedOps.take(5)) {
      debugPrint('[PERFORMANCE_MONITOR] ${metrics.operationName}:');
      debugPrint('[PERFORMANCE_MONITOR]   Total: ${metrics.totalCount}, Success: ${(metrics.successRate * 100).toStringAsFixed(1)}%');
      debugPrint('[PERFORMANCE_MONITOR]   Avg: ${metrics.averageDuration.inMilliseconds}ms, Max: ${metrics.maxDuration.inMilliseconds}ms');
    }
    
    // Check for performance issues
    _detectPerformanceIssues();
  }
  
  /// Detect performance issues
  void _detectPerformanceIssues() {
    final issues = <String>[];
    
    for (final metrics in _operationMetrics.values) {
      // Check for high failure rate
      if (metrics.successRate < 0.8 && metrics.totalCount > 5) {
        issues.add('${metrics.operationName}: High failure rate ${(metrics.successRate * 100).toStringAsFixed(1)}%');
      }
      
      // Check for slow operations
      if (metrics.averageDuration > const Duration(seconds: 3)) {
        issues.add('${metrics.operationName}: Slow average response ${metrics.averageDuration.inMilliseconds}ms');
      }
      
      // Check for inconsistent performance
      if (metrics.standardDeviation > metrics.averageDuration.inMilliseconds * 0.5) {
        issues.add('${metrics.operationName}: Inconsistent performance (high std dev)');
      }
    }
    
    if (issues.isNotEmpty) {
      debugPrint('[PERFORMANCE_MONITOR] ⚠️ PERFORMANCE ISSUES DETECTED:');
      for (final issue in issues) {
        debugPrint('[PERFORMANCE_MONITOR]   - $issue');
      }
    }
  }
  
  /// Get performance summary
  PerformanceSummary getSummary() {
    final totalOperations = _operationMetrics.values.fold(0, (sum, m) => sum + m.totalCount);
    final totalSuccesses = _operationMetrics.values.fold(0, (sum, m) => sum + m.successCount);
    final totalFailures = _operationMetrics.values.fold(0, (sum, m) => sum + m.failureCount);
    
    final avgDurations = _operationMetrics.values.map((m) => m.averageDuration.inMilliseconds).toList();
    final overallAvgDuration = avgDurations.isEmpty ? 0.0 : avgDurations.reduce((a, b) => a + b) / avgDurations.length;
    
    return PerformanceSummary(
      totalOperations: totalOperations,
      successfulOperations: totalSuccesses,
      failedOperations: totalFailures,
      averageDurationMs: overallAvgDuration,
      operationTypes: _operationMetrics.length,
      recentEvents: _recentEvents.length,
    );
  }
  
  /// Clear all metrics and events
  void clear() {
    _operationMetrics.clear();
    _recentEvents.clear();
    debugPrint('[PERFORMANCE_MONITOR] 🧹 Cleared all metrics and events');
  }
  
  /// Export metrics to JSON-like structure for debugging
  Map<String, dynamic> exportMetrics() {
    return {
      'summary': getSummary().toMap(),
      'operations': _operationMetrics.map((name, metrics) => MapEntry(name, metrics.toMap())),
      'recent_events': _recentEvents.map((e) => e.toMap()).toList(),
    };
  }
}

/// Tracks individual operation performance
class OperationTracker {
  final String operationName;
  final PerformanceMonitor monitor;
  final DateTime startTime;
  final Map<String, dynamic>? metadata;
  bool _completed = false;
  
  OperationTracker(this.operationName, this.monitor, {this.metadata}) 
      : startTime = DateTime.now();
  
  /// Mark operation as completed successfully
  void complete({Map<String, dynamic>? additionalMetadata}) {
    if (_completed) return;
    _completed = true;
    
    final duration = DateTime.now().difference(startTime);
    final combinedMetadata = {...?metadata, ...?additionalMetadata};
    
    monitor.recordOperation(
      operationName, 
      duration, 
      true, 
      metadata: combinedMetadata.isEmpty ? null : combinedMetadata,
    );
  }
  
  /// Mark operation as failed
  void fail(String errorMessage, {Map<String, dynamic>? additionalMetadata}) {
    if (_completed) return;
    _completed = true;
    
    final duration = DateTime.now().difference(startTime);
    final combinedMetadata = {...?metadata, ...?additionalMetadata};
    
    monitor.recordOperation(
      operationName, 
      duration, 
      false, 
      errorMessage: errorMessage,
      metadata: combinedMetadata.isEmpty ? null : combinedMetadata,
    );
  }
  
  /// Get elapsed time
  Duration get elapsed => DateTime.now().difference(startTime);
}

/// Metrics for a specific operation type
class OperationMetrics {
  final String operationName;
  int totalCount = 0;
  int successCount = 0;
  int failureCount = 0;
  Duration totalDuration = const Duration();
  Duration minDuration = const Duration(days: 1);
  Duration maxDuration = Duration.zero;
  final List<int> _durations = [];
  final List<String> _recentErrors = [];
  final int _maxRecentErrors = 10;
  
  OperationMetrics(this.operationName);
  
  void recordOperation(Duration duration, bool success, {String? errorMessage}) {
    totalCount++;
    totalDuration += duration;
    
    if (duration < minDuration) minDuration = duration;
    if (duration > maxDuration) maxDuration = duration;
    
    _durations.add(duration.inMilliseconds);
    if (_durations.length > 100) _durations.removeAt(0); // Keep last 100
    
    if (success) {
      successCount++;
    } else {
      failureCount++;
      if (errorMessage != null) {
        _recentErrors.add(errorMessage);
        if (_recentErrors.length > _maxRecentErrors) {
          _recentErrors.removeAt(0);
        }
      }
    }
  }
  
  double get successRate => totalCount == 0 ? 0.0 : successCount / totalCount;
  double get failureRate => totalCount == 0 ? 0.0 : failureCount / totalCount;
  Duration get averageDuration => totalCount == 0 ? Duration.zero : Duration(milliseconds: totalDuration.inMilliseconds ~/ totalCount);
  
  double get standardDeviation {
    if (_durations.length < 2) return 0.0;
    
    final mean = _durations.reduce((a, b) => a + b) / _durations.length;
    final variance = _durations.map((d) => (d - mean) * (d - mean)).reduce((a, b) => a + b) / _durations.length;
    return sqrt(variance);
  }
  
  List<String> get recentErrors => UnmodifiableListView(_recentErrors);
  
  Map<String, dynamic> toMap() {
    return {
      'operation_name': operationName,
      'total_count': totalCount,
      'success_count': successCount,
      'failure_count': failureCount,
      'success_rate': successRate,
      'average_duration_ms': averageDuration.inMilliseconds,
      'min_duration_ms': minDuration.inMilliseconds,
      'max_duration_ms': maxDuration.inMilliseconds,
      'standard_deviation_ms': standardDeviation,
      'recent_errors': _recentErrors,
    };
  }
}

/// Individual performance event
class PerformanceEvent {
  final String operationName;
  final Duration duration;
  final bool success;
  final DateTime timestamp;
  final String? errorMessage;
  final Map<String, dynamic>? metadata;
  
  PerformanceEvent({
    required this.operationName,
    required this.duration,
    required this.success,
    required this.timestamp,
    this.errorMessage,
    this.metadata,
  });
  
  Map<String, dynamic> toMap() {
    return {
      'operation_name': operationName,
      'duration_ms': duration.inMilliseconds,
      'success': success,
      'timestamp': timestamp.toIso8601String(),
      'error_message': errorMessage,
      'metadata': metadata,
    };
  }
}

/// Overall performance summary
class PerformanceSummary {
  final int totalOperations;
  final int successfulOperations;
  final int failedOperations;
  final double averageDurationMs;
  final int operationTypes;
  final int recentEvents;
  
  PerformanceSummary({
    required this.totalOperations,
    required this.successfulOperations,
    required this.failedOperations,
    required this.averageDurationMs,
    required this.operationTypes,
    required this.recentEvents,
  });
  
  double get successRate => totalOperations == 0 ? 0.0 : successfulOperations / totalOperations;
  double get failureRate => totalOperations == 0 ? 0.0 : failedOperations / totalOperations;
  
  Map<String, dynamic> toMap() {
    return {
      'total_operations': totalOperations,
      'successful_operations': successfulOperations,
      'failed_operations': failedOperations,
      'success_rate': successRate,
      'failure_rate': failureRate,
      'average_duration_ms': averageDurationMs,
      'operation_types': operationTypes,
      'recent_events': recentEvents,
    };
  }
  
  @override
  String toString() {
    return 'PerformanceSummary(total: $totalOperations, success: ${(successRate * 100).toStringAsFixed(1)}%, avg: ${averageDurationMs.toStringAsFixed(1)}ms)';
  }
}