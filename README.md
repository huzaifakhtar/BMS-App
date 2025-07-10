# JBD BMS Configuration App

A Flutter mobile application for connecting to JBD (Jiabaida) Battery Management Systems via Bluetooth Low Energy (BLE) to read and configure device parameters.

## Features

✅ **Bluetooth Low Energy Connection**
- Discover and connect to JBD BMS devices
- Automatic service and characteristic discovery
- Real-time connection status monitoring

✅ **Register Reading & Writing**
- Read basic system information (voltage, current, capacity, etc.)
- Configure device parameters (manufacturer name, device name, protection settings)
- Real-time data display with timestamps

✅ **JBD Protocol Implementation**
- Complete JBD communication protocol with checksum validation
- Proper command formatting and response parsing
- Debug mode for protocol inspection

✅ **User-Friendly Interface**
- Material 3 design with clean, intuitive layout
- Tabbed interface for monitoring and configuration
- Status indicators and progress feedback
- Error handling with user-friendly messages

## Screenshots

The app consists of two main screens:

1. **Connection Screen**: Scan for and connect to JBD BMS devices
2. **Configuration Screen**: Monitor values and configure device parameters

## Setup Instructions

### Prerequisites

- Flutter SDK (3.0.0 or higher)
- Android Studio / Xcode for mobile development
- Physical Android/iOS device (BLE doesn't work reliably in simulators)

### Installation

1. **Clone the repository**
   ```bash
   git clone <repository-url>
   cd jbd_bms_app
   ```

2. **Install dependencies**
   ```bash
   flutter pub get
   ```

3. **Configure permissions** (already included in the project)
   - Android: Bluetooth and location permissions in `android/app/src/main/AndroidManifest.xml`
   - iOS: Bluetooth usage descriptions in `ios/Runner/Info.plist`

4. **Run the app**
   ```bash
   flutter run
   ```

## Usage Guide

### Connecting to a JBD BMS

1. **Enable Bluetooth** on your mobile device
2. **Launch the app** and tap "Scan for Devices"
3. **Select your JBD BMS** from the discovered devices list
4. **Wait for connection** - the app will automatically discover services
5. **Navigate to Configuration** once connected

### Reading BMS Data

1. Go to the **Monitor tab**
2. Tap **"Read All Values"** to refresh all basic parameters
3. Tap individual registers to read specific values
4. Values display with timestamps and appropriate units

### Configuring BMS Parameters

1. Go to the **Configure tab**
2. Tap **"Load Current"** to read existing configuration values
3. **Modify the desired parameters** in the text fields
4. Tap **"Save Changes"** and confirm the write operation
5. **Verify changes** by reading the values again

### Debug Mode

- Tap the bug icon in the app bar to enable debug mode
- View raw hex commands and responses
- Useful for troubleshooting communication issues

## Supported Registers

### Read-Only Registers (Monitor)
- Battery Voltage (V)
- Current (A)
- Remaining Capacity (mAh)
- Nominal Capacity (mAh)
- Cycle Count
- Remaining Capacity (%)
- Software Version

### Configurable Registers
- Manufacturer Name
- Device Name
- Design Capacity (mAh)
- Over Voltage Protection (V)
- Under Voltage Protection (V)
- Over Current Charge Protection (A)
- Over Current Discharge Protection (A)

## Technical Details

### JBD Protocol Implementation

The app implements the standard JBD BMS communication protocol:

- **Command Format**: `[START][CMD][REG][LEN][DATA][CHECKSUM_H][CHECKSUM_L][END]`
- **Start Byte**: `0xDD`
- **Read Command**: `0xA5`
- **Write Command**: `0x5A`
- **End Byte**: `0x77`
- **Checksum**: `0x10000 - Sum(all_bytes)`

### Architecture

- **BLE Service** (`lib/services/ble_service.dart`): Handles Bluetooth operations
- **JBD Service** (`lib/services/jbd_service.dart`): Implements JBD protocol
- **Register Models** (`lib/models/jbd_registers.dart`): Defines register mappings
- **UI Screens**: Connection and configuration interfaces
- **State Management**: Provider pattern with ChangeNotifier

### Dependencies

- `flutter_blue_plus`: ^1.31.15 - Bluetooth Low Energy functionality
- `permission_handler`: ^11.3.1 - Runtime permission management
- `provider`: ^6.1.2 - State management
- `cupertino_icons`: ^1.0.2 - iOS-style icons

## Troubleshooting

### Connection Issues

- **Device not found**: Ensure the BMS is powered on and in pairing mode
- **Connection fails**: Try restarting Bluetooth on your mobile device
- **Permission denied**: Grant location and Bluetooth permissions in device settings

### Communication Issues

- **Checksum errors**: Enable debug mode to inspect raw protocol messages
- **Write failures**: Ensure you're writing valid values within acceptable ranges
- **No response**: Check that the device supports the specific register you're accessing

### Performance Tips

- **Avoid rapid commands**: Add delays between consecutive read/write operations
- **Monitor connection**: The app automatically handles disconnections
- **Battery optimization**: Disable battery optimization for the app on Android

## Development Notes

### Extending Register Support

To add new registers:

1. Add the register definition to `JbdRegister` enum in `lib/models/jbd_registers.dart`
2. Update parsing logic in `parseRegisterValue()` method
3. Add encoding logic in `encodeValueForWrite()` method
4. Update UI screens to display the new register

### Customizing UI

The app uses Material 3 design system. Key UI files:
- `lib/screens/connection_screen.dart` - Device discovery and connection
- `lib/screens/configuration_screen.dart` - Register monitoring and configuration

### Testing

- Test on physical devices only (BLE simulators are unreliable)
- Use different JBD BMS models to verify compatibility
- Test error conditions (disconnection, invalid data, etc.)

## License

This project is open source. Please refer to the LICENSE file for details.

## Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Test thoroughly on physical devices
4. Submit a pull request with detailed description

## Support

For issues and questions:
- Check the troubleshooting section above
- Review the JBD protocol documentation
- Create an issue in the repository

---

**Note**: This app is designed for JBD BMS devices. Compatibility with other BMS manufacturers is not guaranteed. Always verify register addresses and data formats for your specific device model.