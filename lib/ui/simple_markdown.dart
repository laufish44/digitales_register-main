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

/// Just enough Markdown for release notes: headings, bullet and numbered
/// lists, paragraphs, and inline bold, italics, code and links.
///
/// The notes come from GitHub, where they are written in Markdown. Shown as
/// plain text the update dialog was full of `**` and `##`. A full Markdown
/// package would be a new dependency for one dialog; this covers what the
/// notes actually use and shows anything else as the text it is.
library;

import 'package:flutter/material.dart';

enum MarkdownBlockKind { heading, bullet, paragraph }

class MarkdownBlock {
  MarkdownBlock(this.kind, this.text, {this.level = 0, this.marker = "•"});

  MarkdownBlockKind kind;

  /// Lines that belong together are joined with a space, like Markdown does.
  String text;

  /// 1 for `#`, 2 for `##`, … — headings only.
  int level;

  /// "•", or "1." for a numbered list — list items only.
  final String marker;
}

final _heading = RegExp(r"^(#{1,6})\s+(.*?)\s*#*$");
final _bullet = RegExp(r"^[*+-]\s+(.*)$");
final _numbered = RegExp(r"^(\d+[.)])\s+(.*)$");

/// A line of `===` or `---`. Under a line of text it makes that line a
/// heading ("setext" style, which also reads well as plain text); on its own
/// it is a rule and shows nothing.
final _underline = RegExp(r"^(=+|-+)$");

/// Splits [source] into headings, list items and paragraphs.
List<MarkdownBlock> parseMarkdownBlocks(String source) {
  final blocks = <MarkdownBlock>[];
  // The paragraph or list item a following line continues.
  MarkdownBlock? open;
  for (final raw in source.replaceAll("\r\n", "\n").split("\n")) {
    final line = raw.trim();
    if (line.isEmpty) {
      open = null;
      continue;
    }
    final underline = _underline.firstMatch(line);
    if (underline != null) {
      if (open != null && open.kind == MarkdownBlockKind.paragraph) {
        open
          ..kind = MarkdownBlockKind.heading
          ..level = line.startsWith("=") ? 1 : 2;
      }
      open = null;
      continue;
    }
    final heading = _heading.firstMatch(line);
    if (heading != null) {
      blocks.add(MarkdownBlock(
        MarkdownBlockKind.heading,
        heading.group(2)!,
        level: heading.group(1)!.length,
      ));
      open = null;
      continue;
    }
    final bullet = _bullet.firstMatch(line);
    if (bullet != null) {
      open = MarkdownBlock(MarkdownBlockKind.bullet, bullet.group(1)!);
      blocks.add(open);
      continue;
    }
    final numbered = _numbered.firstMatch(line);
    if (numbered != null) {
      open = MarkdownBlock(
        MarkdownBlockKind.bullet,
        numbered.group(2)!,
        marker: numbered.group(1)!,
      );
      blocks.add(open);
      continue;
    }
    if (open != null) {
      open.text = "${open.text} $line";
      continue;
    }
    open = MarkdownBlock(MarkdownBlockKind.paragraph, line);
    blocks.add(open);
  }
  return blocks;
}

// Bold, code, link, then italics with * or _ (not inside a word, so file
// names like digitales_register stay as they are).
final _inline = RegExp(
  r"\*\*(.+?)\*\*"
  "|__(.+?)__"
  "|`([^`]+)`"
  r"|\[([^\]]+)\]\(([^)\s]+)\)"
  r"|\*(?!\s)(.+?)(?<!\s)\*"
  r"|(?<![A-Za-z0-9])_(?!\s)(.+?)(?<!\s)_(?![A-Za-z0-9])",
);

/// The inline formatting of [text] as spans, with the markers removed.
List<InlineSpan> markdownInline(
  String text, {
  TextStyle? style,
  Color? linkColor,
}) {
  final spans = <InlineSpan>[];
  var position = 0;
  for (final match in _inline.allMatches(text)) {
    if (match.start > position) {
      spans.add(
          TextSpan(text: text.substring(position, match.start), style: style));
    }
    final base = style ?? const TextStyle();
    if (match.group(1) != null || match.group(2) != null) {
      spans.addAll(markdownInline(
        match.group(1) ?? match.group(2)!,
        style: base.copyWith(fontWeight: FontWeight.bold),
        linkColor: linkColor,
      ));
    } else if (match.group(3) != null) {
      spans.add(TextSpan(
        text: match.group(3),
        style: base.copyWith(fontFamily: "monospace"),
      ));
    } else if (match.group(4) != null) {
      spans.addAll(markdownInline(
        match.group(4)!,
        style: base.copyWith(
          color: linkColor,
          decoration: TextDecoration.underline,
        ),
        linkColor: linkColor,
      ));
    } else {
      spans.addAll(markdownInline(
        match.group(6) ?? match.group(7)!,
        style: base.copyWith(fontStyle: FontStyle.italic),
        linkColor: linkColor,
      ));
    }
    position = match.end;
  }
  if (position < text.length) {
    spans.add(TextSpan(text: text.substring(position), style: style));
  }
  return spans;
}

/// Shows [source] as formatted text.
class SimpleMarkdown extends StatelessWidget {
  const SimpleMarkdown(this.source, {super.key});

  final String source;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final linkColor = theme.colorScheme.primary;
    Widget rich(String text, [TextStyle? style]) => Text.rich(
          TextSpan(
            children: markdownInline(text, style: style, linkColor: linkColor),
          ),
        );

    final children = <Widget>[];
    for (final block in parseMarkdownBlocks(source)) {
      switch (block.kind) {
        case MarkdownBlockKind.heading:
          children.add(Padding(
            padding: EdgeInsets.only(top: children.isEmpty ? 0 : 12, bottom: 4),
            child: rich(
              block.text,
              (block.level <= 1
                      ? theme.textTheme.titleMedium
                      : theme.textTheme.titleSmall)
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
          ));
        case MarkdownBlockKind.bullet:
          children.add(Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 20, child: Text(block.marker)),
                Expanded(child: rich(block.text)),
              ],
            ),
          ));
        case MarkdownBlockKind.paragraph:
          children.add(Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: rich(block.text),
          ));
      }
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }
}
