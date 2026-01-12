/// Even G2 BLE Protocol Constants

class G2Constants {
  // Service UUIDs
  static const String baseUuid = '00002760-08c2-11e1-9073-0e8ac72e';
  static const String mainServiceUuid = '${baseUuid}0000';
  static const String serviceDeclarationUuid = '${baseUuid}5450';

  // Characteristic UUIDs
  static const String commandWriteUuid = '${baseUuid}5401'; // Write commands
  static const String responseNotifyUuid = '${baseUuid}5402'; // Receive responses
  static const String displayControlUuid = '${baseUuid}6402'; // Display commands

  // Packet Header Constants
  static const int magicByte = 0xAA;
  static const int typeCommand = 0x21;
  static const int typeResponse = 0x12;

  // Service IDs
  static const int serviceAuthSession = 0x8000;
  static const int serviceAuthPayload = 0x8020;
  static const int serviceAuthAck = 0x8001;
  static const int serviceTeleprompter = 0x0620;
  static const int serviceDisplayConfig = 0x0E20;
  static const int serviceDashboard = 0x0720;

  // Teleprompter Constants
  static const int teleprompterInit = 1;
  static const int teleprompterContent = 3;
  static const int teleprompterMidMarker = 255;
  static const int teleprompterComplete = 4;
  static const int displayWidth = 267;
  static const int lineHeight = 230;
  static const int linesPerPage = 10;
  static const int charsPerLine = 25;

  // CRC Constants
  static const int crcInit = 0xFFFF;
  static const int crcPolynomial = 0x1021;
}

/// BLE Log Entry
class BleLogEntry {
  final DateTime timestamp;
  final BleLogDirection direction;
  final String characteristic;
  final List<int> data;
  final String? description;

  BleLogEntry({
    required this.timestamp,
    required this.direction,
    required this.characteristic,
    required this.data,
    this.description,
  });

  String get hexData => data.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join(' ');

  String toLogString() {
    final dir = direction == BleLogDirection.send ? 'TX' : 'RX';
    final time = '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}:${timestamp.second.toString().padLeft(2, '0')}.${timestamp.millisecond.toString().padLeft(3, '0')}';
    return '[$time] $dir [$characteristic] $hexData${description != null ? ' // $description' : ''}';
  }
}

enum BleLogDirection { send, receive }

/// G2 Packet Structure
class G2Packet {
  final int type;
  final int sequenceId;
  final int serviceId;
  final List<int> payload;

  G2Packet({
    required this.type,
    required this.sequenceId,
    required this.serviceId,
    required this.payload,
  });

  @override
  String toString() {
    return 'G2Packet(type: 0x${type.toRadixString(16)}, seq: $sequenceId, service: 0x${serviceId.toRadixString(16)}, payload: ${payload.length} bytes)';
  }
}
