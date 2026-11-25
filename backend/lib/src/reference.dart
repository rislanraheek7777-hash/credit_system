import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Binds the opaque operation id to the challenge expiry with a backend-held
/// pepper. The digest is stored in the challenge row, so a reference stops
/// working at expiry even though the id itself never changes.
class OperationReference {
  OperationReference(this._pepper);

  final String _pepper;

  String digestFor(String clientOperationId, Object expiresAt) {
    final expiry = expiresAt is DateTime
        ? expiresAt.toUtc().toIso8601String()
        : expiresAt.toString();
    return Hmac(sha256, utf8.encode(_pepper))
        .convert(utf8.encode('$clientOperationId|$expiry'))
        .toString();
  }
}
