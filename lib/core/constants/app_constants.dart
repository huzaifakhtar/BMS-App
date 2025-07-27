class AppConstants {
  // BMS Protocol Constants
  static const int startByte = 0xDD;
  static const int readCommand = 0xA5;
  static const int writeCommand = 0x5A;
  static const int endByte = 0x77;
  
  // Data Conversion Factors
  static const double voltageMultiplier = 0.01;
  static const double currentMultiplier = 0.01;
  static const double temperatureDivisor = 10.0;
  static const double temperatureOffset = 273.15;
  
  // Timing Constants
  static const Duration updateInterval = Duration(seconds: 1);
  static const Duration responseTimeout = Duration(milliseconds: 100);
  static const Duration connectionTimeout = Duration(seconds: 10);
  static const Duration scanTimeout = Duration(seconds: 15);
  
  // Buffer Sizes
  static const int minPacketSize = 7;
  static const int maxPacketSize = 256;
  
  // BLE Service UUIDs
  static const String jbdServiceUuid = '0000ff00-0000-1000-8000-00805f9b34fb';
  static const String jbdWriteCharUuid = '0000ff02-0000-1000-8000-00805f9b34fb';
  static const String jbdReadCharUuid = '0000ff01-0000-1000-8000-00805f9b34fb';
  
  // Basic Commands
  static const List<int> basicInfoCommand = [0xDD, 0xA5, 0x03, 0x00, 0xFF, 0xFD, 0x77];
  static const List<int> cellVoltageCommand = [0xDD, 0xA5, 0x04, 0x00, 0xFF, 0xFC, 0x77];
  static const List<int> temperatureCommand = [0xDD, 0xA5, 0x11, 0x00, 0xFF, 0xEF, 0x77];
  
  // Factory Mode Command (required for some parameter reads)
  static const List<int> factoryModeCommand = [0xDD, 0x5A, 0x00, 0x02, 0x56, 0x78, 0xFF, 0x30, 0x77];
  
  // Parameter Read Commands (0xFA register)
  // Production Date
  static const List<int> productionDateCommand = [0xDD, 0xA5, 0xFA, 0x03, 0x00, 0x05, 0x01, 0xFF, 0xF6, 0x77];
  
  // Serial Number/Bar Code  
  static const List<int> serialNumberCommand = [0xDD, 0xA5, 0xFA, 0x03, 0x00, 0x06, 0x01, 0xFF, 0xF5, 0x77];
  
  // Manufacturer Info
  static const List<int> manufacturerInfoCommand = [0xDD, 0xA5, 0xFA, 0x03, 0x00, 0x38, 0x10, 0xFE, 0xBB, 0x77];
  
  // BMS Model/Coding Info
  static const List<int> bmsModelCommand = [0xDD, 0xA5, 0xFA, 0x03, 0x00, 0x48, 0x10, 0xFE, 0xAB, 0x77];
  
  // Battery Model
  static const List<int> batteryModelCommand = [0xDD, 0xA5, 0xFA, 0x03, 0x00, 0x9E, 0x0C, 0xFE, 0x45, 0x77];
  
  // Barcode Info
  static const List<int> barcodeInfoCommand = [0xDD, 0xA5, 0xFA, 0x03, 0x00, 0x58, 0x10, 0xFE, 0x9B, 0x77];
  
  // Legacy Commands for compatibility
  static const List<int> manufacturerCommand = [0xDD, 0xA5, 0xA0, 0x00, 0xFF, 0x60, 0x77];
  static const List<int> deviceNameCommand = [0xDD, 0xA5, 0xA1, 0x00, 0xFF, 0x5F, 0x77];
  static const List<int> barcodeCommand = [0xDD, 0xA5, 0xA2, 0x00, 0xFF, 0x5E, 0x77];
  static const List<int> hardwareVersionCommand = [0xDD, 0xA5, 0x05, 0x00, 0xFF, 0xFB, 0x77];
}