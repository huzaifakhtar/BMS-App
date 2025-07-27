# Integration Example

## Adding BMS Communication Service to Your App

### 1. Update main.dart

```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'presentation/pages/navigation/main_navigation.dart';
import 'services/bluetooth/ble_service.dart';
import 'services/bms_communication.dart';
import 'services/dashboard_service_v2.dart';
import 'services/basic_info_service.dart';
import 'services/parameters_service.dart';
import 'presentation/cubits/theme_cubit.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        // Core services
        ChangeNotifierProvider(create: (_) => BleService()),
        ChangeNotifierProvider(create: (_) => BMSCommunication()),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        
        // Screen-specific services
        ChangeNotifierProxyProvider<BMSCommunication, DashboardService>(
          create: (context) => DashboardService(context.read<BMSCommunication>()),
          update: (context, communication, previous) => 
            previous ?? DashboardService(communication),
        ),
        ChangeNotifierProxyProvider<BMSCommunication, BasicInfoService>(
          create: (context) => BasicInfoService(context.read<BMSCommunication>()),
          update: (context, communication, previous) => 
            previous ?? BasicInfoService(communication),
        ),
        ChangeNotifierProxyProvider<BMSCommunication, ParametersService>(
          create: (context) => ParametersService(context.read<BMSCommunication>()),
          update: (context, communication, previous) => 
            previous ?? ParametersService(communication),
        ),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, child) {
          return MaterialApp(
            title: 'Humaya Connect',
            theme: themeProvider.isDarkMode ? themeProvider.darkTheme : themeProvider.lightTheme,
            home: const MainNavigation(),
          );
        },
      ),
    );
  }
}
```

### 2. Update Device Connection Flow

```dart
// In your device connection logic
class DeviceConnectionService {
  final BleService _bleService;
  final BMSCommunication _bmsComm;
  
  DeviceConnectionService(this._bleService, this._bmsComm);
  
  Future<bool> connectToDevice(BluetoothDevice device) async {
    try {
      // First connect via BLE service
      final bleConnected = await _bleService.connectToDevice(device);
      if (!bleConnected) return false;
      
      // Then establish BMS communication
      final bmsConnected = await _bmsComm.connect(device);
      if (!bmsConnected) {
        await _bleService.disconnect();
        return false;
      }
      
      print('✅ Connected to BMS successfully');
      return true;
      
    } catch (e) {
      print('❌ Connection failed: $e');
      return false;
    }
  }
  
  Future<void> disconnect() async {
    await _bmsComm.disconnect();
    await _bleService.disconnect();
  }
}
```

### 3. Updated Dashboard Page

```dart
class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  late DashboardService _dashboardService;
  late BMSCommunication _communication;

  @override
  void initState() {
    super.initState();
    _dashboardService = context.read<DashboardService>();
    _communication = context.read<BMSCommunication>();
    
    // Listen to connection state
    _communication.addListener(_onConnectionChanged);
    
    // Start data updates if already connected
    if (_communication.isConnected) {
      _dashboardService.startDataUpdates();
    }
  }

  @override
  void dispose() {
    _communication.removeListener(_onConnectionChanged);
    super.dispose();
  }

  void _onConnectionChanged() {
    if (_communication.isConnected) {
      _dashboardService.startDataUpdates();
    } else {
      _dashboardService.stopDataUpdates();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<DashboardService>(
      builder: (context, dashboardService, _) {
        final data = dashboardService.data;
        final isShowingDummyData = dashboardService.isShowingDummyData;
        
        return Scaffold(
          appBar: AppBar(title: const Text('Dashboard')),
          body: Column(
            children: [
              if (isShowingDummyData)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  color: Colors.orange,
                  child: const Text(
                    'DEMO MODE - Connect to BMS for live data',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
              
              // Your dashboard UI here
              Text('Voltage: ${data.voltage.toStringAsFixed(2)}V'),
              Text('Current: ${data.current.toStringAsFixed(2)}A'),
              Text('SOC: ${data.soc}%'),
              // ... rest of your UI
            ],
          ),
        );
      },
    );
  }
}
```

### 4. Basic Info Page Example

```dart
class BasicInfoPage extends StatefulWidget {
  const BasicInfoPage({super.key});

  @override
  State<BasicInfoPage> createState() => _BasicInfoPageState();
}

class _BasicInfoPageState extends State<BasicInfoPage> {
  late BasicInfoService _basicInfoService;

  @override
  void initState() {
    super.initState();
    _basicInfoService = context.read<BasicInfoService>();
    
    // Fetch data when page loads
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _basicInfoService.fetchBasicInfo();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Basic Info'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _basicInfoService.fetchBasicInfo(),
          ),
        ],
      ),
      body: Consumer<BasicInfoService>(
        builder: (context, service, _) {
          if (service.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          
          final data = service.data;
          
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _buildInfoCard('Manufacturer', data.manufacturer),
              _buildInfoCard('Device Model', data.deviceModel),
              _buildInfoCard('Barcode', data.barcode),
              _buildInfoCard('Version', data.version),
              _buildInfoCard('Production Date', data.productionDate),
            ],
          );
        },
      ),
    );
  }
  
  Widget _buildInfoCard(String label, String value) {
    return Card(
      child: ListTile(
        title: Text(label),
        subtitle: Text(value.isEmpty ? 'Not available' : value),
      ),
    );
  }
}
```

### 5. Parameters Page Example

```dart
class ParametersPage extends StatefulWidget {
  const ParametersPage({super.key});

  @override
  State<ParametersPage> createState() => _ParametersPageState();
}

class _ParametersPageState extends State<ParametersPage> {
  late ParametersService _parametersService;
  
  // Parameters to display
  static const List<int> displayParameters = [
    0x24, // Cell OVP
    0x26, // Cell UVP
    0x20, // Pack OVP
    0x22, // Pack UVP
    0x28, // Charge OCP
    0x29, // Discharge OCP
  ];

  @override
  void initState() {
    super.initState();
    _parametersService = context.read<ParametersService>();
    
    // Load parameters when page opens
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _parametersService.readParameters(displayParameters);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Parameters'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _parametersService.readParameters(displayParameters),
          ),
        ],
      ),
      body: Consumer<ParametersService>(
        builder: (context, service, _) {
          if (service.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: displayParameters.length,
            itemBuilder: (context, index) {
              final register = displayParameters[index];
              final parameter = service.getParameter(register);
              
              return Card(
                child: ListTile(
                  title: Text(parameter?.name ?? 'Unknown Parameter'),
                  subtitle: parameter?.hasError == true
                      ? const Text('Error reading parameter')
                      : Text('${parameter?.value ?? 'Loading...'} ${parameter?.unit ?? ''}'),
                  trailing: parameter?.isLoaded == true
                      ? const Icon(Icons.check, color: Colors.green)
                      : const CircularProgressIndicator(),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
```

This integration approach provides:

✅ **Clean separation** between communication and UI logic  
✅ **Centralized BMS communication** used by all screens  
✅ **Automatic state management** through Provider pattern  
✅ **Dummy data fallback** when not connected  
✅ **Easy screen-specific data parsing** in dedicated services  
✅ **Reusable communication service** across the entire app  