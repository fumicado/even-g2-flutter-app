import 'dart:convert';
import 'dart:typed_data';
import '../models/g2_constants.dart';
import '../utils/crc16.dart';

/// G2 Protocol Handler - Based on i-soxi/even-g2-protocol
/// Implements the reverse-engineered Even G2 BLE protocol
class G2Protocol {
  int _sequenceId = 0;
  int _messageId = 0x14; // Start at 0x14 like Python example

  /// Get next sequence ID (0-255)
  int get nextSequenceId {
    _sequenceId = (_sequenceId + 1) & 0xFF;
    return _sequenceId;
  }

  /// Get next message ID
  int get nextMessageId {
    _messageId++;
    return _messageId;
  }

  /// Reset counters
  void resetSequence() {
    _sequenceId = 0;
    _messageId = 0x14;
  }

  /// Encode integer as protobuf varint
  List<int> encodeVarint(int value) {
    final result = <int>[];
    while (value > 0x7F) {
      result.add((value & 0x7F) | 0x80);
      value >>= 7;
    }
    result.add(value & 0x7F);
    return result;
  }

  /// Build packet with header and CRC
  /// Format: [0xAA][type][seq][len][pkt_tot][pkt_ser][svc_hi][svc_lo][payload][crc_lo][crc_hi]
  List<int> buildPacket({
    required int serviceHi,
    required int serviceLo,
    required List<int> payload,
    int? sequenceId,
  }) {
    final seq = sequenceId ?? nextSequenceId;
    final payloadLen = payload.length + 2; // +2 for service ID bytes

    // Build header (8 bytes)
    final header = <int>[
      0xAA, // Magic byte
      0x21, // Type: command
      seq,
      payloadLen,
      0x01, // Packet total
      0x01, // Packet serial
      serviceHi,
      serviceLo,
    ];

    // Combine header and payload
    final packet = [...header, ...payload];

    // Calculate CRC on data after header (payload only)
    final crc = Crc16.calculate(payload);

    return [...packet, ...crc];
  }

  /// Build the 7-packet authentication sequence
  List<List<int>> buildAuthSequence() {
    final packets = <List<int>>[];
    final timestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final tsVarint = encodeVarint(timestamp);
    final txid = [0xE8, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x01];

    // Auth 1: Capability query
    packets.add(_addCrc([
      0xAA, 0x21, 0x01, 0x0C, 0x01, 0x01, 0x80, 0x00,
      0x08, 0x04, 0x10, 0x0C, 0x1A, 0x04, 0x08, 0x01, 0x10, 0x04
    ]));

    // Auth 2: Capability response request
    packets.add(_addCrc([
      0xAA, 0x21, 0x02, 0x0A, 0x01, 0x01, 0x80, 0x20,
      0x08, 0x05, 0x10, 0x0E, 0x22, 0x02, 0x08, 0x02
    ]));

    // Auth 3: Time sync with transaction ID
    final payload3 = [0x08, 0x80, 0x01, 0x10, 0x0F, 0x82, 0x08, 0x11, 0x08, ...tsVarint, 0x10, ...txid];
    packets.add(_addCrc([0xAA, 0x21, 0x03, payload3.length + 2, 0x01, 0x01, 0x80, 0x20, ...payload3]));

    // Auth 4: Capability exchange
    packets.add(_addCrc([
      0xAA, 0x21, 0x04, 0x0C, 0x01, 0x01, 0x80, 0x00,
      0x08, 0x04, 0x10, 0x10, 0x1A, 0x04, 0x08, 0x01, 0x10, 0x04
    ]));

    // Auth 5: Capability exchange
    packets.add(_addCrc([
      0xAA, 0x21, 0x05, 0x0C, 0x01, 0x01, 0x80, 0x00,
      0x08, 0x04, 0x10, 0x11, 0x1A, 0x04, 0x08, 0x01, 0x10, 0x04
    ]));

    // Auth 6: Final capability
    packets.add(_addCrc([
      0xAA, 0x21, 0x06, 0x0A, 0x01, 0x01, 0x80, 0x20,
      0x08, 0x05, 0x10, 0x12, 0x22, 0x02, 0x08, 0x01
    ]));

    // Auth 7: Final time sync
    final payload7 = [0x08, 0x80, 0x01, 0x10, 0x13, 0x82, 0x08, 0x11, 0x08, ...tsVarint, 0x10, ...txid];
    packets.add(_addCrc([0xAA, 0x21, 0x07, payload7.length + 2, 0x01, 0x01, 0x80, 0x20, ...payload7]));

    _sequenceId = 0x07; // After auth, sequence is at 7
    return packets;
  }

  /// Add CRC to packet (calculated on payload after 8-byte header)
  List<int> _addCrc(List<int> packet) {
    final payload = packet.sublist(8);
    final crc = Crc16.calculate(payload);
    return [...packet, ...crc];
  }

  /// Build display config packet (Service 0x0E-20)
  List<int> buildDisplayConfig() {
    final msgId = nextMessageId;
    final seq = nextSequenceId;

    // Display config from Python example
    final configHex = '0801121308021090'
        '4E1D00E094442500'
        '000000280030001213'
        '0803100D0F1D0040'
        '8D44250000000028'
        '0030001212080410'
        '001D0000884225'
        '00000000280030'
        '001212080510001D'
        '00009242250000'
        'A242280030001212'
        '080610001D0000C6'
        '42250000C4422800'
        '30001800';

    final config = _hexToBytes(configHex);
    final msgIdVarint = encodeVarint(msgId);

    final payload = [0x08, 0x02, 0x10, ...msgIdVarint, 0x22, 0x6A, ...config];
    return _addCrc([0xAA, 0x21, seq, payload.length + 2, 0x01, 0x01, 0x0E, 0x20, ...payload]);
  }

  /// Build teleprompter init packet (Service 0x06-20 type=1)
  List<int> buildTeleprompterInit({int totalLines = 10, bool manualMode = true}) {
    final msgId = nextMessageId;
    final seq = nextSequenceId;
    final mode = manualMode ? 0x00 : 0x01;

    // Scale content height based on line count
    final contentHeight = (totalLines * 2665) ~/ 140;
    final contentHeightVarint = encodeVarint(contentHeight > 0 ? contentHeight : 1);
    final msgIdVarint = encodeVarint(msgId);

    // Display settings
    final display = [
      0x08, 0x01, 0x10, 0x00, 0x18, 0x00, 0x20, 0x8B, 0x02, // Fixed settings (width=267)
      0x28, ...contentHeightVarint, // Content height
      0x30, 0xE6, 0x01, // Line height = 230
      0x38, 0x8E, 0x0A, // Viewport = 1294
      0x40, 0x05, 0x48, mode, // Font size + mode
    ];

    final settings = [0x08, 0x01, 0x12, display.length, ...display];
    final payload = [0x08, 0x01, 0x10, ...msgIdVarint, 0x1A, settings.length, ...settings];

    return _addCrc([0xAA, 0x21, seq, payload.length + 2, 0x01, 0x01, 0x06, 0x20, ...payload]);
  }

  /// Build teleprompter content page (Service 0x06-20 type=3)
  List<int> buildContentPage(int pageNum, String text) {
    final msgId = nextMessageId;
    final seq = nextSequenceId;
    final msgIdVarint = encodeVarint(msgId);
    final pageVarint = encodeVarint(pageNum);

    // Text with leading newline - use UTF-8 for Japanese support
    final textBytes = utf8.encode('\n$text');
    final textLenVarint = encodeVarint(textBytes.length);

    final inner = [
      0x08, ...pageVarint, // Page number
      0x10, 0x0A, // 10 lines
      0x1A, ...textLenVarint, ...textBytes, // Text content
    ];

    final innerLenVarint = encodeVarint(inner.length);
    final content = [0x2A, ...innerLenVarint, ...inner];
    final payload = [0x08, 0x03, 0x10, ...msgIdVarint, ...content];

    return _addCrc([0xAA, 0x21, seq, payload.length + 2, 0x01, 0x01, 0x06, 0x20, ...payload]);
  }

  /// Build mid-stream marker (Service 0x06-20 type=255)
  List<int> buildMarker() {
    final msgId = nextMessageId;
    final seq = nextSequenceId;
    final msgIdVarint = encodeVarint(msgId);

    final payload = [0x08, 0xFF, 0x01, 0x10, ...msgIdVarint, 0x6A, 0x04, 0x08, 0x00, 0x10, 0x06];
    return _addCrc([0xAA, 0x21, seq, payload.length + 2, 0x01, 0x01, 0x06, 0x20, ...payload]);
  }

  /// Build sync trigger (Service 0x80-00 type=14)
  List<int> buildSync() {
    final msgId = nextMessageId;
    final seq = nextSequenceId;
    final msgIdVarint = encodeVarint(msgId);

    final payload = [0x08, 0x0E, 0x10, ...msgIdVarint, 0x6A, 0x00];
    return _addCrc([0xAA, 0x21, seq, payload.length + 2, 0x01, 0x01, 0x80, 0x00, ...payload]);
  }

  /// Format text into pages (25 chars/line, 10 lines/page, min 14 pages)
  List<String> formatText(String text, {int charsPerLine = 25, int linesPerPage = 10}) {
    // Handle escaped newlines
    text = text.replaceAll('\\n', '\n');

    // Wrap lines
    final wrapped = <String>[];
    for (var line in text.split('\n')) {
      if (line.trim().isEmpty) {
        wrapped.add('');
        continue;
      }

      final words = line.split(' ');
      var current = '';
      for (final word in words) {
        if (current.length + word.length + 1 > charsPerLine) {
          if (current.isNotEmpty) {
            wrapped.add(current.trim());
          }
          current = '$word ';
        } else {
          current += '$word ';
        }
      }
      if (current.trim().isNotEmpty) {
        wrapped.add(current.trim());
      }
    }

    if (wrapped.isEmpty) {
      wrapped.add(text);
    }

    // Pad to at least 10 lines
    while (wrapped.length < linesPerPage) {
      wrapped.add(' ');
    }

    // Split into pages
    final pages = <String>[];
    for (var i = 0; i < wrapped.length; i += linesPerPage) {
      final end = (i + linesPerPage < wrapped.length) ? i + linesPerPage : wrapped.length;
      final pageLines = wrapped.sublist(i, end);
      while (pageLines.length < linesPerPage) {
        pageLines.add(' ');
      }
      pages.add('${pageLines.join('\n')} \n');
    }

    // Pad to minimum 14 pages
    while (pages.length < 14) {
      pages.add('${List.filled(linesPerPage, ' ').join('\n')} \n');
    }

    return pages;
  }

  /// Parse received packet
  G2Packet? parsePacket(List<int> data) {
    if (data.length < 10) return null;
    if (data[0] != 0xAA) return null;

    final type = data[1];
    final sequenceId = data[2];
    final serviceId = (data[6] << 8) | data[7];
    final payload = data.sublist(8, data.length - 2);

    return G2Packet(
      type: type,
      sequenceId: sequenceId,
      serviceId: serviceId,
      payload: payload,
    );
  }

  /// Convert hex string to bytes
  List<int> _hexToBytes(String hex) {
    hex = hex.replaceAll(' ', '').replaceAll('\n', '');
    final result = <int>[];
    for (var i = 0; i < hex.length; i += 2) {
      result.add(int.parse(hex.substring(i, i + 2), radix: 16));
    }
    return result;
  }

  // Legacy methods for compatibility
  List<int> buildPacketLegacy({
    required int serviceId,
    required List<int> payload,
    int? sequenceId,
    int packetTotal = 1,
    int packetSerial = 1,
  }) {
    return buildPacket(
      serviceHi: (serviceId >> 8) & 0xFF,
      serviceLo: serviceId & 0xFF,
      payload: payload,
      sequenceId: sequenceId,
    );
  }

  List<int> buildAuthRequest() => buildAuthSequence().first;
  List<int> buildAuthPayload(List<int> authData) => [];

  List<int> buildTeleprompterContent(String text, int pageIndex) {
    return buildContentPage(pageIndex, text);
  }

  List<int> buildTeleprompterMidMarker() => buildMarker();

  List<int> buildTeleprompterComplete(int totalPages, int totalLines) {
    // Not used in new protocol - sync is used instead
    return buildSync();
  }

  List<String> splitTextIntoPages(String text) => formatText(text);
}
