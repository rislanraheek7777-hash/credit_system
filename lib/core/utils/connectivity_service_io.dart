import 'dart:io';

/// Native connectivity gate. A non-loopback interface is required before a
/// recovery request is attempted; the backend still enforces the real boundary.
class ConnectivityService {
  Future<bool> isOnline() async {
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );
      return interfaces.any(
        (interface) => interface.addresses.any(
          (address) => !address.isLoopback,
        ),
      );
    } catch (_) {
      return false;
    }
  }
}
