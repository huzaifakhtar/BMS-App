import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../services/bluetooth/ble_service.dart';
import '../../cubits/theme_cubit.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});


  @override
  Widget build(BuildContext context) {
    return Consumer2<BleService, ThemeProvider>(
      builder: (context, bleService, themeProvider, _) {
        final isConnected = bleService.isConnected;
        final deviceName = isConnected ? (bleService.connectedDevice?.platformName ?? 'Unknown Device') : 'Not Connected';

        return Scaffold(
          backgroundColor: themeProvider.backgroundColor,
          appBar: AppBar(
            backgroundColor: themeProvider.primaryColor,
            elevation: 0,
            title: const Text(
              'Profile',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            automaticallyImplyLeading: false,
          ),
          body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Device Information Card
            _buildInfoCard(
              'Device Information',
              Icons.bluetooth,
              [
                _buildInfoRow('Device Name', deviceName),
                _buildInfoRow('Connection Status', isConnected ? 'Connected' : 'Disconnected'),
                _buildInfoRow('Device Type', 'JBD BMS'),
              ],
            ),
            
            const SizedBox(height: 20),
            
            // App Information Card
            _buildInfoCard(
              'App Information',
              Icons.info,
              [
                _buildInfoRow('App Name', 'Smart BMS Monitor'),
                _buildInfoRow('Version', '1.0.0'),
                _buildInfoRow('Developer', 'BMS Team'),
                _buildInfoRow('Last Updated', 'June 2025'),
              ],
            ),
            
            const SizedBox(height: 20),
            
            // Statistics Card
            _buildInfoCard(
              'Statistics',
              Icons.analytics,
              [
                _buildInfoRow('Total Connections', '12'),
                _buildInfoRow('Data Points Collected', '1,250'),
                _buildInfoRow('Uptime', '15 days'),
                _buildInfoRow('Last Sync', 'Just now'),
              ],
            ),
            
            const SizedBox(height: 20),
            
            
            // Settings Card
            _buildInfoCard(
              'Settings',
              Icons.settings,
              [
                _buildSettingRow('Auto Connect', true),
                _buildSettingRow('Data Logging', true),
                _buildSettingRow('Notifications', false),
                _buildSettingRow('Dark Mode', false),
              ],
            ),
          ],
        ),
      ),
        );
      },
    );
  }

  Widget _buildInfoCard(String title, IconData icon, List<Widget> children) {
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, _) {
        return Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: themeProvider.cardColor,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: themeProvider.primaryColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    icon,
                    color: themeProvider.primaryColor,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: themeProvider.textColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ...children,
          ],
        ),
      ),
        );
      },
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, _) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  color: themeProvider.secondaryTextColor,
                ),
              ),
              Text(
                value,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: themeProvider.primaryColor,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSettingRow(String label, bool value) {
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, _) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  color: themeProvider.secondaryTextColor,
                ),
              ),
              Switch(
                value: value,
                activeColor: themeProvider.primaryColor,
                onChanged: (newValue) {
                  // Handle setting change
                },
              ),
            ],
          ),
        );
      },
    );
  }



}