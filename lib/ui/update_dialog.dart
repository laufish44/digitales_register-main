// Copyright (C) 2021 Michael Debertol
//
// This file is part of digitales_register.
//
// digitales_register is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// digitales_register is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with digitales_register.  If not, see <http://www.gnu.org/licenses/>.

/// Offers an available update and shows the download progress.
library;

import 'package:dr/update/update_service.dart';
import 'package:dr/util.dart';
import 'package:flutter/material.dart';

/// Tells the user about [info] and, if they agree, downloads and starts it.
Future<void> showUpdateDialog(
  BuildContext context,
  UpdateInfo info, {
  UpdateService service = const UpdateService(),
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _UpdateDialog(info: info, service: service),
  );
}

class _UpdateDialog extends StatefulWidget {
  const _UpdateDialog({required this.info, required this.service});

  final UpdateInfo info;
  final UpdateService service;

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  bool downloading = false;
  double? progress;
  String? message;
  bool messageIsError = false;

  Future<void> _install() async {
    final build = widget.info.build;
    if (build == null) return;
    setState(() {
      downloading = true;
      message = null;
      progress = null;
    });
    final result = await widget.service.download(
      build,
      onProgress: (value) {
        if (mounted) setState(() => progress = value);
      },
    );
    if (!mounted) return;
    setState(() {
      downloading = false;
      message = result.message;
      messageIsError = !result.success;
    });
    // On Windows the app exits from inside download(). Elsewhere the installer
    // has taken over; the dialog only stays open when there is something left
    // to say — on Android, what to do if no install prompt appeared.
    if (result.success && result.message == null && mounted) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final build = widget.info.build;
    return AlertDialog(
      title: Text("Version ${widget.info.version} verfügbar"),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Installiert: $appVersion"),
          if (widget.info.notes != null && widget.info.notes!.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(widget.info.notes!),
            ),
          if (build == null)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: Text(
                "Für dieses Betriebssystem wird kein Download angeboten.",
              ),
            ),
          if (downloading) ...[
            const SizedBox(height: 16),
            LinearProgressIndicator(value: progress),
            const SizedBox(height: 8),
            Text(
              progress == null
                  ? "Wird heruntergeladen …"
                  : "${(progress! * 100).round()} %",
            ),
          ],
          if (message != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                message!,
                style: messageIsError
                    ? TextStyle(color: Theme.of(context).colorScheme.error)
                    : null,
              ),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: downloading ? null : () => Navigator.pop(context),
          // Once the file is handed over there is nothing left to wait for.
          child: Text(
            message != null && !messageIsError ? "Schließen" : "Später",
          ),
        ),
        if (build != null)
          ElevatedButton(
            onPressed: downloading ? null : _install,
            child: Text(
              message != null && !messageIsError
                  ? "Erneut versuchen"
                  : "Aktualisieren",
            ),
          ),
      ],
    );
  }
}
