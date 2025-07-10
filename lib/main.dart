import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'presentation/pages/navigation/main_navigation.dart';
import 'services/bluetooth/ble_service.dart';
import 'services/bluetooth/bms_service.dart';
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
        ChangeNotifierProvider(create: (_) => BleService()),
        ChangeNotifierProvider(create: (_) => BmsService()),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
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