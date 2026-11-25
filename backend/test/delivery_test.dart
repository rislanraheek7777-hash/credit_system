import 'dart:convert';
import 'dart:io';

import 'package:credential_recovery_backend/src/config.dart';
import 'package:credential_recovery_backend/src/delivery.dart';
import 'package:test/test.dart';

void main() {
  test('email delivery performs a TLS SMTP handshake and sends the stored code',
      () async {
    const certPath = 'test/fixtures/smtp_cert.pem';
    const keyPath = 'test/fixtures/smtp_key.pem';
    final server = await SecureServerSocket.bind(
      InternetAddress.loopbackIPv4,
      0,
      SecurityContext()
        ..useCertificateChain(certPath)
        ..usePrivateKey(keyPath),
    );
    final received = StringBuffer();
    var inData = false;

    server.listen((socket) {
      socket.add(utf8.encode('220 test-smtp ready\r\n'));
      socket.listen((bytes) {
        final text = utf8.decode(bytes, allowMalformed: true);
        received.write(text);
        for (final line in text.split('\r\n')) {
          if (line.isEmpty) continue;
          if (inData) {
            if (line == '.') {
              inData = false;
              socket.add(utf8.encode('250 queued\r\n'));
            }
            continue;
          }
          if (line.toUpperCase().startsWith('DATA')) {
            inData = true;
            socket.add(utf8.encode('354 send data\r\n'));
          } else {
            socket.add(utf8.encode('250 ok\r\n'));
          }
        }
      });
    });

    try {
      final delivery = RecoveryDelivery(
        SmtpConfig(
          host: '127.0.0.1',
          port: server.port,
          username: '',
          password: '',
          from: 'noreply@example.test',
          useTls: true,
        ),
        const SmsConfig(endpoint: '', sender: '', apiKey: ''),
        socketSecurityContext: SecurityContext(withTrustedRoots: false)
          ..setTrustedCertificates(certPath),
      );
      await delivery.send(
        channel: 'email',
        destination: 'staff@example.test',
        otp: '0123456789abcdef',
      );

      final transcript = received.toString();
      expect(transcript, contains('EHLO localhost'));
      expect(transcript, contains('MAIL FROM:<noreply@example.test>'));
      expect(transcript, contains('RCPT TO:<staff@example.test>'));
      expect(transcript, contains('Your recovery code is: 0123456789abcdef'));
    } finally {
      await server.close();
    }
  });
}
