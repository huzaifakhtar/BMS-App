class JbdBmsData {
  final double totalVoltage;
  final double current;
  final double remainingCapacity;
  final double nominalCapacity;
  final int cycleCount;
  final int chargeLevel;
  final bool chargeFetOn;
  final bool dischargeFetOn;
  final int numberOfCells;
  final List<double> temperatures;
  final List<double> cellVoltages;
  final int balanceStatus;
  final int protectionStatus;
  final DateTime productionDate;

  JbdBmsData({
    required this.totalVoltage,
    required this.current,
    required this.remainingCapacity,
    required this.nominalCapacity,
    required this.cycleCount,
    required this.chargeLevel,
    required this.chargeFetOn,
    required this.dischargeFetOn,
    required this.numberOfCells,
    required this.temperatures,
    required this.cellVoltages,
    required this.balanceStatus,
    required this.protectionStatus,
    required this.productionDate,
  });

  // Computed properties
  double get power => totalVoltage * current;
  bool get isCharging => current > 0;
  bool get isDischarging => current < 0;
  double get avgTemperature {
    var validTemps = temperatures.where((t) => !t.isNaN);
    return validTemps.isEmpty ? 0.0 : validTemps.reduce((a, b) => a + b) / validTemps.length;
  }
  
  // Balance status - check if any cells are being balanced
  bool get isBalancing => balanceStatus != 0;
  
  // Protection status - check if any protection is active
  bool get hasProtection => protectionStatus != 0;
}

JbdBmsData parseJbdResponse(List<int> payload) {
  // JBD Register 0x03 parsing - EXACT PROTOCOL SPECIFICATION
  // DD A5 03 00 FF FD 77 command response format:
  
  // Check 3rd byte (index 2) for response status - must be 0x00 for correct response
  final responseStatus = payload[2];
  if (responseStatus != 0x00) {
    String errorMessage = "BMS Error Response: ";
    switch (responseStatus) {
      case 0x81:
        errorMessage += "Command not recognized (0x81)";
        break;
      case 0x82:
        errorMessage += "Invalid parameter (0x82)";
        break;
      case 0x83:
        errorMessage += "Access denied (0x83)";
        break;
      default:
        errorMessage += "Unknown error (0x${responseStatus.toRadixString(16).padLeft(2, '0')})";
    }
    throw Exception(errorMessage);
  }
  
  // Get data length from 4th byte (index 3)
  final dataLength = payload[3];
  
  // Extract data portion
  final data = payload.sublist(4, 4 + dataLength);
  
  // Validate checksum: 0x10000 - (response byte + data length byte + sum of data bytes)
  final responseByte = payload[1]; // Register byte
  int dataSum = 0;
  for (int byte in data) {
    dataSum += byte;
  }
  
  final calculatedChecksum = (0x10000 - (responseByte + dataLength + dataSum)) & 0xFFFF;
  final receivedChecksum = (payload[4 + dataLength] << 8) | payload[4 + dataLength + 1];
  
  if (calculatedChecksum != receivedChecksum) {
    throw Exception("Checksum mismatch. Expected: 0x${calculatedChecksum.toRadixString(16).padLeft(4, '0')}, Got: 0x${receivedChecksum.toRadixString(16).padLeft(4, '0')}");
  }
  
  // Bytes 0-1: Total voltage (10mV units, high byte first)
  final totalVoltage = ((data[0] << 8) | data[1]) * 0.01;
  
  // Bytes 2-3: Current (10mA units, signed - charging positive, discharging negative)
  int currentRaw = (data[2] << 8) | data[3];
  if (currentRaw > 32767) {
    currentRaw = currentRaw - 65536; // Convert to signed
  }
  final current = currentRaw * 0.01;
  
  // Bytes 4-5: Remaining capacity (10mAh units)
  final remainingCapacity = ((data[4] << 8) | data[5]) * 0.01;
  // Bytes 6-7: Nominal capacity (10mAh units)  
  final nominalCapacity = ((data[6] << 8) | data[7]) * 0.01;
  // Bytes 8-9: Cycles (2 bytes)
  final cycleCount = ((data[8] << 8) | data[9]);
  // Bytes 10-11: Production Date (2 bytes)
  // Format: date = lowest 5 bits, month = bits 5-8, year = 2000 + (bits 9-15)
  final productionDateBytes = (data[10] << 8) | data[11];
  final day = productionDateBytes & 0x1F;  // lowest 5 bits
  final month = (productionDateBytes >> 5) & 0x0F;  // bits 5-8
  final year = 2000 + (productionDateBytes >> 9);  // bits 9-15
  final productionDate = DateTime(year, month, day);
  
  // Bytes 12-13: Balance1 (2 bytes) - Each bit represents balance of strings 1-16
  final balance1 = (data[12] << 8) | data[13];
  final balance2 = (data[14] << 8) | data[15];
  // Balance status: if both balance1 and balance2 are 0, then OFF, else ON
  final balanceStatus = (balance1 != 0 || balance2 != 0) ? 1 : 0;
  
  // Bytes 16-17: Protection Status (2 bytes)
  // bit0: monomer overvoltage protection
  // bit1: monomer undervoltage protection  
  // bit2: whole group overvoltage protection
  // bit3: whole group undervoltage protection
  // bit4: charging over temperature protection
  // bit5: charging low temperature protection
  // bit6: discharge over-temperature protection
  // bit7: discharge low temperature protection
  // bit8: charging overcurrent protection
  // bit9: discharge overcurrent protection
  // bit10: short circuit protection
  // bit11: Front-end detection IC error
  // bit12: software lock MOS
  // bit13-15: reserved
  final protectionStatus = ((data[16] << 8) | data[17]);
  
  // Byte 18: Software version (1 byte) - 0x10 means version 1.0
  // final softwareVersion = data[18];
  
  // Byte 19: RSOC (1 byte) - Percentage of remaining capacity
  final chargeLevel = data[19];
  
  // Byte 20: FET control status (1 byte)
  // bit0: charging MOS (0=off, 1=on)
  // bit1: discharging MOS (0=off, 1=on)
  final fetControl = data[20];
  final chargeFetOn = (fetControl & 0x01) != 0;
  final dischargeFetOn = (fetControl & 0x02) != 0;
  
  // Byte 21: Number of battery strings (1 byte)
  final numberOfCells = data[21];
  
  // Byte 22: Number of NTC (1 byte)
  final ntcCount = data[22];
  
  // Bytes 23+: NTC content (2*N bytes) - temperature sensors
  // Format: 2731+(actual temperature*10) for absolute temperature transmission
  // 0 degrees = 2731, 25 degrees = 2731+25*10 = 2981
  List<double> temperatures = [];
  
  if (data.length >= 23 + (ntcCount * 2)) {
    for (int i = 0; i < ntcCount; i++) {
      int pos = 23 + (i * 2);
      int tempRaw = (data[pos] << 8) | data[pos + 1];
      
      // Convert from absolute temperature (2731 + temp*10) to Celsius
      double tempCelsius = (tempRaw - 2731) / 10.0;
      
      // Validate temperature range (-40°C to +85°C)
      if (tempCelsius >= -40 && tempCelsius <= 85) {
        temperatures.add(tempCelsius);
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
    cellVoltages: [], // Will be populated separately by cell voltage command
    balanceStatus: balanceStatus,
    protectionStatus: protectionStatus,
    productionDate: productionDate,
  );
}

List<double> parseCellVoltages(List<int> payload) {
  List<double> cellVoltages = [];
  
  // Cell voltages are stored as 2-byte values in mV
  for (int i = 0; i < payload.length - 1; i += 2) {
    int voltageRaw = (payload[i] << 8) | payload[i + 1];
    
    // Convert from mV to V and validate reasonable range
    if (voltageRaw > 0 && voltageRaw < 5000) { // 0V to 5V range
      double voltage = voltageRaw / 1000.0;
      cellVoltages.add(voltage);
    }
  }
  
  return cellVoltages;
}