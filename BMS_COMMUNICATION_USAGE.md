# BMS Communication Service Usage Guide

## Overview

The `BMSCommunication` service provides a centralized, clean way for all screen files to communicate with the BMS. It handles the low-level BLE communication, packet assembly, and response management, allowing screen files to focus on their specific data parsing and UI logic.

## Architecture

```
Screen Files → Communication Service → BLE Service → BMS Hardware
     ↑                    ↓
   Parsed Data ← Raw BMS Response ← BLE Data ← Hardware Response
```

## Key Features

✅ **Centralized Communication**: Single point of contact for all BMS communication  
✅ **Request-Response Pattern**: Clean async/await interface for screens  
✅ **Automatic Packet Assembly**: Handles BLE data chunking and packet reconstruction  
✅ **Command Queue Management**: Manages multiple concurrent requests  
✅ **Error Handling**: Graceful handling of timeouts and communication errors  
✅ **Predefined Commands**: Common BMS commands ready to use  
✅ **Custom Commands**: Support for any BMS register  

## Basic Usage

### 1. Initialize Communication Service

```dart
// In your app initialization or service locator
final bmsComm = BMSCommunication();

// Connect to BMS device
final connected = await bmsComm.connect(bluetoothDevice);
if (connected) {
  print('Connected to BMS');
}
```

### 2. Screen Files Request Data

```dart
// Dashboard Screen Example
class DashboardService extends ChangeNotifier {
  final BMSCommunication _communication;
  
  DashboardService(this._communication);
  
  Future<void> fetchDashboardData() async {
    // Request basic info and cell voltages
    final results = await Future.wait([
      _communication.getBasicInfo(),
      _communication.getCellVoltages(),
    ]);
    
    final basicInfo = results[0];
    final cellVoltages = results[1];
    
    if (basicInfo != null && cellVoltages != null) {
      _parseAndUpdateUI(basicInfo, cellVoltages);
    }
  }
  
  void _parseAndUpdateUI(List<int> basicInfo, List<int> cellVoltages) {
    // Each screen parses its own data according to its needs
    final response = BMSResponse(basicInfo);
    if (response.isSuccess) {
      final data = response.data;
      // Parse voltage, current, SOC, etc.
      final voltage = ((data[0] << 8) | data[1]) * 0.01;
      final soc = data[19];
      // Update UI...
    }
  }
}
```

### 3. Parameters Screen Example

```dart
class ParametersScreen extends StatefulWidget {
  @override
  _ParametersScreenState createState() => _ParametersScreenState();
}

class _ParametersScreenState extends State<ParametersScreen> {
  late BMSCommunication _communication;
  Map<String, dynamic> _parameters = {};
  
  @override
  void initState() {
    super.initState();
    _communication = context.read<BMSCommunication>();
    _loadParameters();
  }
  
  Future<void> _loadParameters() async {
    // Read specific parameters
    final ovpResponse = await _communication.sendCustomCommand(0x24); // Cell OVP
    final uvpResponse = await _communication.sendCustomCommand(0x26); // Cell UVP
    
    if (ovpResponse != null) {
      final response = BMSResponse(ovpResponse);
      if (response.isSuccess && response.data.length >= 2) {
        final ovpValue = ((response.data[0] << 8) | response.data[1]) / 1000.0;
        setState(() {
          _parameters['cellOVP'] = '${ovpValue.toStringAsFixed(3)}V';
        });
      }
    }
    
    // Similar parsing for other parameters...
  }
  
  Future<void> _writeParameter(int register, List<int> value) async {
    final response = await _communication.sendCustomCommand(register, data: value);
    if (response != null) {
      final bmsResponse = BMSResponse(response);
      if (bmsResponse.isSuccess) {
        // Parameter written successfully
        _showSuccess();
      } else {
        _showError();
      }
    }
  }
}
```

### 4. Basic Info Screen Example

```dart
class BasicInfoScreen extends StatefulWidget {
  @override
  _BasicInfoScreenState createState() => _BasicInfoScreenState();
}

class _BasicInfoScreenState extends State<BasicInfoScreen> {
  late BMSCommunication _communication;
  String _manufacturer = '';
  String _deviceModel = '';
  String _barcode = '';
  
  @override
  void initState() {
    super.initState();
    _communication = context.read<BMSCommunication>();
    _loadBasicInfo();
  }
  
  Future<void> _loadBasicInfo() async {
    // Request all basic info in parallel
    final results = await Future.wait([
      _communication.getManufacturer(),
      _communication.getDeviceModel(),
      _communication.getBarcode(),
    ]);
    
    // Parse manufacturer
    if (results[0] != null) {
      final response = BMSResponse(results[0]!);
      if (response.isSuccess) {
        _manufacturer = _parseTextData(response.data);
      }
    }
    
    // Parse device model
    if (results[1] != null) {
      final response = BMSResponse(results[1]!);
      if (response.isSuccess) {
        _deviceModel = _parseTextData(response.data);
      }
    }
    
    // Parse barcode
    if (results[2] != null) {
      final response = BMSResponse(results[2]!);
      if (response.isSuccess) {
        _barcode = _parseTextData(response.data);
      }
    }
    
    setState(() {}); // Update UI
  }
  
  String _parseTextData(List<int> data) {
    return data.where((b) => b >= 32 && b <= 126)
               .map((b) => String.fromCharCode(b))
               .join('')
               .trim();
  }
}
```

## Available Commands

### Predefined Commands
```dart
// Basic BMS data
final basicInfo = await communication.getBasicInfo();        // 0x03
final cellVoltages = await communication.getCellVoltages();  // 0x04
final temperatures = await communication.getTemperatures();  // 0x11

// Device information
final manufacturer = await communication.getManufacturer();  // 0xA0
final deviceModel = await communication.getDeviceModel();    // 0x05
final barcode = await communication.getBarcode();           // 0xA2
```

### Custom Commands
```dart
// Read any register
final response = await communication.sendCustomCommand(0x20); // Pack OVP

// Write to any register
final writeResponse = await communication.sendCustomCommand(
  0x20, 
  data: [0x10, 0x68] // 4200mV = 4200/10 = 420 = 0x01A4
);

// Create command manually
final customCommand = communication.createCommand(0x15); // Production date
final response = await communication.sendCommand(customCommand);
```

## Response Handling

### Using BMSResponse Helper
```dart
final rawResponse = await communication.getBasicInfo();
if (rawResponse != null) {
  final response = BMSResponse(rawResponse);
  
  print('Register: 0x${response.register.toRadixString(16)}');
  print('Status: 0x${response.status.toRadixString(16)}');
  print('Success: ${response.isSuccess}');
  print('Data Length: ${response.data.length}');
  print('Raw Data: ${response.data}');
}
```

### Manual Response Parsing
```dart
final rawResponse = await communication.getBasicInfo();
if (rawResponse != null && rawResponse.length >= 7) {
  final register = rawResponse[1];
  final status = rawResponse[2];
  final dataLength = rawResponse[3];
  final data = rawResponse.sublist(4, 4 + dataLength);
  
  if (status == 0x00) {
    // Parse data according to your needs
    final voltage = ((data[0] << 8) | data[1]) * 0.01;
    // ...
  }
}
```

## Error Handling

```dart
try {
  final response = await communication.getBasicInfo();
  
  if (response == null) {
    // Timeout or communication error
    print('Failed to get response from BMS');
    return;
  }
  
  final bmsResponse = BMSResponse(response);
  if (!bmsResponse.isSuccess) {
    // BMS returned error status
    print('BMS error: Status 0x${bmsResponse.status.toRadixString(16)}');
    return;
  }
  
  // Process successful response
  _processData(bmsResponse.data);
  
} catch (e) {
  print('Communication error: $e');
}
```

## Best Practices

### 1. **Screen-Specific Services**
Create dedicated services for each screen that handle their specific data parsing:

```dart
// dashboard_service.dart - Uses communication service
// parameters_service.dart - Uses communication service  
// basic_info_service.dart - Uses communication service
```

### 2. **Batch Requests**
Group related requests together to minimize BLE overhead:

```dart
// Good: Parallel requests
final results = await Future.wait([
  communication.getBasicInfo(),
  communication.getCellVoltages(),
]);

// Avoid: Sequential requests when not necessary
final basic = await communication.getBasicInfo();
final cells = await communication.getCellVoltages();
```

### 3. **Error Recovery**
Implement proper error handling and retry logic:

```dart
Future<List<int>?> _requestWithRetry(Future<List<int>?> request, {int maxRetries = 3}) async {
  for (int i = 0; i < maxRetries; i++) {
    try {
      final response = await request;
      if (response != null) return response;
    } catch (e) {
      if (i == maxRetries - 1) rethrow;
      await Future.delayed(Duration(milliseconds: 500 * (i + 1)));
    }
  }
  return null;
}
```

### 4. **Data Validation**
Always validate BMS responses before using the data:

```dart
void _parseBasicInfo(List<int> data) {
  if (data.length < 23) {
    print('Insufficient data for basic info parsing');
    return;
  }
  
  final voltage = ((data[0] << 8) | data[1]) * 0.01;
  if (voltage < 0 || voltage > 100) {
    print('Invalid voltage reading: $voltage');
    return;
  }
  
  // Proceed with valid data...
}
```

## Benefits

1. **Separation of Concerns**: Communication logic separated from UI logic
2. **Reusability**: Same communication service used by all screens
3. **Maintainability**: Changes to BLE communication only affect one file
4. **Testability**: Easy to mock communication service for testing
5. **Error Handling**: Centralized error handling and recovery
6. **Performance**: Efficient packet assembly and request management

This architecture provides a clean, maintainable way for all screen files to get the data they need from the BMS while keeping the communication complexity hidden.