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

import 'package:badges/badges.dart' as badge;
import 'package:built_collection/built_collection.dart';
import 'package:deleteable_tile/deleteable_tile.dart';
import 'package:dr/app_state.dart';
import 'package:dr/container/dashboard_widgets_container.dart';
import 'package:dr/container/days_container.dart';
import 'package:dr/container/homework_filter_container.dart';
import 'package:dr/container/notification_icon_container.dart';
import 'package:dr/container/sidebar_container.dart';
import 'package:dr/data.dart';
import 'package:dr/main.dart';
import 'package:dr/middleware/middleware.dart';
import 'package:dr/reminder_links.dart';
import 'package:dr/ui/animated_linear_progress_indicator.dart';
import 'package:dr/ui/attachment_actions.dart';
import 'package:dr/ui/dialog.dart';
import 'package:dr/ui/last_fetched_overlay.dart';
import 'package:dr/ui/link_text.dart';
import 'package:dr/ui/no_internet.dart';
import 'package:dr/ui/search_page.dart';
import 'package:dr/utc_date_time.dart';
import 'package:dr/util.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:intl/intl.dart';
import 'package:responsive_scaffold/responsive_scaffold.dart';
import 'package:scroll_to_index/scroll_to_index.dart';
import 'package:tuple/tuple.dart';

typedef AddReminderCallback = void Function(Day day, String reminder);
typedef EditReminderCallback = void Function(
    Homework reminder, Day day, String text);
typedef RemoveReminderCallback = void Function(Homework hw, Day day);
typedef ToggleDoneCallback = void Function(Homework hw, bool done);
typedef MarkAsNotNewOrChangedCallback = void Function(Homework hw);
typedef MarkDeletedHomeworkAsSeenCallback = void Function(Day day);

class DaysWidget extends StatefulWidget {
  final DaysViewModel vm;

  final MarkAsNotNewOrChangedCallback markAsSeenCallback;
  final MarkDeletedHomeworkAsSeenCallback markDeletedHomeworkAsSeenCallback;
  final VoidCallback markAllAsSeenCallback;
  final AddReminderCallback addReminderCallback;
  final EditReminderCallback editReminderCallback;
  final RemoveReminderCallback removeReminderCallback;
  final VoidCallback onSwitchFuture;
  final ToggleDoneCallback toggleDoneCallback;
  final VoidCallback setDoNotAskWhenDeleteCallback;
  final VoidCallback refresh;
  final VoidCallback refreshNoInternet;
  final AttachmentCallback onOpenAttachment;
  final AttachmentCallback onSaveAttachmentAs;
  final AttachmentCallback onCopyAttachment;

  const DaysWidget({
    super.key,
    required this.vm,
    required this.markAsSeenCallback,
    required this.markDeletedHomeworkAsSeenCallback,
    required this.addReminderCallback,
    required this.editReminderCallback,
    required this.removeReminderCallback,
    required this.markAllAsSeenCallback,
    required this.onSwitchFuture,
    required this.toggleDoneCallback,
    required this.setDoNotAskWhenDeleteCallback,
    required this.refresh,
    required this.refreshNoInternet,
    required this.onOpenAttachment,
    required this.onSaveAttachmentAs,
    required this.onCopyAttachment,
  });
  @override
  _DaysWidgetState createState() => _DaysWidgetState();
}

class _DaysWidgetState extends State<DaysWidget> {
  final controller = AutoScrollController(suggestedRowHeight: 100);

  bool _afterFirstFrame = false;

  final List<int> _targets = [];
  final List<int> _focused = [];
  final Map<int, int> _dayStartIndices = {};
  final Map<int, Homework> _homeworkIndexes = {};
  final Map<int, Day> _dayIndexes = {};

  final ValueNotifier<bool> _showScrollUp = ValueNotifier(false);

  void _updateShowScrollUp() {
    if (controller.hasClients) {
      _showScrollUp.value = controller.offset > 250;
    }
  }

  double? _distanceToItem(int item) {
    final ctx = controller.tagMap[item]?.context;
    if (ctx != null) {
      final renderBox = ctx.findRenderObject()! as RenderBox;
      final RenderAbstractViewport viewport =
          RenderAbstractViewport.of(renderBox);
      var offsetToReveal = viewport.getOffsetToReveal(renderBox, 0.5).offset;
      if (offsetToReveal < 0) offsetToReveal = 0;
      final currentOffset = controller.offset;
      return (offsetToReveal - currentOffset).abs();
    }
    return null;
  }

  void _updateReachedHomeworks() {
    for (final target in _targets.toList()) {
      final distance = _distanceToItem(target);
      if (distance != null && distance < 50) {
        _focused.add(target);
        _targets.remove(target);
        controller.highlight(
          target,
          highlightDuration: const Duration(milliseconds: 500),
          cancelExistHighlights: false,
        );
        if (_targets.isEmpty) setState(() {});
      }
    }
    for (final focusedItem in _focused.toList()) {
      final distance = _distanceToItem(focusedItem);
      if (distance == null || distance > 50) {
        _focused.remove(focusedItem);
        if (_dayIndexes.containsKey(focusedItem)) {
          widget.markDeletedHomeworkAsSeenCallback(_dayIndexes[focusedItem]!);
        } else if (_homeworkIndexes.containsKey(focusedItem)) {
          widget.markAsSeenCallback(_homeworkIndexes[focusedItem]!);
        } else {
          assert(
            false,
            "A target index should either be a new/changed homework or a day (deleted homework)",
          );
        }
      }
    }
  }

  void update() {
    _updateShowScrollUp();
    _updateReachedHomeworks();
  }

  void updateValues() {
    _targets.clear();
    _focused.clear();
    var index = 0;
    var dayIndex = 0;
    for (final day in widget.vm.days) {
      _dayStartIndices[dayIndex] = index;
      if (day.deletedHomework.any((h) => h.isChanged)) {
        _targets.add(index);
        _dayIndexes[index] = day;
      }
      index++;
      final links = DayReminderLinks.of(day.homework);
      for (final hw in day.homework) {
        // A linked reminder has no tile of its own to scroll to.
        if ((hw.isNew || hw.isChanged) && !links.isLinked(hw)) {
          _targets.add(index);
        }
        _homeworkIndexes[index] = hw;
        index++;
      }
      dayIndex++;
    }
  }

  @override
  void initState() {
    updateValues();
    controller.addListener(() {
      update();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      update();
      _afterFirstFrame = true;
      setState(() {});
    });
    super.initState();
  }

  @override
  void didUpdateWidget(DaysWidget oldWidget) {
    updateValues();
    update();

    super.didUpdateWidget(oldWidget);
  }

  Widget getItem(
    int n, {
    required bool isLast,
    required bool showLastFetched,
  }) {
    if (n == 0) {
      return DashboardHeader(
        future: widget.vm.future,
        onSwitchFuture: widget.onSwitchFuture,
      );
    }
    if (isLast) {
      return const SizedBox(
        height: 160,
      );
    }
    if (n.isEven) {
      return const Divider(
        height: 16,
      );
    }
    final itemIndex = (n - 1) ~/ 2;
    return DayWidget(
      day: widget.vm.days[itemIndex],
      vm: widget.vm,
      controller: controller,
      index: _dayStartIndices[itemIndex]!,
      addReminderCallback: widget.addReminderCallback,
      editReminderCallback: widget.editReminderCallback,
      removeReminderCallback: widget.removeReminderCallback,
      toggleDoneCallback: widget.toggleDoneCallback,
      setDoNotAskWhenDeleteCallback: widget.setDoNotAskWhenDeleteCallback,
      onOpenAttachment: widget.onOpenAttachment,
      onSaveAttachmentAs: widget.onSaveAttachmentAs,
      onCopyAttachment: widget.onCopyAttachment,
      colorBorders: widget.vm.colorBorders,
      colorTestsInRed: widget.vm.colorTestsInRed,
      subjectThemes: widget.vm.subjectThemes,
      showLastFetched: showLastFetched,
    );
  }

  @override
  Widget build(BuildContext context) {
    final noInternet = widget.vm.noInternet;
    final noEntries = widget.vm.days.isEmpty;
    Widget body;
    if (noEntries) {
      Widget fullScreenBody;
      if (widget.vm.loading) {
        fullScreenBody = const CircularProgressIndicator();
      } else if (noInternet) {
        fullScreenBody = const NoInternet();
      } else {
        fullScreenBody = Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            "Keine Einträge vorhanden",
            style: Theme.of(context).textTheme.headlineMedium,
            textAlign: TextAlign.center,
          ),
        );
      }
      body = Column(
        children: [
          DashboardHeader(
            future: widget.vm.future,
            onSwitchFuture: widget.onSwitchFuture,
          ),
          Expanded(
            child: Center(child: fullScreenBody),
          ),
        ],
      );
    } else {
      UtcDateTime? lastFetched;
      // If not all days were fetched at the same time we want to show a string
      // for each day individually.
      bool daysShouldShowLastFetched = false;
      if (widget.vm.days.first.lastRequested ==
          widget.vm.days.last.lastRequested) {
        lastFetched = widget.vm.days.first.lastRequested;
      } else {
        daysShouldShowLastFetched = true;
      }
      body = LastFetchedOverlay(
        noInternet: widget.vm.noInternet,
        lastFetched: lastFetched,
        child: ListView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          controller: controller,
          // Times two for the divider, minus one because there's no divider after the last item.
          // The first item is the DashboardHeader, the last one a SizedBox (a spacer).
          itemCount: (widget.vm.days.length * 2 - 1) + 2,
          itemBuilder: (context, n) {
            return getItem(
              n,
              isLast: n == (widget.vm.days.length * 2 - 1) + 1,
              showLastFetched:
                  widget.vm.noInternet && daysShouldShowLastFetched,
            );
          },
        ),
      );
      if (!noInternet && !widget.vm.loading) {
        body = RefreshIndicator(
          onRefresh: () async => widget.refresh(),
          child: body,
        );
      }
      body = Stack(
        children: [
          body,
          AnimatedLinearProgressIndicator(show: widget.vm.loading),
        ],
      );
    }
    return ResponsiveScaffold<Pages>(
      key: scaffoldKey,
      homeBody: body,
      onRouteChanged: (route) {
        if (route == Pages.homework) {
          widget.refresh();
        }
      },
      homeFloatingActionButton: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment: MainAxisAlignment.end,
        children: <Widget>[
          ValueListenableBuilder(
            valueListenable: _showScrollUp,
            builder: (context, bool value, child) {
              if (value) {
                return child!;
              } else {
                return const SizedBox();
              }
            },
            child: FloatingActionButton(
              backgroundColor: Theme.of(context).scaffoldBackgroundColor,
              heroTag: null,
              onPressed: () {
                controller.animateTo(
                  0,
                  duration: const Duration(milliseconds: 500),
                  curve: Curves.decelerate,
                );
              },
              mini: true,
              child: Icon(
                Icons.arrow_drop_up,
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.white
                    : Colors.black,
              ),
            ),
          ),
          if (_targets.isNotEmpty || _focused.isNotEmpty)
            FloatingActionButton(
              backgroundColor: Colors.red,
              heroTag: null,
              onPressed: () {
                widget.markAllAsSeenCallback();
              },
              mini: true,
              child: const Icon(Icons.close),
            ),
          if (_targets.isNotEmpty && _afterFirstFrame)
            FloatingActionButton.extended(
              backgroundColor: Colors.red,
              icon: const Icon(Icons.arrow_drop_down),
              label: const Text("Neue Einträge"),
              onPressed: () async {
                await controller.scrollToIndex(
                  _targets.first,
                  preferPosition: AutoScrollPosition.middle,
                );
              },
            ),
        ],
      ),
      homeAppBar: ResponsiveAppBar(
        title: const Text("Register"),
        actions: <Widget>[
          if (widget.vm.noInternet)
            TextButton(
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.onPrimary,
                padding: const EdgeInsets.symmetric(horizontal: 16),
              ),
              onPressed: widget.refreshNoInternet,
              child: const Row(
                children: [
                  Text("Keine Verbindung"),
                  SizedBox(width: 8),
                  Icon(Icons.refresh),
                ],
              ),
            ),
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: "Suchen",
            onPressed: () => Navigator.of(context, rootNavigator: true).push(
              MaterialPageRoute<void>(builder: (_) => const SearchPage()),
            ),
          ),
          if (widget.vm.showNotifications) NotificationIconContainer(),
        ],
      ),
      drawerBuilder: (widgetSelected, goHome, currentSelected, tabletMode) {
        // _widgetSelected is not passed down because routing is done by
        // accessing the ResponsiveScaffoldState via the GlobalKey and calling
        // selectContentWidget on it.
        return SidebarContainer(
          currentSelected: currentSelected,
          goHome: goHome,
          tabletMode: tabletMode,
        );
      },
      homeId: Pages.homework,
      navKey: nestedNavKey,
    );
  }
}

class DashboardHeader extends StatelessWidget {
  final VoidCallback onSwitchFuture;
  final bool future;
  const DashboardHeader({
    super.key,
    required this.future,
    required this.onSwitchFuture,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const DashboardWidgetsContainer(),
        _buildFilterRow(context),
      ],
    );
  }

  Widget _buildFilterRow(BuildContext context) {
    return Stack(
      children: [
        HomeworkFilterContainer(),
        Positioned(
          top: 0,
          bottom: 0,
          left: 0,
          right: 0,
          child: Row(
            children: [
              Expanded(
                child: AbsorbPointer(child: Container()),
              ),
              const SizedBox(
                width: 60,
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 5),
          child: Center(
            child: ElevatedButton(
              onPressed: onSwitchFuture,
              child: Text(
                future ? "Vergangenheit" : "Zukunft",
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class DayWidget extends StatelessWidget {
  final DaysViewModel vm;

  final AddReminderCallback addReminderCallback;
  final EditReminderCallback editReminderCallback;
  final RemoveReminderCallback removeReminderCallback;
  final ToggleDoneCallback toggleDoneCallback;
  final VoidCallback setDoNotAskWhenDeleteCallback;
  final AttachmentCallback onOpenAttachment;
  final AttachmentCallback onSaveAttachmentAs;
  final AttachmentCallback onCopyAttachment;
  final bool colorBorders, colorTestsInRed;
  final BuiltMap<String, SubjectTheme> subjectThemes;

  final Day day;

  final AutoScrollController controller;
  final int index;

  final bool showLastFetched;

  const DayWidget({
    super.key,
    required this.day,
    required this.vm,
    required this.controller,
    required this.index,
    required this.addReminderCallback,
    required this.editReminderCallback,
    required this.removeReminderCallback,
    required this.toggleDoneCallback,
    required this.setDoNotAskWhenDeleteCallback,
    required this.onOpenAttachment,
    required this.onSaveAttachmentAs,
    required this.onCopyAttachment,
    required this.colorBorders,
    required this.subjectThemes,
    required this.colorTestsInRed,
    required this.showLastFetched,
  });

  Future<String?> showEnterReminderDialog(
    BuildContext context, {
    String initial = "",
    String title = "Erinnerung",
  }) async {
    return showDialog(
      context: context,
      builder: (context) {
        String message = initial;
        final controller = TextEditingController(text: initial);
        return StatefulBuilder(builder: (context, setState) {
          final save = message.trim().isEmpty || message == initial
              ? null
              : () => Navigator.pop(context, message);
          return SubmitShortcut(
            onSubmit: save,
            child: InfoDialog(
              title: Text(title),
              content: TextField(
                controller: controller,
                autofocus: true,
                maxLines: null,
                textCapitalization: TextCapitalization.sentences,
                onChanged: (msg) {
                  setState(() => message = msg);
                },
                decoration: InputDecoration(
                  hintText: 'zB. Hausaufgabe',
                  helperText: submitShortcutHint,
                ),
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                  },
                  child: const Text("Abbrechen"),
                ),
                ElevatedButton(
                  onPressed: save,
                  child: const Text(
                    "Speichern",
                  ),
                ),
              ],
            ),
          );
        });
      },
    );
  }

  /// Placeholder that keeps the running index in step; renders nothing.
  Widget _skip(int index) => const SizedBox.shrink();

  /// Ticking an entry ticks the reminders that belong to it as well (#10).
  void _toggle(Homework hw, DayReminderLinks links) {
    final done = !hw.checked;
    toggleDoneCallback(hw, done);
    for (final reminder in links.remindersOf(hw)) {
      if (reminder.checkable && reminder.checked != done) {
        toggleDoneCallback(reminder, done);
      }
    }
  }

  Future<void> _edit(BuildContext context, Homework reminder) async {
    final linkKey = linkKeyIn(reminder.subtitle);
    final text = await showEnterReminderDialog(
      context,
      initial: reminderTextOf(reminder.subtitle),
      title: "Erinnerung bearbeiten",
    );
    if (text == null) return;
    // Keep the link to the entry the reminder belongs to.
    editReminderCallback(
      reminder,
      day,
      linkKey == null ? text.trim() : "${text.trim()} [#$linkKey]",
    );
  }

  Future<void> _addNote(BuildContext context, Homework entry) async {
    final text = await showEnterReminderDialog(
      context,
      title: "Notiz zu ${entry.label ?? entry.title}",
    );
    if (text == null) return;
    addReminderCallback(day, linkedReminderText(text, entry));
  }

  @override
  Widget build(BuildContext context) {
    var i = index;
    final links = DayReminderLinks.of(day.homework);
    return Column(
      children: <Widget>[
        SizedBox(
          height: 48,
          child: Row(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.only(left: 15),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      day.displayName,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    if (showLastFetched)
                      Text(
                        "Zuletzt synchronisiert ${formatTimeAgo(day.lastRequested)}.",
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                  ],
                ),
              ),
              if (day.deletedHomework.isNotEmpty)
                AutoScrollTag(
                  controller: controller,
                  index: index,
                  key: ValueKey(index),
                  highlightColor: Colors.grey.withOpacity(0.5),
                  child: IconButton(
                    icon: badge.Badge(
                      badgeContent: Icon(
                        Icons.delete,
                        size: 15,
                        color: day.deletedHomework.any((h) => h.isChanged)
                            ? Colors.white
                            : null,
                      ),
                      badgeStyle: badge.BadgeStyle(
                        badgeColor: day.deletedHomework.any((h) => h.isChanged)
                            ? Colors.red
                            : Theme.of(context).scaffoldBackgroundColor,
                        padding: EdgeInsets.zero,
                        elevation: 0,
                      ),
                      badgeAnimation: badge.BadgeAnimation.slide(
                        toAnimate: day.deletedHomework.any((h) => h.isChanged),
                      ),
                      position: badge.BadgePosition.topStart(),
                      child: const Icon(Icons.info_outline),
                    ),
                    onPressed: () {
                      showDialog<void>(
                        context: context,
                        builder: (context) {
                          return InfoDialog(
                            title: const Text("Gelöschte Einträge"),
                            content: SingleChildScrollView(
                              child: Column(
                                children: day.deletedHomework
                                    .map(
                                      (i) => ItemWidget(
                                        item: i,
                                        isDeletedView: true,
                                        colorBorder: colorBorders,
                                        subjectThemes: subjectThemes,
                                        colorTestsInRed: colorTestsInRed,
                                        askWhenDelete: vm.askWhenDelete,
                                        noInternet: vm.noInternet,
                                      ),
                                    )
                                    .toList(),
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              const Spacer(),
              if (vm.showAddReminder)
                IconButton(
                  icon: const Icon(Icons.add),
                  onPressed: vm.noInternet
                      ? null
                      : () async {
                          final message =
                              await showEnterReminderDialog(context);
                          if (message != null) {
                            addReminderCallback(day, message);
                          }
                        },
                ),
            ],
          ),
        ),
        for (final hw in day.homework)
          // Linked reminders show inside their entry; the index still counts
          // them so it matches the one the scroll targets were made with.
          if (links.isLinked(hw))
            _skip(++i)
          else
            ItemWidget(
              item: hw,
              toggleDone: () => _toggle(hw, links),
              removeThis: () => removeReminderCallback(hw, day),
              setDoNotAskWhenDelete: setDoNotAskWhenDeleteCallback,
              askWhenDelete: vm.askWhenDelete,
              noInternet: vm.noInternet,
              controller: controller,
              index: ++i,
              onOpenAttachment: onOpenAttachment,
              onSaveAttachmentAs: onSaveAttachmentAs,
              onCopyAttachment: onCopyAttachment,
              subjectThemes: subjectThemes,
              colorBorder: colorBorders,
              colorTestsInRed: colorTestsInRed,
              linkedReminders: links.remindersOf(hw),
              onEdit: isReminder(hw) && hw.deleteable && !vm.noInternet
                  ? () => _edit(context, hw)
                  : null,
              onAddNote: !isReminder(hw) &&
                      vm.showAddReminder &&
                      !vm.noInternet &&
                      !hw.deleted
                  ? () => _addNote(context, hw)
                  : null,
              onEditLinked: vm.noInternet ? null : (r) => _edit(context, r),
              onRemoveLinked:
                  vm.noInternet ? null : (r) => removeReminderCallback(r, day),
              onToggleLinked: vm.noInternet
                  ? null
                  : (r) => toggleDoneCallback(r, !r.checked),
            ),
      ],
    );
  }
}

class ItemWidget extends StatelessWidget {
  final Homework item;
  final VoidCallback? removeThis;
  final VoidCallback? toggleDone;
  final VoidCallback? setDoNotAskWhenDelete;
  final bool askWhenDelete,
      isHistory,
      isDeletedView,
      noInternet,
      isCurrent,
      colorBorder,
      colorTestsInRed;
  final AttachmentCallback? onOpenAttachment;
  final AttachmentCallback? onSaveAttachmentAs;
  final AttachmentCallback? onCopyAttachment;
  final BuiltMap<String, SubjectTheme> subjectThemes;

  final AutoScrollController? controller;
  final int? index;

  /// Own reminders that belong to this entry, shown inside its card (#10).
  final List<Homework> linkedReminders;

  /// Edits this reminder (#11). Null for anything that is not one.
  final VoidCallback? onEdit;

  /// Adds a reminder that belongs to this entry.
  final VoidCallback? onAddNote;

  final void Function(Homework reminder)? onEditLinked;
  final void Function(Homework reminder)? onRemoveLinked;
  final void Function(Homework reminder)? onToggleLinked;

  const ItemWidget({
    super.key,
    required this.item,
    this.removeThis,
    this.toggleDone,
    required this.askWhenDelete,
    this.setDoNotAskWhenDelete,
    this.isHistory = false,
    this.controller,
    this.index,
    this.isDeletedView = false,
    required this.noInternet,
    this.isCurrent = true,
    this.onOpenAttachment,
    this.onSaveAttachmentAs,
    this.onCopyAttachment,
    required this.colorBorder,
    required this.subjectThemes,
    required this.colorTestsInRed,
    this.linkedReminders = const [],
    this.onEdit,
    this.onAddNote,
    this.onEditLinked,
    this.onRemoveLinked,
    this.onToggleLinked,
  });

  /// The text to show: a reminder without the tag that links it.
  String get _subtitle =>
      isReminder(item) ? reminderTextOf(item.subtitle) : item.subtitle;

  Future<Tuple2<bool, bool>> _showConfirmDelete(BuildContext context) async {
    var ask = true;
    final delete = await showDialog<bool>(
      context: context,
      builder: (context) {
        return InfoDialog(
          content: StatefulBuilder(
            builder: (context, setState) => SwitchListTile.adaptive(
              title: const Text("Nie fragen"),
              onChanged: (bool value) {
                setState(() => ask = !value);
              },
              value: !ask,
            ),
          ),
          title: const Text("Erinnerung löschen?"),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Abbrechen"),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text(
                "Löschen",
              ),
            )
          ],
        );
      },
    );
    return Tuple2(delete ?? false, ask);
  }

  void _showHistory(BuildContext context) {
    // if we are in the deleted view, show the history for the previous item
    final historyItem = isDeletedView ? item.previousVersion : item;
    showDialog<void>(
      context: context,
      builder: (context) {
        return InfoDialog(
          title: Text(historyItem!.title),
          content: SingleChildScrollView(
            child: Column(
              children: [
                Text(formatChanged(historyItem)),
                if (historyItem.previousVersion != null)
                  ExpansionTile(
                    title: const Text("Versionen"),
                    children: <Widget>[
                      ItemWidget(
                        item: historyItem,
                        isHistory: true,
                        colorBorder: colorBorder,
                        subjectThemes: subjectThemes,
                        colorTestsInRed: colorTestsInRed,
                        askWhenDelete: askWhenDelete,
                        noInternet: noInternet,
                      ),
                    ],
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Tuple2<Color, double> _getBorderConfig() {
    if (item.warning && colorTestsInRed) {
      return const Tuple2(Colors.red, 1.5);
    }
    if (colorBorder &&
        item.label != null &&
        subjectThemes.containsKey(item.label!)) {
      return Tuple2(Color(subjectThemes[item.label]!.color), 1.5);
    }
    if (item.type == HomeworkType.grade || item.checked) {
      return const Tuple2(Colors.green, 0);
    }
    return const Tuple2(Colors.grey, 0);
  }

  /// The buttons on the right of the card, one row each.
  ///
  /// Editing and adding a note go into the first row, left of what is already
  /// there, so they make the card a little wider instead of taller.
  List<Widget> _sideButtons(BuildContext context) {
    final rows = <Widget>[
      if (!isHistory && item.label != null)
        IconButton(
          icon: (isDeletedView
                      ? item.previousVersion!.previousVersion
                      : item.previousVersion) !=
                  null
              ? badge.Badge(
                  badgeContent: const Icon(Icons.edit, size: 15),
                  badgeStyle: badge.BadgeStyle(
                    padding: EdgeInsets.zero,
                    badgeColor: isDeletedView
                        ? Theme.of(context).dialogTheme.backgroundColor ??
                            Theme.of(context).scaffoldBackgroundColor
                        : Theme.of(context).scaffoldBackgroundColor,
                    elevation: 0,
                  ),
                  badgeAnimation:
                      const badge.BadgeAnimation.slide(toAnimate: false),
                  child: const Icon(
                    Icons.info_outline,
                  ),
                )
              : const Icon(
                  Icons.info_outline,
                ),
          onPressed: () {
            _showHistory(context);
          },
        ),
      if (item.type == HomeworkType.grade)
        Padding(
          padding: const EdgeInsets.only(right: 8.0),
          child: Text(
            item.gradeFormatted!,
            style: const TextStyle(color: Colors.green, fontSize: 30),
          ),
        )
      else if (!isHistory && !isDeletedView && item.checkable)
        Checkbox(
          visualDensity: VisualDensity.standard,
          activeColor: Colors.green,
          value: item.checked,
          onChanged: noInternet
              ? null
              : (done) {
                  toggleDone!();
                },
        ),
    ];
    final actions = <Widget>[
      if (!isHistory && !isDeletedView && onEdit != null)
        IconButton(
          icon: const Icon(Icons.edit_outlined),
          tooltip: "Bearbeiten",
          onPressed: onEdit,
        ),
      if (!isHistory && !isDeletedView && onAddNote != null)
        IconButton(
          icon: const Icon(Icons.note_add_outlined),
          tooltip: "Eigene Notiz dazu",
          onPressed: onAddNote,
        ),
    ];
    if (actions.isEmpty) return rows;
    return [
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [...actions, ...rows.take(1)],
      ),
      ...rows.skip(1),
    ];
  }

  @override
  Widget build(BuildContext context) {
    Widget child = Deleteable(
      // this is a new entry or a reminder the user has just entered
      showEntryAnimation:
          now.difference(item.firstSeen) < const Duration(seconds: 1),
      builder: (context, delete) => Card(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        elevation: 0,
        shape: RoundedRectangleBorder(
          side: BorderSide(
            color: _getBorderConfig().item1,
            width: _getBorderConfig().item2,
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        color: Colors.transparent,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Column(
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(
                        left: 8,
                        top: 8,
                        bottom: 6,
                      ),
                      child: Column(
                        children: <Widget>[
                          if (item.label != null)
                            Stack(
                              clipBehavior: Clip.none,
                              children: <Widget>[
                                Center(
                                  child: Text(
                                    item.label!,
                                    textAlign: TextAlign.center,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if ((!isHistory &&
                                        (item.isNew || item.isChanged)) ||
                                    (isHistory && isCurrent))
                                  Positioned(
                                    right: 0,
                                    child: badge.Badge(
                                      badgeStyle: badge.BadgeStyle(
                                        shape: badge.BadgeShape.square,
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      badgeContent: Text(
                                        isHistory && isCurrent
                                            ? "aktuell"
                                            : item.isNew
                                                ? "neu"
                                                : item.deleted
                                                    ? "gelöscht"
                                                    : "geändert",
                                        style: const TextStyle(
                                            color: Colors.white),
                                      ),
                                    ),
                                  )
                              ],
                            ),
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(item.title),
                            subtitle: _subtitle.isNullOrEmpty
                                ? null
                                : LinkText(_subtitle),
                            leading:
                                !isHistory && !isDeletedView && item.deleteable
                                    ? IconButton(
                                        icon: const Icon(Icons.close),
                                        onPressed: noInternet
                                            ? null
                                            : () async {
                                                if (askWhenDelete) {
                                                  final confirmationResult =
                                                      await _showConfirmDelete(
                                                          context);
                                                  final shouldDelete =
                                                      confirmationResult.item1;
                                                  final ask =
                                                      confirmationResult.item2;
                                                  if (shouldDelete == true) {
                                                    if (!ask) {
                                                      setDoNotAskWhenDelete!();
                                                    }
                                                    await delete();
                                                    removeThis!();
                                                  }
                                                } else {
                                                  await delete();
                                                  removeThis!();
                                                }
                                              },
                                        padding: EdgeInsets.zero)
                                    : null,
                          ),
                        ],
                      ),
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: _sideButtons(context),
                  ),
                ],
              ),
              if (!isHistory && !isDeletedView && linkedReminders.isNotEmpty)
                _LinkedReminders(
                  reminders: linkedReminders,
                  // Ticked together with the entry when it can be ticked.
                  ownCheckboxes: !item.checkable,
                  onEdit: onEditLinked,
                  onRemove: onRemoveLinked,
                  onToggle: onToggleLinked,
                ),
              if (isHistory || isDeletedView) ...[
                const Divider(height: 0),
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Text(
                    formatChanged(item),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
              if (item.gradeGroupSubmissions?.isNotEmpty == true) ...[
                const Divider(),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Text("Anhang",
                        style: Theme.of(context).textTheme.titleMedium),
                  ),
                ),
                for (final attachment in item.gradeGroupSubmissions!)
                  AttachmentWidget(
                    ggs: attachment,
                    noInternet: noInternet,
                    openCallback: onOpenAttachment!,
                    saveAsCallback: onSaveAttachmentAs,
                    copyCallback: onCopyAttachment,
                  )
              ]
            ],
          ),
        ),
      ),
    );
    if (!isHistory && !isDeletedView) {
      child = AutoScrollTag(
        index: index!,
        key: ValueKey(index),
        controller: controller!,
        highlightColor: Colors.grey.withOpacity(0.5),
        child: child,
      );
    }
    return Column(
      key: ValueKey(item.id),
      children: <Widget>[
        child,
        if (isHistory && item.previousVersion != null)
          ItemWidget(
            isHistory: true,
            isCurrent: false,
            item: item.previousVersion!,
            colorBorder: colorBorder,
            subjectThemes: subjectThemes,
            colorTestsInRed: colorTestsInRed,
            askWhenDelete: askWhenDelete,
            noInternet: noInternet,
          ),
      ],
    );
  }
}

String formatChanged(Homework hw) {
  String date;
  if (hw.lastNotSeen == null) {
    date =
        "Vor ${DateFormat("EEEE, dd.MM, HH:mm,", "de").format(hw.firstSeen)}";
  } else if (toDate(hw.firstSeen) == toDate(hw.lastNotSeen!)) {
    date = "Am ${DateFormat("EEEE, dd.MM,", "de").format(hw.firstSeen)}"
        " zwischen ${DateFormat("HH:mm", "de").format(hw.lastNotSeen!)} und ${DateFormat("HH:mm", "de").format(hw.firstSeen)}";
  } else {
    date =
        "Zwischen ${DateFormat("EEEE, dd.MM, HH:mm,", "de").format(hw.lastNotSeen!)} "
        "und ${DateFormat("EEEE, dd.MM, HH:mm,", "de").format(hw.firstSeen)}";
  }
  if (hw.deleted) {
    return "$date gelöscht.";
  } else if (hw.previousVersion == null) {
    return "$date eingetragen.";
  } else if (hw.previousVersion!.deleted) {
    return "$date wiederhergestellt.";
  } else {
    return "$date geändert.";
  }
}

UtcDateTime toDate(UtcDateTime dateTime) {
  return UtcDateTime(dateTime.year, dateTime.month, dateTime.day);
}

class AttachmentWidget extends StatelessWidget {
  final GradeGroupSubmission ggs;
  final AttachmentCallback openCallback;

  /// Optional so the widget keeps working where only opening is wired up.
  final AttachmentCallback? saveAsCallback;
  final AttachmentCallback? copyCallback;
  final bool noInternet;

  const AttachmentWidget(
      {super.key,
      required this.ggs,
      required this.noInternet,
      required this.openCallback,
      this.saveAsCallback,
      this.copyCallback});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Column(
        children: [
          const Divider(
            indent: 16,
            height: 0,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: AttachmentActions(
              name: ggs.originalName,
              enabled: ggs.fileAvailable || !noInternet,
              onOpen: () => openCallback(ggs),
              onSaveAs:
                  saveAsCallback == null ? null : () => saveAsCallback!(ggs),
              onCopy: copyCallback == null ? null : () => copyCallback!(ggs),
            ),
          ),
          AnimatedLinearProgressIndicator(show: ggs.downloading),
        ],
      ),
    );
  }
}

/// The own notes inside an entry's card.
class _LinkedReminders extends StatelessWidget {
  const _LinkedReminders({
    required this.reminders,
    required this.ownCheckboxes,
    this.onEdit,
    this.onRemove,
    this.onToggle,
  });

  final List<Homework> reminders;

  /// Whether each note gets its own checkbox. Not when the entry has one:
  /// then ticking the entry ticks them all.
  final bool ownCheckboxes;
  final void Function(Homework reminder)? onEdit;
  final void Function(Homework reminder)? onRemove;
  final void Function(Homework reminder)? onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        const Divider(height: 1),
        for (final reminder in reminders)
          Padding(
            padding: const EdgeInsets.only(left: 12),
            child: Row(
              children: [
                Icon(
                  Icons.sticky_note_2_outlined,
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: LinkText(
                    reminderTextOf(reminder.subtitle),
                    style: reminder.checked
                        ? const TextStyle(
                            decoration: TextDecoration.lineThrough)
                        : null,
                  ),
                ),
                if (ownCheckboxes && reminder.checkable)
                  Checkbox(
                    activeColor: Colors.green,
                    value: reminder.checked,
                    onChanged:
                        onToggle == null ? null : (_) => onToggle!(reminder),
                  ),
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 20),
                  tooltip: "Bearbeiten",
                  onPressed: onEdit == null ? null : () => onEdit!(reminder),
                ),
                if (reminder.deleteable)
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    tooltip: "Löschen",
                    onPressed:
                        onRemove == null ? null : () => onRemove!(reminder),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
