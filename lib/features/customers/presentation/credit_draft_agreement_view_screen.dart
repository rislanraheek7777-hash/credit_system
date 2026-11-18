import 'package:flutter/material.dart';

import 'package:credit_system/features/customers/domain/models/credit_document_content.dart';

/// Full-screen on-screen rendering of a draft credit agreement (Story 4.4).
///
/// This is the **review-only** presentation of the pre-disbursement draft:
/// every line is rendered from the same resolved [CreditDocumentContent] the
/// PDF renderer consumes, so the two can never drift apart. Nothing is
/// persisted, no file is written and no print or download action is
/// offered — the staff member reviews the agreement on screen and goes back.
///
/// The residential address and customer photo are never printed or shown;
/// NIC and phone follow the document masking rules resolved by the content
/// builder.
class CreditDraftAgreementViewScreen extends StatelessWidget {
  const CreditDraftAgreementViewScreen({super.key, required this.content});

  /// The resolved lines to render, produced by the shared draft content
  /// builder. The renderer must print exactly these lines.
  final CreditDocumentContent content;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Draft Agreement')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (content.watermark != null)
                    Center(
                      child: Text(
                        content.watermark!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.red,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  if (content.watermark != null) const SizedBox(height: 16),
                  Text(
                    content.title,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ...content.headerLines.map(_line),
                  const Divider(height: 24),
                  ...content.bodyLines.map(_line),
                  if (content.watermark != null) ...[
                    const Divider(height: 24),
                    Center(
                      child: Text(
                        content.watermark!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.red,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  ...content.footerLines.map(_footerLine),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _line(String line) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: SelectableText(line, style: const TextStyle(fontSize: 14)),
      );

  Widget _footerLine(String line) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: SelectableText(
          line,
          style: const TextStyle(fontSize: 11, color: Colors.grey),
        ),
      );
}
