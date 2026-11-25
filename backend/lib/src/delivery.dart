import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'config.dart';

/// Delivery failure is always reported to callers as a generic recovery
/// acknowledgement. Provider errors are never forwarded.
class DeliveryException implements Exception {
  const DeliveryException(this.message);

  final String message;

  @override
  String toString() => 'DeliveryException: $message';
}

/// Backend-owned delivery of a backend-generated code. The destination comes
/// exclusively from the challenge row, never from the HTTP request.
class RecoveryDelivery {
  RecoveryDelivery(
    this._smtp,
    this._sms, {
    http.Client? httpClient,
    this._socketSecurityContext,
  })  : _httpClient = httpClient ?? http.Client();

  final SmtpConfig _smtp;
  final SmsConfig _sms;
  final http.Client _httpClient;
  final SecurityContext? _socketSecurityContext;

  Future<void> send({
    required String channel,
    required String destination,
    required String otp,
  }) async {
    if (channel == 'email') {
      await _sendEmail(destination, otp);
    } else if (channel == 'sms') {
      await _sendSms(destination, otp);
    } else {
      throw const DeliveryException('Unsupported channel');
    }
  }

  static bool isValidDestination(String channel, String value) {
    if (value.isEmpty || value.length > 255) return false;
    if (RegExp(r'[\r\n\u0000-\u001f\u007f]').hasMatch(value)) return false;
    if (channel == 'email') {
      return RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value);
    }
    return RegExp(r'^\+[1-9][0-9]{6,14}$').hasMatch(value);
  }

  Future<void> _sendEmail(String to, String otp) async {
    if (_smtp.from.isEmpty || !isValidDestination('email', to)) {
      throw const DeliveryException('Invalid email destination');
    }
    // No cleartext path exists: configuration validation guarantees TLS and
    // this authority never opens a plain SMTP socket.
    Socket socket;
    try {
      socket = await SecureSocket.connect(
        _smtp.host,
        _smtp.port,
        context: _socketSecurityContext,
      ).timeout(const Duration(seconds: 10));
    } catch (_) {
      throw const DeliveryException('Email delivery failed');
    }
    final smtp = _SmtpConnection(socket);
    try {
      await smtp.expect('220');
      await smtp.send('EHLO ${_smtp.helo}\r\n');
      await smtp.expect('250');
      if (_smtp.username.isNotEmpty) {
        await smtp.send('AUTH LOGIN\r\n');
        await smtp.expect('334');
        await smtp.send('${base64.encode(utf8.encode(_smtp.username))}\r\n');
        await smtp.expect('334');
        await smtp.send('${base64.encode(utf8.encode(_smtp.password))}\r\n');
        await smtp.expect('235');
      }
      await smtp.send('MAIL FROM:<${_smtp.from}>\r\n');
      await smtp.expect('250');
      await smtp.send('RCPT TO:<$to>\r\n');
      await smtp.expect('250');
      await smtp.send('DATA\r\n');
      await smtp.expect('354');
      await smtp.send(
        'From: ${_smtp.from}\r\n'
        'To: $to\r\n'
        'Subject: Your recovery code\r\n'
        'Content-Type: text/plain; charset=utf-8\r\n'
        '\r\n'
        'Your recovery code is: $otp\r\n'
        'It expires in 5 minutes. If you did not request it, ignore this message.\r\n'
        '.\r\n',
      );
      await smtp.expect('250');
      await smtp.send('QUIT\r\n');
    } on DeliveryException {
      rethrow;
    } catch (_) {
      throw const DeliveryException('Email delivery failed');
    } finally {
      await smtp.close();
    }
  }

  Future<void> _sendSms(String to, String otp) async {
    if (!isValidDestination('sms', to)) {
      throw const DeliveryException('Invalid phone destination');
    }
    final headers = <String, String>{
      'content-type': 'application/json',
      'accept': 'application/json',
    };
    if (_sms.apiKey.isNotEmpty) {
      headers['authorization'] = 'Bearer ${_sms.apiKey}';
    }
    try {
      final response = await _httpClient
          .post(
            Uri.parse(_sms.endpoint),
            headers: headers,
            body: jsonEncode({
              'to': to,
              'from': _sms.sender,
              'channel': 'sms',
              'otp': otp,
            }),
          )
          .timeout(const Duration(seconds: 10));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw const DeliveryException('SMS delivery failed');
      }
    } on DeliveryException {
      rethrow;
    } catch (_) {
      throw const DeliveryException('SMS delivery failed');
    }
  }
}

/// Minimal SMTP reply reader with one persistent subscription.
class _SmtpConnection {
  _SmtpConnection(this._socket) {
    _subscription = _socket.listen(_onData, onError: (Object error) {
      while (_waiters.isNotEmpty) {
        _waiters.removeFirst().completeError(error);
      }
    });
  }

  final Socket _socket;
  late final StreamSubscription<List<int>> _subscription;
  final Queue<Completer<String>> _waiters = Queue<Completer<String>>();
  final List<String> _pending = <String>[];
  String _buffer = '';

  void _onData(List<int> bytes) {
    _buffer += utf8.decode(bytes, allowMalformed: true);
    while (true) {
      final index = _buffer.indexOf('\r\n');
      if (index < 0) return;
      final line = _buffer.substring(0, index);
      _buffer = _buffer.substring(index + 2);
      if (_waiters.isNotEmpty) {
        _waiters.removeFirst().complete(line);
      } else {
        _pending.add(line);
      }
    }
  }

  Future<void> send(String command) async {
    _socket.add(utf8.encode(command));
    await _socket.flush();
  }

  Future<String> _readLine() {
    if (_pending.isNotEmpty) {
      return Future<String>.value(_pending.removeAt(0));
    }
    final completer = Completer<String>();
    _waiters.add(completer);
    return completer.future.timeout(const Duration(seconds: 10));
  }

  /// Bounded so a silent/misbehaving provider cannot hang the request forever.
  Future<void> expect(String code) =>
      _expect(code).timeout(const Duration(seconds: 15));

  Future<void> _expect(String code) async {
    while (true) {
      final line = await _readLine();
      if (line.length < 3) {
        throw const DeliveryException('Email delivery failed');
      }
      final replyCode = line.substring(0, 3);
      final continuation = line.length > 3 && line[3] == '-';
      if (replyCode.startsWith('4') || replyCode.startsWith('5')) {
        throw const DeliveryException('Email delivery failed');
      }
      if (replyCode == code && !continuation) return;
    }
  }

  Future<void> close() async {
    await _subscription.cancel();
    _socket.destroy();
  }
}
