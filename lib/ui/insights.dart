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

/// Widgets that present the calculations from `stats.dart`.
library;

import 'package:dr/data.dart';
import 'package:dr/stats.dart';
import 'package:dr/util.dart';
import 'package:flutter/material.dart';

/// Warns when too many lessons have been missed.
class AbsenceWarningBanner extends StatelessWidget {
  const AbsenceWarningBanner({
    super.key,
    required this.statistic,
    required this.threshold,
    required this.notYetJustified,
  });

  final AbsenceStatistic? statistic;
  final int threshold;
  final int notYetJustified;

  @override
  Widget build(BuildContext context) {
    final percentage = AbsenceStats.missedPercentage(statistic);
    final warn = AbsenceStats.shouldWarn(
      statistic: statistic,
      thresholdPercentage: threshold.toDouble(),
    );
    if (!warn && notYetJustified == 0) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final color = warn ? theme.colorScheme.error : theme.colorScheme.primary;
    return Card(
      margin: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      color: color.withValues(alpha: 0.12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(warn ? Icons.warning_amber : Icons.info_outline, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (warn)
                    Text(
                      "Du hast ${gradeAverageFormat.format(percentage)} % der "
                      "Stunden versäumt (Grenze: $threshold %).",
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  if (notYetJustified > 0)
                    Padding(
                      padding: EdgeInsets.only(top: warn ? 4 : 0),
                      child: Text(
                        notYetJustified == 1
                            ? "Eine Absenz wartet noch auf eine Entschuldigung."
                            : "$notYetJustified Absenzen warten noch auf eine Entschuldigung.",
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Trend, spread and target calculations for a single subject.
class GradeTrendCard extends StatefulWidget {
  const GradeTrendCard({
    super.key,
    required this.subjectName,
    required this.grades,
    this.target,
    this.onTargetChanged,
  });

  final String subjectName;
  final List<GradeAll> grades;

  /// The saved target for this subject, scaled by 100. Null means none was set.
  final int? target;

  /// Called with the new target, scaled by 100. A value of 0 clears it.
  final ValueChanged<int>? onTargetChanged;

  @override
  State<GradeTrendCard> createState() => _GradeTrendCardState();
}

class _GradeTrendCardState extends State<GradeTrendCard> {
  /// The default when no target was saved for this subject yet.
  static const _defaultTarget = 8.0;

  /// While the slider is being dragged, so it follows the finger without
  /// writing to the store on every frame.
  double? _dragging;

  int targetWeight = 100;

  double get target =>
      _dragging ?? (widget.target != null ? widget.target! / 100 : _defaultTarget);

  String _format(double scaledByHundred) =>
      gradeAverageFormat.format(scaledByHundred / 100);

  @override
  Widget build(BuildContext context) {
    final grades = widget.grades;
    final average = GradeStats.weightedAverage(grades);
    if (average == null) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final trend = GradeStats.trendPerMonth(grades);
    final spread = GradeStats.spread(grades);
    final improvement = GradeStats.improvement(grades);
    final byType = GradeStats.averageByType(grades);
    final required = GradeStats.requiredGradeForTarget(
      grades: grades,
      target: target * 100,
      newWeightPercentage: targetWeight,
    );

    return Card(
      margin: const EdgeInsets.all(8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Auswertung", style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            Wrap(
              spacing: 16,
              runSpacing: 12,
              children: [
                _Stat(label: "Durchschnitt", value: _format(average)),
                if (spread != null) ...[
                  _Stat(label: "Beste", value: _format(spread.best)),
                  _Stat(label: "Schlechteste", value: _format(spread.worst)),
                  _Stat(
                    label: "Streuung",
                    value: "± ${_format(spread.standardDeviation)}",
                  ),
                ],
                if (trend != null)
                  _Stat(
                    label: "Trend / Monat",
                    value:
                        "${trend >= 0 ? "+" : ""}${gradeAverageFormat.format(trend)}",
                    color: trend >= 0.05
                        ? Colors.green
                        : trend <= -0.05
                            ? theme.colorScheme.error
                            : null,
                  ),
                if (improvement != null)
                  _Stat(
                    label: "2. vs. 1. Hälfte",
                    value:
                        "${improvement >= 0 ? "+" : ""}${gradeAverageFormat.format(improvement)}",
                    color: improvement >= 0.05
                        ? Colors.green
                        : improvement <= -0.05
                            ? theme.colorScheme.error
                            : null,
                  ),
              ],
            ),
            if (byType.length > 1) ...[
              const Divider(height: 24),
              Text("Nach Art", style: theme.textTheme.titleSmall),
              const SizedBox(height: 4),
              for (final entry in byType.entries)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      Expanded(child: Text(entry.key)),
                      Text(
                        _format(entry.value),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
            ],
            const Divider(height: 24),
            Row(
              children: [
                Expanded(
                  child: Text("Was brauche ich noch?",
                      style: theme.textTheme.titleSmall),
                ),
                if (widget.target != null && widget.onTargetChanged != null)
                  TextButton(
                    onPressed: () => widget.onTargetChanged!(0),
                    child: const Text("Ziel löschen"),
                  ),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: Slider(
                    value: target,
                    min: 4,
                    max: 10,
                    divisions: 24,
                    label: gradeAverageFormat.format(target),
                    onChanged: (value) => setState(() => _dragging = value),
                    onChangeEnd: (value) {
                      widget.onTargetChanged?.call((value * 100).round());
                      setState(() => _dragging = null);
                    },
                  ),
                ),
                SizedBox(
                  width: 56,
                  child: Text(
                    "Ziel ${gradeAverageFormat.format(target)}",
                    style: theme.textTheme.labelMedium,
                  ),
                ),
              ],
            ),
            Row(
              children: [
                const Text("Gewichtung"),
                const SizedBox(width: 12),
                DropdownButton<int>(
                  value: targetWeight,
                  items: const [
                    DropdownMenuItem(value: 50, child: Text("50 %")),
                    DropdownMenuItem(value: 100, child: Text("100 %")),
                    DropdownMenuItem(value: 200, child: Text("200 %")),
                    DropdownMenuItem(value: 300, child: Text("300 %")),
                  ],
                  onChanged: (value) =>
                      setState(() => targetWeight = value ?? 100),
                ),
              ],
            ),
            const SizedBox(height: 4),
            if (required == null)
              const Text("Noch keine Noten für eine Berechnung.")
            else if (required > 1000)
              Text(
                "Mit einer einzelnen Note nicht mehr erreichbar "
                "(nötig wäre ${_format(required)}).",
                style: TextStyle(color: theme.colorScheme.error),
              )
            else if (required <= 100)
              Text(
                "Das Ziel ist auch mit der schlechtesten Note noch sicher.",
                style: const TextStyle(color: Colors.green),
              )
            else
              Text.rich(
                TextSpan(
                  text: "Du brauchst mindestens ",
                  children: [
                    TextSpan(
                      text: _format(required),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const TextSpan(text: ", um den Schnitt zu erreichen."),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, this.color});

  final String label, value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: theme.textTheme.labelSmall),
        Text(
          value,
          style: theme.textTheme.titleMedium?.copyWith(
            color: color,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}
