import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../cubits/theme_cubit.dart';

class ConnectResistancePage extends StatefulWidget {
  const ConnectResistancePage({super.key});

  @override
  State<ConnectResistancePage> createState() => _ConnectResistancePageState();
}

class _ConnectResistancePageState extends State<ConnectResistancePage> {
  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, _) {
        return Scaffold(
          backgroundColor: themeProvider.backgroundColor,
          appBar: AppBar(
            backgroundColor: themeProvider.primaryColor,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
            title: const Text(
              'Connect Resistance',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
          body: const Center(
            child: Text('Connect Resistance Settings\nComing Soon...'),
          ),
        );
      },
    );
  }
}