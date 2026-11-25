// Platform-aware connectivity gate used by credential recovery.
//
// The web implementation reads `navigator.onLine`; the native implementation
// checks for a non-loopback network interface. Recovery never relies on an
// always-true default in production.
export 'connectivity_service_io.dart' if (dart.library.html) 'connectivity_service_web.dart';
