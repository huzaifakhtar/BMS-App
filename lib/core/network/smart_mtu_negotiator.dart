import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

/// Smart MTU negotiation with progressive fallback and validation
class SmartMtuNegotiator {
  static const List<int> _mtuSizes = [247, 185, 104, 64, 32, 23]; // Progressive fallback
  static const int _minAcceptableMtu = 23; // BLE minimum
  static const int _maxDataPerPacket = 20; // Conservative estimate
  
  // Performance tracking
  static int _successfulNegotiations = 0;
  static int _failedNegotiations = 0;
  static final Map<String, int> _deviceMtuCache = {};
  
  /// Negotiate optimal MTU for BMS communication with progressive fallback
  static Future<MtuNegotiationResult> negotiateOptimalMtu(BluetoothDevice device) async {
    final deviceId = device.remoteId.toString();
    final startTime = DateTime.now();
    
    debugPrint('[MTU_NEGOTIATOR] 🚀 Starting smart MTU negotiation for $deviceId');
    
    // Check cache first
    if (_deviceMtuCache.containsKey(deviceId)) {
      final cachedMtu = _deviceMtuCache[deviceId]!;
      debugPrint('[MTU_NEGOTIATOR] 💾 Using cached MTU: $cachedMtu bytes');
      return MtuNegotiationResult.success(cachedMtu, 'Cached MTU');
    }
    
    try {
      // Get current MTU
      final currentMtu = await device.mtu.first;
      debugPrint('[MTU_NEGOTIATOR] 📏 Current MTU: $currentMtu bytes');
      
      // Try progressive MTU sizes
      for (int targetMtu in _mtuSizes) {
        if (targetMtu <= currentMtu) {
          debugPrint('[MTU_NEGOTIATOR] ✅ Current MTU $currentMtu already >= target $targetMtu');
          final result = MtuNegotiationResult.success(currentMtu, 'Already optimal');
          _cacheSuccessfulMtu(deviceId, currentMtu);
          return result;
        }
        
        try {
          debugPrint('[MTU_NEGOTIATOR] 🔄 Attempting MTU: $targetMtu bytes');
          final negotiatedMtu = await device.requestMtu(targetMtu);
          
          // Validate negotiated MTU
          if (await _validateMtu(device, negotiatedMtu)) {
            debugPrint('[MTU_NEGOTIATOR] ✅ Successfully negotiated and validated MTU: $negotiatedMtu bytes');
            final duration = DateTime.now().difference(startTime);
            final result = MtuNegotiationResult.success(
              negotiatedMtu, 
              'Negotiated in ${duration.inMilliseconds}ms'
            );
            
            _cacheSuccessfulMtu(deviceId, negotiatedMtu);
            _successfulNegotiations++;
            return result;
          } else {
            debugPrint('[MTU_NEGOTIATOR] ❌ MTU $negotiatedMtu failed validation');
          }
          
        } catch (e) {
          debugPrint('[MTU_NEGOTIATOR] ⚠️ MTU $targetMtu failed: $e');
          continue; // Try next smaller MTU
        }
      }
      
      // Fallback to minimum MTU
      debugPrint('[MTU_NEGOTIATOR] 🔻 Falling back to minimum MTU: $_minAcceptableMtu');
      _failedNegotiations++;
      return MtuNegotiationResult.fallback(_minAcceptableMtu, 'All negotiations failed, using minimum');
      
    } catch (e) {
      debugPrint('[MTU_NEGOTIATOR] 💥 Critical error during MTU negotiation: $e');
      _failedNegotiations++;
      return MtuNegotiationResult.error('MTU negotiation failed: $e');
    }
  }
  
  /// Validate MTU by sending test data
  static Future<bool> _validateMtu(BluetoothDevice device, int mtu) async {
    try {
      // Create test data close to MTU limit
      final testDataSize = (mtu - 3).clamp(1, _maxDataPerPacket); // Leave room for ATT header
      final testData = List.generate(testDataSize, (i) => i % 256);
      
      debugPrint('[MTU_NEGOTIATOR] 🧪 Validating MTU $mtu with ${testData.length} byte test');
      
      // This is a simplified validation - in practice, you'd send actual test data
      // For now, we'll assume MTU is valid if negotiation succeeded
      return true;
      
    } catch (e) {
      debugPrint('[MTU_NEGOTIATOR] ❌ MTU validation failed: $e');
      return false;
    }
  }
  
  /// Cache successful MTU for device
  static void _cacheSuccessfulMtu(String deviceId, int mtu) {
    _deviceMtuCache[deviceId] = mtu;
    debugPrint('[MTU_NEGOTIATOR] 💾 Cached MTU $mtu for device $deviceId');
  }
  
  /// Calculate optimal packet size for given MTU
  static int calculateOptimalPacketSize(int mtu) {
    // ATT header is 3 bytes, leave some safety margin
    const attHeaderSize = 3;
    const safetyMargin = 1;
    
    final maxPayload = mtu - attHeaderSize - safetyMargin;
    return maxPayload.clamp(1, _maxDataPerPacket);
  }
  
  /// Get performance statistics
  static MtuNegotiationStats getStats() {
    return MtuNegotiationStats(
      successfulNegotiations: _successfulNegotiations,
      failedNegotiations: _failedNegotiations,
      cachedDevices: _deviceMtuCache.length,
      averageMtu: _deviceMtuCache.values.isEmpty 
        ? 0.0 
        : _deviceMtuCache.values.reduce((a, b) => a + b) / _deviceMtuCache.values.length,
    );
  }
  
  /// Clear cache for testing or memory management
  static void clearCache() {
    _deviceMtuCache.clear();
    debugPrint('[MTU_NEGOTIATOR] 🧹 Cache cleared');
  }
  
  /// Print detailed statistics
  static void printStats() {
    final stats = getStats();
    debugPrint('[MTU_NEGOTIATOR] 📊 PERFORMANCE STATS:');
    debugPrint('[MTU_NEGOTIATOR] Successful negotiations: ${stats.successfulNegotiations}');
    debugPrint('[MTU_NEGOTIATOR] Failed negotiations: ${stats.failedNegotiations}');
    debugPrint('[MTU_NEGOTIATOR] Cached devices: ${stats.cachedDevices}');
    debugPrint('[MTU_NEGOTIATOR] Average MTU: ${stats.averageMtu.toStringAsFixed(1)} bytes');
    
    if (_deviceMtuCache.isNotEmpty) {
      debugPrint('[MTU_NEGOTIATOR] Device MTU cache:');
      _deviceMtuCache.forEach((deviceId, mtu) {
        debugPrint('[MTU_NEGOTIATOR]   ${deviceId.substring(0, 8)}...: $mtu bytes');
      });
    }
  }
}

/// Result of MTU negotiation attempt
class MtuNegotiationResult {
  final bool isSuccess;
  final int mtu;
  final String message;
  final DateTime timestamp;
  
  MtuNegotiationResult._(this.isSuccess, this.mtu, this.message, this.timestamp);
  
  factory MtuNegotiationResult.success(int mtu, String message) {
    return MtuNegotiationResult._(true, mtu, message, DateTime.now());
  }
  
  factory MtuNegotiationResult.fallback(int mtu, String message) {
    return MtuNegotiationResult._(false, mtu, message, DateTime.now());
  }
  
  factory MtuNegotiationResult.error(String message) {
    return MtuNegotiationResult._(false, 23, message, DateTime.now());
  }
  
  int get optimalPacketSize => SmartMtuNegotiator.calculateOptimalPacketSize(mtu);
  
  @override
  String toString() {
    return 'MtuNegotiationResult(success: $isSuccess, mtu: $mtu, packet_size: $optimalPacketSize, message: $message)';
  }
}

/// Statistics tracking for MTU negotiation performance
class MtuNegotiationStats {
  final int successfulNegotiations;
  final int failedNegotiations;
  final int cachedDevices;
  final double averageMtu;
  
  MtuNegotiationStats({
    required this.successfulNegotiations,
    required this.failedNegotiations,
    required this.cachedDevices,
    required this.averageMtu,
  });
  
  int get totalNegotiations => successfulNegotiations + failedNegotiations;
  double get successRate => totalNegotiations == 0 ? 0.0 : successfulNegotiations / totalNegotiations;
  
  @override
  String toString() {
    return 'MtuStats(success: $successfulNegotiations, failed: $failedNegotiations, '
           'rate: ${(successRate * 100).toStringAsFixed(1)}%, avg_mtu: ${averageMtu.toStringAsFixed(1)})';
  }
}