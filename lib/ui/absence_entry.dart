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

/// Dialogs for announcing an absence in advance and for justifying one that
/// already happened.
library;

import 'package:dr/actions/absences_actions.dart';
import 'package:dr/app_state.dart';
import 'package:dr/data.dart';
import 'package:dr/lesson_times.dart';
import 'package:dr/utc_date_time.dart';
import 'package:flutter/material.dart';

/// How many lessons a day can have when the calendar does not tell us.
const _fallbackMaxHour = 10;

String _formatDate(DateTime date) =>
    "${date.day.toString().padLeft(2, "0")}.${date.month.toString().padLeft(2, "0")}.${date.year}";

/// Asks for a date range and a lesson range, and returns the absence to add.
///
/// [lessonTimes] is only used to label the lessons; a lesson without a known
/// time is still offered, just without one.
///
/// Returns null when the user cancels.
Future<AddFutureAbsencePayload?> showAddFutureAbsenceDialog(
  BuildContext context, {
  int maxHour = _fallbackMaxHour,
  DateTime? initialDate,
  List<LessonTime> lessonTimes = const [],
}) {
  return showDialog<AddFutureAbsencePayload>(
    context: context,
    builder: (context) => _AddFutureAbsenceDialog(
      maxHour: maxHour < 1 ? _fallbackMaxHour : maxHour,
      initialDate: initialDate,
      lessonTimes: lessonTimes,
    ),
  );
}

class _AddFutureAbsenceDialog extends StatefulWidget {
  const _AddFutureAbsenceDialog({
    required this.maxHour,
    this.initialDate,
    this.lessonTimes = const [],
  });

  final int maxHour;
  final DateTime? initialDate;
  final List<LessonTime> lessonTimes;

  @override
  State<_AddFutureAbsenceDialog> createState() =>
      _AddFutureAbsenceDialogState();
}

class _AddFutureAbsenceDialogState extends State<_AddFutureAbsenceDialog> {
  late DateTime startDate;
  late DateTime endDate;
  late int startHour;
  late int endHour;
  final noteController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final today = DateTime.now();
    final initial = widget.initialDate ?? today;
    startDate = DateTime(initial.year, initial.month, initial.day);
    endDate = startDate;
    startHour = 1;
    endHour = widget.maxHour;
  }

  @override
  void dispose() {
    noteController.dispose();
    super.dispose();
  }

  /// The first day that may be picked. Announcing an absence for a day in the
  /// past makes no sense, and the server rejects it.
  DateTime get _firstDate {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  Future<void> _pickStart() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: startDate.isBefore(_firstDate) ? _firstDate : startDate,
      firstDate: _firstDate,
      lastDate: _firstDate.add(const Duration(days: 365)),
      helpText: "Erster Tag",
    );
    if (picked == null) return;
    setState(() {
      startDate = picked;
      if (endDate.isBefore(startDate)) endDate = startDate;
      _clampHours();
    });
  }

  Future<void> _pickEnd() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: endDate.isBefore(startDate) ? startDate : endDate,
      firstDate: startDate,
      lastDate: startDate.add(const Duration(days: 365)),
      helpText: "Letzter Tag",
    );
    if (picked == null) return;
    setState(() {
      endDate = picked;
      _clampHours();
    });
  }

  /// Within a single day the last lesson cannot come before the first one.
  void _clampHours() {
    if (_isSingleDay && endHour < startHour) endHour = startHour;
  }

  bool get _isSingleDay =>
      startDate.year == endDate.year &&
      startDate.month == endDate.month &&
      startDate.day == endDate.day;

  /// "3. Stunde (09:45–10:35)" — knowing the time makes picking the right
  /// lesson a lot less error prone than counting.
  String _hourLabel(int hour) =>
      LessonTimes.label(widget.lessonTimes, hour);

  @override
  Widget build(BuildContext context) {
    final hours = [for (var h = 1; h <= widget.maxHour; h++) h];
    return AlertDialog(
      title: const Text("Krank melden / vorentschuldigen"),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event),
              title: const Text("Von"),
              subtitle: Text(_formatDate(startDate)),
              onTap: _pickStart,
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event_available),
              title: const Text("Bis"),
              subtitle: Text(_formatDate(endDate)),
              onTap: _pickEnd,
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<int>(
              value: startHour,
              isExpanded: true,
              decoration: const InputDecoration(labelText: "Von Stunde"),
              items: [
                for (final h in hours)
                  DropdownMenuItem(value: h, child: Text(_hourLabel(h))),
              ],
              onChanged: (value) => setState(() {
                startHour = value!;
                _clampHours();
              }),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<int>(
              value: endHour,
              isExpanded: true,
              decoration: const InputDecoration(labelText: "Bis Stunde"),
              items: [
                for (final h in hours)
                  if (!_isSingleDay || h >= startHour)
                    DropdownMenuItem(value: h, child: Text(_hourLabel(h))),
              ],
              onChanged: (value) => setState(() => endHour = value!),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: noteController,
              decoration: const InputDecoration(
                labelText: "Anmerkung (optional)",
              ),
              maxLines: 2,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text("Abbrechen"),
        ),
        ElevatedButton(
          onPressed: () {
            final note = noteController.text.trim();
            Navigator.pop(
              context,
              AddFutureAbsencePayload(
                (b) => b
                  ..startDate = UtcDateTime(
                      startDate.year, startDate.month, startDate.day)
                  ..endDate =
                      UtcDateTime(endDate.year, endDate.month, endDate.day)
                  ..startHour = startHour
                  ..endHour = endHour
                  ..note = note.isEmpty ? null : note,
              ),
            );
          },
          child: const Text("Eintragen"),
        ),
      ],
    );
  }
}

/// Asks for a reason and a signature for an absence that already happened.
///
/// [selfDeclarations] are the ready-made reasons the school offers (what the
/// website calls "krank melden"); pass an empty list to hide that part.
Future<JustifyAbsencePayload?> showJustifyAbsenceDialog(
  BuildContext context, {
  required AbsenceGroup group,
  String? initialSignature,
  List<SelfDeclaration> selfDeclarations = const [],
  bool selfDeclarationMandatory = false,
}) {
  return showDialog<JustifyAbsencePayload>(
    context: context,
    builder: (context) => _JustifyAbsenceDialog(
      group: group,
      initialSignature: initialSignature,
      selfDeclarations: selfDeclarations,
      selfDeclarationMandatory: selfDeclarationMandatory,
    ),
  );
}

class _JustifyAbsenceDialog extends StatefulWidget {
  const _JustifyAbsenceDialog({
    required this.group,
    this.initialSignature,
    this.selfDeclarations = const [],
    this.selfDeclarationMandatory = false,
  });

  final AbsenceGroup group;
  final String? initialSignature;
  final List<SelfDeclaration> selfDeclarations;
  final bool selfDeclarationMandatory;

  @override
  State<_JustifyAbsenceDialog> createState() => _JustifyAbsenceDialogState();
}

class _JustifyAbsenceDialogState extends State<_JustifyAbsenceDialog> {
  late final TextEditingController reasonController;
  late final TextEditingController signatureController;
  late final TextEditingController noteController;
  late final TextEditingController declarationInputController;
  SelfDeclaration? declaration;

  @override
  void initState() {
    super.initState();
    reasonController = TextEditingController(text: widget.group.reason ?? "");
    signatureController = TextEditingController(
      text: widget.group.reasonSignature ?? widget.initialSignature ?? "",
    );
    noteController = TextEditingController(text: widget.group.note ?? "");
    declarationInputController = TextEditingController();
  }

  @override
  void dispose() {
    reasonController.dispose();
    signatureController.dispose();
    noteController.dispose();
    declarationInputController.dispose();
    super.dispose();
  }

  /// Picking a ready-made reason fills in the wording the school expects, but
  /// the text stays editable.
  void _selectDeclaration(SelfDeclaration? value) {
    setState(() {
      declaration = value;
      if (value != null && value.text.trim().isNotEmpty) {
        reasonController.text = value.text;
      }
      if (value == null) declarationInputController.clear();
    });
  }

  bool get _needsDeclarationInput =>
      declaration != null && declaration!.inputMandatory;

  bool get _isValid {
    if (reasonController.text.trim().isEmpty) return false;
    if (signatureController.text.trim().isEmpty) return false;
    if (widget.selfDeclarationMandatory &&
        widget.selfDeclarations.isNotEmpty &&
        declaration == null) {
      return false;
    }
    if (_needsDeclarationInput &&
        declarationInputController.text.trim().isEmpty) {
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final dates = widget.group.absences.map((a) => a.date).toList()..sort();
    return AlertDialog(
      title: const Text("Absenz entschuldigen"),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (dates.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  dates.length == 1
                      ? _formatDate(dates.first)
                      : "${_formatDate(dates.first)} – ${_formatDate(dates.last)}",
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
            if (widget.selfDeclarations.isNotEmpty) ...[
              DropdownButtonFormField<SelfDeclaration?>(
                value: declaration,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: widget.selfDeclarationMandatory
                      ? "Selbsterklärung"
                      : "Selbsterklärung (optional)",
                ),
                items: [
                  if (!widget.selfDeclarationMandatory)
                    const DropdownMenuItem<SelfDeclaration?>(
                      child: Text("Eigener Grund"),
                    ),
                  for (final d in widget.selfDeclarations)
                    DropdownMenuItem<SelfDeclaration?>(
                      value: d,
                      child: Text(d.title, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: _selectDeclaration,
              ),
              if (_needsDeclarationInput) ...[
                const SizedBox(height: 8),
                TextField(
                  controller: declarationInputController,
                  decoration: InputDecoration(
                    labelText: declaration!.inputExplain.trim().isEmpty
                        ? "Ergänzung"
                        : declaration!.inputExplain,
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ],
              const SizedBox(height: 8),
            ],
            TextField(
              controller: reasonController,
              autofocus: widget.selfDeclarations.isEmpty,
              decoration: const InputDecoration(
                labelText: "Grund",
                hintText: "z. B. Krankheit",
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: signatureController,
              decoration: const InputDecoration(
                labelText: "Unterschrift",
                hintText: "Vor- und Nachname",
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: noteController,
              decoration: const InputDecoration(
                labelText: "Anmerkung (optional)",
              ),
              maxLines: 2,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text("Abbrechen"),
        ),
        ElevatedButton(
          onPressed: _isValid
              ? () {
                  final note = noteController.text.trim();
                  Navigator.pop(
                    context,
                    JustifyAbsencePayload(
                      (b) => b
                        ..group.replace(widget.group)
                        ..reason = reasonController.text.trim()
                        ..signature = signatureController.text.trim()
                        ..note = note.isEmpty ? null : note
                        ..selfDeclaration = declaration?.toBuilder()
                        ..selfDeclarationInput =
                            declarationInputController.text.trim(),
                    ),
                  );
                }
              : null,
          child: const Text("Speichern"),
        ),
      ],
    );
  }
}
