import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';
import '../models/g2_constants.dart';

/// BLE Communication Log Service
/// Records all BLE traffic for debugging and analysis
class BleLogService extends ChangeNotifier {
  final List<BleLogEntry> _logs = [];
  bool _isLogging = true;
  int _maxLogs = 10000;

  List<BleLogEntry> get logs => List.unmodifiable(_logs);
  bool get isLogging => _isLogging;
  int get logCount => _logs.length;

  /// Toggle logging on/off
  void toggleLogging() {
    _isLogging = !_isLogging;
    notifyListeners();
  }

  /// Log a sent packet
  void logSend(String characteristic, List<int> data, {String? description}) {
    if (!_isLogging) return;
    _addLog(BleLogEntry(
      timestamp: DateTime.now(),
      direction: BleLogDirection.send,
      characteristic: characteristic,
      data: List.from(data),
      description: description,
    ));
  }

  /// Log a received packet
  void logReceive(String characteristic, List<int> data, {String? description}) {
    if (!_isLogging) return;
    _addLog(BleLogEntry(
      timestamp: DateTime.now(),
      direction: BleLogDirection.receive,
      characteristic: characteristic,
      data: List.from(data),
      description: description,
    ));
  }

  void _addLog(BleLogEntry entry) {
    _logs.add(entry);
    // Trim old logs if exceeded max
    if (_logs.length > _maxLogs) {
      _logs.removeRange(0, _logs.length - _maxLogs);
    }
    notifyListeners();
  }

  /// Clear all logs
  void clearLogs() {
    _logs.clear();
    notifyListeners();
  }

  /// Get formatted log text
  String getFormattedLogs() {
    final buffer = StringBuffer();
    buffer.writeln('=== Even G2 BLE Communication Log ===');
    buffer.writeln('Generated: ${DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now())}');
    buffer.writeln('Total entries: ${_logs.length}');
    buffer.writeln('=' * 50);
    buffer.writeln();

    for (final entry in _logs) {
      buffer.writeln(entry.toLogString());
    }

    return buffer.toString();
  }

  /// Export logs to file and return path
  Future<String> exportToFile() async {
    final directory = await getApplicationDocumentsDirectory();
    final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final file = File('${directory.path}/g2_ble_log_$timestamp.txt');

    await file.writeAsString(getFormattedLogs());
    return file.path;
  }

  /// Parse log entry to human-readable description
  static String? parsePacketDescription(List<int> data) {
    if (data.length < 8) return null;
    if (data[0] != 0xAA) return null;

    final type = data[1] == 0x21 ? 'CMD' : (data[1] == 0x12 ? 'RSP' : 'UNK');
    final seq = data[2];
    final serviceId = (data[6] << 8) | data[7];

    String serviceName;
    switch (serviceId) {
      case 0x8000:
        serviceName = 'AUTH_SESSION';
        break;
      case 0x8020:
        serviceName = 'AUTH_PAYLOAD';
        break;
      case 0x8001:
        serviceName = 'AUTH_ACK';
        break;
      case 0x0620:
        serviceName = 'TELEPROMPTER';
        break;
      case 0x0E20:
        serviceName = 'DISPLAY_CFG';
        break;
      case 0x0720:
        serviceName = 'DASHBOARD';
        break;
      default:
        serviceName = '0x${serviceId.toRadixString(16).toUpperCase()}';
    }

    return '$type seq=$seq svc=$serviceName';
  }
}
