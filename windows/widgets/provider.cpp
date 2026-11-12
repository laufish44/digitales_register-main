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
// on, how long until the holidays — is worked out here, every 15 seconds, so
// a snapshot from the evening is still right the next morning.
//
// The pictures — progress rings, the calendar sheet, the day's timeline — are
// drawn here with GDI+ and sent along as PNG data URIs: Adaptive Cards have no
// drawing of their own. Text stays in the card, so the host's light or dark
// theme colours it.
//
// Each widget can be customised ("Widget anpassen"); its options are kept in
// the widget's own custom state, so two copies of the same widget can show
// different things.

#include <windows.h>
#include <objidl.h>
#include <shlobj.h>
#include <wincrypt.h>

#include <algorithm>
#include <chrono>
#include <cmath>
#include <fstream>
#include <map>
#include <mutex>
#include <set>
#include <sstream>
#include <string>
#include <thread>
#include <vector>

namespace Gdiplus {
using std::max;
using std::min;
}  // namespace Gdiplus
#include <gdiplus.h>

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
namespace gp = Gdiplus;

// Must match the package manifest (windows/widgets/package/AppxManifest.xml).
static constexpr GUID kProviderClsid = {
    0xfb1e968a, 0x34f7, 0x41d0,
    {0xa7, 0x85, 0xbe, 0x7c, 0x11, 0xc6, 0x33, 0xa9}};

// ---------------------------------------------------------------------------
// Time

struct Now {
  chrono::year_month_day date;
  int minutes;  // since midnight
  int seconds;  // since midnight
};

/// Set by `--dump <file> <YYYY-MM-DDTHH:MM>` to see the cards at another time.
static SYSTEMTIME* g_fakeTime = nullptr;

static Now CurrentTime() {
  SYSTEMTIME t;
  GetLocalTime(&t);
  if (g_fakeTime) t = *g_fakeTime;
  return {chrono::year_month_day{chrono::year{t.wYear},
                                 chrono::month{static_cast<unsigned>(t.wMonth)},
                                 chrono::day{static_cast<unsigned>(t.wDay)}},
          t.wHour * 60 + t.wMinute,
          (t.wHour * 60 + t.wMinute) * 60 + t.wSecond};
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

static wchar_t const* kShortWeekdays[] = {L"Mo", L"Di", L"Mi", L"Do",
                                          L"Fr", L"Sa", L"So"};
static wchar_t const* kMonths[] = {L"JÄN", L"FEB", L"MÄR", L"APR",
                                   L"MAI", L"JUN", L"JUL", L"AUG",
                                   L"SEP", L"OKT", L"NOV", L"DEZ"};

static std::wstring ShortDay(chrono::year_month_day d) {
  return std::wstring(kShortWeekdays[WeekdayIndex(d)]) + L" " +
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

static double ParseNumber(std::wstring s) {
  std::replace(s.begin(), s.end(), L',', L'.');
  return s.empty() ? 0 : _wtof(s.c_str());
}

// ---------------------------------------------------------------------------
// The snapshot

static std::wstring SnapshotPath() {
  // DR_WIDGETS_SNAPSHOT: another snapshot, for drawing the preview pictures
  // from made-up data (see tool/make_widget_assets.ps1).
  wchar_t other[MAX_PATH];
  if (GetEnvironmentVariableW(L"DR_WIDGETS_SNAPSHOT", other, MAX_PATH) > 0) {
    return other;
  }
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

/// Whether [day] has school: a weekday outside the holidays, or an extra
/// school day.
static bool IsSchoolDay(JsonObject const& snapshot,
                        chrono::year_month_day day) {
  if (!ExtraSchoolDay(snapshot, day).empty()) return true;
  if (WeekdayIndex(day) >= 5) return false;
  for (auto const& h : Arr(snapshot, L"holidays")) {
    chrono::year_month_day from, to;
    if (ParseDay(Str(h, L"from"), from) && ParseDay(Str(h, L"to"), to) &&
        DaysBetween(from, day) >= 0 && DaysBetween(day, to) >= 0) {
      return false;
    }
  }
  return true;
}

/// The subject of an entry: "Mathematik · 1. Schularbeit" -> "Mathematik".
static std::wstring EntrySubject(JsonObject const& entry) {
  auto s = Str(entry, L"s");
  auto const dot = s.find(L" · ");
  return dot == std::wstring::npos ? s : s.substr(0, dot);
}

// ---------------------------------------------------------------------------
// Pictures

namespace colors {
constexpr gp::ARGB kBlue = 0xFF3B82F6;
constexpr gp::ARGB kGreen = 0xFF22C55E;
constexpr gp::ARGB kOrange = 0xFFF59E0B;
constexpr gp::ARGB kRed = 0xFFEF4444;
// Grey with some transparency: readable on light and dark backgrounds.
constexpr gp::ARGB kTrack = 0x66808080;
constexpr gp::ARGB kPast = 0x88808080;
}  // namespace colors

static CLSID PngEncoder() {
  UINT count = 0, size = 0;
  gp::GetImageEncodersSize(&count, &size);
  std::vector<BYTE> buffer(size);
  auto* encoders = reinterpret_cast<gp::ImageCodecInfo*>(buffer.data());
  gp::GetImageEncoders(count, size, encoders);
  for (UINT i = 0; i < count; i++) {
    if (wcscmp(encoders[i].MimeType, L"image/png") == 0) {
      return encoders[i].Clsid;
    }
  }
  return CLSID{};
}

static std::wstring ToDataUri(gp::Bitmap& bitmap) {
  static CLSID const png = PngEncoder();
  IStream* stream = nullptr;
  if (FAILED(CreateStreamOnHGlobal(nullptr, TRUE, &stream))) return {};
  std::wstring result;
  if (bitmap.Save(stream, &png, nullptr) == gp::Ok) {
    HGLOBAL memory = nullptr;
    STATSTG stat{};
    if (SUCCEEDED(GetHGlobalFromStream(stream, &memory)) &&
        SUCCEEDED(stream->Stat(&stat, STATFLAG_NONAME))) {
      auto const* bytes = static_cast<BYTE const*>(GlobalLock(memory));
      DWORD const length = stat.cbSize.LowPart;
      DWORD chars = 0;
      CryptBinaryToStringW(bytes, length,
                           CRYPT_STRING_BASE64 | CRYPT_STRING_NOCRLF, nullptr,
                           &chars);
      std::wstring base64(chars, L'\0');
      CryptBinaryToStringW(bytes, length,
                           CRYPT_STRING_BASE64 | CRYPT_STRING_NOCRLF,
                           base64.data(), &chars);
      base64.resize(chars);
      GlobalUnlock(memory);
      result = L"data:image/png;base64," + base64;
    }
  }
  stream->Release();
  return result;
}

/// Pictures are cached by what is on them; a ring only changes every few
/// ticks.
static std::mutex g_imageMutex;
static std::map<std::wstring, std::wstring> g_images;

template <typename Draw>
static std::wstring Picture(std::wstring const& key, int width, int height,
                            Draw draw) {
  std::lock_guard lock(g_imageMutex);
  auto it = g_images.find(key);
  if (it != g_images.end()) return it->second;
  if (g_images.size() > 300) g_images.clear();
  gp::Bitmap bitmap(width, height, PixelFormat32bppARGB);
  {
    gp::Graphics g(&bitmap);
    g.SetSmoothingMode(gp::SmoothingModeAntiAlias);
    g.SetTextRenderingHint(gp::TextRenderingHintAntiAliasGridFit);
    g.Clear(gp::Color(0, 0, 0, 0));
    draw(g);
  }
  auto uri = ToDataUri(bitmap);
  g_images[key] = uri;
  return uri;
}

/// A ring filled to [progress] (0..1) in [color].
static std::wstring RingPicture(double progress, gp::ARGB color) {
  progress = std::clamp(progress, 0.0, 1.0);
  int const steps = static_cast<int>(std::round(progress * 240));
  constexpr int size = 240;
  constexpr float thickness = 22;
  return Picture(L"ring" + std::to_wstring(steps) + L"_" + std::to_wstring(color),
                 size, size, [&](gp::Graphics& g) {
                   float const pad = thickness / 2 + 2;
                   gp::RectF r(pad, pad, size - 2 * pad, size - 2 * pad);
                   gp::Pen track(gp::Color(colors::kTrack), thickness);
                   g.DrawEllipse(&track, r);
                   if (steps > 0) {
                     gp::Pen pen(gp::Color(color), thickness);
                     pen.SetStartCap(gp::LineCapRound);
                     pen.SetEndCap(gp::LineCapRound);
                     g.DrawArc(&pen, r, -90.0f,
                               static_cast<float>(360.0 * steps / 240));
                   }
                 });
}

static void RoundedRect(gp::GraphicsPath& path, float x, float y, float w,
                        float h, float r) {
  path.AddArc(x, y, 2 * r, 2 * r, 180, 90);
  path.AddArc(x + w - 2 * r, y, 2 * r, 2 * r, 270, 90);
  path.AddArc(x + w - 2 * r, y + h - 2 * r, 2 * r, 2 * r, 0, 90);
  path.AddArc(x, y + h - 2 * r, 2 * r, 2 * r, 90, 90);
  path.CloseFigure();
}

/// A tear-off calendar sheet: weekday in the coloured band, the day big.
static std::wstring CalendarSheetPicture(chrono::year_month_day day,
                                         gp::ARGB color) {
  constexpr int w = 200, h = 216;
  auto const key = L"sheet" + DayKey(day) + L"_" + std::to_wstring(color);
  return Picture(key, w, h, [&](gp::Graphics& g) {
    gp::GraphicsPath body;
    RoundedRect(body, 4, 4, w - 8, h - 8, 26);
    gp::SolidBrush white(gp::Color(255, 250, 250, 252));
    g.FillPath(&white, &body);
    gp::Region clip(&body);
    g.SetClip(&clip);
    gp::SolidBrush band{gp::Color(color)};
    g.FillRectangle(&band, 0, 0, w, 62);
    g.ResetClip();

    gp::FontFamily family(L"Segoe UI");
    gp::StringFormat center;
    center.SetAlignment(gp::StringAlignmentCenter);
    center.SetLineAlignment(gp::StringAlignmentCenter);
    gp::Font weekday(&family, 34, gp::FontStyleBold, gp::UnitPixel);
    gp::Font big(&family, 92, gp::FontStyleBold, gp::UnitPixel);
    gp::Font month(&family, 28, gp::FontStyleBold, gp::UnitPixel);
    gp::SolidBrush onBand(gp::Color(255, 255, 255, 255));
    gp::SolidBrush dark(gp::Color(255, 30, 30, 36));
    gp::SolidBrush grey(gp::Color(255, 110, 110, 120));
    g.DrawString(kShortWeekdays[WeekdayIndex(day)], -1, &weekday,
                 gp::RectF(0, 6, w, 56), &center, &onBand);
    g.DrawString(std::to_wstring(static_cast<unsigned>(day.day())).c_str(), -1,
                 &big, gp::RectF(0, 58, w, 112), &center, &dark);
    g.DrawString(kMonths[static_cast<unsigned>(day.month()) - 1], -1, &month,
                 gp::RectF(0, 160, w, 40), &center, &grey);
  });
}

/// The day's lessons as blocks along a line, with a marker at [now] (minutes
/// since midnight, or -1 for another day).
static std::wstring TimelinePicture(std::vector<Lesson> const& lessons,
                                    int now) {
  std::vector<Lesson> timed;
  for (auto const& l : lessons) {
    if (l.from >= 0 && l.to > l.from) timed.push_back(l);
  }
  if (timed.empty()) return {};
  int const start = timed.front().from, end = timed.back().to;
  if (end <= start) return {};
  constexpr int w = 960, h = 72;
  std::wstring key = L"timeline" + std::to_wstring(start) + L"_" +
                     std::to_wstring(end) + L"_" +
                     std::to_wstring(now < 0 ? -1 : now);
  for (auto const& l : timed) key += L"_" + l.hours;
  return Picture(key, w, h, [&](gp::Graphics& g) {
    auto x = [&](int minute) {
      return 6.0f + (w - 12.0f) * (minute - start) / (end - start);
    };
    gp::FontFamily family(L"Segoe UI");
    gp::Font font(&family, 28, gp::FontStyleBold, gp::UnitPixel);
    gp::StringFormat center;
    center.SetAlignment(gp::StringAlignmentCenter);
    center.SetLineAlignment(gp::StringAlignmentCenter);
    gp::SolidBrush white(gp::Color(255, 255, 255, 255));
    for (auto const& l : timed) {
      bool const past = now >= 0 && now >= l.to;
      bool const current = now >= 0 && now >= l.from && now < l.to;
      gp::ARGB const color = past      ? colors::kPast
                             : current ? colors::kOrange
                                       : colors::kBlue;
      gp::GraphicsPath block;
      float const left = x(l.from) + 3, right = x(l.to) - 3;
      if (right - left < 6) continue;
      RoundedRect(block, left, 14, right - left, h - 28, 10);
      gp::SolidBrush brush{gp::Color(color)};
      g.FillPath(&brush, &block);
      auto label = l.hours;
      if (!label.empty() && label.back() == L'.') label.pop_back();
      if (right - left > 34) {
        g.DrawString(label.c_str(), -1, &font,
                     gp::RectF(left, 14, right - left, h - 28), &center,
                     &white);
      }
    }
    if (now >= start && now <= end) {
      gp::Pen marker(gp::Color(colors::kRed), 6);
      marker.SetStartCap(gp::LineCapRound);
      marker.SetEndCap(gp::LineCapRound);
      g.DrawLine(&marker, x(now), 4.0f, x(now), h - 4.0f);
    }
  });
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

static JsonObject With(JsonObject o, wchar_t const* key, wchar_t const* value) {
  o.Insert(key, JsonValue::CreateStringValue(value));
  return o;
}

static JsonObject Spacing(JsonObject o, wchar_t const* spacing) {
  return With(o, L"spacing", spacing);
}

static JsonObject Centered(JsonObject o) {
  return With(o, L"horizontalAlignment", L"center");
}

static JsonObject Image(std::wstring const& uri, wchar_t const* width) {
  JsonObject o;
  o.Insert(L"type", JsonValue::CreateStringValue(L"Image"));
  o.Insert(L"url", JsonValue::CreateStringValue(uri));
  if (std::wstring(width) == L"stretch") {
    o.Insert(L"size", JsonValue::CreateStringValue(L"stretch"));
  } else {
    o.Insert(L"width", JsonValue::CreateStringValue(width));
  }
  return o;
}

static JsonObject Column(JsonArray const& items, std::wstring const& width,
                         bool middle = true) {
  JsonObject column;
  column.Insert(L"type", JsonValue::CreateStringValue(L"Column"));
  column.Insert(L"width", JsonValue::CreateStringValue(width));
  if (middle) {
    column.Insert(L"verticalContentAlignment",
                  JsonValue::CreateStringValue(L"center"));
  }
  column.Insert(L"items", items);
  return column;
}

static JsonObject Columns(std::vector<JsonObject> const& columns,
                          bool center = false) {
  JsonObject set;
  set.Insert(L"type", JsonValue::CreateStringValue(L"ColumnSet"));
  JsonArray array;
  for (auto const& c : columns) array.Append(c);
  set.Insert(L"columns", array);
  if (center) {
    set.Insert(L"horizontalAlignment", JsonValue::CreateStringValue(L"center"));
  }
  return set;
}

/// A row: a short label on the left, the rest beside it.
static JsonObject Row(std::wstring const& left, std::wstring const& title,
                      std::wstring const& subtitle,
                      wchar_t const* color = nullptr) {
  JsonArray leftItems;
  leftItems.Append(Text(left, L"small", true, color));
  JsonArray rightItems;
  rightItems.Append(Text(title, L"small", false, nullptr, false, 1));
  if (!subtitle.empty()) {
    rightItems.Append(Spacing(Text(subtitle, L"small", false, nullptr, true, 1),
                              L"none"));
  }
  auto set = Columns({Column(leftItems, L"auto", false),
                      Column(rightItems, L"stretch", false)});
  return Spacing(set, L"small");
}

/// A ring with a number in it: the ring is the background of a square
/// container, the number its text.
static JsonObject RingBlock(std::wstring const& ringUri,
                            std::wstring const& big, std::wstring const& unit,
                            int px, bool smallText) {
  JsonObject background;
  background.Insert(L"url", JsonValue::CreateStringValue(ringUri));
  background.Insert(L"fillMode", JsonValue::CreateStringValue(L"cover"));
  background.Insert(L"horizontalAlignment",
                    JsonValue::CreateStringValue(L"center"));
  background.Insert(L"verticalAlignment",
                    JsonValue::CreateStringValue(L"center"));
  JsonArray items;
  items.Append(Centered(Text(big, smallText ? L"medium" : L"large", true,
                             nullptr, false, 1)));
  if (!unit.empty()) {
    items.Append(Spacing(
        Centered(Text(unit, L"small", false, nullptr, true, 1)), L"none"));
  }
  JsonObject container;
  container.Insert(L"type", JsonValue::CreateStringValue(L"Container"));
  container.Insert(L"backgroundImage", background);
  container.Insert(L"minHeight", JsonValue::CreateStringValue(
                                     std::to_wstring(px) + L"px"));
  container.Insert(L"verticalContentAlignment",
                   JsonValue::CreateStringValue(L"center"));
  container.Insert(L"items", items);
  JsonArray columnItems;
  columnItems.Append(container);
  return Column(columnItems, std::to_wstring(px) + L"px");
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

static std::vector<Choice> const kYesNo = {{L"1", L"Ja"}, {L"0", L"Nein"}};
static std::vector<Choice> const kDesign = {{L"ring", L"Mit Grafik"},
                                            {L"text", L"Nur Text"}};

/// The subjects in the snapshot, for the subject filters.
static std::vector<std::wstring> Subjects(JsonObject const& snapshot) {
  std::set<std::wstring> names;
  for (auto const& s : Arr(Obj(snapshot, L"grades"), L"subjects")) {
    names.insert(Str(s, L"t"));
  }
  for (auto const& e : Arr(snapshot, L"upcoming")) {
    auto subject = EntrySubject(e);
    if (!subject.empty()) names.insert(subject);
  }
  names.erase(L"");
  return {names.begin(), names.end()};
}

static std::vector<Option> OptionsOf(std::wstring const& definition,
                                     JsonObject const& snapshot) {
  std::vector<Choice> subjects;
  for (auto const& s : Subjects(snapshot)) subjects.push_back({s, s});
  if (definition == L"lesson") {
    return {
        {L"design", L"Darstellung", L"ring",
         {{L"ring", L"Ring mit Countdown"}, {L"text", L"Nur Text"}}},
        {L"room", L"Raum anzeigen", L"1", kYesNo},
        {L"next", L"Nächste Stunde anzeigen", L"1", kYesNo},
        {L"end", L"Schulschluss anzeigen", L"1", kYesNo},
    };
  }
  if (definition == L"exams") {
    auto withAll = subjects;
    withAll.insert(withAll.begin(), {L"all", L"Alle Fächer"});
    return {
        {L"what", L"Was zeigen", L"exam",
         {{L"exam", L"Nur Prüfungen"},
          {L"all", L"Prüfungen und Hausaufgaben"},
          {L"homework", L"Nur Hausaufgaben"}}},
        {L"subject", L"Fach", L"all", withAll},
        {L"range", L"Zeitraum", L"30",
         {{L"7", L"7 Tage"}, {L"14", L"14 Tage"}, {L"30", L"30 Tage"},
          {L"60", L"60 Tage"}}},
        {L"design", L"Darstellung", L"ring",
         {{L"ring", L"Mit Kalenderblatt"}, {L"text", L"Nur Liste"}}},
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
        {L"timeline", L"Tagesverlauf als Balken", L"1", kYesNo},
        {L"room", L"Räume anzeigen", L"1", kYesNo},
    };
  }
  if (definition == L"countdown") {
    return {
        {L"target", L"Countdown bis", L"holidays",
         {{L"holidays", L"Zu den nächsten Ferien"},
          {L"end", L"Zum Schulende"},
          {L"both", L"Ferien, dazu das Schulende"}}},
        {L"unit", L"Zählen in", L"days",
         {{L"days", L"Tagen"},
          {L"schooldays", L"Schultagen"},
          {L"weeks", L"Wochen"}}},
        {L"design", L"Darstellung", L"ring", kDesign},
    };
  }
  if (definition == L"grades") {
    return {
        {L"show", L"Anzeige", L"overall",
         {{L"overall", L"Gesamtschnitt"},
          {L"subject", L"Ein Fach (unten wählen)"},
          {L"weakest", L"Schwächste Fächer"},
          {L"best", L"Beste Fächer"},
          {L"recent", L"Letzte Noten"}}},
        {L"subject", L"Fach", subjects.empty() ? L"" : subjects.front().value,
         subjects},
        {L"design", L"Darstellung", L"ring", kDesign},
    };
  }
  if (definition == L"absences") {
    return {
        {L"show", L"Anzeige", L"percent",
         {{L"percent", L"Anteil der Fehlstunden"},
          {L"remaining", L"Stunden bis zur Grenze"}}},
        {L"design", L"Darstellung", L"ring", kDesign},
    };
  }
  return {};
}

static std::wstring OptionValue(std::wstring const& definition,
                                JsonObject const& snapshot,
                                JsonObject const& state,
                                std::wstring const& id) {
  auto value = Str(state, id.c_str());
  for (auto const& option : OptionsOf(definition, snapshot)) {
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
  auto const snapshot = g_snapshot.Get();
  JsonArray body;
  body.Append(Text(L"Widget anpassen", L"medium", true));
  for (auto const& option : OptionsOf(definition, snapshot)) {
    if (option.choices.empty()) continue;
    body.Append(Text(option.label, L"small", true));
    JsonObject input;
    input.Insert(L"type", JsonValue::CreateStringValue(L"Input.ChoiceSet"));
    input.Insert(L"id", JsonValue::CreateStringValue(option.id));
    input.Insert(L"value",
                 JsonValue::CreateStringValue(
                     OptionValue(definition, snapshot, state, option.id)));
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
    return OptionValue(definition, snapshot, state, id);
  }
  bool Graphic() const { return Option(L"design") != L"text"; }

  /// The subject as it fits: the nickname from the app's settings in the
  /// small size, and for long names in the others ("BWL" for
  /// "Betriebswirtschaftslehre").
  std::wstring Subject(std::wstring const& name) const {
    if (!Small() && name.size() <= 16) return name;
    auto const nicks = Obj(snapshot, L"nicks");
    if (nicks) {
      for (auto const& pair : nicks) {
        if (_wcsicmp(pair.Key().c_str(), name.c_str()) == 0 &&
            pair.Value().ValueType() == JsonValueType::String) {
          return std::wstring(pair.Value().GetString());
        }
      }
    }
    return name;
  }
  /// The ring's size in the card.
  int RingSize() const { return Small() ? 76 : 96; }
};

/// A ring and, beside it (or below it, in the small size), [side].
static void RingLayout(Context const& c, JsonArray& body,
                       std::wstring const& ring, std::wstring const& big,
                       std::wstring const& unit,
                       std::vector<JsonObject> const& side) {
  auto block = RingBlock(ring, big, unit, c.RingSize(), c.Small());
  if (c.Small()) {
    body.Append(Columns({block}, true));
    for (size_t i = 0; i < side.size() && i < 2; i++) {
      auto item = side[i];
      // The name may take two lines here: there is nothing beside it.
      if (i == 0) item.Insert(L"maxLines", JsonValue::CreateNumberValue(2));
      body.Append(Spacing(Centered(item), i == 0 ? L"small" : L"none"));
    }
    return;
  }
  JsonArray items;
  for (size_t i = 0; i < side.size(); i++) {
    items.Append(i == 0 ? side[i] : Spacing(side[i], L"none"));
  }
  body.Append(Columns({block, Column(items, L"stretch")}));
}

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

/// The large size has room for the rest of the day: the timeline and the
/// lessons still to come.
static void LessonLargeExtras(Context const& c, JsonArray& body,
                              std::vector<Lesson> const& today, bool room) {
  if (!c.Large() || today.empty()) return;
  auto const picture = TimelinePicture(today, c.now.minutes);
  if (!picture.empty()) body.Append(Spacing(Image(picture, L"stretch"), L"medium"));
  int shown = 0;
  for (auto const& l : today) {
    if (l.to <= c.now.minutes || shown >= 4) continue;
    bool const current = c.now.minutes >= l.from;
    body.Append(Row(l.hours, c.Subject(l.subject),
                    Clock(l.from) + L" – " + Clock(l.to) +
                        (room && !l.room.empty() ? L" · " + l.room : L""),
                    current ? L"accent" : nullptr));
    shown++;
  }
}

/// "23" / "Min", "1:12" / "Std".
static std::pair<std::wstring, std::wstring> RingTime(int seconds) {
  int const minutes = (std::max(seconds, 0) + 59) / 60;
  if (minutes < 60) return {std::to_wstring(minutes), L"Min"};
  return {std::to_wstring(minutes / 60) + L":" + Two(minutes % 60), L"Std"};
}

static void LessonWidget(Context const& c, JsonArray& body) {
  auto const today = LessonsOn(c.snapshot, c.now.date);
  auto const now = c.now.minutes;
  auto const nowSeconds = c.now.seconds;
  int lastEnd = -1;
  for (auto const& l : today) lastEnd = std::max(lastEnd, l.to);
  bool const showEnd = c.Option(L"end") == L"1" && lastEnd > now &&
                       !today.empty() && today.front().from <= now;
  bool const showRoom = c.Option(L"room") == L"1";
  bool const showNext = c.Option(L"next") == L"1";

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
    int start = l.from;
    for (size_t j = i; j-- > 0;) {
      if (today[j].subject != l.subject || start - today[j].to > 5) break;
      start = today[j].from;
    }
    std::wstring next;
    for (auto const& n : today) {
      if (n.from >= end) {
        next = L"Danach " + c.Subject(n.subject) + L" um " + Clock(n.from);
        break;
      }
    }
    std::wstring until = L"bis " + Clock(end);
    if (end != l.to) until += L" (Stunde bis " + Clock(l.to) + L")";

    if (c.Graphic()) {
      auto const [big, unit] = RingTime(end * 60 - nowSeconds);
      double const progress =
          static_cast<double>(nowSeconds - start * 60) / ((end - start) * 60);
      std::vector<JsonObject> side{
          Text(c.Subject(l.subject), c.Small() ? L"default" : L"medium", true, nullptr,
               false, 1)};
      side.push_back(Text(until, L"small", false, nullptr, true, 2));
      if (showRoom && !l.room.empty() && !c.Small()) {
        side.push_back(Text(l.room, L"small", false, nullptr, true, 1));
      }
      if (showNext && !next.empty() && !c.Small()) {
        side.push_back(Text(next, L"small", false, nullptr, true, 1));
      }
      if (showEnd && lastEnd != end && !c.Small()) {
        side.push_back(Text(L"Schulschluss " + Clock(lastEnd), L"small", false,
                            L"accent", false, 1));
      }
      RingLayout(c, body, RingPicture(progress, colors::kBlue), big, unit, side);
      LessonLargeExtras(c, body, today, showRoom);
      return;
    }

    body.Append(Text(c.Subject(l.subject), c.Small() ? L"medium" : L"large", true, nullptr,
                     false, 1));
    std::wstring left = L"noch " + Duration(end - now);
    if (end != l.to) left += L" (" + Duration(l.to - now) + L")";
    body.Append(Spacing(Text(left, L"medium", false, L"accent"), L"none"));
    if (!c.Small() && showRoom && !l.room.empty()) {
      body.Append(Spacing(Text(l.hours + L" Stunde · " + l.room, L"small",
                               false, nullptr, true),
                          L"none"));
    }
    if (!c.Small() && showNext && !next.empty()) {
      body.Append(Text(next, L"small", false, nullptr, true));
    }
    if (showEnd && lastEnd != end) {
      body.Append(Text(L"Schulschluss " + Clock(lastEnd) + L" (in " +
                           Duration(lastEnd - now) + L")",
                       L"small", false, nullptr, true));
    }
    return;
  }

  // A break: after a lesson, before the next one.
  for (size_t i = 0; i < today.size(); i++) {
    auto const& n = today[i];
    if (n.from <= now || today.front().to > now) continue;
    int previousEnd = today.front().to;
    for (size_t j = 0; j < i; j++) previousEnd = std::max(previousEnd, today[j].to);
    if (c.Graphic()) {
      auto const [big, unit] = RingTime(n.from * 60 - nowSeconds);
      double const progress = static_cast<double>(nowSeconds - previousEnd * 60) /
                              std::max(1, (n.from - previousEnd) * 60);
      std::vector<JsonObject> side{
          Text(L"Pause", c.Small() ? L"default" : L"medium", true)};
      side.push_back(Text(L"→ " + c.Subject(n.subject) + L" um " + Clock(n.from), L"small",
                          false, nullptr, true, 2));
      if (showRoom && !n.room.empty() && !c.Small()) {
        side.push_back(Text(n.room, L"small", false, nullptr, true, 1));
      }
      if (showEnd && !c.Small()) {
        side.push_back(Text(L"Schulschluss " + Clock(lastEnd), L"small", false,
                            L"accent", false, 1));
      }
      RingLayout(c, body, RingPicture(progress, colors::kGreen), big, unit,
                 side);
      LessonLargeExtras(c, body, today, showRoom);
      return;
    }
    body.Append(Text(L"Pause", c.Small() ? L"medium" : L"large", true));
    body.Append(Spacing(Text(L"noch " + Duration(n.from - now) + L" → " +
                                 c.Subject(n.subject),
                             L"medium", false, L"accent", false, 1),
                        L"none"));
    if (showEnd) {
      body.Append(Text(L"Schulschluss " + Clock(lastEnd), L"small", false,
                       nullptr, true));
    }
    return;
  }

  // Before school today.
  if (!today.empty() && now < today.front().from) {
    auto const& first = today.front();
    if (c.Graphic() && first.from - now <= 120) {
      auto const [big, unit] = RingTime(first.from * 60 - nowSeconds);
      RingLayout(c, body, RingPicture(0, colors::kBlue), big, unit,
                 {Text(L"Gleich: " + c.Subject(first.subject),
                       c.Small() ? L"default" : L"medium", true, nullptr, false,
                       1),
                  Text(L"um " + Clock(first.from), L"small", false, nullptr,
                       true, 1)});
      return;
    }
    body.Append(Text(L"Gleich: " + c.Subject(first.subject), L"medium", true, nullptr,
                     false, 1));
    body.Append(Spacing(Text(L"um " + Clock(first.from) + L" (in " +
                                 Duration(first.from - now) + L")",
                             L"small", false, L"accent"),
                        L"none"));
    return;
  }

  body.Append(Text(today.empty() ? L"Kein Unterricht" : L"Schulschluss!",
                   L"medium", true));
  chrono::year_month_day next;
  if (NextDayWithLessons(c.snapshot, AddDays(c.now.date, 1), next)) {
    auto const lessons = LessonsOn(c.snapshot, next);
    auto const& first = lessons.front();
    auto const days = DaysBetween(c.now.date, next);
    std::wstring when = days == 1 ? L"Morgen" : ShortDay(next);
    auto const extra = ExtraSchoolDay(c.snapshot, next);
    body.Append(Spacing(
        Text(when + L" " + Clock(first.from) + L" · " + c.Subject(first.subject), L"small",
             false, nullptr, true, 2),
        L"none"));
    if (!extra.empty() && !c.Small()) {
      body.Append(Text(extra + L" – ausnahmsweise Schule", L"small", false,
                       L"warning"));
    }
  }
}

static void ExamsWidget(Context const& c, JsonArray& body) {
  auto const what = c.Option(L"what");
  auto const subject = c.Option(L"subject");
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
    if (subject != L"all" && EntrySubject(e) != subject) continue;
    chrono::year_month_day date;
    if (!ParseDay(Str(e, L"d"), date)) continue;
    auto days = DaysBetween(c.now.date, date);
    if (days < 0 || days > range) continue;
    entries.push_back({date, Str(e, L"t"), Str(e, L"s"), kind});
  }
  std::wstring heading = what == L"homework" ? L"Hausaufgaben"
                         : what == L"all"     ? L"Anstehend"
                                              : L"Prüfungen";
  if (subject != L"all") heading += L" · " + subject;
  if (entries.empty()) {
    body.Append(Text(heading, L"small", true, nullptr, true, 1));
    body.Append(Text(what == L"homework" ? L"Keine offenen Hausaufgaben"
                                         : L"Nichts in Sicht",
                     L"medium", true));
    body.Append(Text(L"in den nächsten " + std::to_wstring(range) + L" Tagen",
                     L"small", false, nullptr, true));
    return;
  }
  auto const& first = entries.front();
  auto const firstColor =
      first.kind == L"exam" ? colors::kRed : colors::kBlue;
  auto const relative = InDays(DaysBetween(c.now.date, first.date));
  auto const* relativeColor = first.kind == L"exam" ? L"attention" : L"accent";

  if (c.Graphic()) {
    auto const sheet = CalendarSheetPicture(first.date, firstColor);
    if (c.Small()) {
      JsonArray sheetItems;
      sheetItems.Append(Image(sheet, L"60px"));
      body.Append(Columns({Column(sheetItems, L"60px")}, true));
      body.Append(Spacing(Centered(Text(first.title, L"default", true, nullptr,
                                        false, 1)),
                          L"small"));
      body.Append(Spacing(
          Centered(Text(relative, L"small", true, relativeColor, false, 1)),
          L"none"));
      return;
    }
    JsonArray sheetItems;
    sheetItems.Append(Image(sheet, L"72px"));
    JsonArray textItems;
    textItems.Append(Text(relative, L"small", true, relativeColor, false, 1));
    textItems.Append(Spacing(Text(first.title, L"medium", true, nullptr, false,
                                  1),
                             L"none"));
    textItems.Append(Spacing(Text(first.subtitle, L"small", false, nullptr,
                                  true, 2),
                             L"none"));
    body.Append(Columns({Column(sheetItems, L"72px"),
                         Column(textItems, L"stretch")}));
    size_t const max = c.Large() ? 7 : 2;
    for (size_t i = 1; i < entries.size() && i <= max; i++) {
      auto const& e = entries[i];
      body.Append(Row(ShortDay(e.date), e.title, e.subtitle,
                      e.kind == L"exam" ? L"attention" : nullptr));
    }
    if (entries.size() > max + 1) {
      body.Append(Text(L"+ " + std::to_wstring(entries.size() - max - 1) +
                           L" weitere",
                       L"small", false, nullptr, true));
    }
    return;
  }

  if (c.Small()) {
    body.Append(Text(relative, L"small", true, relativeColor));
    body.Append(Spacing(Text(first.title, L"medium", true, nullptr, false, 1),
                        L"none"));
    body.Append(Spacing(Text(first.subtitle, L"small", false, nullptr, true, 1),
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
  bool const timeline = c.Option(L"timeline") == L"1";
  bool const rooms = c.Option(L"room") == L"1";
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
  bool const isToday = DaysBetween(c.now.date, day) == 0;

  auto const lessons = LessonsOn(c.snapshot, day);
  auto const entries =
      Arr(Obj(Obj(c.snapshot, L"days"), DayKey(day).c_str()), L"entries");
  auto const extra = ExtraSchoolDay(c.snapshot, day);

  body.Append(Text(label + L" · " + ShortDay(day), L"small", true,
                   extra.empty() ? nullptr : L"warning"));
  if (!extra.empty()) {
    body.Append(Spacing(Text(extra + L" – ausnahmsweise Schule", L"small",
                             false, L"warning", false, 1),
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
  add(homework, c.Small() ? L"HA" : L"Hausaufgabe",
      c.Small() ? L"HA" : L"Hausaufgaben");
  add(reminders, L"Erinnerung", L"Erinnerungen");

  if (summary.empty()) {
    auto const weekday = WeekdayIndex(day);
    body.Append(Text(weekday >= 5 && extra.empty() ? L"Wochenende"
                                                   : L"Nichts eingetragen",
                     L"medium", true));
    return;
  }
  if (timeline && !lessons.empty()) {
    auto const picture =
        TimelinePicture(lessons, isToday ? c.now.minutes : -1);
    if (!picture.empty()) {
      body.Append(Spacing(Image(picture, L"stretch"), L"small"));
      if (!c.Small()) {
        body.Append(Spacing(
            Text(Clock(lessons.front().from) + L" – " +
                     Clock(lessons.back().to),
                 L"small", false, nullptr, true, 1),
            L"none"));
      }
    }
  }
  if (c.Small()) {
    body.Append(Text(summary, L"small", true, tests ? L"attention" : nullptr,
                     false, 3));
    return;
  }
  body.Append(Text(summary, L"small", true, tests ? L"attention" : nullptr));
  size_t rows = 0;
  size_t const max = c.Large() ? (timeline ? 6 : 10) : (timeline ? 1 : 3);
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
      bool const now = isToday && c.now.minutes >= l.from &&
                       c.now.minutes < l.to;
      body.Append(Row(l.hours, c.Subject(l.subject),
                      (l.from >= 0 ? Clock(l.from) : L"") +
                          (rooms && !l.room.empty() ? L" · " + l.room : L""),
                      now ? L"accent" : nullptr));
    }
  }
}

/// Days from [from] up to (not including) [to], in the unit of the widget.
static std::pair<std::wstring, std::wstring> CountIn(
    Context const& c, chrono::year_month_day from, chrono::year_month_day to,
    std::wstring const& unit) {
  int const days = DaysBetween(from, to);
  if (unit == L"schooldays") {
    int n = 0;
    for (int i = 0; i < days; i++) {
      if (IsSchoolDay(c.snapshot, AddDays(from, i))) n++;
    }
    return {std::to_wstring(n), n == 1 ? L"Schultag" : L"Schultage"};
  }
  if (unit == L"weeks") {
    if (days < 14) return {std::to_wstring(days), days == 1 ? L"Tag" : L"Tage"};
    return {std::to_wstring(days / 7), L"Wochen"};
  }
  return {std::to_wstring(days), days == 1 ? L"Tag" : L"Tage"};
}

static void CountdownWidget(Context const& c, JsonArray& body) {
  auto const target = c.Option(L"target");
  auto const unit = c.Option(L"unit");
  chrono::year_month_day firstDay;
  bool const knowsStart = ParseDay(Str(c.snapshot, L"firstSchoolDay"), firstDay);
  chrono::year_month_day last;
  bool const knowsEnd = ParseDay(Str(c.snapshot, L"lastSchoolDay"), last) &&
                        DaysBetween(c.now.date, last) >= 0;

  if (target != L"end") {
    JsonObject best{nullptr};
    chrono::year_month_day bestFrom{}, bestTo{};
    // Where the stretch of school towards these holidays began: the end of
    // the holidays before, or the first day of school.
    // Without the first day of school (older snapshots), the end of the
    // holidays before is the start.
    chrono::year_month_day periodStart =
        knowsStart ? firstDay : AddDays(c.now.date, -365);
    for (auto const& h : Arr(c.snapshot, L"holidays")) {
      chrono::year_month_day from, to;
      if (!ParseDay(Str(h, L"from"), from) || !ParseDay(Str(h, L"to"), to)) {
        continue;
      }
      if (DaysBetween(c.now.date, to) < 0) {
        if (DaysBetween(periodStart, AddDays(to, 1)) > 0) {
          periodStart = AddDays(to, 1);
        }
        continue;
      }
      if (!best || DaysBetween(from, bestFrom) > 0) {
        best = h;
        bestFrom = from;
        bestTo = to;
      }
    }
    if (best) {
      auto const name = Str(best, L"t");
      auto const days = DaysBetween(c.now.date, bestFrom);
      bool const ongoing = days <= 0;
      std::wstring big, unitLabel;
      double progress = 0;
      gp::ARGB color = colors::kBlue;
      if (ongoing) {
        int const left = DaysBetween(c.now.date, bestTo) + 1;
        big = std::to_wstring(left);
        unitLabel = left == 1 ? L"Tag frei" : L"Tage frei";
        progress = 1.0 - static_cast<double>(left) /
                             std::max(1, DaysBetween(bestFrom, bestTo) + 1);
        color = colors::kGreen;
      } else {
        std::tie(big, unitLabel) = CountIn(c, c.now.date, bestFrom, unit);
        int const total = std::max(1, DaysBetween(periodStart, bestFrom));
        progress = static_cast<double>(DaysBetween(periodStart, c.now.date)) /
                   total;
        color = days <= 7 ? colors::kGreen : colors::kBlue;
      }
      std::vector<JsonObject> side{
          Text(name, c.Small() ? L"default" : L"medium", true, nullptr, false,
               1)};
      side.push_back(Text(ongoing ? L"bis " + ShortDay(bestTo)
                                  : L"ab " + ShortDay(bestFrom),
                          L"small", false, nullptr, true, 1));
      if (target == L"both" && knowsEnd && !c.Small()) {
        auto const [n, u] = CountIn(c, c.now.date, last, unit);
        side.push_back(Text(L"Schulende in " + n + L" " + u, L"small", false,
                            L"accent", false, 1));
      }
      if (c.Graphic()) {
        RingLayout(c, body, RingPicture(progress, color), big, unitLabel, side);
        if (c.Large()) {
          // The holidays after these, for planning ahead.
          std::vector<std::pair<chrono::year_month_day, std::wstring>> later;
          for (auto const& h : Arr(c.snapshot, L"holidays")) {
            chrono::year_month_day from;
            if (ParseDay(Str(h, L"from"), from) &&
                DaysBetween(bestFrom, from) > 0) {
              later.emplace_back(from, Str(h, L"t"));
            }
          }
          std::sort(later.begin(), later.end(), [](auto const& a, auto const& b) {
            return DaysBetween(a.first, b.first) > 0;
          });
          if (!later.empty()) {
            body.Append(Spacing(Text(L"Danach", L"small", true, nullptr, true),
                                L"medium"));
          }
          for (size_t i = 0; i < later.size() && i < 5; i++) {
            auto const [n, u] = CountIn(c, c.now.date, later[i].first, unit);
            body.Append(Row(ShortDay(later[i].first), later[i].second,
                            L"in " + n + L" " + u));
          }
        }
      } else {
        body.Append(Text(name, L"small", true, nullptr, true, 1));
        body.Append(Spacing(Text(big + L" " + unitLabel, L"extraLarge", true,
                                 ongoing ? L"good" : L"accent"),
                            L"none"));
        for (size_t i = 1; i < side.size() && !c.Small(); i++) {
          body.Append(Spacing(side[i], L"none"));
        }
      }
      return;
    }
  }
  if (knowsEnd) {
    auto const [big, unitLabel] = CountIn(c, c.now.date, last, unit);
    double const progress =
        knowsStart ? static_cast<double>(DaysBetween(firstDay, c.now.date)) /
                         std::max(1, DaysBetween(firstDay, last))
                   : 0;
    std::vector<JsonObject> side{
        Text(L"Schulende", c.Small() ? L"default" : L"medium", true),
        Text(ShortDay(last), L"small", false, nullptr, true, 1)};
    if (c.Graphic()) {
      RingLayout(c, body, RingPicture(progress, colors::kOrange), big,
                 unitLabel, side);
    } else {
      body.Append(Text(L"Schulende", L"small", true, nullptr, true));
      body.Append(Spacing(Text(big + L" " + unitLabel, L"extraLarge", true,
                               L"accent"),
                          L"none"));
    }
    return;
  }
  body.Append(Text(L"Keine Ferien eingetragen", L"medium", true));
}

static gp::ARGB GradeColor(double average) {
  if (average < 6) return colors::kRed;
  if (average < 7) return colors::kOrange;
  if (average < 8) return colors::kBlue;
  return colors::kGreen;
}

static void GradesWidget(Context const& c, JsonArray& body) {
  auto const grades = Obj(c.snapshot, L"grades");
  if (!grades) {
    body.Append(Text(L"Noch keine Noten", L"medium", true));
    return;
  }
  auto show = c.Option(L"show");
  auto subjects = Arr(grades, L"subjects");  // weakest first

  if (show == L"overall" || show == L"subject") {
    std::wstring name = L"Gesamtschnitt", value = Str(grades, L"overall");
    std::wstring hint;
    if (show == L"subject") {
      auto const wanted = c.Option(L"subject");
      bool found = false;
      for (auto const& s : subjects) {
        if (Str(s, L"t") == wanted) {
          name = wanted;
          value = Str(s, L"v");
          found = true;
        }
      }
      if (!found) hint = L"Noch keine Noten in " + wanted;
    } else {
      auto trend = Str(grades, L"trend");
      if (!trend.empty()) hint = L"Trend " + trend + L" pro Monat";
    }
    if (value.empty()) {
      body.Append(Text(name, L"medium", true));
      body.Append(Text(hint.empty() ? L"Noch keine Noten" : hint, L"small",
                       false, nullptr, true));
      return;
    }
    double const average = ParseNumber(value);
    if (c.Graphic()) {
      std::vector<JsonObject> side{Text(name, c.Small() ? L"default" : L"medium",
                                        true, nullptr, false, 1)};
      if (!hint.empty()) {
        side.push_back(Text(hint, L"small", false, nullptr, true, 2));
      }
      RingLayout(c, body,
                 RingPicture((average - 4) / 6, GradeColor(average)), value,
                 L"Schnitt", side);
      if (c.Large() && show == L"overall") {
        // Every subject, best first.
        body.Append(Spacing(Text(L"Fächer", L"small", true, nullptr, true),
                            L"medium"));
        for (size_t i = subjects.size(), shown = 0; i-- > 0 && shown < 9;
             shown++) {
          auto const& s = subjects[i];
          body.Append(Row(Str(s, L"v"), Str(s, L"t"), L"",
                          Bool(s, L"low") ? L"attention" : nullptr));
        }
      }
      return;
    }
    body.Append(Text(name, L"small", true, nullptr, true, 1));
    body.Append(Spacing(Text(value, L"extraLarge", true,
                             average < 6 ? L"attention" : L"accent"),
                        L"none"));
    if (!hint.empty()) {
      body.Append(Spacing(Text(hint, L"small", false, nullptr, true), L"none"));
    }
    return;
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
  auto const percent = Str(a, L"percent");
  double const value = ParseNumber(percent);
  double const limit = std::max(1.0, ParseNumber(Str(a, L"limit")));
  double const share = value / limit;
  gp::ARGB const color = share < 0.6    ? colors::kGreen
                         : share < 0.85 ? colors::kOrange
                                        : colors::kRed;
  auto const remaining = Str(a, L"remaining");
  auto const open = Str(a, L"open");
  bool const showRemaining =
      c.Option(L"show") == L"remaining" && !remaining.empty();

  std::wstring const big = showRemaining ? remaining
                                         : (percent.empty() ? L"–" : percent);
  std::wstring const unit = showRemaining ? L"Std. Luft" : L"%";
  std::vector<JsonObject> side{
      Text(L"Absenzen", c.Small() ? L"default" : L"medium", true)};
  side.push_back(Text(showRemaining ? L"bis zur Grenze von " + Str(a, L"limit") +
                                          L" %"
                                    : L"Grenze " + Str(a, L"limit") + L" %",
                      L"small", false, nullptr, true, 1));
  if (!c.Small() && !showRemaining && !remaining.empty()) {
    side.push_back(Text(L"Noch " + remaining + L" Stunden Luft", L"small",
                        false, nullptr, true, 1));
  }
  if (!c.Small() && !open.empty() && open != L"0") {
    side.push_back(Text(open + L" noch nicht entschuldigt", L"small", false,
                        L"warning", false, 1));
  }
  if (c.Graphic()) {
    RingLayout(c, body, RingPicture(share, color), big, unit, side);
    return;
  }
  body.Append(Text(L"Absenzen", L"small", true, nullptr, true));
  body.Append(Spacing(Text(big + L" " + unit, L"extraLarge", true,
                           Bool(a, L"overLimit") ? L"attention" : L"accent"),
                      L"none"));
  for (size_t i = 1; i < side.size(); i++) {
    body.Append(Spacing(side[i], L"none"));
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
/// The pictures are saved next to it as PNG files.
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
  gp::GdiplusStartupInput gdiplusInput;
  ULONG_PTR gdiplusToken = 0;
  gp::GdiplusStartup(&gdiplusToken, &gdiplusInput, nullptr);
  if (__argc >= 3 && std::wstring(__wargv[1]) == L"--dump") {
    static SYSTEMTIME fake{};
    int y = 0, mo = 0, d = 0, h = 0, mi = 0;
    if (__argc >= 4 && swscanf_s(__wargv[3], L"%d-%d-%dT%d:%d", &y, &mo, &d,
                                 &h, &mi) == 5) {
      fake.wYear = static_cast<WORD>(y);
      fake.wMonth = static_cast<WORD>(mo);
      fake.wDay = static_cast<WORD>(d);
      fake.wHour = static_cast<WORD>(h);
      fake.wMinute = static_cast<WORD>(mi);
      g_fakeTime = &fake;
    }
    return Dump(__wargv[2]);
  }
  g_exitEvent = CreateEventW(nullptr, TRUE, FALSE, nullptr);

  auto factory = make<ProviderFactory>();
  DWORD cookie = 0;
  check_hresult(CoRegisterClassObject(kProviderClsid, factory.get(),
                                      CLSCTX_LOCAL_SERVER, REGCLS_MULTIPLEUSE,
                                      &cookie));

  // Redraws every 15 seconds, so the rings move along; leaves once there
  // have been no widgets for two minutes (Windows starts us again when it
  // needs us).
  std::thread([] {
    int idle = 0;
    while (WaitForSingleObject(g_exitEvent, 15000) == WAIT_TIMEOUT) {
      auto provider = WidgetProvider::instance_;
      if (provider && provider->Count() > 0) {
        idle = 0;
        provider->Tick();
      } else if (++idle >= 8) {
        SetEvent(g_exitEvent);
      }
    }
  }).detach();

  WaitForSingleObject(g_exitEvent, INFINITE);
  CoRevokeClassObject(cookie);
  gp::GdiplusShutdown(gdiplusToken);
  return 0;
}
