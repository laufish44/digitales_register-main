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

/// Selectable text whose links can be opened (#17).
///
/// On a computer a link opens with Ctrl+click (Cmd+click on a Mac), as in an
/// editor: a plain click keeps placing the cursor and selecting, which is
/// what the text is selectable for. On a phone a tap opens it.
library;

import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

/// A piece of text, and where it links to if it is a link.
class TextPiece {
  const TextPiece(this.text, [this.url]);

  final String text;
  final String? url;

  bool get isLink => url != null;

  @override
  bool operator ==(Object other) =>
      other is TextPiece && other.text == text && other.url == url;

  @override
  int get hashCode => Object.hash(text, url);

  @override
  String toString() => isLink ? "[$text]($url)" : text;
}

// `[text](https://…)` first, then bare addresses. A bare address stops at
// whitespace and does not take trailing punctuation with it ("…, siehe
// www.x.it." links www.x.it).
final _link = RegExp(
  r"\[([^\]\n]+)\]\(((?:https?://|www\.)[^\s)]+)\)"
  r"|((?:https?://|www\.)[^\s<>]*[^\s<>.,;:!?)\]'"
  '"])',
  caseSensitive: false,
);

/// Splits [text] into plain text and links.
List<TextPiece> splitLinks(String text) {
  final pieces = <TextPiece>[];
  var at = 0;
  for (final match in _link.allMatches(text)) {
    if (match.start > at) {
      pieces.add(TextPiece(text.substring(at, match.start)));
    }
    final label = match.group(1);
    final target = match.group(2) ?? match.group(3)!;
    pieces.add(TextPiece(label ?? target, _withScheme(target)));
    at = match.end;
  }
  if (at < text.length) pieces.add(TextPiece(text.substring(at)));
  return pieces;
}

String _withScheme(String url) =>
    url.toLowerCase().startsWith("www.") ? "https://$url" : url;

bool get _needsModifier =>
    Platform.isWindows || Platform.isLinux || Platform.isMacOS;

bool get _modifierPressed => Platform.isMacOS
    ? HardwareKeyboard.instance.isMetaPressed
    : HardwareKeyboard.instance.isControlPressed;

class LinkText extends StatefulWidget {
  const LinkText(this.text, {super.key, this.style});

  final String text;
  final TextStyle? style;

  @override
  State<LinkText> createState() => _LinkTextState();
}

class _LinkTextState extends State<LinkText> {
  final _recognizers = <TapGestureRecognizer>[];

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  void _disposeRecognizers() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
  }

  void _open(String url) {
    if (_needsModifier && !_modifierPressed) return;
    launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final pieces = splitLinks(widget.text);
    if (!pieces.any((p) => p.isLink)) {
      return SelectableText(widget.text, style: widget.style);
    }
    _disposeRecognizers();
    final linkStyle = TextStyle(
      color: Theme.of(context).colorScheme.primary,
      decoration: TextDecoration.underline,
    );
    TapGestureRecognizer recognizerFor(String url) {
      final recognizer = TapGestureRecognizer()..onTap = () => _open(url);
      _recognizers.add(recognizer);
      return recognizer;
    }

    final text = SelectableText.rich(
      TextSpan(
        style: widget.style,
        children: [
          for (final piece in pieces)
            if (piece.isLink)
              TextSpan(
                text: piece.text,
                style: linkStyle,
                mouseCursor: SystemMouseCursors.click,
                recognizer: recognizerFor(piece.url!),
              )
            else
              TextSpan(text: piece.text),
        ],
      ),
    );
    if (!_needsModifier) return text;
    return Tooltip(
      message: Platform.isMacOS
          ? "⌘+Klick öffnet den Link"
          : "Strg+Klick öffnet den Link",
      waitDuration: const Duration(milliseconds: 600),
      child: text,
    );
  }
}
