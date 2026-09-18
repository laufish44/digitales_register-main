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

/// Searching across everything the app has loaded.
///
/// Only over what is already in the store — the register has no search endpoint
/// and asking it page by page would be slow and rude. What has not been opened
/// yet is therefore not searchable, and the UI says so.
///
/// Free of Flutter so the matching can be tested on its own.
library;

import 'package:dr/app_state.dart';
import 'package:dr/data.dart';
import 'package:dr/stats.dart';
import 'package:dr/utc_date_time.dart';

enum SearchCategory {
  message,
  entry,
  grade,
  subject,
  lesson,
  absence,
}

extension SearchCategoryName on SearchCategory {
  String get label {
    switch (this) {
      case SearchCategory.message:
        return "Mitteilungen";
      case SearchCategory.entry:
        return "Einträge";
      case SearchCategory.grade:
        return "Noten";
      case SearchCategory.subject:
        return "Fächer";
      case SearchCategory.lesson:
        return "Stundenplan";
      case SearchCategory.absence:
        return "Absenzen";
    }
  }
}

class SearchResult {
  const SearchResult({
    required this.category,
    required this.title,
    required this.subtitle,
    required this.score,
    this.date,
    this.messageId,
  });

  final SearchCategory category;
  final String title;
  final String subtitle;

  /// Higher is a better match.
  final int score;

  final UtcDateTime? date;

  /// Set for messages, so tapping the result can open it.
  final int? messageId;
}

/// How well [text] matches [query], or null when it does not.
///
/// Three tiers, so that typing "mat" puts "Mathematik" above "Informatik" and
/// both above a subsequence match like "Mitteilung an Tobias".
int? scoreMatch(String text, String query) {
  if (query.isEmpty) return null;
  final haystack = text.toLowerCase();
  final needle = query.toLowerCase();

  if (haystack == needle) return 1000;
  if (haystack.startsWith(needle)) return 800 - haystack.length.clamp(0, 200);

  final index = haystack.indexOf(needle);
  if (index >= 0) {
    // A match at a word boundary reads as more deliberate than one inside a
    // word.
    final atWordStart = index > 0 && haystack[index - 1] == " ";
    return (atWordStart ? 600 : 400) - index.clamp(0, 200);
  }

  // Every letter in order but not adjacent: the last resort, and only for
  // queries long enough that it is not just noise.
  if (needle.length < 3) return null;
  var position = 0;
  for (final rune in needle.runes) {
    final found = haystack.indexOf(String.fromCharCode(rune), position);
    if (found < 0) return null;
    position = found + 1;
  }
  return 100;
}

class Search {
  Search._();

  /// Everything matching [query], best first.
  ///
  /// [categories] limits which kinds are searched; empty means all of them.
  static List<SearchResult> run(
    AppState state,
    String query, {
    Set<SearchCategory> categories = const {},
    int limit = 100,
  }) {
    final trimmed = query.trim();
    if (trimmed.length < 2) return const [];
    bool wanted(SearchCategory category) =>
        categories.isEmpty || categories.contains(category);

    final results = <SearchResult>[];

    if (wanted(SearchCategory.message)) {
      for (final message in state.messagesState.messages) {
        final score = _best([
          scoreMatch(message.subject, trimmed),
          scoreMatch(message.fromName, trimmed),
          // The body is worth searching but is a weaker signal than the
          // subject, so it is damped.
          _damp(scoreMatch(message.text, trimmed)),
        ]);
        if (score == null) continue;
        results.add(SearchResult(
          category: SearchCategory.message,
          title: message.subject,
          subtitle: "${message.fromName} · ${_formatDate(message.timeSent)}",
          score: score,
          date: message.timeSent,
          messageId: message.id,
        ));
      }
    }

    if (wanted(SearchCategory.entry)) {
      final seen = <String>{};
      for (final entry in Agenda.collect(
        calendar: state.calendarState,
        dashboard: state.dashboardState,
      )) {
        if (!seen.add(entry.identity)) continue;
        final score = _best([
          scoreMatch(entry.name, trimmed),
          scoreMatch(entry.subject, trimmed),
          _damp(scoreMatch(entry.typeName, trimmed)),
        ]);
        if (score == null) continue;
        results.add(SearchResult(
          category: SearchCategory.entry,
          title: entry.name,
          subtitle: [
            entry.subject,
            entry.isExam ? "Prüfung" : "Hausaufgabe",
            _formatDate(entry.deadline),
          ].where((s) => s.isNotEmpty).join(" · "),
          score: score,
          date: entry.deadline,
        ));
      }
    }

    for (final subject in state.gradesState.subjects) {
      if (wanted(SearchCategory.subject)) {
        final score = scoreMatch(subject.name, trimmed);
        if (score != null) {
          final average = GradeStats.weightedAverage(
              subject.basicGrades(state.gradesState.semester) ??
                  const <GradeAll>[]);
          results.add(SearchResult(
            category: SearchCategory.subject,
            title: subject.name,
            subtitle: average == null
                ? "Noch keine Noten"
                : "Schnitt ${(average / 100).toStringAsFixed(2)}",
            score: score,
          ));
        }
      }

      if (wanted(SearchCategory.grade)) {
        for (final grade
            in subject.basicGrades(state.gradesState.semester) ??
                const <GradeAll>[]) {
          final score = _best([
            scoreMatch(grade.type, trimmed),
            _damp(scoreMatch(subject.name, trimmed)),
          ]);
          if (score == null) continue;
          results.add(SearchResult(
            category: SearchCategory.grade,
            title: "${subject.name}: ${formatGradeFromInt(grade.grade)}",
            subtitle: "${grade.type} · ${_formatDate(grade.date)}",
            score: score,
            date: grade.date,
          ));
        }
      }
    }

    if (wanted(SearchCategory.lesson)) {
      final seen = <String>{};
      for (final day in state.calendarState.days.values) {
        for (final hour in day.hours) {
          final teachers = hour.teachers.map((t) => t.fullName).join(", ");
          final rooms = hour.rooms.join(", ");
          final score = _best([
            scoreMatch(hour.subject, trimmed),
            scoreMatch(teachers, trimmed),
            scoreMatch(rooms, trimmed),
          ]);
          if (score == null) continue;
          // One row per subject, not per occurrence in the timetable.
          if (!seen.add("${hour.subject}|$teachers|$rooms")) continue;
          results.add(SearchResult(
            category: SearchCategory.lesson,
            title: hour.subject,
            subtitle: [
              if (teachers.isNotEmpty) teachers,
              if (rooms.isNotEmpty) "Raum $rooms",
            ].join(" · "),
            score: score,
          ));
        }
      }
    }

    if (wanted(SearchCategory.absence)) {
      for (final group in state.absencesState.absences) {
        final score = _best([
          scoreMatch(group.reason ?? "", trimmed),
          scoreMatch(group.note ?? "", trimmed),
        ]);
        if (score == null) continue;
        final first = group.absences.isEmpty ? null : group.absences.first.date;
        results.add(SearchResult(
          category: SearchCategory.absence,
          title: group.reason?.isNotEmpty == true
              ? group.reason!
              : "Absenz ohne Grund",
          subtitle: [
            if (first != null) _formatDate(first),
            "${group.absences.length} Stunden",
          ].join(" · "),
          score: score,
          date: first,
        ));
      }
    }

    results.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      if (byScore != 0) return byScore;
      // Equally good matches: the more recent one first.
      final aDate = a.date, bDate = b.date;
      if (aDate != null && bDate != null) return bDate.compareTo(aDate);
      return a.title.compareTo(b.title);
    });
    return results.length > limit ? results.sublist(0, limit) : results;
  }

  static int? _best(List<int?> scores) {
    int? best;
    for (final score in scores) {
      if (score == null) continue;
      if (best == null || score > best) best = score;
    }
    return best;
  }

  /// Halves a score, for fields that should match but not win.
  static int? _damp(int? score) => score == null ? null : score ~/ 2;

  static String _formatDate(UtcDateTime date) =>
      "${date.day}.${date.month}.${date.year}";
}
