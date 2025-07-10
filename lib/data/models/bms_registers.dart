enum JbdRegister {
  // Basic Information Registers (0x03 command)
  basicInfo(0x03, 23, true, false),  // Combined basic info (23 bytes standard)
  voltage(0x04, 2, true, false),
  current(0x05, 2, true, false),
  remainingCapacity(0x06, 2, true, false),
  nominalCapacity(0x07, 2, true, false),
  cycleCount(0x08, 2, true, false),
  productionDate(0x09, 2, true, false),
  balanceStatus(0x0A, 2, true, false),
  protectionStatus(0x0B, 2, true, false),
  softwareVersion(0x0C, 1, true, false),
  remainingCapacityPercent(0x0D, 1, true, false),
  mosfetStatus(0x0E, 1, true, false),
  batteryString(0x0F, 1, true, false),
  ntcCount(0x10, 1, true, false),
  ntcTemperatures(0x11, 2, true, false),

  // Cell Voltages (0x04 command)
  cellVoltages(0x04, 32, true, false),  // All cell voltages
  cellVoltage1(0x80, 2, true, false),
  cellVoltage2(0x81, 2, true, false),
  cellVoltage3(0x82, 2, true, false),
  cellVoltage4(0x83, 2, true, false),

  // Configuration Registers
  manufacturerName(0xA0, 20, true, true),
  deviceName(0xA1, 20, true, true),
  barcode(0xA2, 20, true, true),
  bmsModel(0xFA, 8, true, true),
  
  // Parameter mode registers (0xFA with different parameter numbers)
  manufacturerParam(0xFA, 32, true, false),    // Parameter 56 (0x38) - 32 bytes
  deviceModelParam(0xFA, 32, true, false),     // Parameter 72 (0x48) - 32 bytes  
  barcodeParam(0xFA, 32, true, false),         // Parameter 88 (0x58) - 32 bytes
  batteryModel(0xFA, 24, true, false),         // Parameter 158 (0x9E) - 24 bytes
  bmsId(0xFA, 12, true, false),               // Parameter 170 (0xAA) - 12 bytes
  productionDateParam(0xFA, 2, true, false),   // Parameter 5 (0x05) - 2 bytes
  
  // Protection Parameters
  overVoltageProtection(0xB0, 2, true, true),
  underVoltageProtection(0xB1, 2, true, true),
  overCurrentChargeProtection(0xB2, 2, true, true),
  overCurrentDischargeProtection(0xB3, 2, true, true),
  
  // Capacity Settings
  designCapacity(0xC0, 2, true, true),
  cycleCapacity(0xC1, 2, true, true),
  
  // Temperature Protection Settings
  chargeHighTempProtection(0x18, 2, true, true),        // Charge over temp threshold
  chargeHighTempRecovery(0x19, 2, true, true),          // Charge over temp recovery
  chargeLowTempProtection(0x1A, 2, true, true),         // Charge under temp threshold
  chargeLowTempRecovery(0x1B, 2, true, true),           // Charge under temp recovery
  dischargeHighTempProtection(0x1C, 2, true, true),     // Discharge over temp threshold
  dischargeHighTempRecovery(0x1D, 2, true, true),       // Discharge over temp recovery
  dischargeLowTempProtection(0x1E, 2, true, true),      // Discharge under temp threshold
  dischargeLowTempRecovery(0x1F, 2, true, true),        // Discharge under temp recovery
  
  // Temperature Delay Settings
  chargeTempDelays(0x3A, 2, true, true),                // Charge temp delays (under, over)
  dischargeTempDelays(0x3B, 2, true, true);

  const JbdRegister(this.address, this.length, this.readable, this.writable);

  final int address;
  final int length;
  final bool readable;
  final bool writable;

  String get name => toString().split('.').last;
  
  String get displayName {
    switch (this) {
      case basicInfo:
        return 'Basic Information';
      case voltage:
        return 'Pack Voltage';
      case current:
        return 'Pack Current';
      case remainingCapacity:
        return 'Remaining Capacity';
      case nominalCapacity:
        return 'Full Capacity';
      case cycleCount:
        return 'Charge Cycles';
      case remainingCapacityPercent:
        return 'State of Charge';
      case protectionStatus:
        return 'Protection Status';
      case balanceStatus:
        return 'Balance Status';
      case mosfetStatus:
        return 'MOSFET Status';
      case softwareVersion:
        return 'Software Version';
      case batteryString:
        return 'Cell Count';
      case ntcCount:
        return 'Temperature Sensors';
      case ntcTemperatures:
        return 'Temperatures';
      case cellVoltages:
        return 'Cell Voltages';
      case manufacturerName:
        return 'Manufacturer Name';
      case deviceName:
        return 'Device Name';
      case bmsModel:
        return 'BMS Model';
      case manufacturerParam:
        return 'Manufacturer (Param Mode)';
      case deviceModelParam:
        return 'Device Model (Param Mode)';
      case barcodeParam:
        return 'Barcode (Param Mode)';
      case batteryModel:
        return 'Battery Model';
      case bmsId:
        return 'BMS ID';
      case productionDateParam:
        return 'Production Date (Param Mode)';
      case designCapacity:
        return 'Design Capacity';
      case overVoltageProtection:
        return 'Over Voltage Protection';
      case underVoltageProtection:
        return 'Under Voltage Protection';
      case overCurrentChargeProtection:
        return 'Over Current Charge Protection';
      case overCurrentDischargeProtection:
        return 'Over Current Discharge Protection';
      case chargeHighTempProtection:
        return 'Charge High Temperature Protection';
      case chargeHighTempRecovery:
        return 'Charge High Temperature Recovery';
      case chargeLowTempProtection:
        return 'Charge Low Temperature Protection';
      case chargeLowTempRecovery:
        return 'Charge Low Temperature Recovery';
      case dischargeHighTempProtection:
        return 'Discharge High Temperature Protection';
      case dischargeHighTempRecovery:
        return 'Discharge High Temperature Recovery';
      case dischargeLowTempProtection:
        return 'Discharge Low Temperature Protection';
      case dischargeLowTempRecovery:
        return 'Discharge Low Temperature Recovery';
      case chargeTempDelays:
        return 'Charge Temperature Delays';
      case dischargeTempDelays:
        return 'Discharge Temperature Delays';
      default:
        return name.replaceAllMapped(RegExp(r'([A-Z])'), (match) => ' ${match.group(1)}').trim();
    }
  }

  String get unit {
    switch (this) {
      case voltage:
      case overVoltageProtection:
      case underVoltageProtection:
        return 'V';
      case current:
      case overCurrentChargeProtection:
      case overCurrentDischargeProtection:
        return 'A';
      case remainingCapacity:
      case nominalCapacity:
      case designCapacity:
      case cycleCapacity:
        return 'mAh';
      case remainingCapacityPercent:
        return '%';
      case ntcTemperatures:
      case chargeHighTempProtection:
      case chargeHighTempRecovery:
      case chargeLowTempProtection:
      case chargeLowTempRecovery:
      case dischargeHighTempProtection:
      case dischargeHighTempRecovery:
      case dischargeLowTempProtection:
      case dischargeLowTempRecovery:
        return '°C';
      case chargeTempDelays:
      case dischargeTempDelays:
        return 's';
      case cellVoltages:
        return 'mV';
      default:
        return '';
    }
  }
}

class JbdRegisterValue {
  final JbdRegister register;
  final dynamic value;
  final DateTime timestamp;

  JbdRegisterValue({
    required this.register,
    required this.value,
    required this.timestamp,
  });

  String get formattedValue {
    if (value == null) return 'N/A';
    
    switch (register) {
      case JbdRegister.voltage:
      case JbdRegister.overVoltageProtection:
      case JbdRegister.underVoltageProtection:
        return (value / 100).toStringAsFixed(2);
      case JbdRegister.current:
      case JbdRegister.overCurrentChargeProtection:
      case JbdRegister.overCurrentDischargeProtection:
        return (value / 100).toStringAsFixed(2);
      case JbdRegister.manufacturerName:
      case JbdRegister.deviceName:
      case JbdRegister.barcode:
        return value.toString();
      default:
        return value.toString();
    }
  }
}