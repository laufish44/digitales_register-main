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

/// The register as an overview (22): one row per day with a symbol for each
/// entry. A tap on the row opens the day's full cards below it.
library;

import 'package:built_collection/built_collection.dart';
import 'package:dr/app_state.dart';
import 'package:dr/data.dart';
import 'package:dr/reminder_links.dart' show linkKeyIn;
import 'package:dr/ui/days.dart' show dayKind;
import 'package:flutter/material.dart';

/// What kind of entry a symbol stands for.
enum CompactKind { test, homework, reminder, grade, other }

CompactKind compactKindOf(Homework entry) {
  switch (entry.type) {
    case HomeworkType.homework:
      return CompactKind.reminder;
    case HomeworkType.grade:
      return CompactKind.grade;
    case HomeworkType.gradeGroup:
      return entry.warning ? CompactKind.test : CompactKind.homework;
    case HomeworkType.lessonHomework:
      return CompactKind.homework;
    default:
      return entry.warning ? CompactKind.test : CompactKind.other;
  }
}

class CompactDayRow extends StatefulWidget {
  const CompactDayRow({
    super.key,
    required this.day,
    required this.holidays,
    required this.nicks,
    required this.expanded,
  });

  final Day day;
  final BuiltList<HolidayPeriod> holidays;
  final BuiltMap<String, String> nicks;

  /// The day's full cards, shown when the row is opened.
  final Widget expanded;

  @override
  State<CompactDayRow> createState() => _CompactDayRowState();
}

class _CompactDayRowState extends State<CompactDayRow> {
  var _open = false;

  String _nick(String? subject) {
    if (subject == null || subject.isEmpty) return "";
    for (final e in widget.nicks.entries) {
      if (e.key.toLowerCase() == subject.toLowerCase()) return e.value;
    }
    return subject.length > 8 ? "${subject.substring(0, 7)}." : subject;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final kind = dayKind(widget.day.date, widget.holidays);
    // Notes that belong to an entry show inside it, not as a symbol of
    // their own.
    final entries = widget.day.homework
        .where((h) => !h.deleted)
        .where((h) =>
            !(h.type == HomeworkType.homework && linkKeyIn(h.subtitle) != null))
        .toList();
    if (_open) {
      return Column(
        children: [
          InkWell(
            onTap: () => setState(() => _open = false),
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 4),
              child: Icon(Icons.expand_less),
            ),
          ),
          widget.expanded,
        ],
      );
    }
    return InkWell(
      onTap: entries.isEmpty ? null : () => setState(() => _open = true),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 120,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.day.displayName,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(color: kind.color(theme)),
                  ),
                  if (kind.label != null)
                    Text(
                      kind.label!,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall
                          ?.copyWith(color: kind.color(theme)),
                    ),
                ],
              ),
            ),
            Expanded(
              child: entries.isEmpty
                  ? Text("–",
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: theme.disabledColor))
                  : Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        for (final entry in entries)
                          _Symbol(
                            kind: compactKindOf(entry),
                            label: _nick(entry.label),
                            done: entry.checkable && entry.checked,
                            tooltip: [
                              entry.label,
                              entry.title,
                              entry.subtitle,
                            ]
                                .whereType<String>()
                                .where((s) => s.isNotEmpty)
                                .join(" · "),
                          ),
                      ],
                    ),
            ),
            if (entries.isNotEmpty)
              const Icon(Icons.expand_more, size: 20, color: Colors.grey),
          ],
        ),
      ),
    );
  }
}

class _Symbol extends StatelessWidget {
  const _Symbol({
    required this.kind,
    required this.label,
    required this.done,
    required this.tooltip,
  });

  final CompactKind kind;
  final String label;
  final bool done;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (icon, color) = switch (kind) {
      CompactKind.test => (Icons.grade, theme.colorScheme.error),
      CompactKind.homework => (
          Icons.assignment_outlined,
          theme.colorScheme.primary
        ),
      CompactKind.reminder => (Icons.notes, theme.colorScheme.tertiary),
      CompactKind.grade => (Icons.star_outline, Colors.amber.shade700),
      CompactKind.other => (Icons.circle_outlined, Colors.grey),
    };
    final faded = done ? 0.45 : 1.0;
    return Tooltip(
      message: tooltip,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12 * faded),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: color.withValues(alpha: faded)),
            if (label.isNotEmpty) ...[
              const SizedBox(width: 3),
              Text(
                label,
                style: theme.textTheme.labelMedium?.copyWith(
                  decoration: done ? TextDecoration.lineThrough : null,
                  color: theme.textTheme.labelMedium?.color
                      ?.withValues(alpha: faded),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
