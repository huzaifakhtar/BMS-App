import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../dashboard/dashboard_page.dart';
import '../settings/profile_page.dart';
import '../parameters/parameters_page.dart';
import '../debug/command_send_page.dart';
import '../../cubits/theme_cubit.dart';

class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  int _selectedIndex = 0;

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  Widget _getCurrentScreen() {
    switch (_selectedIndex) {
      case 0:
        return const DashboardPage(key: ValueKey('dashboard'));
      case 1:
        return const ParametersPage();
      case 2:
        return const CommandSendPage();
      case 3:
        return const ProfilePage();
      default:
        return const DashboardPage(key: ValueKey('dashboard'));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, child) {
        return Scaffold(
          body: _getCurrentScreen(),
          bottomNavigationBar: Container(
            decoration: BoxDecoration(
              color: themeProvider.cardColor,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(24),
                topRight: Radius.circular(24),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.12),
                  blurRadius: 20,
                  offset: const Offset(0, -4),
                  spreadRadius: 0,
                ),
                BoxShadow(
                  color: themeProvider.primaryColor.withOpacity(0.05),
                  blurRadius: 8,
                  offset: const Offset(0, -1),
                ),
              ],
              border: Border(
                top: BorderSide(
                  color: themeProvider.borderColor.withOpacity(0.2),
                  width: 1,
                ),
              ),
            ),
            child: ClipRRect(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(24),
                topRight: Radius.circular(24),
              ),
              child: BottomNavigationBar(
                type: BottomNavigationBarType.fixed,
                backgroundColor: Colors.transparent,
                selectedItemColor: themeProvider.primaryColor,
                unselectedItemColor: themeProvider.secondaryTextColor,
                selectedFontSize: 14,
                unselectedFontSize: 14,
                iconSize: 26,
                currentIndex: _selectedIndex,
                onTap: _onItemTapped,
                elevation: 0,
                selectedLabelStyle: const TextStyle(
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
                unselectedLabelStyle: const TextStyle(
                  fontWeight: FontWeight.w500,
                ),
                items: [
                  BottomNavigationBarItem(
                    icon: Container(
                      padding: const EdgeInsets.all(8),
                      child: const Icon(Icons.monitor_heart_outlined),
                    ),
                    activeIcon: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: themeProvider.primaryColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.monitor_heart,
                        color: themeProvider.primaryColor,
                      ),
                    ),
                    label: 'Monitor',
                  ),
                  BottomNavigationBarItem(
                    icon: Container(
                      padding: const EdgeInsets.all(8),
                      child: const Icon(Icons.settings_outlined),
                    ),
                    activeIcon: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: themeProvider.primaryColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.settings,
                        color: themeProvider.primaryColor,
                      ),
                    ),
                    label: 'Parameters',
                  ),
                  BottomNavigationBarItem(
                    icon: Container(
                      padding: const EdgeInsets.all(8),
                      child: const Icon(Icons.terminal_outlined),
                    ),
                    activeIcon: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: themeProvider.primaryColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.terminal,
                        color: themeProvider.primaryColor,
                      ),
                    ),
                    label: 'Commands',
                  ),
                  BottomNavigationBarItem(
                    icon: Container(
                      padding: const EdgeInsets.all(8),
                      child: const Icon(Icons.person_outline),
                    ),
                    activeIcon: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: themeProvider.primaryColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.person,
                        color: themeProvider.primaryColor,
                      ),
                    ),
                    label: 'Profile',
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}