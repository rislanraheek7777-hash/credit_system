import 'package:web/web.dart' as web;

/// Web connectivity gate using the browser's own online/offline signal.
class ConnectivityService {
  Future<bool> isOnline() async => web.window.navigator.onLine;
}
