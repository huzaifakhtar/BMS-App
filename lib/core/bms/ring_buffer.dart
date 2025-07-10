import 'package:flutter/foundation.dart';

class RingBuffer {
  late final List<int> _buffer;
  int _head = 0;
  int _tail = 0;
  int _size = 0;
  final int capacity;
  
  // Performance metrics
  int _totalBytesAdded = 0;
  int _totalOverwrites = 0;
  DateTime? _lastActivity;

  RingBuffer(this.capacity) {
    _buffer = List<int>.filled(capacity, 0);
  }

  int get size => _size;
  int get availableSpace => capacity - _size;
  bool get isEmpty => _size == 0;
  bool get isFull => _size == capacity;
  double get utilization => _size / capacity;
  int get totalBytesAdded => _totalBytesAdded;
  int get totalOverwrites => _totalOverwrites;

  /// Add multiple bytes efficiently (zero-copy when possible)
  void addAll(List<int> data) {
    if (data.isEmpty) return;
    
    _lastActivity = DateTime.now();
    _totalBytesAdded += data.length;
    
    debugPrint('[RING_BUFFER] 📥 Adding ${data.length} bytes (buffer: $_size/$capacity)');
    
    for (int byte in data) {
      _buffer[_head] = byte;
      _head = (_head + 1) % capacity;
      
      if (_size < capacity) {
        _size++;
      } else {
        // Buffer full, overwrite old data
        _tail = (_tail + 1) % capacity;
        _totalOverwrites++;
      }
    }
    
    debugPrint('[RING_BUFFER] 📊 Buffer state: $_size/$capacity (${(utilization * 100).toStringAsFixed(1)}% full)');
  }

  /// Add single byte
  void add(int byte) {
    _lastActivity = DateTime.now();
    _totalBytesAdded++;
    
    _buffer[_head] = byte;
    _head = (_head + 1) % capacity;
    
    if (_size < capacity) {
      _size++;
    } else {
      _tail = (_tail + 1) % capacity;
      _totalOverwrites++;
    }
  }

  /// Peek at byte without removing it
  int? peek(int offset) {
    if (offset >= _size) return null;
    int index = (_tail + offset) % capacity;
    return _buffer[index];
  }

  /// Get bytes without removing them
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

  /// Remove and return single byte
  int? removeByte() {
    if (_size == 0) return null;
    
    int byte = _buffer[_tail];
    _tail = (_tail + 1) % capacity;
    _size--;
    
    return byte;
  }

  /// Remove multiple bytes efficiently
  void removeBytes(int count) {
    if (count <= 0) return;
    
    int actualCount = (count > _size) ? _size : count;
    _tail = (_tail + actualCount) % capacity;
    _size -= actualCount;
    
    debugPrint('[RING_BUFFER] 🗑️ Removed $actualCount bytes (buffer: $_size/$capacity)');
  }

  /// Find pattern in buffer (e.g., find start/end bytes)
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

  /// Find single byte
  int findByte(int byte, [int startOffset = 0]) {
    if (startOffset >= _size) return -1;
    
    for (int i = startOffset; i < _size; i++) {
      int index = (_tail + i) % capacity;
      if (_buffer[index] == byte) return i;
    }
    
    return -1;
  }

  /// Extract data range and remove it
  List<int> extractRange(int start, int length) {
    List<int> data = peekRange(start, length);
    if (data.isNotEmpty) {
      removeBytes(start + data.length);
    }
    return data;
  }

  /// Try to extract complete BMS packet (DD ... 77)
  List<int>? tryExtractBmsPacket() {
    // Find start byte (0xDD)
    int startIndex = findByte(0xDD);
    if (startIndex == -1) return null;
    
    // Remove any junk data before start byte
    if (startIndex > 0) {
      removeBytes(startIndex);
      debugPrint('[RING_BUFFER] 🧹 Removed $startIndex junk bytes before packet start');
    }
    
    // Check if we have enough bytes for header (DD REG STATUS LENGTH)
    if (_size < 4) return null;
    
    // Get data length from packet
    int? lengthByte = peek(3);
    if (lengthByte == null) return null;
    
    // Calculate total packet size: header(4) + data(length) + checksum(2) + end(1)
    int totalPacketSize = 4 + lengthByte + 2 + 1;
    
    // Check if complete packet is available
    if (_size < totalPacketSize) {
      debugPrint('[RING_BUFFER] ⏳ Waiting for complete packet: have $_size bytes, need $totalPacketSize');
      return null;
    }
    
    // Verify end byte
    int? endByte = peek(totalPacketSize - 1);
    if (endByte != 0x77) {
      debugPrint('[RING_BUFFER] ❌ Invalid end byte: 0x${endByte?.toRadixString(16)}, removing corrupted packet');
      removeBytes(1); // Remove start byte and try again
      return null;
    }
    
    // Extract complete packet
    List<int> packet = extractRange(0, totalPacketSize);
    debugPrint('[RING_BUFFER] ✅ Extracted complete packet: $totalPacketSize bytes');
    
    return packet;
  }

  /// Clear all data
  void clear() {
    _head = 0;
    _tail = 0;
    _size = 0;
    debugPrint('[RING_BUFFER] 🧹 Buffer cleared');
  }

  /// Get all data without removing it
  List<int> getAllData() {
    return peekRange(0, _size);
  }

  /// Performance statistics
  void printStats() {
    debugPrint('[RING_BUFFER] 📊 PERFORMANCE STATS:');
    debugPrint('[RING_BUFFER] Capacity: $capacity bytes');
    debugPrint('[RING_BUFFER] Current size: $_size bytes (${(utilization * 100).toStringAsFixed(1)}%)');
    debugPrint('[RING_BUFFER] Total bytes added: $_totalBytesAdded');
    debugPrint('[RING_BUFFER] Total overwrites: $_totalOverwrites');
    debugPrint('[RING_BUFFER] Head: $_head, Tail: $_tail');
    debugPrint('[RING_BUFFER] Last activity: $_lastActivity');
  }

  /// Compact representation for debugging
  @override
  String toString() {
    return 'RingBuffer(size: $_size/$capacity, util: ${(utilization * 100).toStringAsFixed(1)}%)';
  }
}