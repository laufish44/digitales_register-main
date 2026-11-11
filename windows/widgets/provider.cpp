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

// The Windows widgets (Widgets board and lock screen).
//
// Windows starts this program through COM when a widget of ours is shown. It
// reads the snapshot the app writes after every change (widgets.json in the
// app's data folder, the same one the Android widgets get, see
// lib/home_widgets.dart), turns it into Adaptive Cards and hands them to the
// widget host. Everything that depends on the time of day — which lesson is
// on, how long until the holidays — is worked out here, every 20 seconds, so a
// snapshot from the evening is still right the next morning.
//
// Each widget can be customised ("Widget anpassen"); its options are kept in
// the widget's own custom state, so two copies of the same widget can show
// different things.

#include <windows.h>
#include <shlobj.h>

#include <algorithm>
#include <chrono>
#include <fstream>
#include <map>
#include <mutex>
#include <sstream>
#include <string>
#include <thread>
#include <vector>

#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Windows.Data.Json.h>
#include <winrt/Microsoft.Windows.Widgets.h>
#include <winrt/Microsoft.Windows.Widgets.Providers.h>

using namespace winrt;
using namespace winrt::Windows::Data::Json;
using namespace winrt::Microsoft::Windows::Widgets;
using namespace winrt::Microsoft::Windows::Widgets::Providers;
namespace chrono = std::chrono;

// Must match the package manifest (windows/widgets/package/AppxManifest.xml).
static constexpr GUID kProviderClsid = {
    0xfb1e968a, 0x34f7, 0x41d0,
    {0xa7, 0x85, 0xbe, 0x7c, 0x11, 0xc6, 0x33, 0xa9}};

// ---------------------------------------------------------------------------
// Time

struct Now {
  chrono::year_month_day date;
  int minutes;  // since midnight
};

static Now CurrentTime() {
  SYSTEMTIME t;
  GetLocalTime(&t);
  return {chrono::year_month_day{chrono::year{t.wYear},
                                 chrono::month{static_cast<unsigned>(t.wMonth)},
                                 chrono::day{static_cast<unsigned>(t.wDay)}},
          t.wHour * 60 + t.wMinute};
}

static chrono::year_month_day AddDays(chrono::year_month_day d, int days) {
  return chrono::year_month_day{chrono::sys_days{d} + chrono::days{days}};
}

static int DaysBetween(chrono::year_month_day from, chrono::year_month_day to) {
  return static_cast<int>(
      (chrono::sys_days{to} - chrono::sys_days{from}).count());
}

static std::wstring Two(unsigned v) {
  return (v < 10 ? L"0" : L"") + std::to_wstring(v);
}

static std::wstring DayKey(chrono::year_month_day d) {
  return std::to_wstring(static_cast<int>(d.year())) + L"-" +
         Two(static_cast<unsigned>(d.month())) + L"-" +
         Two(static_cast<unsigned>(d.day()));
}

static bool ParseDay(std::wstring const& key, chrono::year_month_day& out) {
  int y = 0, m = 0, d = 0;
  if (swscanf_s(key.c_str(), L"%d-%d-%d", &y, &m, &d) != 3) return false;
  out = chrono::year_month_day{chrono::year{y},
                               chrono::month{static_cast<unsigned>(m)},
                               chrono::day{static_cast<unsigned>(d)}};
  return out.ok();
}

static unsigned WeekdayIndex(chrono::year_month_day d) {
  // 0 = Monday
  return (chrono::weekday{chrono::sys_days{d}}.c_encoding() + 6) % 7;
}

static std::wstring ShortDay(chrono::year_month_day d) {
  static wchar_t const* names[] = {L"Mo", L"Di", L"Mi", L"Do",
                                   L"Fr", L"Sa", L"So"};
  return std::wstring(names[WeekdayIndex(d)]) + L" " +
         std::to_wstring(static_cast<unsigned>(d.day())) + L"." +
         std::to_wstring(static_cast<unsigned>(d.month())) + L".";
}

static std::wstring LongWeekday(chrono::year_month_day d) {
  static wchar_t const* names[] = {L"Montag",  L"Dienstag", L"Mittwoch",
                                   L"Donnerstag", L"Freitag", L"Samstag",
                                   L"Sonntag"};
  return names[WeekdayIndex(d)];
}

static int ParseClock(std::wstring const& s) {
  int h = 0, m = 0;
  if (swscanf_s(s.c_str(), L"%d:%d", &h, &m) != 2) return -1;
  return h * 60 + m;
}

static std::wstring Clock(int minutes) {
  return Two(minutes / 60) + L":" + Two(minutes % 60);
}

/// "23 Min", "1:12 h".
static std::wstring Duration(int minutes) {
  if (minutes < 0) minutes = 0;
  if (minutes < 60) return std::to_wstring(minutes) + L" Min";
  return std::to_wstring(minutes / 60) + L":" + Two(minutes % 60) + L" h";
}

static std::wstring InDays(int days) {
  if (days <= 0) return L"heute";
  if (days == 1) return L"morgen";
  return L"in " + std::to_wstring(days) + L" Tagen";
}

// ---------------------------------------------------------------------------
// The snapshot

static std::wstring SnapshotPath() {
  PWSTR roaming = nullptr;
  std::wstring path;
  if (SUCCEEDED(SHGetKnownFolderPath(FOLDERID_RoamingAppData, 0, nullptr,
                                     &roaming))) {
    path = std::wstring(roaming) +
           L"\\Laurin Feichter\\Digitales Register\\widgets.json";
  }
  CoTaskMemFree(roaming);
  return path;
}

class Snapshot {
 public:
  /// The latest snapshot, read again when the file changed. Null without one.
  JsonObject Get() {
    std::lock_guard lock(mutex_);
    auto const path = SnapshotPath();
    WIN32_FILE_ATTRIBUTE_DATA info{};
    if (path.empty() ||
        !GetFileAttributesExW(path.c_str(), GetFileExInfoStandard, &info)) {
      return nullptr;
    }
    ULARGE_INTEGER stamp{{info.ftLastWriteTime.dwLowDateTime,
                          info.ftLastWriteTime.dwHighDateTime}};
    if (json_ && stamp.QuadPart == stamp_) return json_;
    std::ifstream file(path, std::ios::binary);
    std::stringstream buffer;
    buffer << file.rdbuf();
    JsonObject parsed{nullptr};
    if (JsonObject::TryParse(to_hstring(buffer.str()), parsed)) {
      json_ = parsed;
      stamp_ = stamp.QuadPart;
    }
    return json_;
  }

 private:
  std::mutex mutex_;
  JsonObject json_{nullptr};
  unsigned long long stamp_ = 0;
};

static Snapshot g_snapshot;

static std::wstring Str(JsonObject const& o, wchar_t const* key) {
  if (!o || !o.HasKey(key)) return {};
  auto v = o.GetNamedValue(key);
  if (v.ValueType() == JsonValueType::String) return std::wstring(v.GetString());
  if (v.ValueType() == JsonValueType::Number) {
    return std::to_wstring(static_cast<long long>(v.GetNumber()));
  }
  return {};
}

static bool Bool(JsonObject const& o, wchar_t const* key) {
  if (!o || !o.HasKey(key)) return false;
  auto v = o.GetNamedValue(key);
  return v.ValueType() == JsonValueType::Boolean && v.GetBoolean();
}

static JsonObject Obj(JsonObject const& o, wchar_t const* key) {
  if (!o || !o.HasKey(key)) return nullptr;
  auto v = o.GetNamedValue(key);
  return v.ValueType() == JsonValueType::Object ? v.GetObject() : nullptr;
}

static std::vector<JsonObject> Arr(JsonObject const& o, wchar_t const* key) {
  std::vector<JsonObject> result;
  if (!o || !o.HasKey(key)) return result;
  auto v = o.GetNamedValue(key);
  if (v.ValueType() != JsonValueType::Array) return result;
  for (auto const& item : v.GetArray()) {
    if (item.ValueType() == JsonValueType::Object) {
      result.push_back(item.GetObject());
    }
  }
  return result;
}

struct Lesson {
  std::wstring subject, room, hours;
  int from = -1, to = -1;
};

static std::vector<Lesson> LessonsOn(JsonObject const& snapshot,
                                     chrono::year_month_day day) {
  std::vector<Lesson> result;
  auto const d = Obj(Obj(snapshot, L"days"), DayKey(day).c_str());
  for (auto const& l : Arr(d, L"lessons")) {
    result.push_back({Str(l, L"t"), Str(l, L"r"), Str(l, L"h"),
                      ParseClock(Str(l, L"from")), ParseClock(Str(l, L"to"))});
  }
  return result;
}

static std::wstring ExtraSchoolDay(JsonObject const& snapshot,
                                   chrono::year_month_day day) {
  auto const key = DayKey(day);
  for (auto const& e : Arr(snapshot, L"extraSchoolDays")) {
    if (Str(e, L"d") == key) return Str(e, L"t");
  }
  return {};
}

// ---------------------------------------------------------------------------
// Adaptive Cards

static JsonObject Text(std::wstring const& text, wchar_t const* size = nullptr,
                       bool bold = false, wchar_t const* color = nullptr,
                       bool subtle = false, int maxLines = 0) {
  JsonObject o;
  o.Insert(L"type", JsonValue::CreateStringValue(L"TextBlock"));
  o.Insert(L"text", JsonValue::CreateStringValue(text));
  o.Insert(L"wrap", JsonValue::CreateBooleanValue(true));
  if (size) o.Insert(L"size", JsonValue::CreateStringValue(size));
  if (bold) o.Insert(L"weight", JsonValue::CreateStringValue(L"bolder"));
  if (color) o.Insert(L"color", JsonValue::CreateStringValue(color));
  if (subtle) o.Insert(L"isSubtle", JsonValue::CreateBooleanValue(true));
  if (maxLines > 0) {
    o.Insert(L"maxLines", JsonValue::CreateNumberValue(maxLines));
  }
  return o;
}

static JsonObject Spacing(JsonObject o, wchar_t const* spacing) {
  o.Insert(L"spacing", JsonValue::CreateStringValue(spacing));
  return o;
}

/// A row: a short label on the left, the rest beside it.
static JsonObject Row(std::wstring const& left, std::wstring const& title,
                      std::wstring const& subtitle,
                      wchar_t const* color = nullptr) {
  JsonObject leftColumn;
  leftColumn.Insert(L"type", JsonValue::CreateStringValue(L"Column"));
  leftColumn.Insert(L"width", JsonValue::CreateStringValue(L"auto"));
  JsonArray leftItems;
  leftItems.Append(Text(left, L"small", true, color));
  leftColumn.Insert(L"items", leftItems);

  JsonObject rightColumn;
  rightColumn.Insert(L"type", JsonValue::CreateStringValue(L"Column"));
  rightColumn.Insert(L"width", JsonValue::CreateStringValue(L"stretch"));
  JsonArray rightItems;
  rightItems.Append(Text(title, L"small", false, nullptr, false, 1));
  if (!subtitle.empty()) {
    rightItems.Append(Spacing(Text(subtitle, L"small", false, nullptr, true, 1),
                              L"none"));
  }
  rightColumn.Insert(L"items", rightItems);

  JsonObject set;
  set.Insert(L"type", JsonValue::CreateStringValue(L"ColumnSet"));
  set.Insert(L"spacing", JsonValue::CreateStringValue(L"small"));
  JsonArray columns;
  columns.Append(leftColumn);
  columns.Append(rightColumn);
  set.Insert(L"columns", columns);
  return set;
}

static JsonObject Card(JsonArray const& body) {
  JsonObject card;
  card.Insert(L"type", JsonValue::CreateStringValue(L"AdaptiveCard"));
  card.Insert(L"$schema", JsonValue::CreateStringValue(
                              L"http://adaptivecards.io/schemas/adaptive-card.json"));
  card.Insert(L"version", JsonValue::CreateStringValue(L"1.5"));
  card.Insert(L"body", body);
  return card;
}

// ---------------------------------------------------------------------------
// Options

struct Choice {
  std::wstring value, title;
};

struct Option {
  std::wstring id, label, fallback;
  std::vector<Choice> choices;
};

static std::vector<Option> OptionsOf(std::wstring const& definition) {
  if (definition == L"lesson") {
    return {
        {L"end", L"Schulschluss anzeigen", L"1", {{L"1", L"Ja"}, {L"0", L"Nein"}}},
        {L"next", L"Nächste Stunde anzeigen (mittel)", L"1",
         {{L"1", L"Ja"}, {L"0", L"Nein"}}},
    };
  }
  if (definition == L"exams") {
    return {
        {L"what", L"Was zeigen", L"exam",
         {{L"exam", L"Nur Prüfungen"},
          {L"all", L"Prüfungen und Hausaufgaben"},
          {L"homework", L"Nur Hausaufgaben"}}},
        {L"range", L"Zeitraum", L"30",
         {{L"7", L"7 Tage"}, {L"14", L"14 Tage"}, {L"30", L"30 Tage"},
          {L"60", L"60 Tage"}}},
    };
  }
  if (definition == L"day") {
    return {
        {L"day", L"Tag", L"auto",
         {{L"auto", L"Heute, nach Schulschluss morgen"},
          {L"today", L"Heute"},
          {L"tomorrow", L"Morgen"},
          {L"next", L"Nächster Schultag"}}},
        {L"show", L"Inhalt", L"both",
         {{L"both", L"Einträge und Stunden"},
          {L"entries", L"Nur Einträge"},
          {L"lessons", L"Nur Stunden"}}},
    };
  }
  if (definition == L"countdown") {
    return {
        {L"target", L"Countdown bis", L"holidays",
         {{L"holidays", L"Zu den nächsten Ferien"},
          {L"end", L"Zum Schulende"},
          {L"both", L"Beides"}}},
    };
  }
  if (definition == L"grades") {
    return {
        {L"show", L"Anzeige", L"overall",
         {{L"overall", L"Gesamtschnitt und Trend"},
          {L"weakest", L"Schwächste Fächer"},
          {L"best", L"Beste Fächer"},
          {L"recent", L"Letzte Noten"}}},
    };
  }
  return {};
}

static std::wstring OptionValue(std::wstring const& definition,
                                JsonObject const& state,
                                std::wstring const& id) {
  auto value = Str(state, id.c_str());
  for (auto const& option : OptionsOf(definition)) {
    if (option.id != id) continue;
    for (auto const& choice : option.choices) {
      if (choice.value == value) return value;
    }
    return option.fallback;
  }
  return value;
}

static JsonObject CustomizeCard(std::wstring const& definition,
                                JsonObject const& state) {
  JsonArray body;
  body.Append(Text(L"Widget anpassen", L"medium", true));
  for (auto const& option : OptionsOf(definition)) {
    body.Append(Text(option.label, L"small", true));
    JsonObject input;
    input.Insert(L"type", JsonValue::CreateStringValue(L"Input.ChoiceSet"));
    input.Insert(L"id", JsonValue::CreateStringValue(option.id));
    input.Insert(L"value", JsonValue::CreateStringValue(
                               OptionValue(definition, state, option.id)));
    JsonArray choices;
    for (auto const& choice : option.choices) {
      JsonObject c;
      c.Insert(L"title", JsonValue::CreateStringValue(choice.title));
      c.Insert(L"value", JsonValue::CreateStringValue(choice.value));
      choices.Append(c);
    }
    input.Insert(L"choices", choices);
    body.Append(Spacing(input, L"none"));
  }
  auto card = Card(body);
  JsonArray actions;
  for (auto const& [verb, title] :
       {std::pair{L"save", L"Speichern"}, std::pair{L"cancel", L"Abbrechen"}}) {
    JsonObject action;
    action.Insert(L"type", JsonValue::CreateStringValue(L"Action.Execute"));
    action.Insert(L"verb", JsonValue::CreateStringValue(verb));
    action.Insert(L"title", JsonValue::CreateStringValue(title));
    actions.Append(action);
  }
  card.Insert(L"actions", actions);
  return card;
}

// ---------------------------------------------------------------------------
// The widgets

struct Context {
  JsonObject snapshot;
  JsonObject state;  // the widget's options
  std::wstring definition;
  WidgetSize size;
  Now now;

  bool Small() const { return size == WidgetSize::Small; }
  bool Large() const { return size == WidgetSize::Large; }
  std::wstring Option(wchar_t const* id) const {
    return OptionValue(definition, state, id);
  }
};

/// The next day from [from] on (at most three weeks ahead) with lessons.
static bool NextDayWithLessons(JsonObject const& snapshot,
                               chrono::year_month_day from,
                               chrono::year_month_day& out) {
  for (int i = 0; i < 21; i++) {
    auto day = AddDays(from, i);
    if (!LessonsOn(snapshot, day).empty()) {
      out = day;
      return true;
    }
  }
  return false;
}

static void LessonWidget(Context const& c, JsonArray& body) {
  auto const today = LessonsOn(c.snapshot, c.now.date);
  auto const now = c.now.minutes;
  int lastEnd = -1;
  for (auto const& l : today) lastEnd = std::max(lastEnd, l.to);
  bool const showEnd = c.Option(L"end") == L"1" && lastEnd > now &&
                       !today.empty() && today.front().from <= now;

  for (size_t i = 0; i < today.size(); i++) {
    auto const& l = today[i];
    if (l.from < 0 || now < l.from || now >= l.to) continue;
    // A double lesson counts down to the end of both, unless the break
    // between them is longer than five minutes.
    int end = l.to;
    for (size_t j = i + 1; j < today.size(); j++) {
      if (today[j].subject != l.subject || today[j].from - end > 5) break;
      end = today[j].to;
    }
    body.Append(Text(l.subject, c.Small() ? L"medium" : L"large", true, nullptr,
                     false, 1));
    std::wstring left = L"noch " + Duration(end - now);
    if (end != l.to) left += L" (" + Duration(l.to - now) + L")";
    body.Append(Spacing(Text(left, L"medium", false, L"accent"), L"none"));
    if (!c.Small() && !l.room.empty()) {
      body.Append(Spacing(Text(l.hours + L" Stunde · " + l.room, L"small",
                               false, nullptr, true),
                          L"none"));
    }
    if (!c.Small() && c.Option(L"next") == L"1") {
      for (auto const& n : today) {
        if (n.from >= end) {
          body.Append(Text(L"Danach: " + n.subject + L" um " + Clock(n.from),
                           L"small", false, nullptr, true));
          break;
        }
      }
    }
    if (showEnd && lastEnd != end) {
      body.Append(Text(L"Schulschluss " + Clock(lastEnd) + L" (in " +
                           Duration(lastEnd - now) + L")",
                       L"small", false, nullptr, true));
    }
    return;
  }

  // A break: after a lesson, before the next one.
  for (auto const& n : today) {
    if (n.from > now && today.front().to <= now) {
      body.Append(Text(L"Pause", c.Small() ? L"medium" : L"large", true));
      body.Append(Spacing(Text(L"noch " + Duration(n.from - now) + L" → " +
                                   n.subject,
                               L"medium", false, L"accent", false, 1),
                          L"none"));
      if (showEnd) {
        body.Append(Text(L"Schulschluss " + Clock(lastEnd), L"small", false,
                         nullptr, true));
      }
      return;
    }
  }

  // Before school today.
  if (!today.empty() && now < today.front().from) {
    auto const& first = today.front();
    body.Append(Text(L"Gleich: " + first.subject, L"medium", true, nullptr,
                     false, 1));
    body.Append(Spacing(Text(L"um " + Clock(first.from) + L" (in " +
                                 Duration(first.from - now) + L")",
                             L"small", false, L"accent"),
                        L"none"));
    return;
  }

  body.Append(Text(L"Kein Unterricht", L"medium", true));
  chrono::year_month_day next;
  if (NextDayWithLessons(c.snapshot, AddDays(c.now.date, 1), next)) {
    auto const lessons = LessonsOn(c.snapshot, next);
    auto const& first = lessons.front();
    auto const days = DaysBetween(c.now.date, next);
    std::wstring when = days == 1 ? L"Morgen" : ShortDay(next);
    body.Append(Spacing(
        Text(when + L" " + Clock(first.from) + L" · " + first.subject, L"small",
             false, nullptr, true, 2),
        L"none"));
  }
}

static void ExamsWidget(Context const& c, JsonArray& body) {
  auto const what = c.Option(L"what");
  auto const range = std::stoi(c.Option(L"range"));
  struct Entry {
    chrono::year_month_day date;
    std::wstring title, subtitle, kind;
  };
  std::vector<Entry> entries;
  for (auto const& e : Arr(c.snapshot, L"upcoming")) {
    auto kind = Str(e, L"k");
    if (kind == L"reminder") continue;
    if (what == L"exam" && kind != L"exam") continue;
    if (what == L"homework" && kind != L"homework") continue;
    chrono::year_month_day date;
    if (!ParseDay(Str(e, L"d"), date)) continue;
    auto days = DaysBetween(c.now.date, date);
    if (days < 0 || days > range) continue;
    entries.push_back({date, Str(e, L"t"), Str(e, L"s"), kind});
  }
  std::wstring const heading = what == L"homework" ? L"Hausaufgaben"
                               : what == L"all"     ? L"Anstehend"
                                                    : L"Prüfungen";
  if (entries.empty()) {
    body.Append(Text(heading, L"small", true, nullptr, true));
    body.Append(Text(what == L"homework" ? L"Keine offenen Hausaufgaben"
                                         : L"Nichts in Sicht",
                     L"medium", true));
    return;
  }
  if (c.Small()) {
    auto const& e = entries.front();
    body.Append(Text(InDays(DaysBetween(c.now.date, e.date)), L"small", true,
                     e.kind == L"exam" ? L"attention" : L"accent"));
    body.Append(Spacing(Text(e.title, L"medium", true, nullptr, false, 1),
                        L"none"));
    body.Append(Spacing(Text(e.subtitle, L"small", false, nullptr, true, 1),
                        L"none"));
    if (entries.size() > 1) {
      body.Append(Text(L"+ " + std::to_wstring(entries.size() - 1) + L" weitere",
                       L"small", false, nullptr, true));
    }
    return;
  }
  body.Append(Text(heading + L" (" + std::to_wstring(entries.size()) + L")",
                   L"small", true));
  size_t const max = c.Large() ? 8 : 3;
  for (size_t i = 0; i < entries.size() && i < max; i++) {
    auto const& e = entries[i];
    body.Append(Row(ShortDay(e.date), e.title, e.subtitle,
                    e.kind == L"exam" ? L"attention" : nullptr));
  }
}

static void DayWidget(Context const& c, JsonArray& body) {
  auto const which = c.Option(L"day");
  auto const show = c.Option(L"show");
  auto day = c.now.date;
  std::wstring label = L"Heute";
  auto const todayLessons = LessonsOn(c.snapshot, day);
  int todayEnd = -1;
  for (auto const& l : todayLessons) todayEnd = std::max(todayEnd, l.to);
  bool const afterSchool = todayLessons.empty() || c.now.minutes >= todayEnd;
  if (which == L"tomorrow" || (which == L"auto" && afterSchool)) {
    day = AddDays(day, 1);
    label = L"Morgen";
  } else if (which == L"next") {
    chrono::year_month_day next;
    if (NextDayWithLessons(c.snapshot, AddDays(day, 1), next)) day = next;
    else day = AddDays(day, 1);
    label = DaysBetween(c.now.date, day) == 1 ? L"Morgen" : LongWeekday(day);
  }

  auto const lessons = LessonsOn(c.snapshot, day);
  auto const entries =
      Arr(Obj(Obj(c.snapshot, L"days"), DayKey(day).c_str()), L"entries");
  auto const extra = ExtraSchoolDay(c.snapshot, day);

  body.Append(Text(label + L" · " + ShortDay(day), L"small", true,
                   extra.empty() ? nullptr : L"warning"));
  if (!extra.empty()) {
    body.Append(Spacing(Text(extra + L" – ausnahmsweise Schule", L"small",
                             false, L"warning"),
                        L"none"));
  }

  int tests = 0, homework = 0, reminders = 0;
  for (auto const& e : entries) {
    auto k = Str(e, L"k");
    if (k == L"exam") tests++;
    else if (k == L"homework") homework++;
    else reminders++;
  }
  std::wstring summary;
  auto add = [&](int n, wchar_t const* one, wchar_t const* many) {
    if (n == 0) return;
    if (!summary.empty()) summary += L" · ";
    summary += std::to_wstring(n) + L" " + (n == 1 ? one : many);
  };
  add(static_cast<int>(lessons.size()), L"Stunde", L"Stunden");
  add(tests, L"Test", L"Tests");
  add(homework, L"Hausaufgabe", L"Hausaufgaben");
  add(reminders, L"Erinnerung", L"Erinnerungen");

  if (summary.empty()) {
    auto const weekday = WeekdayIndex(day);
    body.Append(Text(weekday >= 5 && extra.empty() ? L"Wochenende"
                                                   : L"Nichts eingetragen",
                     L"medium", true));
    return;
  }
  if (c.Small()) {
    body.Append(Text(summary, L"medium", true, nullptr, false, 3));
    return;
  }
  body.Append(Spacing(Text(summary, L"small", false, nullptr, true), L"none"));
  size_t rows = 0;
  size_t const max = c.Large() ? 12 : 4;
  if (show != L"lessons") {
    for (auto const& e : entries) {
      if (rows++ >= max) break;
      auto k = Str(e, L"k");
      // A reminder's title is just "Erinnerung"; its text is what matters.
      bool const reminder = k != L"exam" && k != L"homework";
      body.Append(Row(k == L"exam"       ? L"Test"
                      : k == L"homework" ? L"HA"
                                         : L"Notiz",
                      reminder ? Str(e, L"s") : Str(e, L"t"),
                      reminder ? L"" : Str(e, L"s"),
                      k == L"exam" ? L"attention" : nullptr));
    }
  }
  if (show != L"entries") {
    for (auto const& l : lessons) {
      if (rows++ >= max) break;
      body.Append(Row(l.hours, l.subject,
                      (l.from >= 0 ? Clock(l.from) : L"") +
                          (l.room.empty() ? L"" : L" · " + l.room)));
    }
  }
}

static void CountdownWidget(Context const& c, JsonArray& body) {
  auto const target = c.Option(L"target");
  bool shown = false;
  if (target != L"end") {
    JsonObject best{nullptr};
    chrono::year_month_day bestFrom{}, bestTo{};
    for (auto const& h : Arr(c.snapshot, L"holidays")) {
      chrono::year_month_day from, to;
      if (!ParseDay(Str(h, L"from"), from) || !ParseDay(Str(h, L"to"), to)) {
        continue;
      }
      if (DaysBetween(c.now.date, to) < 0) continue;
      if (!best || DaysBetween(from, bestFrom) > 0) {
        best = h;
        bestFrom = from;
        bestTo = to;
      }
    }
    if (best) {
      shown = true;
      auto const days = DaysBetween(c.now.date, bestFrom);
      body.Append(Text(Str(best, L"t"), L"small", true, nullptr, true, 1));
      if (days <= 0) {
        body.Append(Spacing(
            Text(L"Ferien! Noch " +
                     std::to_wstring(DaysBetween(c.now.date, bestTo) + 1) +
                     L" Tage",
                 L"large", true, L"good"),
            L"none"));
      } else {
        body.Append(Spacing(Text(std::to_wstring(days) +
                                     (days == 1 ? L" Tag" : L" Tage"),
                                 L"extraLarge", true, L"accent"),
                            L"none"));
        if (!c.Small()) {
          body.Append(Spacing(Text(L"ab " + ShortDay(bestFrom), L"small",
                                   false, nullptr, true),
                              L"none"));
        }
      }
    }
  }
  if (target != L"holidays") {
    chrono::year_month_day last;
    if (ParseDay(Str(c.snapshot, L"lastSchoolDay"), last) &&
        DaysBetween(c.now.date, last) >= 0) {
      auto const days = DaysBetween(c.now.date, last);
      if (shown) {
        body.Append(Text(L"Schulende in " + std::to_wstring(days) + L" Tagen",
                         L"small", false, nullptr, true));
      } else {
        shown = true;
        body.Append(Text(L"Schulende", L"small", true, nullptr, true));
        body.Append(Spacing(Text(std::to_wstring(days) + L" Tage",
                                 L"extraLarge", true, L"accent"),
                            L"none"));
      }
    }
  }
  if (!shown) body.Append(Text(L"Keine Ferien eingetragen", L"medium", true));
}

static void GradesWidget(Context const& c, JsonArray& body) {
  auto const grades = Obj(c.snapshot, L"grades");
  if (!grades) {
    body.Append(Text(L"Noch keine Noten", L"medium", true));
    return;
  }
  auto const show = c.Option(L"show");
  auto subjects = Arr(grades, L"subjects");  // weakest first
  if (show == L"overall" || c.Small() && show != L"recent") {
    if (show == L"overall" || subjects.empty()) {
      body.Append(Text(L"Gesamtschnitt", L"small", true, nullptr, true));
      body.Append(Spacing(Text(Str(grades, L"overall"), L"extraLarge", true,
                               Bool(grades, L"overallLow") ? L"attention"
                                                           : L"accent"),
                          L"none"));
      auto trend = Str(grades, L"trend");
      if (!trend.empty()) {
        body.Append(Spacing(Text(L"Trend " + trend + L" pro Monat", L"small",
                                 false, nullptr, true),
                            L"none"));
      }
      return;
    }
  }
  if (show == L"recent") {
    auto const recent = Arr(grades, L"recent");
    body.Append(Text(L"Letzte Noten", L"small", true));
    size_t const max = c.Small() ? 2 : c.Large() ? 8 : 4;
    for (size_t i = 0; i < recent.size() && i < max; i++) {
      auto const& g = recent[i];
      body.Append(Row(Str(g, L"v"), Str(g, L"t"), c.Small() ? L"" : Str(g, L"s"),
                      Bool(g, L"low") ? L"attention" : L"good"));
    }
    return;
  }
  if (show == L"best") std::reverse(subjects.begin(), subjects.end());
  body.Append(Text(show == L"best" ? L"Beste Fächer" : L"Schwächste Fächer",
                   L"small", true));
  size_t const max = c.Small() ? 3 : c.Large() ? 10 : 4;
  for (size_t i = 0; i < subjects.size() && i < max; i++) {
    auto const& s = subjects[i];
    body.Append(Row(Str(s, L"v"), Str(s, L"t"), L"",
                    Bool(s, L"low") ? L"attention" : nullptr));
  }
}

static void AbsencesWidget(Context const& c, JsonArray& body) {
  auto const a = Obj(c.snapshot, L"absences");
  if (!a) {
    body.Append(Text(L"Absenzen noch nicht geladen", L"medium", true));
    return;
  }
  body.Append(Text(L"Absenzen", L"small", true, nullptr, true));
  auto const percent = Str(a, L"percent");
  body.Append(Spacing(Text((percent.empty() ? L"–" : percent) + L" %",
                           L"extraLarge", true,
                           Bool(a, L"overLimit") ? L"attention" : L"accent"),
                      L"none"));
  body.Append(Spacing(Text(L"Grenze " + Str(a, L"limit") + L" %", L"small",
                           false, nullptr, true),
                      L"none"));
  if (!c.Small()) {
    auto remaining = Str(a, L"remaining");
    if (!remaining.empty()) {
      body.Append(Text(L"Noch " + remaining + L" Stunden Luft", L"small"));
    }
    auto open = Str(a, L"open");
    if (!open.empty() && open != L"0") {
      body.Append(Text(open + L" noch nicht entschuldigt", L"small", false,
                       L"warning"));
    }
  }
}

static JsonObject Render(std::wstring const& definition, WidgetSize size,
                         JsonObject const& state) {
  JsonArray body;
  auto const snapshot = g_snapshot.Get();
  if (!snapshot) {
    body.Append(Text(L"Digitales Register", L"small", true));
    body.Append(Text(L"Öffne die App einmal, dann erscheinen hier deine Daten.",
                     L"small", false, nullptr, true));
    return Card(body);
  }
  Context c{snapshot, state, definition, size, CurrentTime()};
  if (!Bool(snapshot, L"loggedIn")) {
    body.Append(Text(L"Nicht angemeldet", L"medium", true));
    body.Append(Text(L"Melde dich in der App an.", L"small", false, nullptr,
                     true));
    return Card(body);
  }
  if (definition == L"lesson") LessonWidget(c, body);
  else if (definition == L"exams") ExamsWidget(c, body);
  else if (definition == L"day") DayWidget(c, body);
  else if (definition == L"countdown") CountdownWidget(c, body);
  else if (definition == L"grades") GradesWidget(c, body);
  else if (definition == L"absences") AbsencesWidget(c, body);

  // Data more than three days old: say so, the app has not run since.
  auto const generated = Str(snapshot, L"generated");
  chrono::year_month_day stamp;
  if (generated.size() >= 10 && ParseDay(generated.substr(0, 10), stamp) &&
      DaysBetween(stamp, c.now.date) > 3 && !c.Small()) {
    body.Append(Text(L"Stand " + ShortDay(stamp) + L" – öffne die App",
                     L"small", false, L"warning"));
  }
  return Card(body);
}

// ---------------------------------------------------------------------------
// The provider

struct WidgetState {
  std::wstring definition;
  WidgetSize size = WidgetSize::Medium;
  std::wstring customState;  // JSON with the options
  bool customizing = false;
  std::wstring lastSent;
};

static HANDLE g_exitEvent = nullptr;

struct WidgetProvider
    : implements<WidgetProvider, IWidgetProvider, IWidgetProvider2> {
  WidgetProvider() {
    // Widgets that exist already, from before this process was started.
    try {
      for (auto const& info : WidgetManager::GetDefault().GetWidgetInfos()) {
        auto const context = info.WidgetContext();
        WidgetState state;
        state.definition = context.DefinitionId();
        state.size = context.Size();
        state.customState = info.CustomState();
        std::lock_guard lock(mutex_);
        widgets_[std::wstring(context.Id())] = state;
      }
    } catch (...) {
    }
    instance_ = this;
  }

  static WidgetProvider* instance_;

  void CreateWidget(WidgetContext const& context) {
    {
      std::lock_guard lock(mutex_);
      WidgetState state;
      state.definition = context.DefinitionId();
      state.size = context.Size();
      widgets_[std::wstring(context.Id())] = state;
    }
    Update(std::wstring(context.Id()), true);
  }

  void DeleteWidget(hstring const& widgetId, hstring const&) {
    std::lock_guard lock(mutex_);
    widgets_.erase(std::wstring(widgetId));
  }

  void OnActionInvoked(WidgetActionInvokedArgs const& args) {
    auto const id = std::wstring(args.WidgetContext().Id());
    auto const verb = std::wstring(args.Verb());
    {
      std::lock_guard lock(mutex_);
      auto it = widgets_.find(id);
      if (it == widgets_.end()) return;
      if (verb == L"save") {
        JsonObject data{nullptr};
        if (JsonObject::TryParse(args.Data(), data)) {
          it->second.customState = data.Stringify();
        }
      }
      it->second.customizing = false;
    }
    Update(id, true);
  }

  void OnWidgetContextChanged(WidgetContextChangedArgs const& args) {
    auto const context = args.WidgetContext();
    {
      std::lock_guard lock(mutex_);
      auto it = widgets_.find(std::wstring(context.Id()));
      if (it == widgets_.end()) return;
      it->second.size = context.Size();
    }
    Update(std::wstring(context.Id()), true);
  }

  void Activate(WidgetContext const& context) {
    Update(std::wstring(context.Id()), true);
  }

  void Deactivate(hstring const&) {}

  void OnCustomizationRequested(WidgetCustomizationRequestedArgs const& args) {
    auto const id = std::wstring(args.WidgetContext().Id());
    {
      std::lock_guard lock(mutex_);
      auto it = widgets_.find(id);
      if (it == widgets_.end()) return;
      it->second.customizing = true;
    }
    Update(id, true);
  }

  /// Draws every widget again; sends only what changed.
  void Tick() {
    std::vector<std::wstring> ids;
    {
      std::lock_guard lock(mutex_);
      for (auto const& [id, _] : widgets_) ids.push_back(id);
    }
    for (auto const& id : ids) Update(id, false);
  }

  size_t Count() {
    std::lock_guard lock(mutex_);
    return widgets_.size();
  }

 private:
  void Update(std::wstring const& id, bool force) {
    std::wstring templateJson, customState;
    {
      std::lock_guard lock(mutex_);
      auto it = widgets_.find(id);
      if (it == widgets_.end()) return;
      auto& w = it->second;
      JsonObject state{nullptr};
      if (w.customState.empty() || !JsonObject::TryParse(w.customState, state)) {
        state = JsonObject();
      }
      try {
        templateJson = std::wstring(
            (w.customizing ? CustomizeCard(w.definition, state)
                           : Render(w.definition, w.size, state))
                .Stringify());
      } catch (...) {
        JsonArray body;
        body.Append(Text(L"Fehler beim Anzeigen", L"small", true));
        templateJson = std::wstring(Card(body).Stringify());
      }
      if (!force && templateJson == w.lastSent) return;
      w.lastSent = templateJson;
      customState = w.customState;
    }
    try {
      WidgetUpdateRequestOptions options{hstring(id)};
      options.Template(hstring(templateJson));
      options.Data(L"{}");
      options.CustomState(hstring(customState));
      WidgetManager::GetDefault().UpdateWidget(options);
    } catch (...) {
    }
  }

  std::mutex mutex_;
  std::map<std::wstring, WidgetState> widgets_;
};

WidgetProvider* WidgetProvider::instance_ = nullptr;

struct ProviderFactory : implements<ProviderFactory, IClassFactory> {
  HRESULT __stdcall CreateInstance(::IUnknown* outer, GUID const& iid,
                                   void** result) noexcept final {
    *result = nullptr;
    if (outer) return CLASS_E_NOAGGREGATION;
    try {
      std::lock_guard lock(mutex_);
      if (!provider_) provider_ = make<WidgetProvider>();
      return provider_.as<::IUnknown>()->QueryInterface(iid, result);
    } catch (...) {
      return to_hresult();
    }
  }

  HRESULT __stdcall LockServer(BOOL) noexcept final { return S_OK; }

 private:
  std::mutex mutex_;
  IWidgetProvider provider_{nullptr};
};

/// `dr_widgets.exe --dump <file>`: every widget in every size, with default
/// options, as one JSON file — for checking the cards without the widget host.
static int Dump(std::wstring const& path) {
  JsonObject all;
  for (auto const* definition :
       {L"lesson", L"exams", L"day", L"countdown", L"grades", L"absences"}) {
    for (auto const& [name, size] :
         {std::pair{L"small", WidgetSize::Small},
          std::pair{L"medium", WidgetSize::Medium},
          std::pair{L"large", WidgetSize::Large}}) {
      all.Insert(std::wstring(definition) + L"_" + name,
                 Render(definition, size, JsonObject()));
    }
    all.Insert(std::wstring(definition) + L"_customize",
               CustomizeCard(definition, JsonObject()));
  }
  auto const text = to_string(all.Stringify());
  std::ofstream(path, std::ios::binary) << text;
  return 0;
}

int WINAPI wWinMain(HINSTANCE, HINSTANCE, PWSTR, int) {
  init_apartment();
  if (__argc >= 3 && std::wstring(__wargv[1]) == L"--dump") {
    return Dump(__wargv[2]);
  }
  g_exitEvent = CreateEventW(nullptr, TRUE, FALSE, nullptr);

  auto factory = make<ProviderFactory>();
  DWORD cookie = 0;
  check_hresult(CoRegisterClassObject(kProviderClsid, factory.get(),
                                      CLSCTX_LOCAL_SERVER, REGCLS_MULTIPLEUSE,
                                      &cookie));

  // Redraws every 20 seconds; leaves once there have been no widgets for two
  // minutes (Windows starts us again when it needs us).
  std::thread([] {
    int idle = 0;
    while (WaitForSingleObject(g_exitEvent, 20000) == WAIT_TIMEOUT) {
      auto provider = WidgetProvider::instance_;
      if (provider && provider->Count() > 0) {
        idle = 0;
        provider->Tick();
      } else if (++idle >= 6) {
        SetEvent(g_exitEvent);
      }
    }
  }).detach();

  WaitForSingleObject(g_exitEvent, INFINITE);
  CoRevokeClassObject(cookie);
  return 0;
}
