import 'package:flutter/material.dart';

/// Full-screen loading indicator used during app initialization
/// and other blocking async operations.
class LoadingScreen extends StatelessWidget {
  final String? message;
  final String? userName;

  const LoadingScreen({super.key, this.message, this.userName});

  String get _greeting {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  String get _greetingLine {
    if (userName != null && userName!.trim().isNotEmpty) {
      return '$_greeting, ${userName!.trim()}';
    }
    return _greeting;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF1565C0), Color(0xFF42A5F5)],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(28),
                ),
                child: Image.asset(
                  'assets/logo.png',
                  width: 128,
                  height: 128,
                  errorBuilder: (context, error, stackTrace) =>
                      const FlutterLogo(size: 128),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                _greetingLine,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Credit System',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              const Icon(Icons.payments_rounded, size: 32, color: Colors.white70),
              const SizedBox(height: 28),
              const SizedBox(
                width: 40,
                height: 40,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 3,
                ),
              ),
              if (message != null) ...[
                const SizedBox(height: 20),
                Text(
                  message!,
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
