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

import 'package:deleteable_tile/deleteable_tile.dart';
import 'package:dr/app_state.dart';
import 'package:dr/container/settings_page.dart';
import 'package:dr/ui/autocomplete_options.dart';
import 'package:dr/ui/dialog.dart';
import 'package:dr/ui/donations.dart';
import 'package:dr/background/android_background.dart';
import 'package:dr/fork_info.dart';
import 'package:dr/lesson_times.dart';
import 'package:dr/school_year.dart';
import 'package:dr/theme.dart';
import 'package:dr/ui/network_protocol_page.dart';
import 'package:dr/ui/update_dialog.dart';
import 'package:dr/update/update_service.dart';
import 'package:dr/utc_date_time.dart';
import 'package:dr/util.dart';
import 'package:dr/widgets/widget_catalog.dart';
import 'package:dynamic_theme/dynamic_theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:responsive_scaffold/responsive_scaffold.dart';
import 'package:scroll_to_index/scroll_to_index.dart';
import 'package:url_launcher/url_launcher.dart';

enum _Theme {
  light,
  dark,
  followDevice,
}

String _formatDate(UtcDateTime date) =>
    "${date.day.toString().padLeft(2, "0")}."
    "${date.month.toString().padLeft(2, "0")}.${date.year}";

/// The same calendar day as a local [DateTime], for the date picker.
///
/// `toLocal()` would be wrong here: the app stores dates at midnight UTC, and
/// converting that to a zone behind UTC lands on the day before.
DateTime _asLocalDay(UtcDateTime date) =>
    DateTime(date.year, date.month, date.day);

/// The list of dashboard cards: switch on, configure, reorder.
class _WidgetSettings extends StatelessWidget {
  const _WidgetSettings({required this.configs, required this.onChanged});

  final List<DashboardWidgetConfig> configs;
  final OnSettingChanged<List<DashboardWidgetConfig>> onChanged;

  void _replace(DashboardWidgetConfig updated) {
    onChanged([
      for (final config in configs)
        if (config.type == updated.type) updated else config,
    ]);
  }

  void _move(int oldIndex, int newIndex) {
    final reordered = List.of(configs);
    // ReorderableListView reports the target index as it would be *before* the
    // dragged item is taken out.
    final target = newIndex > oldIndex ? newIndex - 1 : newIndex;
    reordered.insert(target, reordered.removeAt(oldIndex));
    onChanged(reordered);
  }

  @override
  Widget build(BuildContext context) {
    return ReorderableListView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      buildDefaultDragHandles: false,
      onReorder: _move,
      children: [
        for (var index = 0; index < configs.length; index++)
          _WidgetSettingsTile(
            // The type is unique within the list, so it is a stable key even
            // while the order changes.
            key: ValueKey(configs[index].type),
            index: index,
            config: configs[index],
            onChanged: _replace,
          ),
      ],
    );
  }
}

class _WidgetSettingsTile extends StatelessWidget {
  const _WidgetSettingsTile({
    super.key,
    required this.index,
    required this.config,
    required this.onChanged,
  });

  final int index;
  final DashboardWidgetConfig config;
  final void Function(DashboardWidgetConfig) onChanged;

  @override
  Widget build(BuildContext context) {
    final type = dashboardWidgetTypeById(config.type);
    if (type == null) return const SizedBox.shrink();

    return ExpansionTile(
      leading: ReorderableDragStartListener(
        index: index,
        child: const Icon(Icons.drag_handle),
      ),
      title: Text(type.name),
      subtitle: Text(type.description),
      trailing: Switch.adaptive(
        value: config.enabled,
        onChanged: (value) =>
            onChanged(config.rebuild((b) => b..enabled = value)),
      ),
      children: [
        if (type.supports(DashboardWidgetOption.includeExams))
          SwitchListTile.adaptive(
            dense: true,
            title: const Text("Prüfungen und Tests"),
            value: config.includeExams,
            onChanged: (value) =>
                onChanged(config.rebuild((b) => b..includeExams = value)),
          ),
        if (type.supports(DashboardWidgetOption.includeHomework))
          SwitchListTile.adaptive(
            dense: true,
            title: const Text("Hausaufgaben"),
            value: config.includeHomework,
            onChanged: (value) =>
                onChanged(config.rebuild((b) => b..includeHomework = value)),
          ),
        if (type.supports(DashboardWidgetOption.includeLessons))
          SwitchListTile.adaptive(
            dense: true,
            title: const Text("Stundenplan"),
            subtitle: const Text("Lädt zusätzlich die Kalenderwoche"),
            value: config.includeLessons,
            onChanged: (value) =>
                onChanged(config.rebuild((b) => b..includeLessons = value)),
          ),
        if (type.supports(DashboardWidgetOption.daysAhead))
          ListTile(
            dense: true,
            title: Text("Vorschau: ${config.daysAhead} Tage"),
            subtitle: Slider(
              value: config.daysAhead.toDouble(),
              min: 1,
              max: 60,
              divisions: 59,
              label: "${config.daysAhead} Tage",
              onChanged: (value) => onChanged(
                  config.rebuild((b) => b..daysAhead = value.round())),
            ),
          ),
        if (type.supports(DashboardWidgetOption.maxEntries))
          ListTile(
            dense: true,
            title: Text(
              config.maxEntries == 0
                  ? "Alle Einträge zeigen"
                  : "Höchstens ${config.maxEntries} Einträge",
            ),
            subtitle: Slider(
              value: config.maxEntries.toDouble(),
              min: 0,
              max: 15,
              divisions: 15,
              label: config.maxEntries == 0 ? "alle" : "${config.maxEntries}",
              onChanged: (value) => onChanged(
                  config.rebuild((b) => b..maxEntries = value.round())),
            ),
          ),
        if (type.supports(DashboardWidgetOption.compact))
          SwitchListTile.adaptive(
            dense: true,
            title: const Text("Schmal"),
            subtitle: const Text("Ohne die erklärende zweite Zeile"),
            value: config.compact,
            onChanged: (value) =>
                onChanged(config.rebuild((b) => b..compact = value)),
          ),
      ],
    );
  }
}

/// The timetable: when each lesson runs.
///
/// The breaks are drawn as empty space rather than written out — a five minute
/// change of room and a real break look different at a glance, which is the
/// whole point of showing the schedule as a list.
class _LessonTimeSettings extends StatelessWidget {
  const _LessonTimeSettings({
    required this.times,
    required this.fromServer,
    required this.serverTimes,
    required this.onChanged,
    required this.onSetFromServer,
  });

  /// What is stored — the table the user edits.
  final List<LessonTime> times;

  final bool fromServer;

  /// What the calendar reported, for "übernehmen".
  final Map<int, LessonTime> serverTimes;

  final OnSettingChanged<List<LessonTime>> onChanged;
  final OnSettingChanged<bool> onSetFromServer;

  void _replace(LessonTime updated) => onChanged([
        for (final time in times)
          if (time.hour == updated.hour) updated else time,
      ]);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sorted = List.of(times)..sort((a, b) => a.hour.compareTo(b.hour));
    final breaks = LessonTimes.breaksBefore(sorted);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SwitchListTile.adaptive(
          title: const Text("Zeiten aus dem Stundenplan übernehmen"),
          subtitle: Text(
            fromServer
                ? "Die Zeiten aus dem Register haben Vorrang vor der Tabelle"
                : "Aus: es gilt die Tabelle unten. Das Register liefert zwar "
                    "eigene Zeiten mit, die stimmen aber nicht überall",
          ),
          value: fromServer,
          onChanged: onSetFromServer,
        ),
        for (final time in sorted) ...[
          SizedBox(height: LessonTimes.spacingBefore(breaks[time.hour])),
          ListTile(
            dense: true,
            title: Text("${time.hour}. Stunde"),
            subtitle: serverTimes[time.hour] == null ||
                    serverTimes[time.hour] == time
                ? null
                : Text(
                    "Stundenplan: ${serverTimes[time.hour]!.rangeLabel}",
                    style: theme.textTheme.bodySmall,
                  ),
            trailing: Text(
              time.rangeLabel,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            onTap: () async {
              final edited = await _editLessonTime(context, time);
              if (edited != null) _replace(edited);
            },
          ),
        ],
        Row(
          children: [
            Expanded(
              child: TextButton.icon(
                icon: const Icon(Icons.remove),
                label: const Text("Weniger"),
                onPressed: sorted.length <= 1
                    ? null
                    : () => onChanged(sorted.sublist(0, sorted.length - 1)),
              ),
            ),
            Expanded(
              child: TextButton.icon(
                icon: const Icon(Icons.add),
                label: const Text("Stunde"),
                onPressed: sorted.length >= 14
                    ? null
                    : () => onChanged([...sorted, _nextLesson(sorted)]),
              ),
            ),
          ],
        ),
        ListTile(
          dense: true,
          leading: const Icon(Icons.download),
          title: const Text("Aus dem Stundenplan übernehmen"),
          subtitle: Text(
            serverTimes.isEmpty
                ? "Dafür muss der Kalender einmal geladen sein"
                : "${serverTimes.length} Stunden bekannt",
          ),
          enabled: serverTimes.isNotEmpty,
          onTap: serverTimes.isEmpty
              ? null
              : () {
                  // Keep the table's own entries for lessons the calendar has
                  // not seen, so a free lesson does not vanish.
                  final merged = {for (final t in sorted) t.hour: t}
                    ..addAll(serverTimes);
                  onChanged(merged.values.toList());
                },
        ),
        ListTile(
          dense: true,
          leading: const Icon(Icons.restore),
          title: const Text("Voreinstellung wiederherstellen"),
          onTap: () => onChanged(List.of(defaultLessonTimes)),
        ),
      ],
    );
  }

  /// A new lesson right after the last one, same length.
  static LessonTime _nextLesson(List<LessonTime> sorted) {
    final last = sorted.isEmpty ? null : sorted.last;
    final start = last?.endMinutes ?? 8 * 60;
    final length = last?.lengthMinutes ?? 50;
    return LessonTime((b) => b
      ..hour = (last?.hour ?? 0) + 1
      ..startMinutes = start
      ..endMinutes = start + length);
  }
}

/// Asks for the start and end of one lesson.
Future<LessonTime?> _editLessonTime(
    BuildContext context, LessonTime time) async {
  var start = time.startMinutes;
  var end = time.endMinutes;

  Future<int?> pick(BuildContext context, String title, int minutes) async {
    final picked = await showTimePicker(
      context: context,
      helpText: title,
      initialTime:
          TimeOfDay(hour: (minutes ~/ 60) % 24, minute: minutes % 60),
    );
    return picked == null ? null : picked.hour * 60 + picked.minute;
  }

  return showDialog<LessonTime>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text("${time.hour}. Stunde"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text("Beginn"),
              trailing: Text(formatMinutesOfDay(start)),
              onTap: () async {
                final picked = await pick(context, "Beginn", start);
                if (picked == null) return;
                setState(() {
                  start = picked;
                  // Keep the lesson at least a minute long; the reducer would
                  // otherwise drop it.
                  if (end <= start) end = start + time.lengthMinutes;
                });
              },
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text("Ende"),
              trailing: Text(formatMinutesOfDay(end)),
              onTap: () async {
                final picked = await pick(context, "Ende", end);
                if (picked == null || picked <= start) return;
                setState(() => end = picked);
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Abbrechen"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(
              context,
              time.rebuild((b) => b
                ..startMinutes = start
                ..endMinutes = end),
            ),
            child: const Text("Speichern"),
          ),
        ],
      ),
    ),
  );
}

/// Editing the holiday list the countdown uses.
class _HolidaySettings extends StatelessWidget {
  const _HolidaySettings({required this.holidays, required this.onChanged});

  final List<HolidayPeriod> holidays;
  final OnSettingChanged<List<HolidayPeriod>> onChanged;

  @override
  Widget build(BuildContext context) {
    final sorted = List.of(holidays)
      ..sort((a, b) => a.start.compareTo(b.start));
    return ExpansionTile(
      title: const Text("Ferien"),
      subtitle: Text(
        sorted.isEmpty
            ? "Keine eingetragen"
            : "${sorted.length} Zeiträume – bitte einmal prüfen",
      ),
      children: [
        for (final holiday in sorted)
          ListTile(
            dense: true,
            title: Text(holiday.name),
            subtitle: Text(holiday.start == holiday.end
                ? _formatDate(holiday.start)
                : "${_formatDate(holiday.start)} – "
                    "${_formatDate(holiday.end)}"),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: "Entfernen",
              onPressed: () => onChanged(
                  [for (final h in holidays) if (h != holiday) h]),
            ),
            onTap: () async {
              final edited = await _showHolidayDialog(context, holiday);
              if (edited != null) {
                onChanged([
                  for (final h in holidays)
                    if (h == holiday) edited else h,
                ]);
              }
            },
          ),
        ListTile(
          dense: true,
          leading: const Icon(Icons.add),
          title: const Text("Ferien hinzufügen"),
          onTap: () async {
            final added = await _showHolidayDialog(context, null);
            if (added != null) onChanged([...holidays, added]);
          },
        ),
        ListTile(
          dense: true,
          leading: const Icon(Icons.restore),
          title: const Text("Voreinstellung wiederherstellen"),
          subtitle: const Text(
              "Die üblichen Südtiroler Termine – trotzdem nachprüfen"),
          onTap: () => onChanged(List.of(defaultHolidays)),
        ),
      ],
    );
  }
}

/// Asks for a name and a date range; returns null when cancelled.
Future<HolidayPeriod?> _showHolidayDialog(
    BuildContext context, HolidayPeriod? existing) async {
  final controller = TextEditingController(text: existing?.name ?? "");
  var start = existing?.start ?? now;
  var end = existing?.end ?? now;

  return showDialog<HolidayPeriod>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(existing == null ? "Ferien hinzufügen" : "Ferien ändern"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
              autofocus: existing == null,
              decoration: const InputDecoration(
                labelText: "Name",
                hintText: "z. B. Weihnachtsferien",
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text("Von"),
              trailing: Text(_formatDate(start)),
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _asLocalDay(start),
                  firstDate: DateTime(now.year - 1),
                  lastDate: DateTime(now.year + 2),
                );
                if (picked == null) return;
                setState(() {
                  start = UtcDateTime(picked.year, picked.month, picked.day);
                  // Keeping end >= start saves a validation message.
                  if (end.isBefore(start)) end = start;
                });
              },
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text("Bis"),
              trailing: Text(_formatDate(end)),
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _asLocalDay(end),
                  firstDate: _asLocalDay(start),
                  lastDate: DateTime(now.year + 2),
                );
                if (picked == null) return;
                setState(() =>
                    end = UtcDateTime(picked.year, picked.month, picked.day));
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Abbrechen"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(
              context,
              HolidayPeriod((b) => b
                ..name = controller.text.trim().isEmpty
                    ? "Ferien"
                    : controller.text.trim()
                ..start = start
                ..end = end),
            ),
            child: const Text("Speichern"),
          ),
        ],
      ),
    ),
  );
}

Future<int?> _askForWeeklyLessons(BuildContext context, int current) {
  const choices = [0, 20, 25, 28, 30, 32, 34, 36, 40];
  return showDialog<int>(
    context: context,
    builder: (context) => SimpleDialog(
      title: const Text("Stunden pro Woche"),
      children: [
        for (final value in choices)
          RadioListTile<int>(
            value: value,
            groupValue: current,
            title: Text(value == 0
                ? "Automatisch aus dem Stundenplan"
                : "$value Stunden"),
            onChanged: (picked) => Navigator.pop(context, picked),
          ),
      ],
    ),
  );
}

/// A small colour circle so the presets can be told apart at a glance.
class _ThemeSwatch extends StatelessWidget {
  const _ThemeSwatch({required this.preset});

  final AppThemePreset preset;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: preset.previewColor,
        shape: BoxShape.circle,
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
    );
  }
}

/// The intervals offered in the settings, in seconds.
const _intervalChoices = [15, 30, 60, 120, 300, 600, 1800, 3600];

String _formatInterval(int seconds) {
  if (seconds < 60) return "Alle $seconds Sekunden";
  final minutes = seconds ~/ 60;
  if (minutes == 1) return "Jede Minute";
  if (minutes < 60) return "Alle $minutes Minuten";
  return "Jede Stunde";
}

/// A one-line text prompt, used for the server addresses.
Future<String?> showTextInputDialog(
  BuildContext context, {
  required String title,
  required String initialValue,
  String? hint,
  String? helper,
  TextInputType? keyboardType,
}) {
  final controller = TextEditingController(text: initialValue);
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: controller,
            autofocus: true,
            keyboardType: keyboardType,
            autocorrect: false,
            decoration: InputDecoration(hintText: hint),
            onSubmitted: (value) => Navigator.pop(context, value),
          ),
          if (helper != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                helper,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text("Abbrechen"),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, ""),
          child: const Text("Leeren"),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, controller.text),
          child: const Text("Speichern"),
        ),
      ],
    ),
  );
}

Future<int?> _askForInterval(BuildContext context, int current) {
  return showDialog<int>(
    context: context,
    builder: (context) => SimpleDialog(
      title: const Text("Wie oft soll geprüft werden?"),
      children: [
        for (final seconds in _intervalChoices)
          RadioListTile<int>(
            value: seconds,
            groupValue: current,
            title: Text(_formatInterval(seconds)),
            onChanged: (value) => Navigator.pop(context, value),
          ),
        const Padding(
          padding: EdgeInsets.fromLTRB(24, 8, 24, 8),
          child: Text(
            "Kurze Intervalle verbrauchen mehr Akku und Datenvolumen.",
            style: TextStyle(fontSize: 12),
          ),
        ),
      ],
    ),
  );
}

class SettingsPageWidget extends StatefulWidget {
  final OnSettingChanged<bool> onSetNoPassSaving;
  final OnSettingChanged<bool> onSetNoDataSaving;
  final OnSettingChanged<bool> onSetAskWhenDelete;
  final OnSettingChanged<bool> onSetDeleteDataOnLogout;
  final OnSettingChanged<bool> onSetShowCalendarEditNicksBar;
  final OnSettingChanged<bool> onSetShowGradesDiagram;
  final OnSettingChanged<bool> onSetShowAllSubjectsAverage;
  final OnSettingChanged<bool> onSetDashboardMarkNewOrChangedEntries;
  final OnSettingChanged<bool> onSetDashboardDeduplicateEntries;
  final OnSettingChanged<bool> onSetDarkMode;
  final OnSettingChanged<bool> onSetFollowDeviceDarkMode;
  final OnSettingChanged<bool> onSetPlatformOverride;
  final OnSettingChanged<bool> onSetDashboardColorBorders;
  final OnSettingChanged<bool> onSetCalenderColorBackground;
  final OnSettingChanged<bool> onSetDashboardColorTestsInRed;
  final OnSettingChanged<MapEntry<String, SubjectTheme>> onSetSubjectTheme;
  final OnSettingChanged<Map<String, String>> onSetSubjectNicks;
  final OnSettingChanged<List<String>> onSetIgnoreForGradesAverage;
  final OnSettingChanged<bool> onSetNotificationsEnabled;
  final OnSettingChanged<int> onSetNotificationInterval;
  final OnSettingChanged<bool> onSetBackgroundServiceEnabled;
  final OnSettingChanged<bool> onSetShowGradeTrends;
  final OnSettingChanged<bool> onSetAbsenceWarningEnabled;
  final OnSettingChanged<int> onSetAbsenceWarningThreshold;
  final OnSettingChanged<bool> onSetPrefetchAttachments;
  final OnSettingChanged<bool> onSetAbsenceEntryEnabled;
  final OnSettingChanged<bool> onSetMessageComposeEnabled;
  final OnSettingChanged<bool> onSetMarkAbsencesInCalendar;
  final OnSettingChanged<String> onSetThemePreset;
  final OnSettingChanged<bool> onSetUpdateCheckEnabled;
  final OnSettingChanged<String> onSetUpdateReleaseUrl;
  final OnSettingChanged<List<DashboardWidgetConfig>> onSetDashboardWidgets;
  final OnSettingChanged<List<HolidayPeriod>> onSetHolidays;
  final OnSettingChanged<UtcDateTime?> onSetLastSchoolDay;
  final OnSettingChanged<bool> onSetShowSchoolYearCountdown;
  final OnSettingChanged<int> onSetWeeklyLessons;
  final OnSettingChanged<bool> onSetShowAbsenceBudget;
  final OnSettingChanged<List<LessonTime>> onSetLessonTimes;
  final OnSettingChanged<bool> onSetLessonTimesFromServer;
  final VoidCallback onShowProfile;
  final SettingsViewModel vm;

  const SettingsPageWidget({
    super.key,
    required this.onSetNoPassSaving,
    required this.onSetNoDataSaving,
    required this.onSetAskWhenDelete,
    required this.onSetDeleteDataOnLogout,
    required this.onSetShowCalendarEditNicksBar,
    required this.onSetShowGradesDiagram,
    required this.onSetShowAllSubjectsAverage,
    required this.onSetDashboardMarkNewOrChangedEntries,
    required this.onSetDashboardDeduplicateEntries,
    required this.onSetDarkMode,
    required this.onSetSubjectNicks,
    required this.vm,
    required this.onSetPlatformOverride,
    required this.onSetFollowDeviceDarkMode,
    required this.onShowProfile,
    required this.onSetIgnoreForGradesAverage,
    required this.onSetDashboardColorBorders,
    required this.onSetCalenderColorBackground,
    required this.onSetSubjectTheme,
    required this.onSetDashboardColorTestsInRed,
    required this.onSetNotificationsEnabled,
    required this.onSetNotificationInterval,
    required this.onSetBackgroundServiceEnabled,
    required this.onSetShowGradeTrends,
    required this.onSetAbsenceWarningEnabled,
    required this.onSetAbsenceWarningThreshold,
    required this.onSetPrefetchAttachments,
    required this.onSetAbsenceEntryEnabled,
    required this.onSetMessageComposeEnabled,
    required this.onSetMarkAbsencesInCalendar,
    required this.onSetThemePreset,
    required this.onSetUpdateCheckEnabled,
    required this.onSetUpdateReleaseUrl,
    required this.onSetDashboardWidgets,
    required this.onSetHolidays,
    required this.onSetLastSchoolDay,
    required this.onSetShowSchoolYearCountdown,
    required this.onSetWeeklyLessons,
    required this.onSetShowAbsenceBudget,
    required this.onSetLessonTimes,
    required this.onSetLessonTimesFromServer,
  });

  @override
  _SettingsPageWidgetState createState() => _SettingsPageWidgetState();
}

class _SettingsPageWidgetState extends State<SettingsPageWidget> {
  final controller = AutoScrollController(suggestedRowHeight: 250);

  List<String> get subjectsWithoutNick => widget.vm.allSubjects
      .where((element) => !widget.vm.subjectNicks.keys.contains(element))
      .toList();
  List<String> get notYetIgnoredForAverageSubjects => widget.vm.allSubjects
      .where((element) => !widget.vm.ignoreForGradesAverage.contains(element))
      .toList();

  @override
  void initState() {
    if (widget.vm.showSubjectNicks) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await controller.scrollToIndex(4,
            preferPosition: AutoScrollPosition.begin);
        if (!mounted) return;
        final newValue =
            await showEditSubjectNick(context, "", "", subjectsWithoutNick);
        if (newValue != null) {
          widget.onSetSubjectNicks(
            Map.fromEntries(
                widget.vm.subjectNicks.entries.toList()..insert(0, newValue)),
          );
        }
      });
    }
    if (widget.vm.showGradesSettings) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        controller.scrollToIndex(3, preferPosition: AutoScrollPosition.begin);
      });
    }
    super.initState();
  }

  Future<void> _checkForUpdates(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(content: Text("Suche nach Updates …")),
    );
    final info = await const UpdateService()
        .check(baseUrl: widget.vm.updateReleaseUrl);
    if (!context.mounted) return;
    if (info == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text("Du hast bereits die neueste Version.")),
      );
      return;
    }
    await showUpdateDialog(context, info);
  }

  void _selectTheme(_Theme? theme) {
    setState(() {
      switch (theme!) {
        case _Theme.light:
          widget.onSetFollowDeviceDarkMode(false);
          widget.onSetDarkMode(false);
          break;
        case _Theme.dark:
          widget.onSetFollowDeviceDarkMode(false);
          widget.onSetDarkMode(true);
          break;
        case _Theme.followDevice:
          widget.onSetFollowDeviceDarkMode(true);
          break;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.vm.showSubjectNicks) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await controller.scrollToIndex(4,
            preferPosition: AutoScrollPosition.begin);
      });
    }
    final currentTheme = DynamicTheme.of(context)!.followDevice
        ? _Theme.followDevice
        : DynamicTheme.of(context)!.customBrightness == Brightness.dark
            ? _Theme.dark
            : _Theme.light;
    return Scaffold(
      appBar: const ResponsiveAppBar(
        title: Text("Einstellungen"),
      ),
      body: ListView(
        controller: controller,
        children: <Widget>[
          if (!widget.vm.demoMode) ...[
            const SizedBox(height: 8),
            ListTile(
              title: Text(
                "Profil",
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: widget.onShowProfile,
            ),
            const Divider(),
          ],
          AutoScrollTag(
            controller: controller,
            index: 0,
            key: const ObjectKey(0),
            child: ListTile(
              title: Text(
                "Anmeldung",
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
          ),
          SwitchListTile.adaptive(
            title: const Text("Angemeldet bleiben"),
            subtitle: const Text("Deine Zugangsdaten werden lokal gespeichert"),
            onChanged: (bool value) {
              widget.onSetNoPassSaving(!value);
            },
            value: !widget.vm.noPassSaving,
          ),
          SwitchListTile.adaptive(
            title: const Text("Daten lokal speichern"),
            subtitle: const Text('Sehen, wann etwas eingetragen wurde'),
            onChanged: (bool value) {
              widget.onSetNoDataSaving(!value);
            },
            value: !widget.vm.noDataSaving,
          ),
          SwitchListTile.adaptive(
            title: const Text("Daten beim Ausloggen löschen"),
            onChanged: !widget.vm.noPassSaving && !widget.vm.noDataSaving
                ? (bool value) {
                    widget.onSetDeleteDataOnLogout(value);
                  }
                : null,
            value: widget.vm.deleteDataOnLogout,
          ),
          const Divider(),
          AutoScrollTag(
            controller: controller,
            index: 1,
            key: const ObjectKey(1),
            child: ListTile(
              title: Text(
                "Aussehen",
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
          ),
          ListTile(
            title: const Text("Farbschema"),
            subtitle: Text(themePresetById(widget.vm.themePreset).name),
            trailing: _ThemeSwatch(
              preset: themePresetById(widget.vm.themePreset),
            ),
            onTap: () async {
              final picked = await showDialog<String>(
                context: context,
                builder: (context) => SimpleDialog(
                  title: const Text("Farbschema"),
                  children: [
                    for (final preset in appThemePresets)
                      RadioListTile<String>(
                        value: preset.id,
                        groupValue: widget.vm.themePreset,
                        onChanged: (value) => Navigator.pop(context, value),
                        secondary: _ThemeSwatch(preset: preset),
                        title: Text(preset.name),
                        subtitle: Text(preset.description),
                      ),
                  ],
                ),
              );
              if (picked != null) widget.onSetThemePreset(picked);
            },
          ),
          RadioListTile(
            value: _Theme.followDevice,
            groupValue: currentTheme,
            onChanged: _selectTheme,
            title: const Text("Geräte-Theme folgen"),
          ),
          RadioListTile(
            value: _Theme.light,
            groupValue: currentTheme,
            onChanged: _selectTheme,
            title: const Text("Hell"),
          ),
          RadioListTile(
            value: _Theme.dark,
            groupValue: currentTheme,
            onChanged: _selectTheme,
            title: const Text("Dunkel"),
          ),
          const Divider(
            indent: 15,
            endIndent: 15,
            height: 0,
          ),
          ExpansionTile(
            title: const Text("Fächerfarben"),
            children: [
              for (final theme in widget.vm.subjectThemes.entries)
                ListTile(
                  onTap: () async {
                    final Color? color = await showDialog(
                      context: context,
                      builder: (context) => _ColorPicker(
                        initialColor: Color(theme.value.color),
                      ),
                    );
                    if (color != null) {
                      widget.onSetSubjectTheme(
                        MapEntry(
                          theme.key,
                          theme.value.rebuild(
                            (b) => b.color = color.value,
                          ),
                        ),
                      );
                    }
                  },
                  title: Text(theme.key),
                  trailing: Container(
                    width: 50,
                    height: 20,
                    decoration: BoxDecoration(
                      color: Color(theme.value.color),
                      //  border: Border.all(),
                      borderRadius: BorderRadius.circular(5),
                    ),
                  ),
                ),
            ],
          ),
          SwitchListTile.adaptive(
            title: const Text(
              "Hausaufgaben mit diesen Farben umrahmen",
            ),
            value: widget.vm.dashboardColorBorders,
            onChanged: widget.onSetDashboardColorBorders,
          ),
          SwitchListTile.adaptive(
            title: const Text(
              "Stunden im Kalender mit diesen Farben färben",
            ),
            value: widget.vm.calendarColorBackground,
            onChanged: widget.onSetCalenderColorBackground,
          ),
          SwitchListTile.adaptive(
            title: const Text(
              "Tests immer rot umrahmen",
            ),
            value: widget.vm.dashboardColorTestsInRed,
            onChanged: widget.onSetDashboardColorTestsInRed,
          ),
          const Divider(),
          AutoScrollTag(
            controller: controller,
            index: 2,
            key: const ObjectKey(2),
            child: ListTile(
              title: Text(
                "Merkheft",
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
          ),
          SwitchListTile.adaptive(
            title: const Text("Neue oder geänderte Einträge markieren"),
            onChanged: (bool value) {
              widget.onSetDashboardMarkNewOrChangedEntries(value);
            },
            value: widget.vm.dashboardMarkNewOrChangedEntries,
          ),
          SwitchListTile.adaptive(
            title: const Text("Doppelte Einträge ignorieren"),
            onChanged: (bool value) {
              widget.onSetDashboardDeduplicateEntries(value);
            },
            value: widget.vm.dashboardDeduplicateEntries,
          ),
          SwitchListTile.adaptive(
            title: const Text("Beim Löschen von Erinnerungen fragen"),
            onChanged: (bool value) {
              widget.onSetAskWhenDelete(value);
            },
            value: widget.vm.askWhenDelete,
          ),
          const Divider(),
          AutoScrollTag(
            controller: controller,
            index: 3,
            key: const ObjectKey(3),
            child: ListTile(
              title: Text(
                "Noten",
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
          ),
          SwitchListTile.adaptive(
            title: const Text("Noten in einem Diagramm darstellen"),
            onChanged: (bool value) {
              widget.onSetShowGradesDiagram(value);
            },
            value: widget.vm.showGradesDiagram,
          ),
          SwitchListTile.adaptive(
            title: const Text('Durchschnitt aller Fächer anzeigen'),
            onChanged: (bool value) {
              widget.onSetShowAllSubjectsAverage(value);
            },
            value: widget.vm.showAllSubjectsAverage,
          ),
          ListTile(
            title: const Text("Fächer aus dem Notendurchschnitt ausschließen"),
            trailing: IconButton(
              icon: const Icon(Icons.add),
              onPressed: () async {
                final newSubject = await showDialog<String>(
                  context: context,
                  builder: (context) => AddSubject(
                    availableSubjects: notYetIgnoredForAverageSubjects,
                  ),
                );
                if (newSubject != null) {
                  widget.onSetIgnoreForGradesAverage(
                      widget.vm.ignoreForGradesAverage..add(newSubject));
                }
              },
            ),
          ),
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 250),
            crossFadeState: widget.vm.ignoreForGradesAverage.isEmpty
                ? CrossFadeState.showFirst
                : CrossFadeState.showSecond,
            firstChild: const Padding(
              padding: EdgeInsets.only(left: 16),
              child: ListTile(
                title: Text(
                  "Kein Fach ausgeschlossen",
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            ),
            secondChild: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final subject in widget.vm.ignoreForGradesAverage)
                  Deleteable(
                    // don't show an animation if this is the only item
                    // in that case, the AnimatedCrossFade will do a different animation
                    showExitAnimation:
                        widget.vm.ignoreForGradesAverage.length != 1,
                    showEntryAnimation:
                        widget.vm.ignoreForGradesAverage.length != 1,
                    key: ValueKey(subject),
                    builder: (context, delete) => Padding(
                      padding: const EdgeInsets.only(left: 16),
                      child: ListTile(
                        title: Text(subject),
                        trailing: IconButton(
                          icon: const Icon(
                            Icons.close,
                          ),
                          onPressed: () async {
                            await delete();
                            widget.onSetIgnoreForGradesAverage(
                              widget.vm.ignoreForGradesAverage..remove(subject),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const Divider(),
          AutoScrollTag(
            controller: controller,
            index: 4,
            key: const ObjectKey(4),
            child: ListTile(
              title: Text(
                "Kalender",
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
          ),
          ExpansionTile(
            initiallyExpanded: widget.vm.showSubjectNicks,
            title: const Text("Fächerkürzel"),
            children: List.generate(
              widget.vm.subjectNicks.length + 1,
              (i) {
                if (i == 0) {
                  return ListTile(
                    trailing: IconButton(
                      icon: const Icon(Icons.add),
                      onPressed: () async {
                        final newValue = await showEditSubjectNick(
                          context,
                          "",
                          "",
                          subjectsWithoutNick,
                        );
                        if (newValue != null) {
                          widget.onSetSubjectNicks(
                            Map.fromEntries(
                                widget.vm.subjectNicks.entries.toList()
                                  ..insert(0, newValue)),
                          );
                        }
                      },
                    ),
                  );
                }
                i -= 1;
                final key = widget.vm.subjectNicks.entries.toList()[i].key;
                final value = widget.vm.subjectNicks[key];
                return Deleteable(
                  key: ValueKey(key),
                  builder: (context, delete) => ListTile(
                    title: Text(key),
                    subtitle: Text(value!),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        IconButton(
                          icon: const Icon(Icons.delete),
                          onPressed: () async {
                            await delete();
                            widget.onSetSubjectNicks(
                              Map.of(widget.vm.subjectNicks)..remove(key),
                            );
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.edit),
                          onPressed: () async {
                            final newValue = await showEditSubjectNick(
                              context,
                              key,
                              value,
                              subjectsWithoutNick..add(key),
                            );
                            if (newValue != null) {
                              widget.onSetSubjectNicks(
                                Map.fromEntries(
                                  List.of(widget.vm.subjectNicks.entries)
                                    ..[i] = newValue,
                                ),
                              );
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          SwitchListTile.adaptive(
            title: const Text("Hinweis zum Bearbeiten von Kürzeln"),
            subtitle: const Text(
                "Wird angezeigt, wenn für ein Fach kein Kürzel vorhanden ist"),
            onChanged: (bool value) {
              widget.onSetShowCalendarEditNicksBar(value);
            },
            value: widget.vm.showCalendarEditNicksBar,
          ),
          const Divider(),
          ListTile(
            title: Text(
              "Benachrichtigungen",
              style: Theme.of(context).textTheme.headlineSmall,
            ),
          ),
          SwitchListTile.adaptive(
            title: const Text("Benachrichtigungen anzeigen"),
            subtitle: const Text(
                "Melden, sobald es etwas Neues im Register gibt"),
            onChanged: widget.onSetNotificationsEnabled,
            value: widget.vm.notificationsEnabled,
          ),
          ListTile(
            enabled: widget.vm.notificationsEnabled,
            title: const Text("Prüfintervall"),
            subtitle: Text(
              _formatInterval(widget.vm.notificationIntervalSeconds),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: widget.vm.notificationsEnabled
                ? () async {
                    final seconds = await _askForInterval(
                      context,
                      widget.vm.notificationIntervalSeconds,
                    );
                    if (seconds != null) {
                      widget.onSetNotificationInterval(seconds);
                    }
                  }
                : null,
          ),
          if (Platform.isWindows)
            SwitchListTile.adaptive(
              title: const Text("Im Hintergrund weiter prüfen"),
              subtitle: const Text(
                "Startet mit Windows und benachrichtigt dich auch, "
                "wenn die App geschlossen ist",
              ),
              onChanged: widget.vm.notificationsEnabled
                  ? widget.onSetBackgroundServiceEnabled
                  : null,
              value: widget.vm.backgroundServiceEnabled,
            ),
          if (AndroidBackgroundCheck.isSupported)
            SwitchListTile.adaptive(
              title: const Text("Im Hintergrund weiter prüfen"),
              subtitle: Text(
                "Android schaut dann etwa alle "
                "${androidCheckInterval.inMinutes} Minuten selbst nach – "
                "auch wenn die App geschlossen ist. Es wird nichts an einen "
                "fremden Server gesendet.",
              ),
              onChanged: widget.vm.notificationsEnabled
                  ? widget.onSetBackgroundServiceEnabled
                  : null,
              value: widget.vm.backgroundServiceEnabled,
            ),
          const Divider(),
          ListTile(
            title: Text(
              "Widgets",
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            subtitle: const Text(
                "Die Karten über den Hausaufgaben – an- und ausschalten, "
                "einstellen und sortieren"),
          ),
          _WidgetSettings(
            configs: widget.vm.dashboardWidgets,
            onChanged: widget.onSetDashboardWidgets,
          ),
          const Divider(),
          ListTile(
            title: Text(
              "Schuljahr",
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            subtitle: const Text(
                "Das Register kennt die Ferien nicht – hier eintragen"),
          ),
          SwitchListTile.adaptive(
            title: const Text("Countdown in der Seitenleiste"),
            subtitle:
                const Text("Bis zu den nächsten Ferien und bis zum Schulende"),
            onChanged: widget.onSetShowSchoolYearCountdown,
            value: widget.vm.showSchoolYearCountdown,
          ),
          ListTile(
            title: const Text("Letzter Schultag"),
            subtitle: Text(
              widget.vm.lastSchoolDay == null
                  ? "Nicht eingetragen"
                  : _formatDate(widget.vm.lastSchoolDay!),
            ),
            trailing: const Icon(Icons.edit_calendar),
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate:
                    _asLocalDay(widget.vm.lastSchoolDay ?? defaultLastSchoolDay),
                firstDate: DateTime(now.year - 1),
                lastDate: DateTime(now.year + 2),
                helpText: "Letzter Schultag",
              );
              if (picked != null) {
                widget.onSetLastSchoolDay(
                    UtcDateTime(picked.year, picked.month, picked.day));
              }
            },
          ),
          _HolidaySettings(
            holidays: widget.vm.holidays,
            onChanged: widget.onSetHolidays,
          ),
          const Divider(),
          ListTile(
            title: Text(
              "Stundenzeiten",
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            subtitle: const Text(
                "Wann die Stunden beginnen und enden – die Abstände zeigen "
                "die Pausen"),
          ),
          _LessonTimeSettings(
            times: widget.vm.lessonTimes,
            fromServer: widget.vm.lessonTimesFromServer,
            serverTimes: widget.vm.serverLessonTimes,
            onChanged: widget.onSetLessonTimes,
            onSetFromServer: widget.onSetLessonTimesFromServer,
          ),
          const Divider(),
          ListTile(
            title: Text(
              "Auswertungen & Extras",
              style: Theme.of(context).textTheme.headlineSmall,
            ),
          ),
          SwitchListTile.adaptive(
            title: const Text("Notenauswertung"),
            subtitle: const Text(
                "Trend, Streuung und „Was brauche ich noch?“ bei den Noten"),
            onChanged: widget.onSetShowGradeTrends,
            value: widget.vm.showGradeTrends,
          ),
          SwitchListTile.adaptive(
            title: const Text("Absenzen-Warnung"),
            subtitle: Text(
              "Warnen ab ${widget.vm.absenceWarningThreshold} % versäumten Stunden",
            ),
            onChanged: widget.onSetAbsenceWarningEnabled,
            value: widget.vm.absenceWarningEnabled,
          ),
          if (widget.vm.absenceWarningEnabled)
            ListTile(
              title: const Text("Warnschwelle"),
              subtitle: Slider(
                value: widget.vm.absenceWarningThreshold.toDouble(),
                min: 5,
                max: 50,
                divisions: 45,
                label: "${widget.vm.absenceWarningThreshold} %",
                onChanged: (value) =>
                    widget.onSetAbsenceWarningThreshold(value.round()),
              ),
            ),
          SwitchListTile.adaptive(
            title: const Text("Absenz-Budget"),
            subtitle: Text(
              "Auf der Absenzenseite zeigen, wie viele Stunden bis zur Grenze "
              "von ${widget.vm.absenceWarningThreshold} % noch bleiben",
            ),
            onChanged: widget.onSetShowAbsenceBudget,
            value: widget.vm.showAbsenceBudget,
          ),
          if (widget.vm.showAbsenceBudget)
            ListTile(
              title: const Text("Stunden pro Woche"),
              subtitle: Text(
                widget.vm.weeklyLessons == 0
                    ? "Wird aus dem Stundenplan ermittelt"
                    : "${widget.vm.weeklyLessons} Stunden – für die Umrechnung "
                        "in Wochen",
              ),
              trailing: const Icon(Icons.edit),
              onTap: () async {
                final value = await _askForWeeklyLessons(
                    context, widget.vm.weeklyLessons);
                if (value != null) widget.onSetWeeklyLessons(value);
              },
            ),
          SwitchListTile.adaptive(
            title: const Text("Anhänge im Voraus laden"),
            subtitle: const Text(
                "Lädt Anhänge automatisch herunter, damit sie offline verfügbar sind"),
            onChanged: widget.onSetPrefetchAttachments,
            value: widget.vm.prefetchAttachments,
          ),
          SwitchListTile.adaptive(
            title: const Text("Absenzen eintragen"),
            subtitle: const Text(
                "Vorentschuldigen und Entschuldigungen aus der App senden"),
            onChanged: widget.onSetAbsenceEntryEnabled,
            value: widget.vm.absenceEntryEnabled,
          ),
          SwitchListTile.adaptive(
            title: const Text("Absenzen im Kalender markieren"),
            subtitle: const Text(
                "Vorentschuldigte und vergangene Absenzen farbig hervorheben"),
            onChanged: widget.onSetMarkAbsencesInCalendar,
            value: widget.vm.markAbsencesInCalendar,
          ),
          SwitchListTile.adaptive(
            title: const Text("Mitteilungen schreiben"),
            subtitle:
                const Text("Neue Mitteilungen direkt aus der App senden"),
            onChanged: widget.onSetMessageComposeEnabled,
            value: widget.vm.messageComposeEnabled,
          ),
          const Divider(),
          ListTile(
            title: Text(
              "Updates",
              style: Theme.of(context).textTheme.headlineSmall,
            ),
          ),
          SwitchListTile.adaptive(
            title: const Text("Nach Updates suchen"),
            subtitle: const Text(
                "Beim Start prüfen, ob eine neuere Version bereitsteht"),
            onChanged: widget.onSetUpdateCheckEnabled,
            value: widget.vm.updateCheckEnabled,
          ),
          ListTile(
            enabled: widget.vm.updateCheckEnabled,
            title: const Text("Quelle der Releases"),
            subtitle: Text(
              widget.vm.updateReleaseUrl.isEmpty
                  ? "Nicht eingerichtet"
                  : UpdateService.gitHubApiUri(widget.vm.updateReleaseUrl) !=
                          null
                      ? "${widget.vm.updateReleaseUrl} (GitHub-Releases)"
                      : widget.vm.updateReleaseUrl,
            ),
            trailing: const Icon(Icons.edit),
            onTap: widget.vm.updateCheckEnabled
                ? () async {
                    final value = await showTextInputDialog(
                      context,
                      title: "Quelle der Releases",
                      hint: "https://github.com/benutzer/repo",
                      helper: "Bei einer GitHub-Adresse wird das neueste "
                          "Release gelesen und die passende Datei (.exe unter "
                          "Windows, .apk unter Android) heruntergeladen. "
                          "Jede andere Adresse wird als latest.json gelesen.",
                      initialValue: widget.vm.updateReleaseUrl,
                      keyboardType: TextInputType.url,
                    );
                    if (value != null) widget.onSetUpdateReleaseUrl(value);
                  }
                : null,
          ),
          ListTile(
            enabled: widget.vm.updateReleaseUrl.isNotEmpty,
            leading: const Icon(Icons.system_update),
            title: const Text("Jetzt nach Updates suchen"),
            subtitle: Text("Installiert: $appVersion"),
            onTap: widget.vm.updateReleaseUrl.isEmpty
                ? null
                : () => _checkForUpdates(context),
          ),
          const Divider(),
          AutoScrollTag(
            controller: controller,
            index: 5,
            key: const ObjectKey(5),
            child: ListTile(
              title: Text(
                "Erweitert",
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
          ),
          if (Platform.isAndroid)
            SwitchListTile.adaptive(
              title: const Text("iOS Mode"),
              subtitle: const Text(
                  "Imitiere das Aussehen einer iOS-App (ein bisschen)"),
              onChanged: (bool value) {
                widget.onSetPlatformOverride(value);
              },
              value: DynamicTheme.of(context)!.platformOverride,
            ),
          ListTile(
            title: const Text("Netzwerkprotokoll"),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (context) {
                    return NetworkProtocolPage();
                  },
                ),
              );
            },
          ),
          if (!Platform.isMacOS)
            ListTile(
              leading: const Icon(Icons.monetization_on),
              title: const Text(
                "Unterstütze uns jetzt!",
              ),
              onTap: () {
                Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (context) => Donate()));
              },
            ),
          ListTile(
            leading: const Icon(Icons.feedback),
            title: const Text("Feedback geben"),
            trailing: const Icon(Icons.open_in_new),
            onTap: () async {
              await launchUrl(
                Uri.parse(
                  "https://docs.google.com/forms/d/e/1FAIpQLSeRYFLq346UH6sMzKicMHwE8KhtnTm4KBv_yho5b0GSrRsluA/viewform?usp=sf_link&entry.1362624919=${Uri.encodeQueryComponent(appVersion)}",
                ),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.code),
            trailing: const Icon(Icons.open_in_new),
            title: const Text("Zum Quellcode"),
            subtitle: Text(
              hasOwnSource
                  ? "Der Quellcode dieser Version"
                  : "Das ursprüngliche Projekt",
            ),
            onTap: () => launchUrl(Uri.parse(sourceUrl)),
          ),
          AboutListTile(
            icon: const Icon(Icons.info_outline),
            applicationIcon: SizedBox(
              width: 100,
              child: Image.asset("assets/transparent.png"),
            ),
            applicationLegalese: forkLegalese,
            applicationName: forkDisplayName,
            applicationVersion: appVersion,
            aboutBoxChildren: [
              const Text("Ein Client für das Digitale Register."),
              const SizedBox(height: 8),
              const Text(
                "Diese Version ist ein eigenständiger Fork, gepflegt von "
                "$forkAuthor — ohne Verbindung zum ursprünglichen Projekt und "
                "nicht von dessen Autoren unterstützt.",
              ),
              const SizedBox(height: 8),
              Text.rich(
                TextSpan(children: [
                  const TextSpan(text: "Entwickelt von "),
                  TextSpan(
                    text: "Michael Debertol",
                    style: const TextStyle(color: Colors.blue),
                    recognizer: TapGestureRecognizer()
                      ..onTap = () {
                        launchUrl(
                          Uri.parse("https://blog.debertol.com"),
                          mode: LaunchMode.externalApplication,
                        );
                      },
                  ),
                  const TextSpan(text: " @ "),
                  TextSpan(
                    text: "evvvolution.com",
                    style: const TextStyle(color: Colors.blue),
                    recognizer: TapGestureRecognizer()
                      ..onTap = () {
                        launchUrl(
                          Uri.parse("https://evvvolution.com"),
                          mode: LaunchMode.externalApplication,
                        );
                      },
                  ),
                ]),
              ),
              const SizedBox(
                height: 8,
              ),
              const Text(
                "This is free software, and you are welcome to redistribute it under certain conditions.\n"
                "This program comes with ABSOLUTELY NO WARRANTY.",
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: InkWell(
                  child: const Text(
                    "See the GNU General Public License for more details.",
                    style: TextStyle(color: Colors.blue),
                  ),
                  onTap: () {
                    launchUrl(
                      Uri.parse("https://www.gnu.org/licenses/gpl-3.0.html"),
                      mode: LaunchMode.externalApplication,
                    );
                  },
                ),
              )
            ],
            child: const Text("Über diese App"),
          ),
        ],
      ),
    );
  }

  Future<MapEntry<String, String>?> showEditSubjectNick(BuildContext context,
      String key, String? value, List<String> suggestions) async {
    return showDialog(
      context: context,
      builder: (context) => EditSubjectsNicks(
        subjectName: key,
        subjectNick: value,
        suggestions: suggestions,
      ),
    );
  }
}

class EditSubjectsNicks extends StatefulWidget {
  final String? subjectName;
  final String? subjectNick;
  final List<String>? suggestions;

  const EditSubjectsNicks(
      {super.key, this.subjectName, this.subjectNick, this.suggestions});
  @override
  _EditSubjectsNicksState createState() => _EditSubjectsNicksState();
}

class _EditSubjectsNicksState extends State<EditSubjectsNicks> {
  late TextEditingController nickController;
  late TextEditingController subjectNameController;
  late FocusNode nickFocusNode, nameFocusNode;
  late bool forNewNick;

  @override
  void initState() {
    forNewNick = widget.subjectName!.isEmpty;
    nickController = TextEditingController(text: widget.subjectNick);
    subjectNameController = TextEditingController(text: widget.subjectName)
      ..addListener(
        () {
          setState(() {});
        },
      );
    nickFocusNode = FocusNode();
    nameFocusNode = FocusNode();
    super.initState();
  }

  @override
  void dispose() {
    nickController.dispose();
    subjectNameController.dispose();
    nickFocusNode.dispose();
    nameFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return InfoDialog(
      title: Text("Kürzel ${forNewNick ? "hinzufügen" : "bearbeiten"}"),
      content: Row(
        children: [
          const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text("Fach"),
              SizedBox(
                height: 27,
              ),
              Text("Kürzel"),
            ],
          ),
          const SizedBox(
            width: 16,
          ),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                RawAutocomplete<String>(
                  focusNode: nameFocusNode,
                  textEditingController: subjectNameController,
                  optionsBuilder: (textEditingValue) {
                    return widget.suggestions!.where((suggestion) => suggestion
                        .toLowerCase()
                        .contains(textEditingValue.text.toLowerCase()));
                  },
                  optionsViewBuilder: (context, onSelected, options) {
                    return AutocompleteOptions(
                      displayStringForOption:
                          RawAutocomplete.defaultStringForOption,
                      onSelected: onSelected,
                      options: options,
                      maxOptionsHeight: 200,
                      // We can't use a LayoutBuilder to get the size inside an AlertDialog,
                      // so we hardcode it here.
                      // TODO: Remove once https://github.com/flutter/flutter/issues/78746 is fixed.
                      width: 170,
                    );
                  },
                  fieldViewBuilder: (context, textEditingController, focusNode,
                      onFieldSubmitted) {
                    return TextFormField(
                      controller: textEditingController,
                      focusNode: focusNode,
                      onFieldSubmitted: (String value) {
                        onFieldSubmitted();
                      },
                      autofocus: subjectNameController.text.isEmpty,
                    );
                  },
                  onSelected: (_) {
                    nameFocusNode.unfocus();
                  },
                ),
                TextField(
                  controller: nickController,
                  textCapitalization: TextCapitalization.sentences,
                  onChanged: (_) => setState(() {}),
                  focusNode: nickFocusNode,
                  onSubmitted: (_) {
                    if (subjectNameController.text != "" &&
                        nickController.text != "") {
                      Navigator.of(context).pop(
                        MapEntry(
                          subjectNameController.text,
                          nickController.text,
                        ),
                      );
                    }
                  },
                ),
              ],
            ),
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () {
            Navigator.of(context).pop();
          },
          child: const Text("Abbrechen"),
        ),
        ElevatedButton(
          onPressed:
              subjectNameController.text != "" && nickController.text != ""
                  ? () {
                      Navigator.of(context).pop(
                        MapEntry(
                          subjectNameController.text,
                          nickController.text,
                        ),
                      );
                    }
                  : null,
          child: const Text("Fertig"),
        ),
      ],
    );
  }
}

class AddSubject extends StatefulWidget {
  final List<String>? availableSubjects;

  const AddSubject({super.key, this.availableSubjects});
  @override
  _AddSubjectState createState() => _AddSubjectState();
}

class _AddSubjectState extends State<AddSubject> {
  late TextEditingController subjectNameController;
  late FocusNode focusNode;

  @override
  void initState() {
    super.initState();
    focusNode = FocusNode();
    subjectNameController = TextEditingController()
      ..addListener(
        () {
          setState(() {});
        },
      );
  }

  @override
  void dispose() {
    subjectNameController.dispose();
    focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return InfoDialog(
      title: const Text("Fach hinzufügen"),
      content: RawAutocomplete<String>(
        focusNode: focusNode,
        textEditingController: subjectNameController,
        optionsBuilder: (textEditingValue) {
          return widget.availableSubjects!.where(
            (suggestion) => suggestion
                .toLowerCase()
                .contains(textEditingValue.text.toLowerCase()),
          );
        },
        optionsViewBuilder: (context, onSelected, options) {
          return AutocompleteOptions(
            displayStringForOption: RawAutocomplete.defaultStringForOption,
            onSelected: onSelected,
            options: options,
            maxOptionsHeight: 200,
            // We can't use a LayoutBuilder to get the size inside an AlertDialog,
            // so we hardcode it here.
            // TODO: Remove once https://github.com/flutter/flutter/issues/78746 is fixed.
            width: 233,
          );
        },
        fieldViewBuilder:
            (context, textEditingController, focusNode, onFieldSubmitted) {
          return TextFormField(
            controller: textEditingController,
            focusNode: focusNode,
            onFieldSubmitted: (String value) {
              onFieldSubmitted();
            },
            autofocus: subjectNameController.text.isEmpty,
          );
        },
        onSelected: (_) {
          focusNode.unfocus();
        },
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () {
            Navigator.of(context).pop();
          },
          child: const Text("Abbrechen"),
        ),
        ElevatedButton(
          onPressed: subjectNameController.text != ""
              ? () {
                  Navigator.of(context).pop(subjectNameController.text);
                }
              : null,
          child: const Text("Fertig"),
        ),
      ],
    );
  }
}

class _ColorPicker extends StatefulWidget {
  final Color? initialColor;

  const _ColorPicker({this.initialColor});
  @override
  _ColorPickerState createState() => _ColorPickerState();
}

class _ColorPickerState extends State<_ColorPicker> {
  Color? color;
  @override
  void initState() {
    color = widget.initialColor;
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return InfoDialog(
      title: const Text("Farbe auswählen"),
      content: SingleChildScrollView(
        child: MaterialPicker(
          pickerColor: color!,
          onColorChanged: (pickedColor) {
            setState(() {
              color = pickedColor;
            });
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.pop(context);
          },
          child: const Text("Abbrechen"),
        ),
        ElevatedButton(
          onPressed: color != widget.initialColor
              ? () {
                  Navigator.pop(context, color);
                }
              : null,
          child: const Text("Auswählen"),
        ),
      ],
    );
  }
}
