import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../../core/app_strings.dart';
import '../../core/pouch_bridge.dart';

class DesktopReportDialog extends StatefulWidget {
  const DesktopReportDialog({
    required this.bridge,
    required this.strings,
    required this.bytes,
    super.key,
  });

  final PouchBridge bridge;
  final AppStrings strings;
  final Uint8List bytes;

  @override
  State<DesktopReportDialog> createState() => _DesktopReportDialogState();
}

class _DesktopReportDialogState extends State<DesktopReportDialog> {
  bool _busy = false;
  String? _message;

  Future<void> _run(
    Future<bool> Function() action,
    String failure,
    String success,
  ) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final completed = await action();
      if (mounted) {
        setState(() => _message = completed ? success : 'reportCancelled');
      }
    } catch (_) {
      if (mounted) setState(() => _message = failure);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Dialog(
    child: SizedBox(
      width: 900,
      height: MediaQuery.sizeOf(context).height * 0.85,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(
              widget.strings.text('reportTitle'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            Expanded(
              child: PdfPreview(
                build: (_) async => widget.bytes,
                useActions: false,
                canDebug: false,
                canChangePageFormat: false,
                canChangeOrientation: false,
                onError: (_, _) => Center(
                  child: Text(widget.strings.text('reportPreviewFailed')),
                ),
              ),
            ),
            if (_message != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(widget.strings.text(_message!)),
              ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: _busy
                      ? null
                      : () => _run(
                          () => widget.bridge.printPdf(
                            widget.strings.text('reportTitle'),
                            widget.bytes,
                          ),
                          'printFailed',
                          'reportPrinted',
                        ),
                  icon: const Icon(Icons.print_outlined),
                  label: Text(widget.strings.text('printReport')),
                ),
                OutlinedButton.icon(
                  onPressed: _busy
                      ? null
                      : () => _run(
                          () => widget.bridge.savePdf(
                            'pouch-report.pdf',
                            widget.bytes,
                          ),
                          'reportSaveFailed',
                          'saved',
                        ),
                  icon: const Icon(Icons.save_alt),
                  label: Text(widget.strings.text('savePdf')),
                ),
                TextButton(
                  onPressed: _busy ? null : () => Navigator.pop(context),
                  child: Text(widget.strings.text('close')),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}
