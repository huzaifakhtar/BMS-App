import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../services/bluetooth/ble_service.dart';
import '../../cubits/theme_cubit.dart';
import 'basic_info_page.dart';
import 'origin_setting_page.dart';
import 'protection_parameter_page.dart';
import 'protection_count_page.dart';
import 'current_settings_page.dart';
import 'temperature_protection_page.dart';
import 'balance_settings_page.dart';
import 'capacity_voltage_page.dart';
import 'connect_resistance_page.dart';
import 'function_setting_page.dart';
import 'system_setting_page.dart';

class ParametersPage extends StatefulWidget {
  const ParametersPage({super.key});

  @override
  State<ParametersPage> createState() => _ParametersPageState();
}

class _ParametersPageState extends State<ParametersPage> {
  bool _factoryModeInitialized = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initializeFactoryMode());
  }

  Future<void> _initializeFactoryMode() async {
    if (_factoryModeInitialized) return;

    final bleService = context.read<BleService>();
    if (bleService.isConnected) {
      try {
        // Factory mode command: DD 5A 00 02 56 78 FF 30 77
        List<int> factoryModeCommand = [0xDD, 0x5A, 0x00, 0x02, 0x56, 0x78, 0xFF, 0x30, 0x77];
        
        debugPrint('[PARAMETERS] Sending factory mode command only');
        await bleService.writeData(factoryModeCommand);
        
        _factoryModeInitialized = true;
        debugPrint('[PARAMETERS] ✅ Factory mode command sent');
      } catch (e) {
        debugPrint('[PARAMETERS] ❌ Factory mode command failed: $e');
      }
    } else {
      debugPrint('[PARAMETERS] ⚠️ Device not connected, skipping factory mode');
    }
  }


  @override
  Widget build(BuildContext context) {
    return Consumer2<BleService, ThemeProvider>(
      builder: (context, bleService, themeProvider, _) {
        final isConnected = bleService.isConnected;

        return Scaffold(
          backgroundColor: themeProvider.backgroundColor,
          appBar: AppBar(
            backgroundColor: themeProvider.primaryColor,
            elevation: 0,
            title: const Text(
              'Parameters',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            automaticallyImplyLeading: false,
            actions: [
              IconButton(
                icon: const Icon(Icons.save, color: Colors.white),
                onPressed: isConnected ? _saveParameters : null,
              ),
            ],
          ),
          body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            // Always show Basic Information and Origin Setting
            _buildMenuTile(
              icon: Icons.info_outline,
              title: 'Basic Information',
              onTap: () => _navigateToBasicInfo(),
            ),
            _buildMenuTile(
              icon: Icons.settings_outlined,
              title: 'Origin Setting',
              onTap: () => _navigateToOriginSetting(),
            ),
            
            // Show additional options only when connected
            if (isConnected) ...[
              _buildMenuTile(
                icon: Icons.security,
                title: 'Protection Params',
                onTap: () => _navigateToProtectionParameter(),
              ),
              _buildMenuTile(
                icon: Icons.numbers,
                title: 'Protection Counts',
                onTap: () => _navigateToProtectionCount(),
              ),
              _buildMenuTile(
                icon: Icons.settings,
                title: 'Current Settings',
                onTap: () => _navigateToCurrentSettings(),
              ),
              _buildMenuTile(
                icon: Icons.thermostat,
                title: 'Temperature Settings',
                onTap: () => _navigateToTemperatureSettings(),
              ),
              _buildMenuTile(
                icon: Icons.balance,
                title: 'Balance Settings',
                onTap: () => _navigateToBalanceSettings(),
              ),
              _buildMenuTile(
                icon: Icons.battery_charging_full,
                title: 'Capacity voltage',
                onTap: () => _navigateToCapacityVoltage(),
              ),
              _buildMenuTile(
                icon: Icons.electrical_services,
                title: 'Connect Resistance',
                onTap: () => _navigateToConnectResistance(),
              ),
              _buildMenuTile(
                icon: Icons.functions,
                title: 'Function Setting',
                onTap: () => _navigateToFunctionSetting(),
              ),
              _buildMenuTile(
                icon: Icons.settings_system_daydream,
                title: 'System Setting',
                onTap: () => _navigateToSystemSetting(),
              ),
            ],
          ],
        ),
      ),
        );
      },
    );
  }

  Widget _buildMenuTile({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, _) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 0),
          child: GestureDetector(
            onTap: onTap,
            child: Row(
              children: [
                Icon(
                  icon,
                  color: themeProvider.primaryColor,
                  size: 20,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: themeProvider.textColor,
                    ),
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  color: themeProvider.secondaryTextColor,
                  size: 16,
                ),
              ],
            ),
          ),
        );
      },
    );
  }


  void _navigateToBasicInfo() {
    debugPrint('[PARAMETERS] Basic Information button tapped');
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const BasicInfoPage(),
      ),
    );
  }


  void _navigateToOriginSetting() {
    debugPrint('[PARAMETERS] Origin Setting button tapped');
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const OriginSettingPage(),
      ),
    );
  }

  void _navigateToProtectionParameter() {
    debugPrint('[PARAMETERS] Protection Parameter button tapped');
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const ProtectionParameterPage(),
      ),
    );
  }

  void _navigateToProtectionCount() {
    debugPrint('[PARAMETERS] Protection Count button tapped');
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const ProtectionCountPage(),
      ),
    );
  }

  void _navigateToCurrentSettings() {
    debugPrint('[PARAMETERS] Current Settings button tapped');
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const CurrentSettingsPage(),
      ),
    );
  }

  void _navigateToTemperatureSettings() {
    debugPrint('[PARAMETERS] Temperature Settings button tapped');
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const TemperatureProtectionPage(),
      ),
    );
  }

  void _navigateToBalanceSettings() {
    debugPrint('[PARAMETERS] Balance Settings button tapped');
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const BalanceSettingsPage(),
      ),
    );
  }

  void _navigateToCapacityVoltage() {
    debugPrint('[PARAMETERS] Capacity Voltage button tapped');
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const CapacityVoltagePage(),
      ),
    );
  }

  void _navigateToConnectResistance() {
    debugPrint('[PARAMETERS] Connect Resistance button tapped');
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const ConnectResistancePage(),
      ),
    );
  }

  void _navigateToFunctionSetting() {
    debugPrint('[PARAMETERS] Function Setting button tapped');
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const FunctionSettingPage(),
      ),
    );
  }

  void _navigateToSystemSetting() {
    debugPrint('[PARAMETERS] System Setting button tapped');
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const SystemSettingPage(),
      ),
    );
  }


  void _saveParameters() {
    // Implement save parameters to file
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Parameters saved to file!')),
    );
  }
}