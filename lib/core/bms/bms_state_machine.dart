import 'dart:collection';
import 'package:flutter/foundation.dart';

enum BmsParsingState {
  waitingForStart,
  readingRegister,
  readingStatus,
  readingLength,
  readingData,
  readingChecksum,
  packetComplete
}

class BmsPacket {
  final int register;
  final int status;
  final List<int> data;
  final bool isValid;
  final DateTime timestamp;

  BmsPacket({
    required this.register,
    required this.status,
    required this.data,
    required this.isValid,
    required this.timestamp,
  });

  @override
  String toString() {
    return 'BmsPacket(reg: 0x${register.toRadixString(16)}, status: 0x${status.toRadixString(16)}, data: ${data.length} bytes, valid: $isValid)';
  }
}

class BmsStateMachine {
  BmsParsingState _state = BmsParsingState.waitingForStart;
  final List<int> _packetBuffer = <int>[];
  int _expectedDataLength = 0;
  int _register = 0;
  int _status = 0;
  int _checksumBytesRead = 0;
  int _dataBytesRead = 0;
  
  final Queue<BmsPacket> _completePackets = Queue<BmsPacket>();

  // Performance metrics
  int _totalChunksProcessed = 0;
  int _totalPacketsCompleted = 0;

  BmsParsingState get currentState => _state;
  int get totalChunksProcessed => _totalChunksProcessed;
  int get totalPacketsCompleted => _totalPacketsCompleted;
  bool get hasCompletePackets => _completePackets.isNotEmpty;

  void reset() {
    _state = BmsParsingState.waitingForStart;
    _packetBuffer.clear();
    _expectedDataLength = 0;
    _register = 0;
    _status = 0;
    _checksumBytesRead = 0;
    _dataBytesRead = 0;
  }

  void processChunk(List<int> chunk) {
    _totalChunksProcessed++;
    
    debugPrint('[STATE_MACHINE] 🔄 Processing chunk: ${chunk.length} bytes, State: $_state');
    
    for (int i = 0; i < chunk.length; i++) {
      int byte = chunk[i];
      _processByte(byte);
    }
  }

  void _processByte(int byte) {
    switch (_state) {
      case BmsParsingState.waitingForStart:
        if (byte == 0xDD) {
          debugPrint('[STATE_MACHINE] ✅ Start byte detected, beginning packet assembly');
          _packetBuffer.clear();
          _packetBuffer.add(byte);
          _state = BmsParsingState.readingRegister;
        }
        break;

      case BmsParsingState.readingRegister:
        _register = byte;
        _packetBuffer.add(byte);
        _state = BmsParsingState.readingStatus;
        debugPrint('[STATE_MACHINE] 📋 Register: 0x${_register.toRadixString(16)}');
        break;

      case BmsParsingState.readingStatus:
        _status = byte;
        _packetBuffer.add(byte);
        _state = BmsParsingState.readingLength;
        debugPrint('[STATE_MACHINE] 📊 Status: 0x${_status.toRadixString(16)}');
        break;

      case BmsParsingState.readingLength:
        _expectedDataLength = byte;
        _packetBuffer.add(byte);
        _dataBytesRead = 0;
        
        if (_expectedDataLength == 0) {
          // No data, go directly to checksum
          _state = BmsParsingState.readingChecksum;
          _checksumBytesRead = 0;
        } else {
          _state = BmsParsingState.readingData;
        }
        debugPrint('[STATE_MACHINE] 📏 Data length: $_expectedDataLength bytes');
        break;

      case BmsParsingState.readingData:
        _packetBuffer.add(byte);
        _dataBytesRead++;
        
        if (_dataBytesRead >= _expectedDataLength) {
          _state = BmsParsingState.readingChecksum;
          _checksumBytesRead = 0;
          debugPrint('[STATE_MACHINE] 📦 Data complete: $_dataBytesRead bytes');
        }
        break;

      case BmsParsingState.readingChecksum:
        _packetBuffer.add(byte);
        _checksumBytesRead++;
        
        if (_checksumBytesRead >= 2) {
          // Check for end byte
          _state = BmsParsingState.packetComplete;
        }
        break;

      case BmsParsingState.packetComplete:
        if (byte == 0x77) {
          _packetBuffer.add(byte);
          _completePacket();
        } else {
          debugPrint('[STATE_MACHINE] ❌ Invalid end byte: 0x${byte.toRadixString(16)}, resetting');
          reset();
        }
        break;
    }
  }

  void _completePacket() {
    debugPrint('[STATE_MACHINE] ✅ COMPLETE PACKET ASSEMBLED');
    debugPrint('[STATE_MACHINE] Total bytes: ${_packetBuffer.length}');
    debugPrint('[STATE_MACHINE] Full packet: ${_packetBuffer.map((b) => '0x${b.toRadixString(16).padLeft(2, '0')}').join(' ')}');
    
    // Extract data portion (skip header: DD REG STATUS LENGTH)
    List<int> dataOnly = _packetBuffer.sublist(4, 4 + _expectedDataLength);
    
    // Verify checksum
    bool isValid = _verifyChecksum();
    
    BmsPacket packet = BmsPacket(
      register: _register,
      status: _status,
      data: dataOnly,
      isValid: isValid,
      timestamp: DateTime.now(),
    );
    
    _completePackets.add(packet);
    _totalPacketsCompleted++;
    
    debugPrint('[STATE_MACHINE] 📋 Packet queued: $packet');
    
    // Reset for next packet
    reset();
  }

  bool _verifyChecksum() {
    if (_packetBuffer.length < 7) return false;
    
    // JBD checksum: 0x10000 - sum of all bytes except start, checksum, and end bytes
    List<int> dataForChecksum = _packetBuffer.sublist(1, _packetBuffer.length - 3);
    int sum = 0;
    for (int byte in dataForChecksum) {
      sum += byte;
    }
    
    int calculatedChecksum = (0x10000 - sum) & 0xFFFF;
    int receivedChecksum = (_packetBuffer[_packetBuffer.length - 3] << 8) | _packetBuffer[_packetBuffer.length - 2];
    
    bool isValid = calculatedChecksum == receivedChecksum;
    debugPrint('[STATE_MACHINE] 🔍 Checksum - Calculated: 0x${calculatedChecksum.toRadixString(16)}, Received: 0x${receivedChecksum.toRadixString(16)}, Valid: $isValid');
    
    return isValid;
  }

  BmsPacket? getNextCompletePacket() {
    if (_completePackets.isEmpty) return null;
    return _completePackets.removeFirst();
  }

  List<BmsPacket> getAllCompletePackets() {
    List<BmsPacket> packets = _completePackets.toList();
    _completePackets.clear();
    return packets;
  }

  void printStats() {
    debugPrint('[STATE_MACHINE] 📊 PERFORMANCE STATS:');
    debugPrint('[STATE_MACHINE] Total chunks processed: $_totalChunksProcessed');
    debugPrint('[STATE_MACHINE] Total packets completed: $_totalPacketsCompleted');
    debugPrint('[STATE_MACHINE] Success rate: ${_totalPacketsCompleted / (_totalChunksProcessed > 0 ? _totalChunksProcessed : 1) * 100}%');
    debugPrint('[STATE_MACHINE] Current state: $_state');
  }
}