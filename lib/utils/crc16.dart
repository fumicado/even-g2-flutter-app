/// CRC-16/CCITT Implementation for Even G2 Protocol
/// Initial value: 0xFFFF, Polynomial: 0x1021

class Crc16 {
  static const int _init = 0xFFFF;
  static const int _polynomial = 0x1021;

  /// Calculate CRC-16/CCITT for the given data
  /// Returns the CRC in little-endian format as [low, high]
  static List<int> calculate(List<int> data) {
    int crc = _init;

    for (int byte in data) {
      crc ^= (byte << 8);
      for (int i = 0; i < 8; i++) {
        if ((crc & 0x8000) != 0) {
          crc = ((crc << 1) ^ _polynomial) & 0xFFFF;
        } else {
          crc = (crc << 1) & 0xFFFF;
        }
      }
    }

    // Return as little-endian [low, high]
    return [crc & 0xFF, (crc >> 8) & 0xFF];
  }

  /// Verify CRC of received data
  /// Data should include the CRC bytes at the end
  static bool verify(List<int> dataWithCrc) {
    if (dataWithCrc.length < 2) return false;

    final data = dataWithCrc.sublist(0, dataWithCrc.length - 2);
    final receivedCrc = dataWithCrc.sublist(dataWithCrc.length - 2);
    final calculatedCrc = calculate(data);

    return receivedCrc[0] == calculatedCrc[0] && receivedCrc[1] == calculatedCrc[1];
  }
}
