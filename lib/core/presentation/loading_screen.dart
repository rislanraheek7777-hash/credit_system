import 'package:flutter/material.dart';

/// Simple full-screen loading indicator used during app initialization
/// and other blocking async operations.
class LoadingScreen extends StatelessWidget {
  final String? message;

  const LoadingScreen({super.key, this.message});

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
              Image.asset(
                'assets/logo.png',
                width: 112,
                height: 112,
                errorBuilder: (context, error, stackTrace) =>
                    const FlutterLogo(size: 112),
              ),
              const SizedBox(height: 16),
              const Icon(Icons.payments_rounded, size: 40, color: Colors.white),
              const SizedBox(height: 24),
              const CircularProgressIndicator(color: Colors.white),
              if (message != null) ...[
                const SizedBox(height: 16),
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