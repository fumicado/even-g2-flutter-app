import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/ble_service.dart';
import 'control_screen.dart';

class ScanScreen extends StatelessWidget {
  const ScanScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Even G2 Scanner'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Consumer<BleService>(
        builder: (context, bleService, child) {
          return Column(
            children: [
              // Status Card
              Card(
                margin: const EdgeInsets.all(16),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Icon(
                        _getStatusIcon(bleService.state),
                        color: _getStatusColor(bleService.state),
                        size: 32,
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _getStatusText(bleService.state),
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            if (bleService.errorMessage != null)
                              Text(
                                bleService.errorMessage!,
                                style: TextStyle(
                                  color: Colors.red[700],
                                  fontSize: 12,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Scan Button
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: bleService.state == BleConnectionState.scanning
                        ? () => bleService.stopScan()
                        : () => bleService.startScan(),
                    icon: Icon(
                      bleService.state == BleConnectionState.scanning
                          ? Icons.stop
                          : Icons.bluetooth_searching,
                    ),
                    label: Text(
                      bleService.state == BleConnectionState.scanning
                          ? 'Stop Scan'
                          : 'Scan for Even G2',
                    ),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.all(16),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 16),
              const Divider(),

              // Device List
              Expanded(
                child: bleService.scanResults.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.bluetooth_disabled,
                              size: 64,
                              color: Colors.grey[400],
                            ),
                            const SizedBox(height: 16),
                            Text(
                              bleService.state == BleConnectionState.scanning
                                  ? 'Scanning for devices...'
                                  : 'No devices found\nTap "Scan" to search',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.grey[600]),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        itemCount: bleService.scanResults.length,
                        itemBuilder: (context, index) {
                          final result = bleService.scanResults[index];
                          return ListTile(
                            leading: Icon(Icons.visibility, size: 40, color: Colors.deepPurple),
                            title: Text(
                              result.device.platformName.isNotEmpty
                                  ? result.device.platformName
                                  : 'Unknown Device',
                            ),
                            subtitle: Text(
                              'RSSI: ${result.rssi} dBm\n${result.device.remoteId}',
                            ),
                            trailing: ElevatedButton(
                              onPressed: bleService.state == BleConnectionState.connecting
                                  ? null
                                  : () async {
                                      final success = await bleService.connect(result.device);
                                      if (success && context.mounted) {
                                        Navigator.pushReplacement(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) => const ControlScreen(),
                                          ),
                                        );
                                      }
                                    },
                              child: bleService.state == BleConnectionState.connecting
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  : const Text('Connect'),
                            ),
                            isThreeLine: true,
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  IconData _getStatusIcon(BleConnectionState state) {
    switch (state) {
      case BleConnectionState.disconnected:
        return Icons.bluetooth_disabled;
      case BleConnectionState.scanning:
        return Icons.bluetooth_searching;
      case BleConnectionState.connecting:
        return Icons.bluetooth_connected;
      case BleConnectionState.connected:
      case BleConnectionState.authenticated:
        return Icons.bluetooth;
    }
  }

  Color _getStatusColor(BleConnectionState state) {
    switch (state) {
      case BleConnectionState.disconnected:
        return Colors.grey;
      case BleConnectionState.scanning:
        return Colors.blue;
      case BleConnectionState.connecting:
        return Colors.orange;
      case BleConnectionState.connected:
        return Colors.green;
      case BleConnectionState.authenticated:
        return Colors.green;
    }
  }

  String _getStatusText(BleConnectionState state) {
    switch (state) {
      case BleConnectionState.disconnected:
        return 'Disconnected';
      case BleConnectionState.scanning:
        return 'Scanning...';
      case BleConnectionState.connecting:
        return 'Connecting...';
      case BleConnectionState.connected:
        return 'Connected';
      case BleConnectionState.authenticated:
        return 'Authenticated';
    }
  }
}
