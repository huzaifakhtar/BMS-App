class BMSCommandUtils {
  // Protocol constants
  static const int startByte = 0xDD;
  static const int readCommand = 0xA5;
  static const int writeCommand = 0x5A;
  static const int endByte = 0x77;
  static const int parameterRegister = 0xFA;
  
  // Response status codes
  static const int statusSuccess = 0x00;
  static const int statusCommandNotFound = 0x80;
  static const int statusInvalidOperation = 0x81;
  static const int statusChecksumError = 0x82;
  static const int statusPasswordMismatch = 0x83;
  
  /// Calculate JBD protocol checksum
  static int calculateChecksum(List<int> command) {
    int sum = 0;
    for (int byte in command) {
      sum += byte;
    }
    return (0x10000 - sum) & 0xFFFF;
  }
  
  /// Create parameter read command for 0xFA register
  static List<int> createParameterCommand({
    required int paramNumber,
    required int dataLength,
  }) {
    List<int> command = [
      startByte,          // 0xDD
      readCommand,        // 0xA5
      parameterRegister,  // 0xFA
      0x03,              // Length = 3 bytes
      0x00,              // Data byte 1
      paramNumber,       // Parameter number
      dataLength,        // Expected data length
    ];
    
    // Calculate and add checksum
    int checksum = calculateChecksum(command);
    command.addAll([
      (checksum >> 8) & 0xFF,  // Checksum high
      checksum & 0xFF,         // Checksum low
      endByte,                 // 0x77
    ]);
    
    return command;
  }
  
  /// Create basic read command
  static List<int> createBasicReadCommand(int register) {
    List<int> command = [
      startByte,    // 0xDD
      readCommand,  // 0xA5
      register,     // Register address
      0x00,        // Length = 0 for read
    ];
    
    // Calculate and add checksum
    int checksum = calculateChecksum(command);
    command.addAll([
      (checksum >> 8) & 0xFF,  // Checksum high
      checksum & 0xFF,         // Checksum low
      endByte,                 // 0x77
    ]);
    
    return command;
  }
  
  /// Factory mode command
  static List<int> get factoryModeCommand {
    return [0xDD, 0x5A, 0x00, 0x02, 0x56, 0x78, 0xFF, 0x30, 0x77];
  }
  
  /// Production Date command
  static List<int> get productionDateCommand {
    return createParameterCommand(paramNumber: 0x05, dataLength: 0x01);
  }
  
  /// Serial Number command
  static List<int> get serialNumberCommand {
    return createParameterCommand(paramNumber: 0x06, dataLength: 0x01);
  }
  
  /// Manufacturer Info command
  static List<int> get manufacturerInfoCommand {
    return createParameterCommand(paramNumber: 0x38, dataLength: 0x10);
  }
  
  /// BMS Model command
  static List<int> get bmsModelCommand {
    return createParameterCommand(paramNumber: 0x48, dataLength: 0x10);
  }
  
  /// Battery Model command
  static List<int> get batteryModelCommand {
    return createParameterCommand(paramNumber: 0x9E, dataLength: 0x0C);
  }
  
  /// Barcode Info command
  static List<int> get barcodeInfoCommand {
    return createParameterCommand(paramNumber: 0x58, dataLength: 0x10);
  }
  
  /// Basic Info command (0x03)
  static List<int> get basicInfoCommand {
    return createBasicReadCommand(0x03);
  }
  
  /// Cell Voltage command (0x04)
  static List<int> get cellVoltageCommand {
    return createBasicReadCommand(0x04);
  }
  
  /// Temperature command (0x11)
  static List<int> get temperatureCommand {
    return createBasicReadCommand(0x11);
  }
  
  /// Hardware Version command (0x05) - BMS Model
  static List<int> get hardwareVersionCommand {
    return [0xDD, 0xA5, 0x05, 0x00, 0xFF, 0xFB, 0x77];
  }
  
  /// Unique ID Code command
  static List<int> get uniqueIdCommand {
    return createParameterCommand(paramNumber: 0xAA, dataLength: 0x06);
  }
  
  /// Legacy manufacturer command (0xA0)
  static List<int> get manufacturerCommand {
    return createBasicReadCommand(0xA0);
  }
  
  /// Legacy device name command (0xA1)
  static List<int> get deviceNameCommand {
    return createBasicReadCommand(0xA1);
  }
  
  /// Legacy barcode command (0xA2)
  static List<int> get barcodeCommand {
    return createBasicReadCommand(0xA2);
  }
  
  /// Format command as hex string for debugging
  static String commandToHexString(List<int> command) {
    return command.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join(' ');
  }
  
  /// Verify command checksum
  static bool verifyChecksum(List<int> command) {
    if (command.length < 7) return false;
    
    // Extract command without checksum and end byte
    List<int> commandPart = command.sublist(0, command.length - 3);
    
    // Calculate expected checksum
    int expectedChecksum = calculateChecksum(commandPart);
    
    // Extract received checksum
    int receivedChecksum = (command[command.length - 3] << 8) | command[command.length - 2];
    
    return expectedChecksum == receivedChecksum;
  }
}

/// BMS Parameter types for easy reference
enum BMSParameter {
  productionDate(0x05, 0x01, 'Production Date'),
  serialNumber(0x06, 0x01, 'Serial Number'),
  manufacturerInfo(0x38, 0x10, 'Manufacturer Info'),
  bmsModel(0x48, 0x10, 'BMS Model'),
  batteryModel(0x9E, 0x0C, 'Battery Model'),
  barcodeInfo(0x58, 0x10, 'Barcode Info'),
  uniqueId(0xAA, 0x06, 'Unique ID Code');
  
  const BMSParameter(this.paramNumber, this.dataLength, this.description);
  
  final int paramNumber;
  final int dataLength;
  final String description;
  
  /// Get command for this parameter
  List<int> get command {
    return BMSCommandUtils.createParameterCommand(
      paramNumber: paramNumber,
      dataLength: dataLength,
    );
  }
}

/// BMS Response Parser - Handles protocol-specific parsing logic
class BMSResponseParser {
  
  /// Validate response frame structure
  static BMSResponseValidation validateResponse(List<int> response) {
    if (response.length < 7) {
      return const BMSResponseValidation(isValid: false, error: 'Response too short');
    }
    
    if (response[0] != BMSCommandUtils.startByte) {
      return const BMSResponseValidation(isValid: false, error: 'Invalid start byte');
    }
    
    if (response[response.length - 1] != BMSCommandUtils.endByte) {
      return const BMSResponseValidation(isValid: false, error: 'Invalid end byte');
    }
    
    // Check status byte (index 2)
    int statusByte = response[2];
    if (statusByte != BMSCommandUtils.statusSuccess) {
      String error = _getStatusError(statusByte);
      return BMSResponseValidation(isValid: false, error: 'Status error: $error');
    }
    
    return const BMSResponseValidation(isValid: true);
  }
  
  /// Parse Hardware Version (BMS Model) - ASCII with length prefix
  static String? parseHardwareVersion(List<int> response) {
    final validation = validateResponse(response);
    if (!validation.isValid) return null;
    
    // Skip header: DD 05 00 [LENGTH]
    if (response.length < 5) return null;
    
    int dataLength = response[3];
    if (response.length < 4 + dataLength + 3) return null; // +3 for checksum and end
    
    // Extract ASCII data
    List<int> asciiData = response.sublist(4, 4 + dataLength);
    return String.fromCharCodes(asciiData).trim();
  }
  
  /// Parse Production Date - 2-byte date value
  static ProductionDate? parseProductionDate(List<int> response) {
    final validation = validateResponse(response);
    if (!validation.isValid) return null;
    
    // Skip header: DD FA 00 [LENGTH]
    if (response.length < 8) return null;
    
    int dataLength = response[3];
    if (dataLength < 2) return null;
    
    // Extract 2-byte date value (big-endian)
    int dateValue = (response[4] << 8) | response[5];
    
    // Decode: Day = value & 0x1F, Month = (value >> 5) & 0x0F, Year = 2000 + (value >> 9)
    int day = dateValue & 0x1F;
    int month = (dateValue >> 5) & 0x0F;
    int year = 2000 + (dateValue >> 9);
    
    return ProductionDate(day: day, month: month, year: year);
  }
  
  /// Parse Serial Number - 2-byte value
  static int? parseSerialNumber(List<int> response) {
    final validation = validateResponse(response);
    if (!validation.isValid) return null;
    
    if (response.length < 8) return null;
    
    int dataLength = response[3];
    if (dataLength < 2) return null;
    
    // Combine high and low bytes (big-endian)
    return (response[4] << 8) | response[5];
  }
  
  /// Parse ASCII String with length prefix (Manufacturer, BMS Model, Battery Model, Barcode)
  static String? parseAsciiStringWithLength(List<int> response) {
    final validation = validateResponse(response);
    if (!validation.isValid) return null;
    
    // Skip header: DD FA 00 [LENGTH]
    if (response.length < 5) return null;
    
    int totalDataLength = response[3];
    if (response.length < 4 + totalDataLength + 3) return null;
    
    // First byte of data is the actual string length
    int stringLength = response[4];
    if (stringLength == 0) return '';
    
    if (totalDataLength < stringLength + 1) return null;
    
    // Extract ASCII string
    List<int> stringData = response.sublist(5, 5 + stringLength);
    return String.fromCharCodes(stringData).trim();
  }
  
  /// Parse Unique ID - 12-byte hex values
  static String? parseUniqueId(List<int> response) {
    final validation = validateResponse(response);
    if (!validation.isValid) return null;
    
    if (response.length < 16) return null; // 4 header + 12 data + 3 footer
    
    int dataLength = response[3];
    if (dataLength < 12) return null;
    
    // Extract 12 hex bytes and format as string
    List<int> hexData = response.sublist(4, 16);
    return hexData.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join('');
  }
  
  /// Get error message for status codes
  static String _getStatusError(int statusCode) {
    switch (statusCode) {
      case BMSCommandUtils.statusCommandNotFound:
        return 'Command not found (0x80)';
      case BMSCommandUtils.statusInvalidOperation:
        return 'Invalid operation - Factory mode required (0x81)';
      case BMSCommandUtils.statusChecksumError:
        return 'Checksum error (0x82)';
      case BMSCommandUtils.statusPasswordMismatch:
        return 'Password mismatch (0x83)';
      default:
        return 'Unknown error (0x${statusCode.toRadixString(16)})';
    }
  }
}

/// Response validation result
class BMSResponseValidation {
  final bool isValid;
  final String? error;
  
  const BMSResponseValidation({required this.isValid, this.error});
}

/// Production date structure
class ProductionDate {
  final int day;
  final int month;
  final int year;
  
  const ProductionDate({required this.day, required this.month, required this.year});
  
  @override
  String toString() => '$day/${month.toString().padLeft(2, '0')}/$year';
  
  /// Convert to DateTime (with day 1 if day is 0)
  DateTime toDateTime() => DateTime(year, month, day == 0 ? 1 : day);
}

/// Factory mode helper
class BMSFactoryMode {
  /// Enter factory mode command
  static List<int> get enterFactoryMode => [0xDD, 0x5A, 0x00, 0x02, 0x56, 0x78, 0xFF, 0x30, 0x77];
  
  /// Exit factory mode command  
  static List<int> get exitFactoryMode => [0xDD, 0x5A, 0x01, 0x02, 0x28, 0x28, 0xFF, 0x58, 0x77];
}