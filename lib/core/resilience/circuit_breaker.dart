import 'package:flutter/foundation.dart';

/// Circuit breaker states
enum CircuitBreakerState { closed, open, halfOpen }

/// Circuit breaker for BLE operations to prevent cascade failures
class CircuitBreaker {
  final String name;
  final int failureThreshold;
  final Duration timeout;
  final Duration resetTimeout;
  
  CircuitBreakerState _state = CircuitBreakerState.closed;
  int _failureCount = 0;
  DateTime? _lastFailureTime;
  DateTime? _nextAttemptTime;
  
  // Statistics
  int _totalCalls = 0;
  int _successfulCalls = 0;
  int _failedCalls = 0;
  int _rejectedCalls = 0;
  
  CircuitBreaker({
    required this.name,
    this.failureThreshold = 5,
    this.timeout = const Duration(seconds: 30),
    this.resetTimeout = const Duration(seconds: 60),
  });
  
  /// Execute operation through circuit breaker
  Future<T> execute<T>(Future<T> Function() operation) async {
    _totalCalls++;
    
    // Check if circuit is open
    if (_state == CircuitBreakerState.open) {
      if (_shouldAttemptReset()) {
        _state = CircuitBreakerState.halfOpen;
        debugPrint('[CIRCUIT_BREAKER] $name: Transitioning to HALF_OPEN state');
      } else {
        _rejectedCalls++;
        debugPrint('[CIRCUIT_BREAKER] $name: Call rejected - circuit is OPEN');
        throw CircuitBreakerException('Circuit breaker is OPEN for $name');
      }
    }
    
    try {
      debugPrint('[CIRCUIT_BREAKER] $name: Executing operation (state: ${_state.name})');
      final result = await operation();
      
      // Success - reset failure count
      _onSuccess();
      return result;
      
    } catch (e) {
      // Operation failed
      _onFailure();
      rethrow;
    }
  }
  
  /// Handle successful operation
  void _onSuccess() {
    _successfulCalls++;
    _failureCount = 0;
    _lastFailureTime = null;
    
    if (_state == CircuitBreakerState.halfOpen) {
      _state = CircuitBreakerState.closed;
      debugPrint('[CIRCUIT_BREAKER] $name: Success in HALF_OPEN - closing circuit');
    }
    
    debugPrint('[CIRCUIT_BREAKER] $name: Operation successful (failures reset)');
  }
  
  /// Handle failed operation
  void _onFailure() {
    _failedCalls++;
    _failureCount++;
    _lastFailureTime = DateTime.now();
    
    debugPrint('[CIRCUIT_BREAKER] $name: Operation failed (failure count: $_failureCount/$failureThreshold)');
    
    if (_failureCount >= failureThreshold) {
      _state = CircuitBreakerState.open;
      _nextAttemptTime = DateTime.now().add(resetTimeout);
      
      debugPrint('[CIRCUIT_BREAKER] $name: Circuit OPENED due to failures. Next attempt at: $_nextAttemptTime');
    }
  }
  
  /// Check if we should attempt to reset the circuit breaker
  bool _shouldAttemptReset() {
    if (_nextAttemptTime == null) return false;
    return DateTime.now().isAfter(_nextAttemptTime!);
  }
  
  /// Force circuit breaker to closed state
  void reset() {
    _state = CircuitBreakerState.closed;
    _failureCount = 0;
    _lastFailureTime = null;
    _nextAttemptTime = null;
    debugPrint('[CIRCUIT_BREAKER] $name: Manually reset to CLOSED state');
  }
  
  /// Force circuit breaker to open state
  void forceOpen() {
    _state = CircuitBreakerState.open;
    _nextAttemptTime = DateTime.now().add(resetTimeout);
    debugPrint('[CIRCUIT_BREAKER] $name: Manually forced to OPEN state');
  }
  
  // Getters
  CircuitBreakerState get state => _state;
  int get failureCount => _failureCount;
  DateTime? get lastFailureTime => _lastFailureTime;
  DateTime? get nextAttemptTime => _nextAttemptTime;
  bool get isOpen => _state == CircuitBreakerState.open;
  bool get isClosed => _state == CircuitBreakerState.closed;
  bool get isHalfOpen => _state == CircuitBreakerState.halfOpen;
  
  /// Get circuit breaker statistics
  CircuitBreakerStats get stats => CircuitBreakerStats(
    name: name,
    state: _state,
    totalCalls: _totalCalls,
    successfulCalls: _successfulCalls,
    failedCalls: _failedCalls,
    rejectedCalls: _rejectedCalls,
    failureCount: _failureCount,
    lastFailureTime: _lastFailureTime,
    nextAttemptTime: _nextAttemptTime,
  );
  
  /// Print detailed statistics
  void printStats() {
    final successRate = _totalCalls == 0 ? 0.0 : _successfulCalls / _totalCalls;
    final failureRate = _totalCalls == 0 ? 0.0 : _failedCalls / _totalCalls;
    final rejectionRate = _totalCalls == 0 ? 0.0 : _rejectedCalls / _totalCalls;
    
    debugPrint('[CIRCUIT_BREAKER] 📊 STATS for $name:');
    debugPrint('[CIRCUIT_BREAKER] State: ${_state.name}');
    debugPrint('[CIRCUIT_BREAKER] Total calls: $_totalCalls');
    debugPrint('[CIRCUIT_BREAKER] Successful: $_successfulCalls (${(successRate * 100).toStringAsFixed(1)}%)');
    debugPrint('[CIRCUIT_BREAKER] Failed: $_failedCalls (${(failureRate * 100).toStringAsFixed(1)}%)');
    debugPrint('[CIRCUIT_BREAKER] Rejected: $_rejectedCalls (${(rejectionRate * 100).toStringAsFixed(1)}%)');
    debugPrint('[CIRCUIT_BREAKER] Current failure count: $_failureCount/$failureThreshold');
    
    if (_lastFailureTime != null) {
      debugPrint('[CIRCUIT_BREAKER] Last failure: $_lastFailureTime');
    }
    
    if (_nextAttemptTime != null) {
      debugPrint('[CIRCUIT_BREAKER] Next attempt: $_nextAttemptTime');
    }
  }
  
  @override
  String toString() {
    return 'CircuitBreaker($name: ${_state.name}, failures: $_failureCount/$failureThreshold)';
  }
}

/// Exception thrown when circuit breaker is open
class CircuitBreakerException implements Exception {
  final String message;
  
  CircuitBreakerException(this.message);
  
  @override
  String toString() => 'CircuitBreakerException: $message';
}

/// Circuit breaker statistics
class CircuitBreakerStats {
  final String name;
  final CircuitBreakerState state;
  final int totalCalls;
  final int successfulCalls;
  final int failedCalls;
  final int rejectedCalls;
  final int failureCount;
  final DateTime? lastFailureTime;
  final DateTime? nextAttemptTime;
  
  CircuitBreakerStats({
    required this.name,
    required this.state,
    required this.totalCalls,
    required this.successfulCalls,
    required this.failedCalls,
    required this.rejectedCalls,
    required this.failureCount,
    this.lastFailureTime,
    this.nextAttemptTime,
  });
  
  double get successRate => totalCalls == 0 ? 0.0 : successfulCalls / totalCalls;
  double get failureRate => totalCalls == 0 ? 0.0 : failedCalls / totalCalls;
  double get rejectionRate => totalCalls == 0 ? 0.0 : rejectedCalls / totalCalls;
  
  @override
  String toString() {
    return 'CircuitBreakerStats($name: ${state.name}, '
           'calls: $totalCalls, success: ${(successRate * 100).toStringAsFixed(1)}%, '
           'failures: $failureCount)';
  }
}

/// Manager for multiple circuit breakers
class CircuitBreakerManager {
  static final Map<String, CircuitBreaker> _circuitBreakers = {};
  
  /// Get or create a circuit breaker
  static CircuitBreaker getCircuitBreaker(String name, {
    int failureThreshold = 5,
    Duration timeout = const Duration(seconds: 30),
    Duration resetTimeout = const Duration(seconds: 60),
  }) {
    return _circuitBreakers.putIfAbsent(name, () => CircuitBreaker(
      name: name,
      failureThreshold: failureThreshold,
      timeout: timeout,
      resetTimeout: resetTimeout,
    ));
  }
  
  /// Reset all circuit breakers
  static void resetAll() {
    for (final breaker in _circuitBreakers.values) {
      breaker.reset();
    }
    debugPrint('[CIRCUIT_BREAKER_MANAGER] All circuit breakers reset');
  }
  
  /// Print stats for all circuit breakers
  static void printAllStats() {
    debugPrint('[CIRCUIT_BREAKER_MANAGER] 📊 ALL CIRCUIT BREAKER STATS:');
    for (final breaker in _circuitBreakers.values) {
      breaker.printStats();
    }
  }
  
  /// Get all circuit breaker statistics
  static List<CircuitBreakerStats> getAllStats() {
    return _circuitBreakers.values.map((cb) => cb.stats).toList();
  }
  
  /// Get circuit breaker count by state
  static Map<CircuitBreakerState, int> getStateDistribution() {
    final distribution = <CircuitBreakerState, int>{
      CircuitBreakerState.closed: 0,
      CircuitBreakerState.open: 0,
      CircuitBreakerState.halfOpen: 0,
    };
    
    for (final breaker in _circuitBreakers.values) {
      distribution[breaker.state] = (distribution[breaker.state] ?? 0) + 1;
    }
    
    return distribution;
  }
}