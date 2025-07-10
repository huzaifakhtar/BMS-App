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
  
  // Commands
  static const List<int> basicInfoCommand = [0xDD, 0xA5, 0x03, 0x00, 0xFF, 0xFD, 0x77];
  static const List<int> cellVoltageCommand = [0xDD, 0xA5, 0x04, 0x00, 0xFF, 0xFC, 0x77];
  static const List<int> factoryModeCommand = [0xDD, 0x5A, 0x00, 0x02, 0x56, 0x78, 0xFF, 0x30, 0x77];
}