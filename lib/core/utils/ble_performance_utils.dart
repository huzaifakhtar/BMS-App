import 'package:flutter/foundation.dart';
import 'dart:async';

/// High-performance BLE response handler utility
/// Optimized to minimize processing time and ensure consistent performance
class BlePerformanceUtils {
  
  /// Optimized BLE packet validation and parsing
  /// Returns null if packet is invalid, otherwise returns parsed data
  static BleResponse? parsePacket(List<int> data) {
    // Fast validation - check minimum length first
    final length = data.length;
    if (length < 7) return null;
    
    // Fast header/footer validation - avoid data.last lookup
    if (data[0] != 0xDD || data[length - 1] != 0x77) return null;
    
    // Extract response fields efficiently
    return BleResponse(
      register: data[1],
      status: data[2],
      dataLength: data[3],
      rawData: data,
    );
  }
  
  /// Optimized BLE data handler factory
  /// Creates consistent, high-performance handlers for all screens
  static void Function(List<int>) createHandler({
    required String screenName,
    required Completer<List<int>>? Function() getCompleter,
    required int Function() getExpectedRegister,
    required Timer? Function() getTimer,
    required void Function(Timer?) setTimer,
  }) {
    return (List<int> data) {
      final response = parsePacket(data);
      if (response == null) return;
      
      // Fast path: only process if we're waiting for a response
      final completer = getCompleter();
      if (completer != null && !completer.isCompleted) {
        // Check register match and success status in one condition
        if (response.register == getExpectedRegister() && response.status == 0x00) {
          completer.complete(data);
          final timer = getTimer();
          timer?.cancel();
          setTimer(null);
          
          // Minimal debug logging to reduce string operations
          if (kDebugMode) {
            debugPrint('[$screenName] ✅ Response completed for register 0x${response.register.toRadixString(16)}');
          }
        }
      }
    };
  }
  
  /// Pre-compiled constants for common operations
  static const int minPacketLength = 7;
  static const int headerByte = 0xDD;
  static const int footerByte = 0x77;
  static const int statusSuccess = 0x00;
  
  /// Fast timeout handler factory
  static Timer createTimeout({
    required Duration timeout,
    required Completer<List<int>> completer,
    required int expectedRegister,
    required String screenName,
  }) {
    return Timer(timeout, () {
      if (!completer.isCompleted) {
        if (kDebugMode) {
          debugPrint('[$screenName] ⏰ Response timeout for register 0x${expectedRegister.toRadixString(16)}');
        }
        completer.complete([]);
      }
    });
  }
  
  /// Optimized string parsing for text data
  static String parseTextData(List<int> data) {
    if (data.isEmpty) return 'Not Available';
    
    // Pre-calculate constants to avoid repeated operations
    const int minPrintable = 32;
    const int maxPrintable = 126;
    
    // Fast path: length-prefixed string (most common case)
    if (data.length > 1 && data[0] > 0 && data[0] < data.length) {
      final stringLength = data[0];
      final endIndex = 1 + stringLength;
      
      if (data.length >= endIndex) {
        final validChars = <int>[];
        for (int i = 1; i < endIndex; i++) {
          final byte = data[i];
          if (byte >= minPrintable && byte <= maxPrintable) {
            validChars.add(byte);
          }
        }
        
        if (validChars.isNotEmpty) {
          final result = String.fromCharCodes(validChars).trim();
          return result.isNotEmpty ? result : 'Not Available';
        }
      }
    }
    
    // Fallback: scan all bytes (less common case)
    final validChars = <int>[];
    final length = data.length;
    for (int i = 0; i < length; i++) {
      final byte = data[i];
      if (byte >= minPrintable && byte <= maxPrintable) {
        validChars.add(byte);
      }
    }
    
    if (validChars.isEmpty) return 'Not Available';
    
    final result = String.fromCharCodes(validChars).trim();
    return result.isNotEmpty ? result : 'Not Available';
  }
  
  /// Apply manufacturer-specific fixes efficiently
  static String applyManufacturerFix(String result) {
    // Cache the common prefix check to avoid repeated string operations
    if (result.length >= 10 && result.startsWith('Humaya Pow')) {
      return 'Humaya Power';
    }
    return result;
  }
}

/// Parsed BLE response data structure
class BleResponse {
  final int register;
  final int status;
  final int dataLength;
  final List<int> rawData;
  
  const BleResponse({
    required this.register,
    required this.status,
    required this.dataLength,
    required this.rawData,
  });
  
  /// Get response data payload efficiently
  List<int> getDataPayload() {
    if (rawData.length >= 4 + dataLength) {
      return rawData.sublist(4, 4 + dataLength);
    }
    return [];
  }
  
  /// Check if response is valid
  bool get isValid => status == BlePerformanceUtils.statusSuccess && 
                     rawData.length >= 4 + dataLength;
}