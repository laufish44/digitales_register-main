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

/// Own notes ("Erinnerungen") that belong to an entry of the register.
///
/// A teacher's entry often says too little ("Test"). A reminder on the same
/// day can add the missing context, and is shown and ticked off together with
/// the entry it belongs to (#10). The register has nowhere to store such a
/// link, so it lives in the reminder's text as a tag at the end,
/// `[#t4711]`: a letter for the kind of entry (ids are only unique per kind)
/// and its id. On the website the tag simply shows as part of the text.
library;

import 'package:dr/data.dart';

final _tag = RegExp(r"\s*\[#([a-z])(\d+)\]\s*$");

const _letters = {
  HomeworkType.lessonHomework: "h",
  HomeworkType.gradeGroup: "t",
  HomeworkType.grade: "n",
  HomeworkType.observation: "b",
  HomeworkType.homework: "e",
  HomeworkType.unknown: "x",
};

/// What identifies [entry] in a tag, e.g. `t4711`.
String linkKeyOf(Homework entry) => "${_letters[entry.type] ?? "x"}${entry.id}";

/// [text] with the tag that links it to [entry].
String linkedReminderText(String text, Homework entry) =>
    "${text.trim()} [#${linkKeyOf(entry)}]";

/// The key a reminder text links to, or null for a plain reminder.
String? linkKeyIn(String text) {
  final match = _tag.firstMatch(text);
  return match == null ? null : "${match.group(1)}${match.group(2)}";
}

/// The reminder's text as the user wrote it, without the tag.
String reminderTextOf(String text) => text.replaceFirst(_tag, "");

bool isReminder(Homework entry) => entry.type == HomeworkType.homework;

/// The reminders of one day, sorted to the entries they belong to.
class DayReminderLinks {
  DayReminderLinks._(this._byParent, this._linked);

  /// Groups [entries] — everything the dashboard shows for one day.
  ///
  /// A reminder whose entry is not on that day (deleted, or the tag was typed
  /// by hand) is not linked and shows on its own, as before.
  factory DayReminderLinks.of(Iterable<Homework> entries) {
    final byKey = {
      for (final entry in entries)
        if (!isReminder(entry)) linkKeyOf(entry): entry,
    };
    final byParent = <Homework, List<Homework>>{};
    final linked = <Homework>{};
    for (final entry in entries) {
      if (!isReminder(entry)) continue;
      final key = linkKeyIn(entry.subtitle);
      final parent = key == null ? null : byKey[key];
      if (parent == null) continue;
      byParent.putIfAbsent(parent, () => []).add(entry);
      linked.add(entry);
    }
    return DayReminderLinks._(byParent, linked);
  }

  final Map<Homework, List<Homework>> _byParent;
  final Set<Homework> _linked;

  /// The reminders that belong to [entry].
  List<Homework> remindersOf(Homework entry) => _byParent[entry] ?? const [];

  /// Whether [entry] is a reminder shown under another entry instead of on
  /// its own.
  bool isLinked(Homework entry) => _linked.contains(entry);
}
