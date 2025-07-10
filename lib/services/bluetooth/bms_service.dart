import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../data/models/bms_registers.dart';
import '../../data/models/bms_data_model.dart';
import '../../core/cache/basic_info_cache.dart';
import '../../core/validation/data_validators.dart';
import '../../core/monitoring/performance_monitor.dart';

class BmsService extends ChangeNotifier {
  final Map<JbdRegister, JbdRegisterValue> _registerValues = {};
  String _statusMessage = '';
  String _debugMessage = '';
  bool _isReading = false;
  bool _isWriting = false;
  
  Timer? _responseTimeout;
  
  // Performance monitoring
  final PerformanceMonitor _performanceMonitor = PerformanceMonitor();

  // Initialize performance monitoring
  BmsService() {
    _performanceMonitor.startMonitoring();
    debugPrint('[BMS_SERVICE] 🚀 Initialized with performance monitoring');
  }
  
  // Serial interface callback
  Function(String)? _serialResponseCallback;
  
  // Data callback for parameter pages
  Function(List<int>)? _dataCallback;
  
  // Simple buffer for BLE packet assembly
  final List<int> _packetBuffer = [];

  // Getters
  Map<JbdRegister, JbdRegisterValue> get registerValues => _registerValues;
  String get statusMessage => _statusMessage;
  String get debugMessage => _debugMessage;
  bool get isReading => _isReading;
  bool get isWriting => _isWriting;

  // JBD Protocol Constants (Based on BMS-Tools Repository)
  // Serial Communication: 9600 baud, 8 data bits, no parity, 1 stop bit
  static const int startByte = 0xDD;
  static const int readCommand = 0xA5;
  static const int writeCommand = 0x5A;
  static const int endByte = 0x77;
  
  // JBD Register Map (from bms-tools repository)
  static const int basicInfoRegister = 0x03;      // Basic battery information (23 bytes)
  static const int cellVoltageRegister = 0x04;    // Individual cell voltages (up to 32 cells)
  static const int hardwareVersionRegister = 0x05; // Hardware version info
  static const int capacityRegister = 0x06;       // Capacity information
  static const int deviceNameRegister = 0xA0;     // Device name (write)
  static const int manufacturerRegister = 0xA1;   // Manufacturer name
  static const int barcodeRegister = 0xA2;        // Device barcode

  List<int> createReadCommand(JbdRegister register) {
    // JBD Protocol: DD A5 [REG] [LEN] [CHECKSUM_H] [CHECKSUM_L] 77
    // For basic info (0x03): DD A5 03 00 FF FD 77
    
    List<int> command = [
      startByte,        // 0xDD
      readCommand,      // 0xA5
      register.address, // Register address
      0x00,            // Length byte (always 0x00 for read commands)
    ];
    
    // Calculate checksum: 0x10000 - sum of bytes before checksum
    int checksum = calculateChecksum(command);
    command.addAll([
      (checksum >> 8) & 0xFF,  // Checksum high byte
      checksum & 0xFF,         // Checksum low byte
      endByte,                 // 0x77
    ]);

    _updateDebugMessage('Read Command: ${command.map((b) => '0x${b.toRadixString(16).padLeft(2, '0')}').join(' ')}');
    debugPrint('[JBD] Created command: ${command.map((b) => '0x${b.toRadixString(16).padLeft(2, '0')}').join(' ')}');
    return command;
  }

  List<int> createWriteCommand(JbdRegister register, List<int> data) {
    List<int> command = [
      startByte,
      writeCommand,
      register.address,
      data.length,
    ];
    command.addAll(data);
    
    int checksum = calculateChecksum(command);
    command.addAll([
      (checksum >> 8) & 0xFF,
      checksum & 0xFF,
      endByte,
    ]);

    _updateDebugMessage('Write Command: ${command.map((b) => '0x${b.toRadixString(16).padLeft(2, '0')}').join(' ')}');
    return command;
  }

  int calculateChecksum(List<int> data) {
    int sum = 0;
    for (int byte in data) {
      sum += byte;
    }
    return (0x10000 - sum) & 0xFFFF;
  }

  bool verifyChecksum(List<int> response) {
    if (response.length < 7) return false;
    
    // JBD checksum calculation based on official BMS Tools implementation
    // Extract data bytes (packet[2:-3] in Python equivalent)
    List<int> data = response.sublist(2, response.length - 3);
    
    // Extract received checksum (last 2 bytes before end byte 0x77)  
    List<int> receivedChecksumBytes = response.sublist(response.length - 3, response.length - 1);
    int receivedChecksum = (receivedChecksumBytes[0] << 8) | receivedChecksumBytes[1];
    
    // Calculate checksum: 0x10000 - sum of data bytes
    int crc = 0x10000;
    for (int byte in data) {
      crc = crc - byte;
    }
    
    // Convert to 2-byte big-endian format
    int calculatedChecksum = crc & 0xFFFF;
    
    debugPrint('[JBD] Checksum verification (BMS Tools method):');
    debugPrint('[JBD] Data bytes: ${data.map((b) => '0x${b.toRadixString(16).padLeft(2, '0')}').join(' ')}');
    debugPrint('[JBD] Received: 0x${receivedChecksum.toRadixString(16).padLeft(4, '0').toUpperCase()}');
    debugPrint('[JBD] Calculated: 0x${calculatedChecksum.toRadixString(16).padLeft(4, '0').toUpperCase()}');
    
    if (receivedChecksum == calculatedChecksum) {
      debugPrint('[JBD] ✅ Checksum verified (BMS Tools standard)');
      return true;
    }
    
    debugPrint('[JBD] ❌ Checksum verification failed');
    debugPrint('[JBD] Full packet: ${response.map((b) => '0x${b.toRadixString(16).padLeft(2, '0')}').join(' ')}');
    
    return false;
  }

  dynamic parseRegisterValue(JbdRegister register, List<int> data) {
    if (data.isEmpty) return null;

    switch (register) {
      case JbdRegister.basicInfo:
        return parseJbdResponse(data);
        
      case JbdRegister.cellVoltages:
        return _parseCellVoltages(data);
        
      case JbdRegister.voltage:
      case JbdRegister.current:
      case JbdRegister.remainingCapacity:
      case JbdRegister.nominalCapacity:
      case JbdRegister.cycleCount:
      case JbdRegister.overVoltageProtection:
      case JbdRegister.underVoltageProtection:
      case JbdRegister.overCurrentChargeProtection:
      case JbdRegister.overCurrentDischargeProtection:
      case JbdRegister.designCapacity:
      case JbdRegister.cycleCapacity:
      case JbdRegister.balanceStatus:
      case JbdRegister.protectionStatus:
        if (data.length >= 2) {
          int value = (data[0] << 8) | data[1];
          // Handle signed values for current
          if (register == JbdRegister.current && value > 32767) {
            value = value - 65536;
          }
          return value;
        }
        return data[0];

      case JbdRegister.manufacturerName:
      case JbdRegister.deviceName:
      case JbdRegister.barcode:
        try {
          List<int> validBytes = data.where((byte) => byte != 0).toList();
          return utf8.decode(validBytes);
        } catch (e) {
          return String.fromCharCodes(data.where((byte) => byte != 0));
        }

      case JbdRegister.remainingCapacityPercent:
      case JbdRegister.softwareVersion:
      case JbdRegister.mosfetStatus:
      case JbdRegister.batteryString:
      case JbdRegister.ntcCount:
        return data[0];

      case JbdRegister.ntcTemperatures:
        return _parseTemperatures(data);

      default:
        if (data.length == 1) {
          return data[0];
        } else if (data.length >= 2) {
          return (data[0] << 8) | data[1];
        }
        return data;
    }
  }


  List<double> _parseCellVoltages(List<int> data) {
    List<double> voltages = [];
    for (int i = 0; i < data.length - 1; i += 2) {
      int voltage = (data[i] << 8) | data[i + 1];
      if (voltage > 0) { // Valid voltage
        voltages.add(voltage / 1000.0); // mV to V
      }
    }
    return voltages;
  }

  List<double> _parseTemperatures(List<int> data) {
    List<double> temps = [];
    for (int i = 0; i < data.length - 1; i += 2) {
      int temp = (data[i] << 8) | data[i + 1];
      if (temp > 0) {
        temps.add(temp / 10.0 - 273.15); // K to °C
      }
    }
    return temps;
  }


  List<int> encodeValueForWrite(JbdRegister register, dynamic value) {
    switch (register) {
      case JbdRegister.overVoltageProtection:
      case JbdRegister.underVoltageProtection:
      case JbdRegister.overCurrentChargeProtection:
      case JbdRegister.overCurrentDischargeProtection:
      case JbdRegister.designCapacity:
      case JbdRegister.cycleCapacity:
        if (value is String) {
          int intValue = int.tryParse(value) ?? 0;
          return [(intValue >> 8) & 0xFF, intValue & 0xFF];
        } else if (value is int) {
          return [(value >> 8) & 0xFF, value & 0xFF];
        }
        return [0, 0];

      case JbdRegister.manufacturerName:
      case JbdRegister.deviceName:
      case JbdRegister.barcode:
        List<int> bytes = utf8.encode(value.toString());
        while (bytes.length < register.length) {
          bytes.add(0);
        }
        if (bytes.length > register.length) {
          bytes = bytes.sublist(0, register.length);
        }
        return bytes;

      default:
        if (value is String) {
          int intValue = int.tryParse(value) ?? 0;
          return [intValue & 0xFF];
        } else if (value is int) {
          return [value & 0xFF];
        }
        return [0];
    }
  }

  void setSerialResponseCallback(Function(String)? callback) {
    _serialResponseCallback = callback;
  }
  
  void setDataCallback(Function(List<int>)? callback) {
    _dataCallback = callback;
  }
  
  void addDataCallback(Function(List<int>) callback) {
    _dataCallback = callback;
  }

  // Add battery data callback
  Function(JbdBmsData)? _batteryDataCallback;
  JbdBmsData? _lastBmsData;
  List<double>? _lastCellVoltages; // Store cell voltages independently
  
  void setBatteryDataCallback(Function(JbdBmsData)? callback) {
    _batteryDataCallback = callback;
  }

  // Getters for cached data
  JbdBmsData? get lastBmsData => _lastBmsData;
  List<double>? get lastCellVoltages => _lastCellVoltages;


  Future<void> handleResponse(List<int> response) async {
    if (response.isEmpty) return;
    
    // Send to serial interface if callback is set
    String timestamp = DateTime.now().toString().substring(11, 19);
    String hexResponse = response.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join(' ');
    _serialResponseCallback?.call('📥 [$timestamp] RX: $hexResponse (${response.length} bytes)');
    
    // Add to buffer for packet assembly
    _packetBuffer.addAll(response);
    
    // Try to extract complete packets
    _processPacketBuffer();
    
    // Set timeout to clear buffer if incomplete
    _responseTimeout?.cancel();
    _responseTimeout = Timer(const Duration(milliseconds: 500), () {
      if (_packetBuffer.isNotEmpty) {
        debugPrint('⏰ Clearing incomplete packet buffer: ${_packetBuffer.length} bytes');
        _packetBuffer.clear();
        _isReading = false;
        _isWriting = false;
        notifyListeners();
      }
    });
  }
  
  void _processPacketBuffer() {
    while (_packetBuffer.isNotEmpty) {
      // Find start byte
      int startIndex = _packetBuffer.indexOf(0xDD);
      if (startIndex == -1) {
        _packetBuffer.clear();
        break;
      }
      
      // Remove bytes before start
      if (startIndex > 0) {
        _packetBuffer.removeRange(0, startIndex);
      }
      
      // Need at least 7 bytes for minimum packet
      if (_packetBuffer.length < 7) break;
      
      // Seedha packet length nikal ke complete packet fetch karo
      if (_packetBuffer.length >= 4) {
        int dataLength = _packetBuffer[3];
        int packetLength = 7 + dataLength;
        
        debugPrint('[JBD] Expected packet length: $packetLength, Buffer length: ${_packetBuffer.length}');
        
        if (_packetBuffer.length >= packetLength) {
          // Complete packet mil gaya - extract aur process karo (don't check end byte in data)
          List<int> packet = _packetBuffer.sublist(0, packetLength);
          
          // Only check end byte at actual calculated position
          if (packet[packet.length - 1] == 0x77) {
            _packetBuffer.removeRange(0, packetLength);
            debugPrint('[JBD] Processing complete packet: ${packet.length} bytes');
            _processCompletePacket(packet);
            continue;
          } else {
            debugPrint('[JBD] ⚠️ Packet length correct but end byte mismatch at position ${packet.length - 1}: 0x${packet[packet.length - 1].toRadixString(16)}');
          }
        }
      }
      
      // Skip fallback end byte search - only use length-based assembly
      // End byte search is unreliable when 0x77 appears in data
      break;
    }
  }

  
  void _processCompletePacket(List<int> packet) {
    // Performance monitoring for packet processing
    final tracker = _performanceMonitor.trackOperation('packet_processing', metadata: {
      'packet_size': packet.length,
      'register': packet.length > 2 ? packet[2] : null,
    });
    
    try {
      _responseTimeout?.cancel();
      
      // Console output for complete packet
      debugPrint('📋 COMPLETE PACKET RECEIVED (${packet.length} bytes):');
      debugPrint('Hex: ${packet.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join(' ')}');
      debugPrint('Dec: ${packet.join(' ')}');
      debugPrint('');
      
      _updateDebugMessage('Complete packet (${packet.length} bytes): ${packet.map((b) => '0x${b.toRadixString(16).padLeft(2, '0')}').join(' ')}');
      debugPrint('[JBD] Complete packet: ${packet.map((b) => '0x${b.toRadixString(16).padLeft(2, '0')}').join(' ')}');
    
      if (packet.length < 7) {
        debugPrint('❌ PACKET TOO SHORT: ${packet.length} bytes (minimum 7 required)');
        debugPrint('='*60);
        _updateStatus('Packet too short: ${packet.length} bytes');
        tracker.fail('Packet too short: ${packet.length} bytes');
        return;
      }

      if (packet[0] != startByte || packet[packet.length - 1] != endByte) {
        _updateStatus('Invalid packet format - Start: 0x${packet[0].toRadixString(16)}, End: 0x${packet[packet.length - 1].toRadixString(16)}');
        tracker.fail('Invalid packet format');
        return;
      }

    bool checksumValid = verifyChecksum(packet);
    if (!checksumValid) {
      debugPrint('[JBD] ⚠️ CHECKSUM MISMATCH - PROCEEDING ANYWAY');
      // Continue processing despite checksum mismatch
    }

    // JBD Response format: DD [REGISTER] [STATUS] [LENGTH] [DATA...] [CHECKSUM_H] [CHECKSUM_L] 77
    int register = packet[1];  // Register that was read (0x03 for basic info)
    int status = packet[2];    // Status byte (0x00 = OK)
    int length = packet[3];    // Data length
    
    debugPrint('[JBD] Response - Register: 0x${register.toRadixString(16).padLeft(2, '0')}, Status: 0x${status.toRadixString(16).padLeft(2, '0')}, Length: $length');
    
    // Skip generic error checking - we handle status byte properly below
    
    if (packet.length < 4 + length + 3) {
      _updateStatus('Packet too short for declared data length');
      return;
    }
    
    List<int> data = packet.sublist(4, 4 + length);

    debugPrint('[JBD] Processing packet - Register: 0x${register.toRadixString(16).padLeft(2, '0')}, Status: 0x${status.toRadixString(16).padLeft(2, '0')}, Length: $length, Data: ${data.length} bytes');
    
      // Check if this is factory mode or write command response
      if (_isFactoryModeOrWriteRegister(register)) {
        if (status == 0x00) {
          debugPrint('[JBD] ✅ FACTORY/WRITE SUCCESS - Register: 0x${register.toRadixString(16)}');
          _updateStatus('Factory/Write command successful');
          tracker.complete(additionalMetadata: {'operation': 'factory_write', 'success': true});
        } else {
          debugPrint('[JBD] ❌ FACTORY/WRITE ERROR - Register: 0x${register.toRadixString(16)}, Status: 0x${status.toRadixString(16)}');
          _updateStatus('Factory/Write command failed');
          tracker.complete(additionalMetadata: {'operation': 'factory_write', 'success': false});
        }
        return; // Done - no parsing needed
      }
    
    // Check if this is basic info register (0x03) response
    if (register == 0x03 && status == 0x00) {
      try {
        debugPrint('[JBD] ✅ COMPLETE 0x03 RESPONSE RECEIVED - PARSING NOW:');
        debugPrint('[JBD] Full packet length: ${packet.length} bytes');
        debugPrint('[JBD] Full packet: ${packet.map((b) => '0x${b.toRadixString(16).padLeft(2, '0')}').join(' ')}');
        debugPrint('[JBD] Data portion length: ${data.length} bytes');
        debugPrint('[JBD] Data portion: ${data.map((b) => '0x${b.toRadixString(16).padLeft(2, '0')}').join(' ')}');
        debugPrint('[JBD] 🔄 PARSING COMPLETE PACKET NOW (not chunks)...');
        
        if (data.length < 23) {
          debugPrint('[JBD] ❌ Insufficient data for JBD parsing (need at least 23 bytes, got ${data.length})');
          _serialResponseCallback?.call('❌ Response too short: ${data.length} bytes (need 23+)');
          _updateStatus('Response too short: ${data.length} bytes');
          return;
        }
        
        // Use data portion directly for parsing, not the full packet
        final parseTracker = _performanceMonitor.trackOperation('basic_info_parsing', metadata: {'data_size': data.length});
        JbdBmsData bmsData;
        try {
          bmsData = _parseBasicInfoData(data);
          parseTracker.complete();
        } catch (e) {
          parseTracker.fail('Basic info parsing failed: $e');
          rethrow;
        }
        
        // Extract and cache version and production date for Basic Info page
        if (data.length >= 19) {
          // Version is at byte 18 (0x10 means version 1.0)
          int versionByte = data[18];
          int major = (versionByte >> 4) & 0x0F;
          int minor = versionByte & 0x0F;
          String versionString = '$major.$minor';
          
          // Update cache
          BasicInfoCache.version = versionString;
          debugPrint('[JBD] Cached version from 0x03: $versionString');
        }
        
        // Cache production date as well
        BasicInfoCache.productionDate = '${bmsData.productionDate.year}-${bmsData.productionDate.month.toString().padLeft(2, '0')}-${bmsData.productionDate.day.toString().padLeft(2, '0')}';
        BasicInfoCache.isLoaded = true;
        
        // Include stored cell voltages if available
        if (_lastCellVoltages != null && _lastCellVoltages!.isNotEmpty) {
          bmsData = JbdBmsData(
            totalVoltage: bmsData.totalVoltage,
            current: bmsData.current,
            remainingCapacity: bmsData.remainingCapacity,
            nominalCapacity: bmsData.nominalCapacity,
            cycleCount: bmsData.cycleCount,
            chargeLevel: bmsData.chargeLevel,
            chargeFetOn: bmsData.chargeFetOn,
            dischargeFetOn: bmsData.dischargeFetOn,
            numberOfCells: bmsData.numberOfCells,
            temperatures: bmsData.temperatures,
            cellVoltages: _lastCellVoltages!, // Use stored cell voltages
            balanceStatus: bmsData.balanceStatus,
            protectionStatus: bmsData.protectionStatus,
            productionDate: bmsData.productionDate,
          );
          debugPrint('[JBD] 🔋 Merged ${_lastCellVoltages!.length} stored cell voltages with basic info');
        }
        
        // Validate data before storing and sending to UI
        final validationResults = DataValidationPipeline.validateAll(bmsData);
        final isDataSafe = DataValidationPipeline.isDataSafe(bmsData);
        
        if (!isDataSafe) {
          final errors = validationResults.where((r) => !r.isValid).toList();
          debugPrint('[JBD] ❌ Data validation failed: ${errors.first.errorMessage}');
          _updateStatus('Data validation failed: ${errors.first.errorMessage}');
          return; // Don't store/send invalid data
        }
        
        // Print validation warnings
        final warnings = validationResults.where((r) => r.warningMessage != null).toList();
        for (final warning in warnings) {
          debugPrint('[JBD] ⚠️ Data warning: ${warning.warningMessage}');
        }
        
        _lastBmsData = bmsData;
        notifyListeners();
        
        debugPrint('✅ JBD BASIC INFO VALIDATED AND PARSED SUCCESSFULLY:');
        debugPrint('🔋 Voltage: ${bmsData.totalVoltage.toStringAsFixed(2)} V');
        debugPrint('⚡ Current: ${bmsData.current.toStringAsFixed(2)} A');
        debugPrint('📊 Charge Level: ${bmsData.chargeLevel}%');
        debugPrint('⚖️ Remaining Capacity: ${bmsData.remainingCapacity.toStringAsFixed(2)} Ah');
        debugPrint('📦 Nominal Capacity: ${bmsData.nominalCapacity.toStringAsFixed(2)} Ah');
        debugPrint('🔄 Cycles: ${bmsData.cycleCount}');
        debugPrint('🌡️ Avg Temperature: ${bmsData.avgTemperature.toStringAsFixed(1)} °C');
        debugPrint('🔧 Cells: ${bmsData.numberOfCells}');
        debugPrint('🔌 Charge FET: ${bmsData.chargeFetOn ? "ON" : "OFF"}');
        debugPrint('🔌 Discharge FET: ${bmsData.dischargeFetOn ? "ON" : "OFF"}');
        debugPrint('⚡ Power: ${bmsData.power.toStringAsFixed(1)} W');
        debugPrint('📅 Production Date: ${bmsData.productionDate}');
        debugPrint('🔋 Cell Voltages: ${bmsData.cellVoltages.length} cells');
        debugPrint('='*60);
        
        // Send battery data to UI callback with debug
        debugPrint('[JBD] 🎯 CALLING BATTERY DATA CALLBACK');
        _batteryDataCallback?.call(bmsData);
        debugPrint('[JBD] ✅ Battery data callback completed');
        
        _serialResponseCallback?.call('✅ Battery data parsed and sent to UI');
        _updateStatus('✓ Basic Info: V=${bmsData.totalVoltage.toStringAsFixed(2)}V, I=${bmsData.current.toStringAsFixed(2)}A, SOC=${bmsData.chargeLevel}%');
        
      } catch (e) {
        debugPrint('[JBD] ❌ Parser failed: $e');
        debugPrint('[JBD] Stack trace: ${StackTrace.current}');
        debugPrint('[JBD] Data that caused error: ${data.map((b) => '0x${b.toRadixString(16).padLeft(2, '0')}').join(' ')}');
        _serialResponseCallback?.call('❌ Parsing error: $e');
        _updateStatus('Error parsing basic info: $e');
      }
    } else if (register == 0x04 && status == 0x00) {
      // Cell voltage response
      try {
        debugPrint('[JBD] ✅ COMPLETE 0x04 RESPONSE RECEIVED - PARSING NOW:');
        debugPrint('[JBD] Data length: ${data.length} bytes');
        debugPrint('[JBD] Raw data: ${data.map((b) => '0x${b.toRadixString(16).padLeft(2, '0')}').join(' ')}');
        debugPrint('[JBD] 🔄 PARSING COMPLETE CELL VOLTAGE PACKET NOW (not chunks)...');
        
        List<double> cellVoltages = _parseCellVoltages(data);
        
        // Always store cell voltages for future use
        _lastCellVoltages = cellVoltages;
        
        debugPrint('✅ JBD CELL VOLTAGES PARSED SUCCESSFULLY:');
        debugPrint('🔋 Cell count: ${cellVoltages.length}');
        for (int i = 0; i < cellVoltages.length; i++) {
          debugPrint('🔋 Cell ${i + 1}: ${cellVoltages[i].toStringAsFixed(3)}V');
        }
        debugPrint('='*60);
        
        // Always send updated data to UI - either with or without basic info
        if (_lastBmsData != null) {
          // Update existing BMS data with new cell voltages
          JbdBmsData updatedData = JbdBmsData(
            totalVoltage: _lastBmsData!.totalVoltage,
            current: _lastBmsData!.current,
            remainingCapacity: _lastBmsData!.remainingCapacity,
            nominalCapacity: _lastBmsData!.nominalCapacity,
            cycleCount: _lastBmsData!.cycleCount,
            chargeLevel: _lastBmsData!.chargeLevel,
            chargeFetOn: _lastBmsData!.chargeFetOn,
            dischargeFetOn: _lastBmsData!.dischargeFetOn,
            numberOfCells: _lastBmsData!.numberOfCells,
            temperatures: _lastBmsData!.temperatures,
            cellVoltages: cellVoltages,
            balanceStatus: _lastBmsData!.balanceStatus,
            protectionStatus: _lastBmsData!.protectionStatus,
            productionDate: _lastBmsData!.productionDate,
          );
          
          _lastBmsData = updatedData;
          notifyListeners();
          _batteryDataCallback?.call(updatedData);
          debugPrint('[JBD] 🔋 Updated existing BMS data with cell voltages');
        } else {
          // Create minimal BMS data with just cell voltages for initial display
          JbdBmsData cellOnlyData = JbdBmsData(
            totalVoltage: cellVoltages.isNotEmpty ? cellVoltages.reduce((a, b) => a + b) : 0.0,
            current: 0.0,
            remainingCapacity: 0.0,
            nominalCapacity: 0.0,
            cycleCount: 0,
            chargeLevel: 0,
            chargeFetOn: false,
            dischargeFetOn: false,
            numberOfCells: cellVoltages.length,
            temperatures: [],
            cellVoltages: cellVoltages,
            balanceStatus: 0,
            protectionStatus: 0,
            productionDate: DateTime.now(),
          );
          
          _lastBmsData = cellOnlyData;
          notifyListeners();
          _batteryDataCallback?.call(cellOnlyData);
          debugPrint('[JBD] 🔋 Created initial BMS data with cell voltages only');
        }
        
        _serialResponseCallback?.call('✅ Cell voltages parsed: ${cellVoltages.length} cells');
        _updateStatus('✓ Cell Voltages: ${cellVoltages.length} cells received');
        
      } catch (e) {
        debugPrint('[JBD] ❌ Cell voltage parser failed: $e');
        _serialResponseCallback?.call('❌ Cell voltage parsing error: $e');
        _updateStatus('Error parsing cell voltages: $e');
      }
    } else if (register == 0x11 && status == 0x00) {
      // Temperature response
      try {
        debugPrint('[JBD] 🔍 ATTEMPTING TO PARSE TEMPERATURE DATA:');
        debugPrint('[JBD] Data length: ${data.length} bytes');
        debugPrint('[JBD] Raw data: ${data.map((b) => '0x${b.toRadixString(16).padLeft(2, '0')}').join(' ')}');
        
        List<double> temperatures = _parseTemperatures(data);
        
        if (temperatures.isNotEmpty) {
          debugPrint('[JBD] ✅ Temperature sensors parsed: ${temperatures.length} sensors');
          for (int i = 0; i < temperatures.length; i++) {
            debugPrint('[JBD] 🌡️ Sensor ${i + 1}: ${temperatures[i].toStringAsFixed(1)}°C');
          }
          
          // Update BMS data with temperatures if we have existing data
          if (_lastBmsData != null) {
            JbdBmsData updatedData = JbdBmsData(
              totalVoltage: _lastBmsData!.totalVoltage,
              current: _lastBmsData!.current,
              remainingCapacity: _lastBmsData!.remainingCapacity,
              nominalCapacity: _lastBmsData!.nominalCapacity,
              cycleCount: _lastBmsData!.cycleCount,
              chargeLevel: _lastBmsData!.chargeLevel,
              chargeFetOn: _lastBmsData!.chargeFetOn,
              dischargeFetOn: _lastBmsData!.dischargeFetOn,
              numberOfCells: _lastBmsData!.numberOfCells,
              temperatures: temperatures, // Use new temperature data
              cellVoltages: _lastBmsData!.cellVoltages,
              balanceStatus: _lastBmsData!.balanceStatus,
              protectionStatus: _lastBmsData!.protectionStatus,
              productionDate: _lastBmsData!.productionDate,
            );
            
            _lastBmsData = updatedData;
            notifyListeners();
            _batteryDataCallback?.call(updatedData);
            debugPrint('[JBD] 🌡️ Updated BMS data with temperature sensors');
          }
          
          _serialResponseCallback?.call('✅ Temperature sensors parsed: ${temperatures.length} sensors');
          _updateStatus('✓ Temperature: ${temperatures.length} sensors received');
        } else {
          debugPrint('[JBD] ⚠️ No valid temperature data found');
          _updateStatus('No valid temperature data');
        }
        
      } catch (e) {
        debugPrint('[JBD] ❌ Temperature parser failed: $e');
        _serialResponseCallback?.call('❌ Temperature parsing error: $e');  
        _updateStatus('Error parsing temperatures: $e');
      }
    } else if (register == 0xFA && status == 0x00) {
      // Parameter reading mode response (BMS model, etc.)
      try {
        debugPrint('[JBD] ✅ COMPLETE 0xFA PARAMETER READING RESPONSE RECEIVED:');
        debugPrint('[JBD] Data length: ${data.length} bytes');
        debugPrint('[JBD] Raw data: ${data.map((b) => '0x${b.toRadixString(16).padLeft(2, '0')}').join(' ')}');
        
        // Parameter reading response format: [PARAM_NUM_H] [PARAM_NUM_L] [PARAM_LEN] [STRING_LEN] [STRING_DATA...]
        if (data.length >= 4) {
          final paramNumber = (data[0] << 8) | data[1];
          final paramLength = data[2];
          final stringLength = data[3];
          debugPrint('[JBD] Parameter number: 0x${paramNumber.toRadixString(16).padLeft(4, '0')}');
          debugPrint('[JBD] Parameter length: $paramLength bytes');
          debugPrint('[JBD] String length: $stringLength bytes');
          
          // Extract string data starting from byte 4
          if (data.length >= 4 + stringLength) {
            final stringData = data.sublist(4, 4 + stringLength);
            debugPrint('[JBD] String data: ${stringData.map((b) => '0x${b.toRadixString(16).padLeft(2, '0')}').join(' ')}');
            
            // Try to extract ASCII string
            final asciiData = stringData.where((b) => b >= 32 && b <= 126).map((b) => String.fromCharCode(b)).join('').trim();
            if (asciiData.isNotEmpty) {
              debugPrint('[JBD] ✅ Parameter ASCII value: "$asciiData"');
              _serialResponseCallback?.call('✅ Parameter 0x${paramNumber.toRadixString(16)} = "$asciiData"');
            } else {
              debugPrint('[JBD] ✅ Parameter binary value: ${stringData.length} bytes');
              _serialResponseCallback?.call('✅ Parameter 0x${paramNumber.toRadixString(16)} = ${stringData.length} bytes');
            }
          }
        }
        
        _updateStatus('✓ Parameter reading successful');
        
        // Call data callback for basic_info_page
        _dataCallback?.call(packet);
        
      } catch (e) {
        debugPrint('[JBD] ❌ Parameter reading parser failed: $e');
        _serialResponseCallback?.call('❌ Parameter reading parsing error: $e');  
        _updateStatus('Error parsing parameter reading response: $e');
      }
    } else if ((register == 0xA0 || register == 0xA1 || register == 0xA2) && status == 0x00) {
      // Text data registers (manufacturer, device name, barcode)
      try {
        debugPrint('[JBD] ✅ COMPLETE 0x${register.toRadixString(16).toUpperCase()} TEXT RESPONSE RECEIVED:');
        debugPrint('[JBD] Data length: ${data.length} bytes');
        debugPrint('[JBD] Raw data: ${data.map((b) => '0x${b.toRadixString(16).padLeft(2, '0')}').join(' ')}');
        
        // Extract text from data - skip null bytes and non-printable characters
        final textData = data.where((b) => b >= 32 && b <= 126).map((b) => String.fromCharCode(b)).join('').trim();
        
        if (textData.isNotEmpty) {
          debugPrint('[JBD] ✅ Text value: "$textData"');
          String registerName = register == 0xA0 ? 'Manufacturer' : 
                               register == 0xA1 ? 'Device Name' : 'Barcode';
          _serialResponseCallback?.call('✅ $registerName = "$textData"');
        } else {
          debugPrint('[JBD] ⚠️ No valid text data found');
        }
        
        _updateStatus('✓ Text data received for register 0x${register.toRadixString(16).padLeft(2, '0')}');
        
      } catch (e) {
        debugPrint('[JBD] ❌ Text data parser failed: $e');
        _serialResponseCallback?.call('❌ Text parsing error: $e');  
        _updateStatus('Error parsing text data: $e');
      }
    } else if (register == 0x15 && status == 0x00) {
      // Production date register
      try {
        debugPrint('[JBD] ✅ COMPLETE 0x15 PRODUCTION DATE RESPONSE RECEIVED:');
        debugPrint('[JBD] Data length: ${data.length} bytes');
        debugPrint('[JBD] Raw data: ${data.map((b) => '0x${b.toRadixString(16).padLeft(2, '0')}').join(' ')}');
        
        if (data.length >= 2) {
          final dateValue = (data[0] << 8) | data[1];
          final year = 2000 + ((dateValue >> 9) & 0x7F);
          final month = (dateValue >> 5) & 0x0F;
          final day = dateValue & 0x1F;
          final dateString = '$year-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
          
          debugPrint('[JBD] ✅ Production date: $dateString');
          _serialResponseCallback?.call('✅ Production Date = $dateString');
        } else {
          debugPrint('[JBD] ❌ Production date data too short');
        }
        
        _updateStatus('✓ Production date received');
        
      } catch (e) {
        debugPrint('[JBD] ❌ Production date parser failed: $e');
        _serialResponseCallback?.call('❌ Production date parsing error: $e');  
        _updateStatus('Error parsing production date: $e');
      }
    } else {
      // Handle other registers - Factory mode commands, protection parameters etc.
      debugPrint('[JBD] Non-data register: 0x${register.toRadixString(16).padLeft(2, '0')}');
      
      // For factory mode and write commands - just check for errors, no parsing needed
      if (_isFactoryModeOrWriteRegister(register)) {
        debugPrint('[JBD] ✅ Factory/Write command response received for register 0x${register.toRadixString(16).padLeft(2, '0')}');
        debugPrint('[JBD] Status: 0x${status.toRadixString(16).padLeft(2, '0')}, Data length: ${data.length}');
        
        if (status == 0x00) {
          _updateStatus('✓ Command successful for register 0x${register.toRadixString(16).padLeft(2, '0')}');
          _serialResponseCallback?.call('✅ Command successful for register 0x${register.toRadixString(16).padLeft(2, '0')}');
        } else {
          _updateStatus('✗ Command failed for register 0x${register.toRadixString(16).padLeft(2, '0')} (status: 0x${status.toRadixString(16).padLeft(2, '0')})');
          _serialResponseCallback?.call('❌ Command failed for register 0x${register.toRadixString(16).padLeft(2, '0')}');
        }
      } else {
        // For other data registers that might need parsing in future
        _updateStatus('Received register 0x${register.toRadixString(16).padLeft(2, '0')} (${data.length} bytes)');
      }
    }

      _isReading = false;
      _isWriting = false;
      notifyListeners();
      
      // Call data callback with complete assembled packet (for parameter pages)
      _dataCallback?.call(packet);
      
      // Mark successful completion
      tracker.complete(additionalMetadata: {
        'register_hex': '0x${register.toRadixString(16).padLeft(2, '0')}',
        'status': status,
        'data_length': length,
      });
      
    } catch (e) {
      debugPrint('[BMS_SERVICE] ❌ Packet processing failed: $e');
      tracker.fail('Packet processing error: $e');
      rethrow;
    }
  }

  void startReading() {
    _isReading = true;
    _updateStatus('Reading registers...');
    notifyListeners();
  }

  void startWriting() {
    _isWriting = true;
    _updateStatus('Writing registers...');
    notifyListeners();
  }

  JbdRegisterValue? getRegisterValue(JbdRegister register) {
    return _registerValues[register];
  }

  void clearValues() {
    _registerValues.clear();
    _packetBuffer.clear();
    _responseTimeout?.cancel();
    _updateStatus('Register values cleared');
    debugPrint('[BMS_SERVICE] 🧹 All data cleared');
    notifyListeners();
  }
  
  @override
  void dispose() {
    _responseTimeout?.cancel();
    _performanceMonitor.stopMonitoring();
    debugPrint('[BMS_SERVICE] 🗑️ Disposed service and cleaned up');
    super.dispose();
  }

  void _updateStatus(String message) {
    _statusMessage = message;
    notifyListeners();
  }

  void _updateDebugMessage(String message) {
    _debugMessage = message;
    notifyListeners();
  }


  JbdBmsData _parseBasicInfoData(List<int> data) {
    debugPrint('[JBD] 🔍 PARSING BASIC INFO DATA (${data.length} bytes)');
    
    // Bytes 0-1: Total voltage (10mV units, high byte first)
    final totalVoltage = ((data[0] << 8) | data[1]) * 0.01;
    debugPrint('[JBD] Voltage: ${totalVoltage}V (raw: ${(data[0] << 8) | data[1]})');
    
    // Bytes 2-3: Current (10mA units, signed)
    int currentRaw = (data[2] << 8) | data[3];
    if (currentRaw > 32767) {
      currentRaw = currentRaw - 65536; // Convert to signed
    }
    final current = currentRaw * 0.01;
    debugPrint('[JBD] Current: ${current}A (raw: $currentRaw)');
    
    // Bytes 4-5: Remaining capacity (10mAh units)
    final remainingCapacity = ((data[4] << 8) | data[5]) * 0.01;
    debugPrint('[JBD] Remaining Capacity: ${remainingCapacity}Ah');
    
    // Bytes 6-7: Nominal capacity (10mAh units)  
    final nominalCapacity = ((data[6] << 8) | data[7]) * 0.01;
    debugPrint('[JBD] Nominal Capacity: ${nominalCapacity}Ah');
    
    // Bytes 8-9: Cycles
    final cycleCount = ((data[8] << 8) | data[9]);
    debugPrint('[JBD] Cycle Count: $cycleCount');
    
    // Bytes 10-11: Production Date
    final productionDateBytes = (data[10] << 8) | data[11];
    final day = productionDateBytes & 0x1F;  // lowest 5 bits
    final month = (productionDateBytes >> 5) & 0x0F;  // bits 5-8
    final year = 2000 + (productionDateBytes >> 9);  // bits 9-15
    final productionDate = DateTime(year, month, day);
    debugPrint('[JBD] Production Date: $productionDate');
    
    // Bytes 12-13: Balance1 
    final balance1 = (data[12] << 8) | data[13];
    final balance2 = (data[14] << 8) | data[15];
    final balanceStatus = (balance1 != 0 || balance2 != 0) ? 1 : 0;
    debugPrint('[JBD] Balance Status: $balanceStatus');
    
    // Bytes 16-17: Protection Status
    final protectionStatus = ((data[16] << 8) | data[17]);
    debugPrint('[JBD] Protection Status: 0x${protectionStatus.toRadixString(16)}');
    
    // Byte 18: Software version
    // Byte 19: RSOC (remaining capacity percentage)
    final chargeLevel = data[19];
    debugPrint('[JBD] Charge Level: $chargeLevel%');
    
    // Byte 20: FET control status
    final fetControl = data[20];
    final chargeFetOn = (fetControl & 0x01) != 0;
    final dischargeFetOn = (fetControl & 0x02) != 0;
    debugPrint('[JBD] Charge FET: $chargeFetOn, Discharge FET: $dischargeFetOn');
    
    // Byte 21: Number of battery strings
    final numberOfCells = data[21];
    debugPrint('[JBD] Number of Cells: $numberOfCells');
    
    // Byte 22: Number of NTC
    final ntcCount = data[22];
    debugPrint('[JBD] NTC Count: $ntcCount');
    
    // Parse temperature sensors
    List<double> temperatures = [];
    if (data.length >= 23 + (ntcCount * 2)) {
      for (int i = 0; i < ntcCount; i++) {
        int pos = 23 + (i * 2);
        if (pos + 1 < data.length) {
          int tempRaw = (data[pos] << 8) | data[pos + 1];
          double tempCelsius = (tempRaw - 2731) / 10.0;
          if (tempCelsius >= -40 && tempCelsius <= 85) {
            temperatures.add(tempCelsius);
            debugPrint('[JBD] Temperature ${i + 1}: $tempCelsius°C');
          }
        }
      }
    }
    
    return JbdBmsData(
      totalVoltage: totalVoltage,
      current: current,
      remainingCapacity: remainingCapacity,
      nominalCapacity: nominalCapacity,
      cycleCount: cycleCount,
      chargeLevel: chargeLevel,
      chargeFetOn: chargeFetOn,
      dischargeFetOn: dischargeFetOn,
      numberOfCells: numberOfCells,
      temperatures: temperatures,
      cellVoltages: [], // Will be populated separately
      balanceStatus: balanceStatus,
      protectionStatus: protectionStatus,
      productionDate: productionDate,
    );
  }


  bool _isFactoryModeOrWriteRegister(int register) {
    // Factory mode and write command registers - no data parsing needed
    // Just check success/error status
    
    // Data registers that NEED parsing (only these will parse data)
    List<int> dataRegisters = [
      0x03, // Basic Info - voltage, current, SOC, etc.
      0x04, // Cell Voltages
      0x11, // Temperature data (when used for reading temps)
      0x15, // Production date
      0xA0, // Manufacturer name
      0xA1, // Device name
      0xA2, // Barcode
      0xFA, // Parameter reading mode (BMS model, etc.)
    ];
    
    // If it's a data register, return false (needs parsing)
    if (dataRegisters.contains(register)) {
      return false;
    }
    
    // All other registers are factory/write mode - just check success/error
    return true;
  }
  
  // BMS Register Map Documentation
  // ===============================
  // 
  // CAPACITY REGISTERS:
  // 0x10 - design_cap (Pack capacity, as designed) - U16, 10mAh
  // 0x11 - cycle_cap (Pack capacity, per cycle) - U16, 10mAh  
  // 0x12 - cap_100 (Cell capacity estimate voltage, 100%) - U16, 1mV
  // 0x32 - cap_80 (Cell capacity estimate voltage, 80%) - U16, 1mV
  // 0x33 - cap_60 (Cell capacity estimate voltage, 60%) - U16, 1mV
  // 0x34 - cap_40 (Cell capacity estimate voltage, 40%) - U16, 1mV
  // 0x35 - cap_20 (Cell capacity estimate voltage, 20%) - U16, 1mV
  // 0x13 - cap_0 (Cell capacity estimate voltage, 0%) - U16, 1mV
  // 0x14 - dsg_rate (Cell estimated self discharge rate) - U16, 0.1%
  //
  // SYSTEM INFO REGISTERS:
  // 0x15 - mfg_date (Manufacture date) - 16bit: bits 15:9=year-2000, 8:5=month, 4:0=day
  // 0x16 - serial_num (Serial number) - U16
  // 0x17 - cycle_cnt (Cycle count) - U16
  //
  // TEMPERATURE PROTECTION REGISTERS:
  // 0x18 - chargeHighTempProtection (Charge High Temp threshold) - U16, 0.1K
  // 0x19 - chargeHighTempRecovery (Charge High Temp recovery threshold) - U16, 0.1K
  // 0x1A - chargeLowTempProtection (Charge Low Temp threshold) - U16, 0.1K
  // 0x1B - chargeLowTempRecovery (Charge Low Temp recovery threshold) - U16, 0.1K
  // 0x1C - dischargeHighTempProtection (Discharge High Temp threshold) - U16, 0.1K
  // 0x1D - dischargeHighTempRecovery (Discharge High Temp recovery threshold) - U16, 0.1K
  // 0x1E - dischargeLowTempProtection (Discharge Low Temp threshold) - U16, 0.1K
  // 0x1F - dischargeLowTempRecovery (Discharge Low Temp recovery threshold) - U16, 0.1K
  // 0x3A - chargeTempDelays (Charge temp delays) - 2 bytes: under_delay, over_delay
  // 0x3B - dischargeTempDelays (Discharge temp delays) - 2 bytes: under_delay, over_delay
  //
  // VOLTAGE PROTECTION REGISTERS:
  // 0x20 - povp (Pack Overvoltage Protection threshold) - U16, 10mV
  // 0x21 - povp_rel (Pack Overvoltage Protection Release threshold) - U16, 10mV
  // 0x22 - puvp (Pack Undervoltage Protection threshold) - U16, 10mV
  // 0x23 - puvp_rel (Pack Undervoltage Protection Release threshold) - U16, 10mV
  // 0x3C - pack_v_delays (Pack over/under voltage release delay) - 2 bytes: under_delay, over_delay
  // 0x24 - covp (Cell Overvoltage Protection threshold) - U16, 1mV
  // 0x25 - covp_rel (Cell Overvoltage Protection Release) - U16, 1mV
  // 0x26 - cuvp (Cell Undervoltage Protection threshold) - U16, 1mV
  // 0x27 - cuvp_rel (Cell Undervoltage Protection Release threshold) - U16, 1mV
  // 0x3D - cell_v_delays (Cell over/under voltage release delay) - 2 bytes: under_delay, over_delay
  //
  // CURRENT PROTECTION REGISTERS:
  // 0x28 - chgoc (Charge overcurrent threshold) - S16, 10mA (positive)
  // 0x3E - chgoc_delays (Charge overcurrent delays) - 2 bytes: delay, release
  // 0x29 - dsgoc (Discharge overcurrent threshold) - S16, 10mA (negative)
  // 0x3F - dsgoc_delays (Discharge overcurrent delays) - 2 bytes: delay, release
  //
  // BALANCE & CONFIGURATION REGISTERS:
  // 0x2A - bal_start (Cell balance voltage) - S16, 1mV
  // 0x2B - bal_window (Balance window) - U16, 1mV
  // 0x2C - shunt_res (Ampere measurement shunt resistor value) - U16, 0.1mΩ
  // 0x2D - func_config (Various functional config bits) - U16: switch, scrl, balance_en, chg_balance_en, led_en, led_num
  // 0x2E - ntc_config (Enable/disable NTCs) - U16: bit0=NTC1, bit1=NTC2, etc.
  // 0x2F - cell_cnt (Number of cells in the pack) - U16, 1 cell
  // 0x30 - fet_ctrl - U16, 1S
  // 0x31 - led_timer - U16, 1S
  //
  // SECONDARY PROTECTION REGISTERS:
  // 0x36 - covp_high (Secondary cell overvoltage protection) - U16, 1mV
  // 0x37 - cuvp_high (Secondary cell undervoltage protection) - U16, 1mV
  // 0x38 - sc_dsgoc2 (Short circuit and secondary overcurrent settings) - 2 bytes: complex bit structure
  // 0x39 - cxvp_high_delay_sc_rel (Secondary cell voltage delays, short circuit release) - 2 bytes: delays + sc_rel
  //
  // STRING REGISTERS:
  // 0xA0 - mfg_name (Manufacturer name) - Variable length string
  // 0xA1 - device_name (Device name) - Variable length string  
  // 0xA2 - barcode (Barcode) - Variable length string
  //
  // ERROR COUNT REGISTERS:
  // 0xAA - error_cnts (Various error condition counts) - 11 U16 values (READ ONLY)
  //
  // CALIBRATION REGISTERS:
  // 0xB0-0xCF - Cell voltage calibration registers (32) - U16, 1mV
  // 0xD0-0xD7 - NTC calibration registers (8) - U16, 0.1K
  // 0xAD - Idle Current Calibration - U16: Write 0x0 when no current flowing
  // 0xAE - Charge Current Calibration - U16, 10mA (positive value)
  // 0xAF - Discharge Current Calibration - U16, 10mA (positive value)
  //
  // CONTROL REGISTERS:
  // 0xE0 - Capacity remaining - U16, 10mAh
  // 0xE1 - MOSFET control - U16: bit0=disable_charge_FET, bit1=disable_discharge_FET
  // 0xE2 - Balance control - U16: 0x01=open_odd, 0x02=open_even, 0x03=close_all
}