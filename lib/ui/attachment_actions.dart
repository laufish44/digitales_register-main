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

/// The row of buttons under an attachment: open, save somewhere, copy.
library;

import 'package:dr/file_actions.dart';
import 'package:flutter/material.dart';

class AttachmentActions extends StatelessWidget {
  const AttachmentActions({
    super.key,
    required this.name,
    required this.onOpen,
    this.onSaveAs,
    this.onCopy,
    this.enabled = true,
  });

  /// Shown as the label of the row.
  final String name;

  final VoidCallback? onOpen;

  /// Opens the system's "save as" dialog (or the share sheet on Android).
  final VoidCallback? onSaveAs;

  /// Puts the file on the clipboard. Hidden where that is not possible.
  final VoidCallback? onCopy;

  final bool enabled;

  @override
  Widget build(BuildContext context) {
    // Copying a file is a Windows-only trick; showing a button that cannot
    // work would be worse than not showing it.
    final showCopy = onCopy != null && canCopyFileToClipboard;

    return Row(
      children: [
        Expanded(
          child: Text(name, softWrap: true),
        ),
        const SizedBox(width: 8),
        _ActionButton(
          icon: Icons.open_in_new,
          tooltip: "Öffnen",
          onPressed: enabled ? onOpen : null,
        ),
        _ActionButton(
          icon: Icons.download,
          tooltip: hasSaveAsDialog ? "Speichern unter …" : "Teilen / sichern",
          onPressed: enabled ? onSaveAs : null,
        ),
        if (showCopy)
          _ActionButton(
            icon: Icons.copy,
            tooltip: "In die Zwischenablage kopieren",
            onPressed: enabled ? onCopy : null,
          ),
      ],
    );
  }
}

/// Small, quiet, and all the same size — these sit next to a file name, not in
/// an app bar.
class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon, size: 20),
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
      padding: EdgeInsets.zero,
      onPressed: onPressed,
    );
  }
}
