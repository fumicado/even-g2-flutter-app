import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/g2_constants.dart';
import 'ble_log_service.dart';
import 'g2_protocol.dart';

enum BleConnectionState { disconnected, scanning, connecting, connected, authenticated }

/// BLE Service for Even G2 Communication
/// Based on i-soxi/even-g2-protocol reverse engineering
class BleService extends ChangeNotifier {
  final BleLogService _logService;
  final G2Protocol _protocol = G2Protocol();

  BluetoothDevice? _connectedDevice;
  BluetoothCharacteristic? _commandChar;
  BluetoothCharacteristic? _responseChar;
  BluetoothCharacteristic? _displayChar;

  StreamSubscription? _scanSubscription;
  StreamSubscription? _connectionSubscription;
  StreamSubscription? _responseSubscription;

  BleConnectionState _state = BleConnectionState.disconnected;
  List<ScanResult> _scanResults = [];
  String? _errorMessage;

  BleService(this._logService);

  /// Check if a scan result is an Even G2 device
  /// Only show devices with "Even" or "G2" in name
  bool _isEvenG2(ScanResult r) {
    final name = r.device.platformName.toLowerCase();
    return name.contains('even') || name.contains('g2');
  }

  /// Check if device is G2 (public method for UI)
  bool isLikelyG2Device(ScanResult r) => _isEvenG2(r);

  // Getters
  BleConnectionState get state => _state;
  List<ScanResult> get scanResults => _scanResults;
  String? get errorMessage => _errorMessage;
  bool get isConnected => _state == BleConnectionState.connected || _state == BleConnectionState.authenticated;
  String? get connectedDeviceName => _connectedDevice?.platformName;
  G2Protocol get protocol => _protocol;

  /// Request BLE permissions
  Future<bool> requestPermissions() async {
    if (Platform.isAndroid) {
      final statuses = await [
        Permission.bluetooth,
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.location,
      ].request();

      return statuses.values.every((s) => s.isGranted);
    } else if (Platform.isIOS) {
      final status = await Permission.bluetooth.request();
      return status.isGranted;
    }
    return true;
  }

  /// Check if Bluetooth is available and on
  Future<bool> checkBluetoothState() async {
    if (await FlutterBluePlus.isSupported == false) {
      _errorMessage = 'Bluetooth is not supported on this device';
      notifyListeners();
      return false;
    }

    final state = await FlutterBluePlus.adapterState.first;
    if (state != BluetoothAdapterState.on) {
      _errorMessage = 'Bluetooth is turned off';
      notifyListeners();
      return false;
    }

    return true;
  }

  /// Start scanning for Even G2 devices only
  Future<void> startScan() async {
    if (!await requestPermissions()) {
      _errorMessage = 'Bluetooth permissions not granted';
      notifyListeners();
      return;
    }

    if (!await checkBluetoothState()) return;

    _state = BleConnectionState.scanning;
    _scanResults = [];
    _errorMessage = null;
    notifyListeners();

    await FlutterBluePlus.startScan(
      timeout: const Duration(seconds: 15),
    );

    _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
      // Filter to show ONLY Even G2 devices
      _scanResults = results.where((r) {
        final name = r.device.platformName;
        return name.isNotEmpty && _isEvenG2(r);
      }).toList();

      // Sort by signal strength
      _scanResults.sort((a, b) => b.rssi.compareTo(a.rssi));

      notifyListeners();
    });

    FlutterBluePlus.isScanning.listen((isScanning) {
      if (!isScanning && _state == BleConnectionState.scanning) {
        _state = BleConnectionState.disconnected;
        notifyListeners();
      }
    });
  }

  /// Stop scanning
  Future<void> stopScan() async {
    await FlutterBluePlus.stopScan();
    _scanSubscription?.cancel();
    _state = BleConnectionState.disconnected;
    notifyListeners();
  }

  /// Connect to a device and perform full authentication
  Future<bool> connect(BluetoothDevice device) async {
    try {
      _state = BleConnectionState.connecting;
      _errorMessage = null;
      notifyListeners();

      // Stop scanning before connecting (fixes Android error 133)
      await FlutterBluePlus.stopScan();
      await _scanSubscription?.cancel();

      // Disconnect any existing connection first
      try {
        await device.disconnect();
        print('Disconnected existing connection');
      } catch (e) {
        // Ignore - device wasn't connected
      }

      await Future.delayed(const Duration(milliseconds: 1000));

      // Try to connect with retry logic for Android error 133
      int retryCount = 0;
      const maxRetries = 3;

      while (retryCount < maxRetries) {
        try {
          print('Connection attempt ${retryCount + 1}...');
          await device.connect(
            timeout: const Duration(seconds: 20),
            autoConnect: false,
          );
          print('Connected successfully!');
          break; // Success
        } catch (e) {
          retryCount++;
          print('Connection attempt $retryCount failed: $e');

          // Try to disconnect before retry
          try {
            await device.disconnect();
          } catch (_) {}

          if (retryCount >= maxRetries) {
            rethrow;
          }

          // Wait longer before retry
          await Future.delayed(Duration(milliseconds: 1000 * retryCount));
        }
      }

      _connectedDevice = device;

      // Listen for disconnection
      _connectionSubscription = device.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected) {
          _handleDisconnection();
        }
      });

      // Request higher MTU for larger packets (Android only)
      if (Platform.isAndroid) {
        try {
          await device.requestMtu(512);
          print('MTU requested: 512');
        } catch (e) {
          print('MTU request failed: $e');
        }
      }

      // Small delay for connection to stabilize
      await Future.delayed(const Duration(milliseconds: 300));

      // Discover services
      final services = await device.discoverServices();
      await _setupCharacteristics(services);

      if (_commandChar == null || _responseChar == null) {
        throw Exception('Required characteristics not found');
      }

      _state = BleConnectionState.connected;
      notifyListeners();

      // Wait for connection to stabilize
      await Future.delayed(const Duration(milliseconds: 500));

      // Perform 7-packet authentication sequence
      await _performAuthentication();

      _state = BleConnectionState.authenticated;
      notifyListeners();

      return true;
    } catch (e) {
      _errorMessage = 'Connection failed: $e';
      _state = BleConnectionState.disconnected;
      notifyListeners();
      return false;
    }
  }

  /// Perform the 7-packet authentication sequence
  Future<void> _performAuthentication() async {
    print('Starting 7-packet authentication sequence...');
    final authPackets = _protocol.buildAuthSequence();

    for (var i = 0; i < authPackets.length; i++) {
      await sendPacket(authPackets[i], description: 'AUTH_${i + 1}');
      await Future.delayed(const Duration(milliseconds: 100));
    }

    // Wait for auth to complete
    await Future.delayed(const Duration(milliseconds: 500));
    print('Authentication complete');
  }

  /// Setup BLE characteristics
  Future<void> _setupCharacteristics(List<BluetoothService> services) async {
    print('Discovering characteristics...');
    for (final service in services) {
      final serviceUuid = service.uuid.toString().toLowerCase();
      print('Service: $serviceUuid');

      if (serviceUuid.contains('2760')) {
        for (final char in service.characteristics) {
          final uuid = char.uuid.toString().toLowerCase();
          final props = char.properties;
          print('  Char: $uuid - write:${props.write} writeNoResp:${props.writeWithoutResponse} notify:${props.notify} read:${props.read}');

          if (uuid.contains('5401')) {
            _commandChar = char;
            print('  -> Command characteristic (5401)');
          } else if (uuid.contains('5402')) {
            _responseChar = char;
            print('  -> Response characteristic (5402)');
            // Enable notifications
            if (props.notify) {
              await char.setNotifyValue(true);
              _responseSubscription = char.onValueReceived.listen(_handleResponse);
              print('  -> Notifications enabled');
            }
          } else if (uuid.contains('6402')) {
            _displayChar = char;
            print('  -> Display characteristic (6402)');
          }
        }
      }
    }
  }

  /// Handle incoming responses
  void _handleResponse(List<int> data) {
    _logService.logReceive(
      '5402',
      data,
      description: BleLogService.parsePacketDescription(data),
    );

    final packet = _protocol.parsePacket(data);
    if (packet != null) {
      print('Received: $packet');
    }
  }

  /// Send a packet to the device
  Future<void> sendPacket(List<int> data, {String? description}) async {
    if (_commandChar == null) {
      throw Exception('Not connected');
    }

    _logService.logSend(
      '5401',
      data,
      description: description ?? BleLogService.parsePacketDescription(data),
    );

    // Check characteristic properties and use appropriate write method
    final props = _commandChar!.properties;
    if (props.write) {
      await _commandChar!.write(data, withoutResponse: false);
    } else if (props.writeWithoutResponse) {
      await _commandChar!.write(data, withoutResponse: true);
    } else {
      throw Exception('Characteristic does not support write');
    }
  }

  /// Send display command
  Future<void> sendDisplayCommand(List<int> data, {String? description}) async {
    if (_displayChar == null) {
      throw Exception('Display characteristic not available');
    }

    _logService.logSend(
      '6402',
      data,
      description: description ?? 'DISPLAY_CMD',
    );

    // Check characteristic properties
    final props = _displayChar!.properties;
    if (props.writeWithoutResponse) {
      await _displayChar!.write(data, withoutResponse: true);
    } else if (props.write) {
      await _displayChar!.write(data, withoutResponse: false);
    } else {
      throw Exception('Display characteristic does not support write');
    }
  }

  /// Send teleprompter text - Full protocol implementation
  Future<void> sendTeleprompterText(String text) async {
    if (_state != BleConnectionState.authenticated) {
      throw Exception('Not authenticated');
    }

    print('Sending teleprompter text...');

    // Format text into pages (min 14 pages)
    final pages = _protocol.formatText(text);
    final totalLines = text.replaceAll('\\n', '\n').split('\n').length;

    print('Formatted into ${pages.length} pages, $totalLines lines');

    // Step 1: Send display config (Service 0x0E-20)
    print('Sending display config...');
    await sendPacket(
      _protocol.buildDisplayConfig(),
      description: 'DISPLAY_CONFIG',
    );
    await Future.delayed(const Duration(milliseconds: 300));

    // Step 2: Send teleprompter init (Service 0x06-20 type=1)
    print('Sending teleprompter init...');
    await sendPacket(
      _protocol.buildTeleprompterInit(totalLines: totalLines),
      description: 'TELEPROMPTER_INIT',
    );
    await Future.delayed(const Duration(milliseconds: 500));

    // Step 3: Send content pages 0-9
    print('Sending pages 0-9...');
    for (var i = 0; i < 10 && i < pages.length; i++) {
      await sendPacket(
        _protocol.buildContentPage(i, pages[i]),
        description: 'PAGE_$i',
      );
      await Future.delayed(const Duration(milliseconds: 100));
    }

    // Step 4: Send mid-stream marker
    print('Sending marker...');
    await sendPacket(
      _protocol.buildMarker(),
      description: 'MARKER',
    );
    await Future.delayed(const Duration(milliseconds: 100));

    // Step 5: Send pages 10-11
    print('Sending pages 10-11...');
    for (var i = 10; i < 12 && i < pages.length; i++) {
      await sendPacket(
        _protocol.buildContentPage(i, pages[i]),
        description: 'PAGE_$i',
      );
      await Future.delayed(const Duration(milliseconds: 100));
    }

    // Step 6: Send sync trigger
    print('Sending sync...');
    await sendPacket(
      _protocol.buildSync(),
      description: 'SYNC',
    );
    await Future.delayed(const Duration(milliseconds: 100));

    // Step 7: Send remaining pages (12+)
    if (pages.length > 12) {
      print('Sending remaining pages...');
      for (var i = 12; i < pages.length; i++) {
        await sendPacket(
          _protocol.buildContentPage(i, pages[i]),
          description: 'PAGE_$i',
        );
        await Future.delayed(const Duration(milliseconds: 100));
      }
    }

    print('Teleprompter text sent! Check your glasses.');
  }

  // ============================================
  // Dashboard / Widget Functions
  // ============================================

  /// Send dashboard widget (time, date, weather)
  Future<void> sendDashboard({
    String? time,
    String? date,
    String? weather,
    int? temperature,
  }) async {
    if (_state != BleConnectionState.authenticated) {
      throw Exception('Not authenticated');
    }

    print('Sending dashboard...');
    await sendPacket(
      _protocol.buildDashboardWidget(
        time: time,
        date: date,
        weather: weather,
        temperature: temperature,
      ),
      description: 'DASHBOARD',
    );
  }

  // ============================================
  // Quick Text / Notification Functions
  // ============================================

  /// Send quick text (short message display)
  Future<void> sendQuickText(String text, {int duration = 5}) async {
    if (_state != BleConnectionState.authenticated) {
      throw Exception('Not authenticated');
    }

    print('Sending quick text...');
    await sendPacket(
      _protocol.buildQuickText(text, displayDuration: duration),
      description: 'QUICK_TEXT',
    );
  }

  /// Send notification
  Future<void> sendNotification({
    required String appName,
    required String title,
    String? message,
    int count = 1,
  }) async {
    if (_state != BleConnectionState.authenticated) {
      throw Exception('Not authenticated');
    }

    print('Sending notification...');
    await sendPacket(
      _protocol.buildNotification(
        appName: appName,
        title: title,
        message: message,
        notificationCount: count,
      ),
      description: 'NOTIFICATION',
    );
  }

  // ============================================
  // AI Functions
  // ============================================

  /// Send transcription text (speech-to-text display)
  Future<void> sendTranscription(String text, {bool isFinal = false}) async {
    if (_state != BleConnectionState.authenticated) {
      throw Exception('Not authenticated');
    }

    await sendPacket(
      _protocol.buildTranscription(text, isFinal: isFinal),
      description: isFinal ? 'TRANSCRIPTION_FINAL' : 'TRANSCRIPTION',
    );
  }

  /// Send AI response using 0x4E command (Official Even Demo App protocol)
  Future<void> sendAIResponse(String response, {bool isStreaming = false}) async {
    if (_state != BleConnectionState.authenticated) {
      throw Exception('Not authenticated');
    }

    print('Sending AI response (0x4E command)...');

    // Build packets using official 0x4E command format
    final packets = _protocol.buildAIResponse(response, isStreaming: isStreaming);

    // Send each packet with small delay
    for (var i = 0; i < packets.length; i++) {
      await sendPacket(
        packets[i],
        description: 'AI_0x4E_${i + 1}/${packets.length}',
      );
      // Small delay between packets
      if (i < packets.length - 1) {
        await Future.delayed(const Duration(milliseconds: 50));
      }
    }

    print('AI response sent! (${packets.length} packets)');
  }

  /// Send simple AI response (single packet for short responses)
  Future<void> sendAIResponseSimple(String response, {bool isComplete = true}) async {
    if (_state != BleConnectionState.authenticated) {
      throw Exception('Not authenticated');
    }

    print('Sending simple AI response...');
    await sendPacket(
      _protocol.buildAIResponseSimple(response, isComplete: isComplete),
      description: isComplete ? 'AI_SIMPLE_COMPLETE' : 'AI_SIMPLE_STREAMING',
    );
  }

  // ============================================
  // Navigation Functions
  // ============================================

  /// Send navigation direction
  Future<void> sendNavigation({
    required NavigationDirection direction,
    required String distance,
    String? streetName,
  }) async {
    if (_state != BleConnectionState.authenticated) {
      throw Exception('Not authenticated');
    }

    print('Sending navigation...');
    await sendPacket(
      _protocol.buildNavigation(
        direction: direction,
        distance: distance,
        streetName: streetName,
      ),
      description: 'NAVIGATION',
    );
  }

  // ============================================
  // Settings Functions
  // ============================================

  /// Set display brightness (0-100)
  Future<void> setBrightness(int level) async {
    if (_state != BleConnectionState.authenticated) {
      throw Exception('Not authenticated');
    }

    print('Setting brightness to $level...');
    await sendPacket(
      _protocol.buildBrightnessControl(level),
      description: 'BRIGHTNESS',
    );
  }

  /// Set display position offset
  Future<void> setPosition({int x = 0, int y = 0}) async {
    if (_state != BleConnectionState.authenticated) {
      throw Exception('Not authenticated');
    }

    print('Setting position to ($x, $y)...');
    await sendPacket(
      _protocol.buildPositionControl(x: x, y: y),
      description: 'POSITION',
    );
  }

  /// Clear display
  Future<void> clearDisplay() async {
    if (_state != BleConnectionState.authenticated) {
      throw Exception('Not authenticated');
    }

    print('Clearing display...');
    await sendPacket(
      _protocol.buildClearDisplay(),
      description: 'CLEAR_DISPLAY',
    );
  }

  /// Activate display
  Future<void> activateDisplay() async {
    if (_state != BleConnectionState.authenticated) {
      throw Exception('Not authenticated');
    }

    print('Activating display...');
    await sendPacket(
      _protocol.buildActivateDisplay(),
      description: 'ACTIVATE_DISPLAY',
    );
  }

  /// Disconnect from device
  Future<void> disconnect() async {
    await _responseSubscription?.cancel();
    await _connectionSubscription?.cancel();
    await _connectedDevice?.disconnect();
    _handleDisconnection();
  }

  void _handleDisconnection() {
    _connectedDevice = null;
    _commandChar = null;
    _responseChar = null;
    _displayChar = null;
    _protocol.resetSequence();
    _state = BleConnectionState.disconnected;
    notifyListeners();
  }

  @override
  void dispose() {
    disconnect();
    _scanSubscription?.cancel();
    super.dispose();
  }
}
