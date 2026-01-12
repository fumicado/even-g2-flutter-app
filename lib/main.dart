import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'services/ble_service.dart';
import 'services/ble_log_service.dart';
import 'screens/scan_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const EvenG2App());
}

class EvenG2App extends StatelessWidget {
  const EvenG2App({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => BleLogService()),
        ChangeNotifierProxyProvider<BleLogService, BleService>(
          create: (context) => BleService(context.read<BleLogService>()),
          update: (context, logService, previous) =>
              previous ?? BleService(logService),
        ),
      ],
      child: MaterialApp(
        title: 'Even G2 Controller',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
          useMaterial3: true,
        ),
        home: const ScanScreen(),
      ),
    );
  }
}
