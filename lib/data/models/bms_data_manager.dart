import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../services/bluetooth/ble_service.dart';
import 'bms_data_model.dart';

// Define what data variables are available
enum BmsDataVariable {
  totalVoltage,
  current,
  power,
  remainingCapacity,
  nominalCapacity,
  cycleCount,
  chargeLevel,
  chargeFetOn,
  dischargeFetOn,
  numberOfCells,
  temperatures,
  cellVoltages,
  balanceStatus,
  protectionStatus,
  productionDate,
}

// Define which commands provide which data
class BmsCommandMapping {
  static const Map<int, List<BmsDataVariable>> commandToVariables = {
    0x03: [  // Basic info command
      BmsDataVariable.totalVoltage,
      BmsDataVariable.current,
      BmsDataVariable.power,
      BmsDataVariable.remainingCapacity,
      BmsDataVariable.nominalCapacity,
      BmsDataVariable.cycleCount,
      BmsDataVariable.chargeLevel,
      BmsDataVariable.chargeFetOn,
      BmsDataVariable.dischargeFetOn,
      BmsDataVariable.numberOfCells,
      BmsDataVariable.temperatures,
      BmsDataVariable.balanceStatus,
      BmsDataVariable.protectionStatus,
      BmsDataVariable.productionDate,
    ],
    0x04: [  // Cell voltages command
      BmsDataVariable.cellVoltages,
    ],
  };

  // Reverse mapping: which command to send for each variable
  static const Map<BmsDataVariable, int> variableToCommand = {
    BmsDataVariable.totalVoltage: 0x03,
    BmsDataVariable.current: 0x03,
    BmsDataVariable.power: 0x03,
    BmsDataVariable.remainingCapacity: 0x03,
    BmsDataVariable.nominalCapacity: 0x03,
    BmsDataVariable.cycleCount: 0x03,
    BmsDataVariable.chargeLevel: 0x03,
    BmsDataVariable.chargeFetOn: 0x03,
    BmsDataVariable.dischargeFetOn: 0x03,
    BmsDataVariable.numberOfCells: 0x03,
    BmsDataVariable.temperatures: 0x03,
    BmsDataVariable.balanceStatus: 0x03,
    BmsDataVariable.protectionStatus: 0x03,
    BmsDataVariable.productionDate: 0x03,
    BmsDataVariable.cellVoltages: 0x04,
  };

  // Command bytes for each command
  static const Map<int, List<int>> commandBytes = {
    0x03: [0xDD, 0xA5, 0x03, 0x00, 0xFF, 0xFD, 0x77], // Basic info
    0x04: [0xDD, 0xA5, 0x04, 0x00, 0xFF, 0xFC, 0x77], // Cell voltages
  };
}

class BmsDataManager extends ChangeNotifier {
  final BleService _bleService;
  
  // Current data cache
  JbdBmsData? _currentData;
  List<double> _currentCellVoltages = [];
  
  // Response handling
  final Map<int, Completer<List<int>>> _pendingRequests = {};
  Timer? _responseTimeout;
  
  BmsDataManager(this._bleService) {
    _bleService.addDataCallback(_handleRawResponse);
  }

  // Main method: Request specific data variables
  Future<Map<BmsDataVariable, dynamic>> requestData(List<BmsDataVariable> variables) async {
    debugPrint('[BMS_MANAGER] 📋 Requesting data for: ${variables.map((v) => v.name).join(', ')}');
    
    // Determine which commands we need to send
    Set<int> requiredCommands = {};
    for (var variable in variables) {
      final command = BmsCommandMapping.variableToCommand[variable];
      if (command != null) {
        requiredCommands.add(command);
      }
    }
    
    debugPrint('[BMS_MANAGER] 📤 Need to send commands: ${requiredCommands.map((c) => '0x${c.toRadixString(16).padLeft(2, '0')}').join(', ')}');
    
    // Send commands and collect responses
    Map<int, JbdBmsData?> commandResponses = {};
    List<double>? cellVoltages;
    
    for (int command in requiredCommands) {
      try {
        if (command == 0x03) {
          // Basic info command
          final response = await _sendCommandAndWait(command);
          final basicData = parseJbdResponse(response);
          commandResponses[command] = basicData;
          _currentData = basicData;
          debugPrint('[BMS_MANAGER] ✅ Basic info received: ${basicData.totalVoltage}V, ${basicData.chargeLevel}%');
        } else if (command == 0x04) {
          // Cell voltages command
          final response = await _sendCommandAndWait(command);
          cellVoltages = parseCellVoltages(response);
          _currentCellVoltages = cellVoltages;
          debugPrint('[BMS_MANAGER] ✅ Cell voltages received: ${cellVoltages.length} cells');
        }
      } catch (e) {
        debugPrint('[BMS_MANAGER] ❌ Command 0x${command.toRadixString(16)} failed: $e');
      }
    }
    
    // Build result map with requested variables
    Map<BmsDataVariable, dynamic> result = {};
    
    for (var variable in variables) {
      switch (variable) {
        case BmsDataVariable.totalVoltage:
          result[variable] = _currentData?.totalVoltage ?? 0.0;
          break;
        case BmsDataVariable.current:
          result[variable] = _currentData?.current ?? 0.0;
          break;
        case BmsDataVariable.power:
          result[variable] = _currentData?.power ?? 0.0;
          break;
        case BmsDataVariable.remainingCapacity:
          result[variable] = _currentData?.remainingCapacity ?? 0.0;
          break;
        case BmsDataVariable.nominalCapacity:
          result[variable] = _currentData?.nominalCapacity ?? 0.0;
          break;
        case BmsDataVariable.cycleCount:
          result[variable] = _currentData?.cycleCount ?? 0;
          break;
        case BmsDataVariable.chargeLevel:
          result[variable] = _currentData?.chargeLevel ?? 0;
          break;
        case BmsDataVariable.chargeFetOn:
          result[variable] = _currentData?.chargeFetOn ?? false;
          break;
        case BmsDataVariable.dischargeFetOn:
          result[variable] = _currentData?.dischargeFetOn ?? false;
          break;
        case BmsDataVariable.numberOfCells:
          result[variable] = _currentData?.numberOfCells ?? 0;
          break;
        case BmsDataVariable.temperatures:
          result[variable] = _currentData?.temperatures ?? <double>[];
          break;
        case BmsDataVariable.cellVoltages:
          result[variable] = _currentCellVoltages;
          break;
        case BmsDataVariable.balanceStatus:
          result[variable] = _currentData?.balanceStatus ?? 0;
          break;
        case BmsDataVariable.protectionStatus:
          result[variable] = _currentData?.protectionStatus ?? 0;
          break;
        case BmsDataVariable.productionDate:
          result[variable] = _currentData?.productionDate ?? DateTime.now();
          break;
      }
    }
    
    debugPrint('[BMS_MANAGER] 🎯 Returning ${result.length} variables');
    notifyListeners();
    return result;
  }

  // Convenience method for dashboard - gets all basic dashboard data
  Future<Map<BmsDataVariable, dynamic>> getDashboardData() async {
    return requestData([
      BmsDataVariable.totalVoltage,
      BmsDataVariable.current,
      BmsDataVariable.power,
      BmsDataVariable.chargeLevel,
      BmsDataVariable.cycleCount,
      BmsDataVariable.chargeFetOn,
      BmsDataVariable.dischargeFetOn,
      BmsDataVariable.temperatures,
      BmsDataVariable.cellVoltages,
      BmsDataVariable.balanceStatus,
      BmsDataVariable.protectionStatus,
    ]);
  }

  // Send command and wait for response
  Future<List<int>> _sendCommandAndWait(int command) async {
    final commandBytes = BmsCommandMapping.commandBytes[command];
    if (commandBytes == null) {
      throw Exception('Unknown command: 0x${command.toRadixString(16)}');
    }

    debugPrint('[BMS_MANAGER] 📤 Sending command 0x${command.toRadixString(16)}: ${commandBytes.map((b) => '0x${b.toRadixString(16).padLeft(2, '0')}').join(' ')}');

    // Set up response expectation
    final completer = Completer<List<int>>();
    _pendingRequests[command] = completer;

    // Set timeout
    _responseTimeout?.cancel();
    _responseTimeout = Timer(const Duration(seconds: 3), () {
      if (!completer.isCompleted) {
        _pendingRequests.remove(command);
        completer.completeError('Command 0x${command.toRadixString(16)} timeout');
      }
    });

    // Send command
    await _bleService.writeData(commandBytes);

    // Wait for response
    return completer.future;
  }

  // Handle raw BLE responses
  void _handleRawResponse(List<int> response) {
    if (response.length < 4) return;

    final register = response[1];
    final status = response[2];

    debugPrint('[BMS_MANAGER] 📥 Raw response for register 0x${register.toRadixString(16)}: ${response.length} bytes');

    // Check if we're waiting for this response
    final completer = _pendingRequests[register];
    if (completer != null && !completer.isCompleted) {
      _pendingRequests.remove(register);
      _responseTimeout?.cancel();

      if (status == 0x00) {
        // Extract data portion
        final dataLength = response[3];
        final data = response.sublist(4, 4 + dataLength);
        debugPrint('[BMS_MANAGER] ✅ Completing request for 0x${register.toRadixString(16)} with ${data.length} bytes');
        completer.complete(data);
      } else {
        debugPrint('[BMS_MANAGER] ❌ Error response for 0x${register.toRadixString(16)}: status=0x${status.toRadixString(16)}');
        completer.completeError('BMS returned error status: 0x${status.toRadixString(16)}');
      }
    }
  }

  // Get cached data without sending commands
  Map<BmsDataVariable, dynamic> getCachedData(List<BmsDataVariable> variables) {
    Map<BmsDataVariable, dynamic> result = {};
    
    for (var variable in variables) {
      switch (variable) {
        case BmsDataVariable.totalVoltage:
          result[variable] = _currentData?.totalVoltage ?? 0.0;
          break;
        case BmsDataVariable.current:
          result[variable] = _currentData?.current ?? 0.0;
          break;
        case BmsDataVariable.power:
          result[variable] = _currentData?.power ?? 0.0;
          break;
        case BmsDataVariable.remainingCapacity:
          result[variable] = _currentData?.remainingCapacity ?? 0.0;
          break;
        case BmsDataVariable.nominalCapacity:
          result[variable] = _currentData?.nominalCapacity ?? 0.0;
          break;
        case BmsDataVariable.cycleCount:
          result[variable] = _currentData?.cycleCount ?? 0;
          break;
        case BmsDataVariable.chargeLevel:
          result[variable] = _currentData?.chargeLevel ?? 0;
          break;
        case BmsDataVariable.chargeFetOn:
          result[variable] = _currentData?.chargeFetOn ?? false;
          break;
        case BmsDataVariable.dischargeFetOn:
          result[variable] = _currentData?.dischargeFetOn ?? false;
          break;
        case BmsDataVariable.numberOfCells:
          result[variable] = _currentData?.numberOfCells ?? 0;
          break;
        case BmsDataVariable.temperatures:
          result[variable] = _currentData?.temperatures ?? <double>[];
          break;
        case BmsDataVariable.cellVoltages:
          result[variable] = _currentCellVoltages;
          break;
        case BmsDataVariable.balanceStatus:
          result[variable] = _currentData?.balanceStatus ?? 0;
          break;
        case BmsDataVariable.protectionStatus:
          result[variable] = _currentData?.protectionStatus ?? 0;
          break;
        case BmsDataVariable.productionDate:
          result[variable] = _currentData?.productionDate ?? DateTime.now();
          break;
      }
    }
    
    return result;
  }

  @override
  void dispose() {
    _responseTimeout?.cancel();
    _pendingRequests.clear();
    super.dispose();
  }
}