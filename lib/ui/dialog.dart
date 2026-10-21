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

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A line under a text field pointing at [SubmitShortcut] — only where there
/// is a keyboard to press it on.
String? get submitShortcutHint {
  if (Platform.isMacOS) return "⌘+Enter speichert";
  if (Platform.isWindows || Platform.isLinux) return "Strg+Enter speichert";
  return null;
}

/// Ctrl+Enter (Cmd+Enter on a Mac) inside [child] does what the dialog's
/// save button does (#16) — also from a text field with several lines, where
/// a plain Enter starts a new line. Nothing happens while [onSubmit] is null,
/// just as the button is disabled then.
class SubmitShortcut extends StatelessWidget {
  const SubmitShortcut({
    super.key,
    required this.onSubmit,
    required this.child,
  });

  final VoidCallback? onSubmit;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    void submit() => onSubmit?.call();
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.enter, control: true): submit,
        const SingleActivator(LogicalKeyboardKey.numpadEnter, control: true):
            submit,
        const SingleActivator(LogicalKeyboardKey.enter, meta: true): submit,
      },
      child: child,
    );
  }
}

/// Shows a close button
class InfoDialog extends StatelessWidget {
  final Widget title;
  final Widget? content;
  final List<Widget>? actions;

  const InfoDialog({
    super.key,
    required this.title,
    this.content,
    this.actions,
  });
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      titlePadding: EdgeInsets.zero,
      title: Row(
        children: <Widget>[
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(
                left: 24,
                right: 24,
                top: 24,
              ),
              child: title,
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4, right: 4),
            child: IconButton(
              icon: const Icon(Icons.close),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 300),
        child: content,
      ),
      actions: actions,
    );
  }
}
