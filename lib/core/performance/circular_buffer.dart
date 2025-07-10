import 'package:flutter/foundation.dart';

/// High-performance circular buffer for BLE data processing
/// Provides O(1) operations for packet assembly
class CircularBuffer {
  late final List<int> _buffer;
  int _head = 0;
  int _tail = 0;
  int _size = 0;
  final int capacity;
  
  // Performance metrics
  int _totalBytesProcessed = 0;
  int _totalPacketsExtracted = 0;
  int _bufferOverflows = 0;
  DateTime? _lastActivity;

  CircularBuffer(this.capacity) {
    _buffer = List<int>.filled(capacity, 0);
    debugPrint('[CIRCULAR_BUFFER] 🚀 Initialized with capacity: $capacity bytes');
  }

  // Getters
  int get size => _size;
  int get availableSpace => capacity - _size;
  bool get isEmpty => _size == 0;
  bool get isFull => _size == capacity;
  double get utilization => _size / capacity;
  int get totalBytesProcessed => _totalBytesProcessed;
  int get totalPacketsExtracted => _totalPacketsExtracted;
  int get bufferOverflows => _bufferOverflows;

  /// Add multiple bytes efficiently - O(1) amortized
  void addAll(List<int> data) {
    if (data.isEmpty) return;
    
    _lastActivity = DateTime.now();
    _totalBytesProcessed += data.length;
    
    // Check for overflow
    if (data.length > availableSpace) {
      debugPrint('[CIRCULAR_BUFFER] ⚠️ Buffer overflow: need ${data.length}, have $availableSpace');
      _bufferOverflows++;
      
      // Remove old data to make space
      int bytesToRemove = data.length - availableSpace;
      _removeOldestBytes(bytesToRemove);
    }
    
    // Add data efficiently
    for (int byte in data) {
      _buffer[_head] = byte;
      _head = (_head + 1) % capacity;
      _size++;
    }
    
    debugPrint('[CIRCULAR_BUFFER] 📥 Added ${data.length} bytes (buffer: $_size/$capacity)');
  }

  /// Add single byte - O(1)
  void add(int byte) {
    _lastActivity = DateTime.now();
    _totalBytesProcessed++;
    
    if (isFull) {
      debugPrint('[CIRCULAR_BUFFER] ⚠️ Buffer full, removing oldest byte');
      _bufferOverflows++;
      _tail = (_tail + 1) % capacity;
      _size--;
    }
    
    _buffer[_head] = byte;
    _head = (_head + 1) % capacity;
    _size++;
  }

  /// Peek at byte without removing - O(1)
  int? peek(int offset) {
    if (offset >= _size) return null;
    int index = (_tail + offset) % capacity;
    return _buffer[index];
  }

  /// Get bytes without removing them - O(n) where n is length
  List<int> peekRange(int start, int length) {
    if (start >= _size || length <= 0) return [];
    
    int actualLength = (start + length > _size) ? _size - start : length;
    List<int> result = List<int>.filled(actualLength, 0);
    
    for (int i = 0; i < actualLength; i++) {
      int index = (_tail + start + i) % capacity;
      result[i] = _buffer[index];
    }
    
    return result;
  }

  /// Remove bytes from front - O(1)
  void removeBytes(int count) {
    if (count <= 0) return;
    
    int actualCount = (count > _size) ? _size : count;
    _tail = (_tail + actualCount) % capacity;
    _size -= actualCount;
    
    debugPrint('[CIRCULAR_BUFFER] 🗑️ Removed $actualCount bytes (buffer: $_size/$capacity)');
  }

  /// Remove oldest bytes to make space - O(1)
  void _removeOldestBytes(int count) {
    if (count <= 0) return;
    
    int actualCount = (count > _size) ? _size : count;
    _tail = (_tail + actualCount) % capacity;
    _size -= actualCount;
    
    debugPrint('[CIRCULAR_BUFFER] 🧹 Evicted $actualCount old bytes');
  }

  /// Find pattern in buffer - O(n) where n is buffer size
  int findPattern(List<int> pattern, [int startOffset = 0]) {
    if (pattern.isEmpty || startOffset >= _size) return -1;
    
    for (int i = startOffset; i <= _size - pattern.length; i++) {
      bool found = true;
      for (int j = 0; j < pattern.length; j++) {
        int index = (_tail + i + j) % capacity;
        if (_buffer[index] != pattern[j]) {
          found = false;
          break;
        }
      }
      if (found) return i;
    }
    
    return -1;
  }

  /// Find single byte - O(n) worst case, but optimized for start bytes
  int findByte(int byte, [int startOffset = 0]) {
    if (startOffset >= _size) return -1;
    
    for (int i = startOffset; i < _size; i++) {
      int index = (_tail + i) % capacity;
      if (_buffer[index] == byte) return i;
    }
    
    return -1;
  }

  /// Extract complete BMS packet if available - O(1) detection + O(n) extraction
  List<int>? tryExtractBmsPacket() {
    // Find start byte (0xDD) - O(n) worst case
    int startIndex = findByte(0xDD);
    if (startIndex == -1) {
      // No start byte, clear buffer if it's getting full
      if (_size > capacity * 0.8) {
        debugPrint('[CIRCULAR_BUFFER] 🧹 No start byte found, clearing buffer to prevent overflow');
        clear();
      }
      return null;
    }
    
    // Remove any junk data before start byte - O(1)
    if (startIndex > 0) {
      removeBytes(startIndex);
      debugPrint('[CIRCULAR_BUFFER] 🧹 Removed $startIndex junk bytes before packet start');
    }
    
    // Check if we have enough bytes for header (DD REG STATUS LENGTH) - O(1)
    if (_size < 4) {
      debugPrint('[CIRCULAR_BUFFER] ⏳ Waiting for header: have $_size bytes, need 4');
      return null;
    }
    
    // Get data length from packet - O(1)
    int? lengthByte = peek(3);
    if (lengthByte == null) return null;
    
    // Calculate total packet size: header(4) + data(length) + checksum(2) + end(1) - O(1)
    int totalPacketSize = 4 + lengthByte + 2 + 1;
    
    // Check if complete packet is available - O(1)
    if (_size < totalPacketSize) {
      debugPrint('[CIRCULAR_BUFFER] ⏳ Waiting for complete packet: have $_size bytes, need $totalPacketSize');
      return null;
    }
    
    // Verify end byte - O(1)
    int? endByte = peek(totalPacketSize - 1);
    if (endByte != 0x77) {
      debugPrint('[CIRCULAR_BUFFER] ❌ Invalid end byte: 0x${endByte?.toRadixString(16)}, removing corrupted data');
      removeBytes(1); // Remove invalid start byte and try again
      return null;
    }
    
    // Extract complete packet - O(n) where n is packet size
    List<int> packet = peekRange(0, totalPacketSize);
    removeBytes(totalPacketSize);
    
    _totalPacketsExtracted++;
    debugPrint('[CIRCULAR_BUFFER] ✅ Extracted complete packet: $totalPacketSize bytes (total packets: $_totalPacketsExtracted)');
    
    return packet;
  }

  /// Extract data range and remove it - O(n) where n is length
  List<int> extractRange(int start, int length) {
    List<int> data = peekRange(start, length);
    if (data.isNotEmpty) {
      removeBytes(start + data.length);
    }
    return data;
  }

  /// Clear all data - O(1)
  void clear() {
    _head = 0;
    _tail = 0;
    _size = 0;
    debugPrint('[CIRCULAR_BUFFER] 🧹 Buffer cleared');
  }

  /// Get all data without removing it - O(n)
  List<int> getAllData() {
    return peekRange(0, _size);
  }

  /// Performance statistics
  void printStats() {
    debugPrint('[CIRCULAR_BUFFER] 📊 PERFORMANCE STATS:');
    debugPrint('[CIRCULAR_BUFFER] Capacity: $capacity bytes');
    debugPrint('[CIRCULAR_BUFFER] Current size: $_size bytes (${(utilization * 100).toStringAsFixed(1)}%)');
    debugPrint('[CIRCULAR_BUFFER] Total bytes processed: $_totalBytesProcessed');
    debugPrint('[CIRCULAR_BUFFER] Total packets extracted: $_totalPacketsExtracted');
    debugPrint('[CIRCULAR_BUFFER] Buffer overflows: $_bufferOverflows');
    debugPrint('[CIRCULAR_BUFFER] Head: $_head, Tail: $_tail');
    debugPrint('[CIRCULAR_BUFFER] Last activity: $_lastActivity');
    
    if (_totalBytesProcessed > 0) {
      double efficiency = (_totalPacketsExtracted / (_totalBytesProcessed / 30)) * 100;
      debugPrint('[CIRCULAR_BUFFER] Extraction efficiency: ${efficiency.toStringAsFixed(1)}%');
    }
  }

  /// Get buffer visualization for debugging
  String getVisualization() {
    if (_size == 0) return 'Empty buffer';
    
    final sb = StringBuffer();
    sb.write('Buffer state: ');
    
    for (int i = 0; i < capacity && i < 50; i++) { // Limit visualization to 50 bytes
      if (i == _tail && _size > 0) sb.write('[');
      if (i == _head) sb.write(']');
      
      if (i >= _tail && i < _tail + _size || 
          (_tail + _size > capacity && (i >= _tail || i < (_tail + _size) % capacity))) {
        sb.write('${_buffer[i].toRadixString(16).padLeft(2, '0')} ');
      } else {
        sb.write('__ ');
      }
    }
    
    return sb.toString();
  }

  /// Compact representation for debugging
  @override
  String toString() {
    return 'CircularBuffer(size: $_size/$capacity, util: ${(utilization * 100).toStringAsFixed(1)}%, packets: $_totalPacketsExtracted)';
  }
}