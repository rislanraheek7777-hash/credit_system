import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import 'package:credit_system/features/auth/data/daos/user_dao.dart';
import 'package:credit_system/features/auth/data/services/auth_service.dart';
import 'package:credit_system/features/auth/data/services/otp_gateway.dart';

/// Two-step, server-authoritative self-service credential recovery.
///
/// Step 1 asks for an identifier and a verified contact channel, then always
/// shows the same generic acknowledgement. Step 2 verifies the one-time code
/// and sets a new password; the username is disclosed **only** after that
/// successful verification.
///
/// The dialog never writes to local Drift storage and never accepts a
/// client-supplied shop id.
class CredentialRecoveryDialog extends StatefulWidget {
  final AuthService authService;

  /// Connectivity gate. Recovery is blocked (with a generic message) when the
  /// device has no server connectivity.
  final Future<bool> Function() isOnline;

  /// Optional narrow cache seeder. Supplied by the login screen so a recovered
  /// staff member can authenticate on a fresh device.
  final UserDao? userDao;

  const CredentialRecoveryDialog({
    super.key,
    required this.authService,
    required this.isOnline,
    this.userDao,
  });

  /// Shows the dialog and returns the confirmed result (including the username)
  /// only after a successful verification, otherwise `null`.
  static Future<CredentialRecoveryConfirmResult?> show(
    BuildContext context, {
    required AuthService authService,
    required Future<bool> Function() isOnline,
    UserDao? userDao,
  }) {
    return showDialog<CredentialRecoveryConfirmResult>(
      context: context,
      builder: (context) => CredentialRecoveryDialog(
        authService: authService,
        isOnline: isOnline,
        userDao: userDao,
      ),
    );
  }

  @override
  State<CredentialRecoveryDialog> createState() =>
      _CredentialRecoveryDialogState();
}

class _CredentialRecoveryDialogState extends State<CredentialRecoveryDialog> {
  static const String _genericRequestMessage =
      'If the account exists, a recovery code has been sent.';
  static const String _genericFailureMessage =
      'Unable to complete recovery. Please check your details and try again.';

  final _identifierController = TextEditingController();
  final _otpController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  RecoveryChannel _channel = RecoveryChannel.email;
  String? _clientOperationId;
  bool _stepTwo = false;
  bool _isLoading = false;
  String? _message;
  String? _error;
  String? _cacheWarning;
  CredentialRecoveryConfirmResult? _result;

  @override
  void dispose() {
    _identifierController.dispose();
    _otpController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _requestCode() async {
    final identifier = _identifierController.text.trim();
    if (identifier.isEmpty) {
      setState(() => _error = 'Enter your username or verified contact detail');
      return;
    }
    if (!await widget.isOnline()) {
      setState(() {
        _error =
            'Recovery is unavailable while offline. Please try again when connected.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
      _message = null;
    });

    // A fresh UUIDv4 per request; re-transmitting the same operation id is
    // de-duplicated server-side by the challenge's idempotency key.
    final operationId = const Uuid().v4();
    try {
      final result = await widget.authService.requestCredentialRecovery(
        identifier: identifier,
        channel: _channel,
        clientOperationId: operationId,
        idempotencyKey: operationId,
      );
      if (!mounted) return;
      // Use the authoritative ids returned by the server, not the locally
      // generated ones. The stored operation id is the /verify reference.
      setState(() {
        _clientOperationId = result.clientOperationId;
        _stepTwo = true;
        _isLoading = false;
        // Identical for known and unknown identifiers — never a username,
        // shop id, or channel.
        _message = _genericRequestMessage;
      });
    } on CredentialRecoveryOfflineException {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error =
            'Recovery is unavailable while offline. Please try again when connected.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _stepTwo = false;
        _message = null;
        _error = _genericFailureMessage;
      });
    }
  }

  /// Requests a fresh code after a delivery failure. A brand-new operation id
  /// and idempotency key guarantee this is not treated as a replay.
  Future<void> _resendCode() async {
    final identifier = _identifierController.text.trim();
    if (identifier.isEmpty || !await widget.isOnline()) {
      setState(() {
        _error =
            'Recovery is unavailable while offline. Please try again when connected.';
      });
      return;
    }
    setState(() {
      _isLoading = true;
      _error = null;
      _message = null;
    });
    final operationId = const Uuid().v4();
    try {
      final result = await widget.authService.requestCredentialRecovery(
        identifier: identifier,
        channel: _channel,
        clientOperationId: operationId,
        idempotencyKey: operationId,
      );
      if (!mounted) return;
      setState(() {
        _clientOperationId = result.clientOperationId;
        _stepTwo = true;
        _isLoading = false;
        _message = _genericRequestMessage;
      });
    } on CredentialRecoveryOfflineException {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _message = null;
        _error =
            'Recovery is unavailable while offline. Please try again when connected.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _message = null;
        _error = _genericFailureMessage;
      });
    }
  }

  Future<void> _confirmRecovery() async {
    final operationId = _clientOperationId;
    final otp = _otpController.text.trim();
    final newPassword = _newPasswordController.text;
    if (operationId == null || otp.isEmpty || newPassword.isEmpty) {
      setState(() => _error = 'Enter the code and a new password');
      return;
    }
    if (newPassword.length < 8) {
      setState(() => _error = 'Password must be at least 8 characters');
      return;
    }
    if (newPassword != _confirmPasswordController.text) {
      setState(() => _error = 'Passwords do not match');
      return;
    }
    if (!await widget.isOnline()) {
      setState(() {
        _error =
            'Recovery is unavailable while offline. Please try again when connected.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final result = await widget.authService.confirmCredentialRecovery(
        clientOperationId: operationId,
        otp: otp,
        newPassword: newPassword,
      );
      // The server-side reset already succeeded. A local cache failure must
      // never be reported as a failed reset.
      String? cacheWarning;
      try {
        await widget.userDao?.seedRecoveryIdentity(
          userId: result.userId,
          shopId: result.shopId,
          username: result.username,
          role: result.role,
          sessionVersion: result.sessionVersion,
        );
      } catch (_) {
        cacheWarning =
            'Password updated, but this device could not cache your sign-in '
            'identity. Please sign in online.';
      }
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _result = result;
        _message = null;
        _error = null;
        _cacheWarning = cacheWarning;
      });
    } on CredentialRecoveryOfflineException {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error =
            'Recovery is unavailable while offline. Please try again when connected.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        // Clear the step-one success notice so no green message is left beside
        // a red failure. Wrong/expired/consumed/threshold failures are identical.
        _message = null;
        _error = _genericFailureMessage;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final succeeded = _result != null;

    return AlertDialog(
      title: Text(succeeded ? 'Password updated' : 'Recover access'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (succeeded) ...[
              const Text(
                'Your password has been reset and all existing sessions were '
                'signed out. Sign in again with your username.',
              ),
              const SizedBox(height: 12),
              // The username is disclosed only AFTER successful verification.
              Text(
                'Username: ${_result!.username}',
                key: const Key('recoveredUsername'),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              if (_cacheWarning != null) ...[
                const SizedBox(height: 12),
                Text(
                  _cacheWarning!,
                  key: const Key('recoveryCacheWarning'),
                  style: const TextStyle(color: Colors.orange),
                ),
              ],
            ] else ...[
              if (!_stepTwo) ...[
                Text(
                  'Choose where to send a recovery code. We will only tell you '
                  'whether a code was sent — never whether an account exists.',
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('recoveryIdentifierField'),
                  controller: _identifierController,
                  decoration: const InputDecoration(
                    labelText: 'Username, email, or phone',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                RadioGroup<RecoveryChannel>(
                  groupValue: _channel,
                  onChanged: (RecoveryChannel? selected) {
                    if (!_isLoading && selected != null) {
                      setState(() => _channel = selected);
                    }
                  },
                  child: Column(
                    children: [
                      ListTile(
                        key: Key('recoveryChannelEmail'),
                        title: Text('Email'),
                        leading: Radio<RecoveryChannel>(
                          value: RecoveryChannel.email,
                        ),
                        onTap: () {
                          if (!_isLoading) {
                            setState(() => _channel = RecoveryChannel.email);
                          }
                        },
                      ),
                      ListTile(
                        key: Key('recoveryChannelSms'),
                        title: Text('SMS'),
                        leading: Radio<RecoveryChannel>(
                          value: RecoveryChannel.sms,
                        ),
                        onTap: () {
                          if (!_isLoading) {
                            setState(() => _channel = RecoveryChannel.sms);
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ] else ...[
                const Text(
                  'Enter the recovery code you received and choose a new '
                  'password.',
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('recoveryOtpField'),
                  controller: _otpController,
                  decoration: const InputDecoration(
                    labelText: 'Recovery code',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('recoveryNewPasswordField'),
                  controller: _newPasswordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'New password (minimum 8 characters)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('recoveryConfirmPasswordField'),
                  controller: _confirmPasswordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Confirm new password',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
              if (_message != null) ...[
                const SizedBox(height: 12),
                Text(
                  _message!,
                  key: const Key('recoveryGenericMessage'),
                  style: const TextStyle(color: Colors.green),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  key: const Key('recoveryError'),
                  style: const TextStyle(color: Colors.red),
                ),
              ],
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
        if (!succeeded && _stepTwo)
          TextButton(
            key: const Key('recoveryResendButton'),
            onPressed: _isLoading ? null : _resendCode,
            child: const Text('Resend code'),
          ),
        if (!succeeded)
          ElevatedButton(
            key: Key(_stepTwo ? 'recoveryConfirmButton' : 'recoveryRequestButton'),
            onPressed: _isLoading ? null : (_stepTwo ? _confirmRecovery : _requestCode),
            child: _isLoading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(_stepTwo ? 'Reset password' : 'Send code'),
          ),
      ],
    );
  }
}


