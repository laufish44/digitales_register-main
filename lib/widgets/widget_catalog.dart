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

/// What kinds of cards the dashboard offers and what each of them can be told.
///
/// Free of Flutter on purpose: `app_state.dart` needs the defaults, and the
/// settings page needs to know which options to offer, without either of them
/// depending on the widget implementations.
library;

/// The options a card can support. Shared across all types so the stored
/// configuration stays one flat record; a type simply ignores what it does not
/// declare here.
enum DashboardWidgetOption {
  includeHomework,
  includeExams,
  includeLessons,
  maxEntries,
  daysAhead,
  compact,
}

class DashboardWidgetType {
  const DashboardWidgetType({
    required this.id,
    required this.name,
    required this.description,
    required this.options,
    this.defaultMaxEntries = 5,
    this.defaultDaysAhead = 14,
    this.defaultIncludeHomework = true,
    this.defaultIncludeExams = true,
    this.defaultIncludeLessons = false,
  });

  /// Stored in the settings; must stay stable.
  final String id;

  final String name;
  final String description;

  /// Which of the options this card actually reads.
  final Set<DashboardWidgetOption> options;

  final int defaultMaxEntries, defaultDaysAhead;
  final bool defaultIncludeHomework, defaultIncludeExams, defaultIncludeLessons;

  bool supports(DashboardWidgetOption option) => options.contains(option);
}

const upcomingWidgetId = "upcoming";
const tomorrowWidgetId = "tomorrow";
const todayWidgetId = "today";
const gradesWidgetId = "grades";
const absencesWidgetId = "absences";
const holidaysWidgetId = "holidays";
const messagesWidgetId = "messages";

const dashboardWidgetTypes = <DashboardWidgetType>[
  DashboardWidgetType(
    id: upcomingWidgetId,
    name: "Demnächst",
    description: "Was in den nächsten Tagen ansteht",
    options: {
      DashboardWidgetOption.includeExams,
      DashboardWidgetOption.includeHomework,
      DashboardWidgetOption.daysAhead,
      DashboardWidgetOption.maxEntries,
      DashboardWidgetOption.compact,
    },
    defaultIncludeHomework: false,
  ),
  DashboardWidgetType(
    id: tomorrowWidgetId,
    name: "Morgen",
    description: "Hausaufgaben, Tests und Stunden von morgen",
    options: {
      DashboardWidgetOption.includeExams,
      DashboardWidgetOption.includeHomework,
      DashboardWidgetOption.includeLessons,
      DashboardWidgetOption.maxEntries,
      DashboardWidgetOption.compact,
    },
  ),
  DashboardWidgetType(
    id: todayWidgetId,
    name: "Heute",
    description: "Was heute noch ansteht",
    options: {
      DashboardWidgetOption.includeExams,
      DashboardWidgetOption.includeHomework,
      DashboardWidgetOption.includeLessons,
      DashboardWidgetOption.maxEntries,
      DashboardWidgetOption.compact,
    },
    defaultIncludeLessons: true,
  ),
  DashboardWidgetType(
    id: gradesWidgetId,
    name: "Noten",
    description: "Schnitt, Trend und die letzten Noten",
    options: {
      DashboardWidgetOption.maxEntries,
      DashboardWidgetOption.compact,
    },
    defaultMaxEntries: 3,
  ),
  DashboardWidgetType(
    id: absencesWidgetId,
    name: "Absenzen",
    description: "Versäumte Stunden und wie viele noch möglich sind",
    options: {DashboardWidgetOption.compact},
  ),
  DashboardWidgetType(
    id: holidaysWidgetId,
    name: "Ferien",
    description: "Countdown bis zu den nächsten Ferien und zum Schulende",
    options: {DashboardWidgetOption.compact},
  ),
  DashboardWidgetType(
    id: messagesWidgetId,
    name: "Mitteilungen",
    description: "Ungelesene Mitteilungen",
    options: {
      DashboardWidgetOption.maxEntries,
      DashboardWidgetOption.compact,
    },
    defaultMaxEntries: 3,
  ),
];

DashboardWidgetType? dashboardWidgetTypeById(String id) {
  for (final type in dashboardWidgetTypes) {
    if (type.id == id) return type;
  }
  return null;
}

/// Which cards a fresh installation starts with.
///
/// Only the two that need no extra request are on by default; the rest are one
/// switch away in the settings.
const defaultEnabledWidgetIds = <String>[upcomingWidgetId, tomorrowWidgetId];
