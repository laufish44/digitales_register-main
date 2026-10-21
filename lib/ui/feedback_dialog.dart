// Copyright (C) 2026 Laurin Feichter
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

/// "Verbesserung vorschlagen": a small form that ends in a GitHub issue.
///
/// The issue is not sent from the app — that would need a GitHub token built
/// into every copy, readable by anyone. Instead the form opens GitHub's "new
/// issue" page with title and text filled in; the user only confirms it there
/// with their own account.
library;

import 'dart:io';

import 'package:dr/fork_info.dart';
import 'package:dr/util.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

enum FeedbackKind {
  idea("Verbesserungsvorschlag", "enhancement"),
  bug("Fehler melden", "bug");

  const FeedbackKind(this.label, this.githubLabel);

  final String label;
  final String githubLabel;
}

/// GitHub cuts off longer links, and a cut-off link loses the text entirely.
const _maxBodyLength = 6000;

/// The "new issue" page of this fork's repository with everything filled in.
Uri feedbackIssueUrl({
  required FeedbackKind kind,
  required String title,
  required String text,
  required String version,
  required String platform,
  String repository = forkSourceUrl,
}) {
  var body = text.trim();
  if (body.length > _maxBodyLength) {
    body = "${body.substring(0, _maxBodyLength)} …";
  }
  body = "$body\n\n---\nApp-Version $version · $platform";
  return Uri.parse("$repository/issues/new").replace(queryParameters: {
    "title": title.trim(),
    "body": body,
    "labels": kind.githubLabel,
  });
}

String get _platformName {
  if (Platform.isAndroid) return "Android";
  if (Platform.isWindows) return "Windows";
  if (Platform.isIOS) return "iOS";
  if (Platform.isMacOS) return "macOS";
  if (Platform.isLinux) return "Linux";
  return Platform.operatingSystem;
}

Future<void> showFeedbackDialog(BuildContext context,
    {FeedbackKind kind = FeedbackKind.idea}) {
  return showDialog<void>(
    context: context,
    builder: (context) => _FeedbackDialog(initialKind: kind),
  );
}

class _FeedbackDialog extends StatefulWidget {
  const _FeedbackDialog({required this.initialKind});

  final FeedbackKind initialKind;

  @override
  State<_FeedbackDialog> createState() => _FeedbackDialogState();
}

class _FeedbackDialogState extends State<_FeedbackDialog> {
  late FeedbackKind kind = widget.initialKind;
  final title = TextEditingController();
  final text = TextEditingController();

  bool get _canSend => title.text.trim().isNotEmpty;

  @override
  void dispose() {
    title.dispose();
    text.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (!_canSend) return;
    final url = feedbackIssueUrl(
      kind: kind,
      title: title.text,
      text: text.text,
      version: appVersion,
      platform: _platformName,
    );
    final opened = await launchUrl(url, mode: LaunchMode.externalApplication);
    if (!mounted) return;
    if (opened) {
      Navigator.pop(context);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text("Der Browser konnte nicht geöffnet werden")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.enter, control: true): _send,
      },
      child: AlertDialog(
        title: const Text("Vorschlag oder Fehler melden"),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SegmentedButton<FeedbackKind>(
                  segments: [
                    for (final k in FeedbackKind.values)
                      ButtonSegment(value: k, label: Text(k.label)),
                  ],
                  selected: {kind},
                  onSelectionChanged: (s) => setState(() => kind = s.first),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: title,
                  autofocus: true,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    labelText: "Titel",
                    hintText: kind == FeedbackKind.idea
                        ? "z. B. Noten nach Datum sortieren"
                        : "z. B. Kalender lädt nicht",
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: text,
                  minLines: 4,
                  maxLines: 10,
                  textCapitalization: TextCapitalization.sentences,
                  keyboardType: TextInputType.multiline,
                  decoration: InputDecoration(
                    labelText: "Beschreibung",
                    alignLabelWithHint: true,
                    hintText: kind == FeedbackKind.idea
                        ? "Was soll die App können, und wofür brauchst du es?"
                        : "Was hast du gemacht, was ist passiert, was hättest "
                            "du erwartet?",
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  "Öffnet GitHub im Browser, mit allem schon ausgefüllt. Dort "
                  "nur noch mit deinem GitHub-Konto auf „Create“ tippen. "
                  "App-Version und Gerät werden angehängt, sonst nichts.",
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Abbrechen"),
          ),
          FilledButton.icon(
            onPressed: _canSend ? _send : null,
            icon: const Icon(Icons.open_in_new),
            label: const Text("Auf GitHub öffnen"),
          ),
        ],
      ),
    );
  }
}
