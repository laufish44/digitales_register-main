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

/// The school year in review: best and weakest subject, missed lessons,
/// tests and how the grades went — also as a picture to share.
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:dr/actions/app_actions.dart';
import 'package:dr/app_state.dart';
import 'package:dr/data.dart';
import 'package:dr/file_actions.dart';
import 'package:dr/main.dart' show showSnackBar;
import 'package:dr/stats.dart';
import 'package:dr/utc_date_time.dart';
import 'package:dr/util.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_built_redux/flutter_built_redux.dart';
import 'package:path_provider/path_provider.dart';

const _months = [
  "Jän",
  "Feb",
  "Mär",
  "Apr",
  "Mai",
  "Jun",
  "Jul",
  "Aug",
  "Sep",
  "Okt",
  "Nov",
  "Dez",
];

/// Everything the review shows, worked out from the store.
class YearReview {
  const YearReview({
    required this.schoolYear,
    required this.overall,
    required this.subjects,
    required this.gradeCount,
    required this.bestGrade,
    required this.missedLessons,
    required this.missedShare,
    required this.tests,
    required this.lessons,
    required this.perMonth,
  });

  /// "2026/27".
  final String schoolYear;

  /// Scaled by 100 like every grade; null without grades.
  final double? overall;

  /// Subject and average, best first.
  final List<(String, double)> subjects;
  final int gradeCount;
  final int? bestGrade;
  final int? missedLessons;
  final String? missedShare;
  final int tests;
  final int lessons;

  /// The average of the grades given in each month, in order.
  final List<(String, double)> perMonth;

  static YearReview from(AppState state, UtcDateTime now) {
    final grades = state.gradesState;
    final subjects = <(String, double)>[];
    final all = <GradeAll>[];
    for (final subject in grades.subjects) {
      final g = subject.basicGrades(Semester.all) ?? const <GradeAll>[];
      all.addAll(g);
      final average = GradeStats.subjectAverage(g);
      if (average != null) subjects.add((subject.name, average));
    }
    subjects.sort((a, b) => b.$2.compareTo(a.$2));

    final counting = all.where(countsTowardsAverage).toList();
    final byMonth = <String, List<GradeAll>>{};
    for (final g in counting) {
      final key = "${g.date.year}-${g.date.month.toString().padLeft(2, "0")}";
      byMonth.putIfAbsent(key, () => []).add(g);
    }
    final perMonth = [
      for (final key in byMonth.keys.toList()..sort())
        (
          _months[int.parse(key.substring(5)) - 1],
          GradeStats.weightedAverage(byMonth[key]!)!,
        ),
    ];

    // Tests and lessons from the calendar, up to today.
    final today = UtcDateTime(now.year, now.month, now.day);
    final testIds = <int>{};
    var lessons = 0;
    for (final day in state.calendarState.days.values) {
      if (day.date.isAfter(today)) continue;
      for (final hour in day.hours) {
        lessons += hour.length;
        for (final exam in hour.homeworkExams) {
          if (!exam.homework) testIds.add(exam.id);
        }
      }
    }

    final startYear = now.month >= 8 ? now.year : now.year - 1;
    final statistic = state.absencesState.statistic;
    return YearReview(
      schoolYear: "$startYear/${(startYear + 1) % 100}",
      overall: GradeStats.overallAverage(grades.subjects, Semester.all,
          ignored: state.settingsState.ignoreForGradesAverage),
      subjects: subjects,
      gradeCount: counting.length,
      bestGrade: counting.isEmpty
          ? null
          : counting.map((g) => g.grade!).reduce((a, b) => a > b ? a : b),
      missedLessons: statistic?.counter,
      missedShare: statistic?.percentage,
      tests: testIds.length,
      lessons: lessons,
      perMonth: perMonth,
    );
  }
}

/// Whether the register offers the review: from the last school day on, for
/// four weeks.
bool showYearReviewBanner(UtcDateTime? lastSchoolDay, UtcDateTime now) {
  if (lastSchoolDay == null) return false;
  final today = UtcDateTime(now.year, now.month, now.day);
  return !today.isBefore(lastSchoolDay) &&
      today.difference(lastSchoolDay).inDays <= 28;
}

class YearReviewPageContainer extends StatefulWidget {
  const YearReviewPageContainer({super.key});

  @override
  State<YearReviewPageContainer> createState() =>
      _YearReviewPageContainerState();
}

class _YearReviewPageContainerState extends State<YearReviewPageContainer> {
  var _requested = false;

  @override
  Widget build(BuildContext context) {
    return StoreConnection<AppState, AppActions, AppState>(
      connect: (state) => state,
      builder: (context, state, actions) {
        if (!_requested && state.loginState.loggedIn) {
          _requested = true;
          // Both semesters, and the absences, for the whole year.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            actions.gradesActions.load(Semester.all);
            if (state.absencesState.statistic == null) {
              actions.absencesActions.load();
            }
          });
        }
        return YearReviewPage(
          review: YearReview.from(state, now),
          name: state.config?.fullName,
        );
      },
    );
  }
}

class YearReviewPage extends StatefulWidget {
  const YearReviewPage({super.key, required this.review, this.name});

  final YearReview review;
  final String? name;

  @override
  State<YearReviewPage> createState() => _YearReviewPageState();
}

class _YearReviewPageState extends State<YearReviewPage> {
  final _pictureKey = GlobalKey();
  var _saving = false;

  Future<void> _saveImage() async {
    setState(() => _saving = true);
    try {
      final boundary = _pictureKey.currentContext!.findRenderObject()!
          as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2.5);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final dir = await getTemporaryDirectory();
      final name =
          "Schuljahr ${widget.review.schoolYear.replaceAll("/", "-")}.png";
      final file = File("${dir.path}${Platform.pathSeparator}$name");
      await file.writeAsBytes(bytes!.buffer.asUint8List());
      final result = await saveFileAs(file.path, suggestedName: name);
      if (result.message != null) showSnackBar(result.message!);
    } catch (e) {
      showSnackBar("Das Bild konnte nicht erstellt werden.");
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Schuljahr im Rückblick"),
        actions: [
          IconButton(
            tooltip: hasSaveAsDialog ? "Als Bild speichern" : "Als Bild teilen",
            icon: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(hasSaveAsDialog ? Icons.image_outlined : Icons.share),
            onPressed: _saving ? null : _saveImage,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: RepaintBoundary(
              key: _pictureKey,
              child: _ReviewCard(review: widget.review, name: widget.name),
            ),
          ),
        ),
      ),
    );
  }
}

class _ReviewCard extends StatelessWidget {
  const _ReviewCard({required this.review, this.name});

  final YearReview review;
  final String? name;

  String _g(double v) => gradeAverageFormat.format(v / 100);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final subjects = review.subjects;
    final tiles = <(String, String, IconData)>[
      if (review.overall != null)
        ("Gesamtschnitt", _g(review.overall!), Icons.star_outline),
      ("Noten", "${review.gradeCount}", Icons.format_list_numbered),
      ("Tests", "${review.tests}", Icons.assignment_outlined),
      if (review.lessons > 0) ("Stunden", "${review.lessons}", Icons.schedule),
      if (review.missedLessons != null)
        (
          "Gefehlt",
          "${review.missedLessons} h"
              "${review.missedShare == null ? "" : " · ${review.missedShare!.replaceAll(".", ",")} %"}",
          Icons.event_busy
        ),
      if (review.bestGrade != null)
        ("Beste Note", _g(review.bestGrade!.toDouble()), Icons.emoji_events),
    ];

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [scheme.primaryContainer, scheme.tertiaryContainer],
        ),
      ),
      child: DefaultTextStyle(
        style: theme.textTheme.bodyMedium!
            .copyWith(color: scheme.onPrimaryContainer),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Schuljahr ${review.schoolYear}",
                style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: scheme.onPrimaryContainer)),
            if (name != null) Text(name!),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final (label, value, icon) in tiles)
                  Container(
                    width: 132,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: scheme.surface.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(icon, size: 18, color: scheme.primary),
                        const SizedBox(height: 4),
                        Text(value,
                            style: theme.textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.bold)),
                        Text(label, style: theme.textTheme.bodySmall),
                      ],
                    ),
                  ),
              ],
            ),
            if (subjects.isNotEmpty) ...[
              const SizedBox(height: 16),
              _Highlight(
                icon: Icons.trending_up,
                label: "Bestes Fach",
                value: "${subjects.first.$1} · ${_g(subjects.first.$2)}",
              ),
              if (subjects.length > 1)
                _Highlight(
                  icon: Icons.trending_down,
                  label: "Schwächstes Fach",
                  value: "${subjects.last.$1} · ${_g(subjects.last.$2)}",
                ),
            ],
            if (review.perMonth.length > 1) ...[
              const SizedBox(height: 16),
              Text("Notenverlauf",
                  style: theme.textTheme.titleMedium
                      ?.copyWith(color: scheme.onPrimaryContainer)),
              const SizedBox(height: 8),
              SizedBox(
                height: 110,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (final (month, average) in review.perMonth)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 3),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Text(_g(average),
                                  style: theme.textTheme.labelSmall),
                              const SizedBox(height: 2),
                              Container(
                                // 4 at the bottom, 10 at the top.
                                height: 8 +
                                    60 * ((average / 100 - 4) / 6).clamp(0, 1),
                                decoration: BoxDecoration(
                                  color: average < 600
                                      ? scheme.error
                                      : scheme.primary,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(month, style: theme.textTheme.labelSmall),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child:
                  Text("Digitales Register", style: theme.textTheme.labelSmall),
            ),
          ],
        ),
      ),
    );
  }
}

class _Highlight extends StatelessWidget {
  const _Highlight(
      {required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label, value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 8),
          Text("$label: ", style: const TextStyle(fontWeight: FontWeight.bold)),
          Expanded(child: Text(value, overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }
}
