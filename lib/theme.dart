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

/// The themes the user can pick from.
///
/// A preset is a colour ([AppThemePreset.swatch]) plus a shape
/// ([AppThemeDesign]): corner radius, elevation, density, typography. The
/// colour alone only ever gave variations of the same app; the design is what
/// makes "Kompakt" and "Papier" feel like different programs.
///
/// The original app built its theme with `ThemeData(colorSchemeSeed: deepOrange)`,
/// but on the Flutter version it shipped with that still produced the Material 2
/// palette. Measured side by side, the two recipes are worlds apart in dark
/// mode:
///
/// | recipe                  | scaffold  | card      | primary   |
/// |-------------------------|-----------|-----------|-----------|
/// | `colorSchemeSeed` (M3)  | `#1A110F` | `#1A110F` | `#FFB5A0` |
/// | `primarySwatch` (M2)    | `#303030` | `#424242` | `#FF5722` |
///
/// Material 3 paints every surface the same near-black, which is why the
/// sidebar and the content area became one flat slab. The Material 2 greys are
/// therefore pinned explicitly below rather than left to the framework, so a
/// future Flutter release cannot quietly change them again.
library;

import 'package:flutter/material.dart';

/// The surface colours the original app used. Material 2 derives these from
/// `Colors.grey`, but they are written out so they stay put.
const _darkScaffold = Color(0xFF303030); // Colors.grey[850]
const _darkSurface = Color(0xFF424242); // Colors.grey[800]
const _lightScaffold = Color(0xFFFAFAFA); // Colors.grey[50]
const _lightSurface = Colors.white;

/// Everything about a theme that is not its colour.
class AppThemeDesign {
  const AppThemeDesign({
    this.cornerRadius = 4,
    this.cardElevation = 1,
    this.cardMargin = const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    this.density = VisualDensity.standard,
    this.outlinedCards = false,
    this.dividerThickness,
    this.appBarElevation,
    this.centerAppBarTitle = false,
    this.fontFamily,
    this.fontFamilyFallback,
    this.titleWeight,
    this.letterSpacing,
    this.filledButtons = false,
  });

  /// Corner radius for cards, dialogs, buttons and input fields.
  final double cornerRadius;

  final double cardElevation;
  final EdgeInsets cardMargin;

  /// How tightly rows are packed. Negative values mean denser.
  final VisualDensity density;

  /// Draw a border instead of relying on the shadow. Reads much better at
  /// elevation 0, where a card would otherwise be invisible.
  final bool outlinedCards;

  final double? dividerThickness;
  final double? appBarElevation;
  final bool centerAppBarTitle;

  /// Typography. Only families that exist on Windows and Android are used, each
  /// with the generic name as the last fallback.
  final String? fontFamily;
  final List<String>? fontFamilyFallback;

  /// Applied to headlines and titles; lets a design read as "bold" or "quiet"
  /// without touching every widget.
  final FontWeight? titleWeight;
  final double? letterSpacing;

  /// Use filled buttons rather than the elevated ones Material 2 defaults to.
  final bool filledButtons;

  static const classic = AppThemeDesign();

  /// Everything a little tighter, so more fits on one screen.
  static const compact = AppThemeDesign(
    cornerRadius: 2,
    cardElevation: 0,
    cardMargin: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    density: VisualDensity(horizontal: -2, vertical: -3),
    outlinedCards: true,
    dividerThickness: 0.5,
    appBarElevation: 0,
  );

  /// Big radii, generous spacing, soft shadows.
  static const soft = AppThemeDesign(
    cornerRadius: 20,
    cardElevation: 3,
    cardMargin: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    density: VisualDensity(horizontal: 0, vertical: 1),
    appBarElevation: 0,
    centerAppBarTitle: true,
    filledButtons: true,
  );

  /// Hard edges, heavy borders, bold headings — made to be readable.
  static const contrast = AppThemeDesign(
    cornerRadius: 0,
    cardElevation: 0,
    outlinedCards: true,
    dividerThickness: 1.5,
    appBarElevation: 0,
    titleWeight: FontWeight.w800,
    letterSpacing: 0.2,
  );

  /// A serif face and calm surfaces, like a printed timetable.
  static const paper = AppThemeDesign(
    cornerRadius: 2,
    cardElevation: 0,
    cardMargin: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    outlinedCards: true,
    dividerThickness: 0.5,
    appBarElevation: 0,
    centerAppBarTitle: true,
    fontFamily: "Georgia",
    fontFamilyFallback: ["Times New Roman", "Noto Serif", "serif"],
  );

  /// Monospace and square, for people who like their register to look like a
  /// terminal.
  static const mono = AppThemeDesign(
    cornerRadius: 0,
    cardElevation: 0,
    cardMargin: EdgeInsets.symmetric(horizontal: 6, vertical: 3),
    density: VisualDensity(horizontal: -1, vertical: -2),
    outlinedCards: true,
    dividerThickness: 1,
    appBarElevation: 0,
    fontFamily: "Consolas",
    fontFamilyFallback: ["Roboto Mono", "DejaVu Sans Mono", "monospace"],
    letterSpacing: -0.2,
  );

  /// Material 3's own shapes.
  static const material3 = AppThemeDesign(
    cornerRadius: 12,
    cardElevation: 1,
    cardMargin: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    appBarElevation: 0,
  );
}

class AppThemePreset {
  const AppThemePreset({
    required this.id,
    required this.name,
    required this.description,
    required this.swatch,
    this.design = AppThemeDesign.classic,
    this.useMaterial3 = false,
    this.pureBlackDark = false,
    this.lightScaffoldOverride,
    this.lightSurfaceOverride,
    this.darkScaffoldOverride,
    this.darkSurfaceOverride,
  });

  /// Stored in the settings; must stay stable.
  final String id;

  final String name;
  final String description;

  /// The accent colour. A full [MaterialColor] because the Material 2 base
  /// needs the shades, not just one tone.
  final MaterialColor swatch;

  final AppThemeDesign design;

  /// Opt into Material 3. Only "Modern" does.
  final bool useMaterial3;

  /// Use a true black background in dark mode (easier on OLED screens).
  final bool pureBlackDark;

  /// Presets that want their own paper rather than the original's greys.
  final Color? lightScaffoldOverride, lightSurfaceOverride;
  final Color? darkScaffoldOverride, darkSurfaceOverride;

  /// The colour shown as this preset's dot in the settings.
  Color get previewColor => swatch;

  ThemeData build(Brightness brightness, TargetPlatform? platform) {
    final isDark = brightness == Brightness.dark;

    final ThemeData base;
    if (useMaterial3) {
      base = ThemeData(
        colorSchemeSeed: swatch,
        brightness: brightness,
        platform: platform,
      );
    } else {
      base = ThemeData(
        primarySwatch: swatch,
        brightness: brightness,
        platform: platform,
        useMaterial3: false,
      );
    }

    final scaffold = isDark
        ? darkScaffoldOverride ??
            (pureBlackDark ? Colors.black : _darkScaffold)
        : lightScaffoldOverride ?? _lightScaffold;
    final surface = isDark
        ? darkSurfaceOverride ??
            (pureBlackDark ? const Color(0xFF121212) : _darkSurface)
        : lightSurfaceOverride ?? _lightSurface;

    // Material 3 derives its own surfaces, and they are part of what makes it
    // look the way it does — only the Material 2 presets get the pinned greys.
    final colorScheme = useMaterial3
        ? base.colorScheme
        : base.colorScheme.copyWith(surface: surface);

    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(design.cornerRadius),
      side: design.outlinedCards
          ? BorderSide(color: colorScheme.outlineVariant)
          : BorderSide.none,
    );

    var textTheme = base.textTheme;
    if (design.fontFamily != null) {
      textTheme = textTheme.apply(
        fontFamily: design.fontFamily,
        fontFamilyFallback: design.fontFamilyFallback,
      );
    }
    if (design.letterSpacing != null) {
      textTheme = _withLetterSpacing(textTheme, design.letterSpacing!);
    }
    if (design.titleWeight != null) {
      TextStyle? weigh(TextStyle? style) =>
          style?.copyWith(fontWeight: design.titleWeight);
      textTheme = textTheme.copyWith(
        headlineSmall: weigh(textTheme.headlineSmall),
        headlineMedium: weigh(textTheme.headlineMedium),
        titleLarge: weigh(textTheme.titleLarge),
        titleMedium: weigh(textTheme.titleMedium),
      );
    }

    return base.copyWith(
      scaffoldBackgroundColor: useMaterial3 ? null : scaffold,
      canvasColor: useMaterial3 ? null : scaffold,
      cardColor: useMaterial3 ? null : surface,
      colorScheme: colorScheme,
      textTheme: textTheme,
      visualDensity: design.density,
      dividerTheme: design.dividerThickness == null
          ? base.dividerTheme
          : base.dividerTheme.copyWith(thickness: design.dividerThickness),
      cardTheme: base.cardTheme.copyWith(
        elevation: design.cardElevation,
        margin: design.cardMargin,
        shape: shape,
        color: useMaterial3 ? null : surface,
      ),
      dialogTheme: base.dialogTheme.copyWith(
        backgroundColor: useMaterial3 ? null : surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(
            // A dialog with square corners looks broken; keep a minimum.
            design.cornerRadius < 4 ? 4 : design.cornerRadius,
          ),
        ),
      ),
      appBarTheme: base.appBarTheme.copyWith(
        elevation: design.appBarElevation,
        scrolledUnderElevation: design.appBarElevation,
        centerTitle: design.centerAppBarTitle,
      ),
      inputDecorationTheme: base.inputDecorationTheme.copyWith(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(design.cornerRadius),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: design.cardElevation == 0 ? 0 : null,
          backgroundColor: design.filledButtons ? colorScheme.primary : null,
          foregroundColor: design.filledButtons ? colorScheme.onPrimary : null,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(design.cornerRadius),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(design.cornerRadius),
          ),
        ),
      ),
      floatingActionButtonTheme: base.floatingActionButtonTheme.copyWith(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(
            design.cornerRadius < 4 ? 4 : design.cornerRadius,
          ),
        ),
      ),
    );
  }
}

/// Shifts the letter spacing of every style by [delta].
///
/// `TextTheme.apply` can change the family and the size but not the spacing, so
/// the slots are mapped by hand.
TextTheme _withLetterSpacing(TextTheme theme, double delta) {
  TextStyle? shift(TextStyle? style) => style?.copyWith(
        letterSpacing: (style.letterSpacing ?? 0) + delta,
      );
  return TextTheme(
    displayLarge: shift(theme.displayLarge),
    displayMedium: shift(theme.displayMedium),
    displaySmall: shift(theme.displaySmall),
    headlineLarge: shift(theme.headlineLarge),
    headlineMedium: shift(theme.headlineMedium),
    headlineSmall: shift(theme.headlineSmall),
    titleLarge: shift(theme.titleLarge),
    titleMedium: shift(theme.titleMedium),
    titleSmall: shift(theme.titleSmall),
    bodyLarge: shift(theme.bodyLarge),
    bodyMedium: shift(theme.bodyMedium),
    bodySmall: shift(theme.bodySmall),
    labelLarge: shift(theme.labelLarge),
    labelMedium: shift(theme.labelMedium),
    labelSmall: shift(theme.labelSmall),
  );
}

/// The preset used when nothing was chosen yet: the original look.
const defaultThemePresetId = "original";

const appThemePresets = <AppThemePreset>[
  AppThemePreset(
    id: "original",
    name: "Original",
    description: "Das Aussehen der ursprünglichen App",
    swatch: Colors.deepOrange,
  ),
  AppThemePreset(
    id: "compact",
    name: "Kompakt",
    description: "Enge Zeilen, dünne Linien – mehr auf einen Blick",
    swatch: Colors.blueGrey,
    design: AppThemeDesign.compact,
  ),
  AppThemePreset(
    id: "soft",
    name: "Weich",
    description: "Runde Karten, viel Luft, mittige Titel",
    swatch: Colors.teal,
    design: AppThemeDesign.soft,
  ),
  AppThemePreset(
    id: "contrast",
    name: "Kontrast",
    description: "Kanten, kräftige Rahmen, fette Überschriften",
    swatch: Colors.indigo,
    design: AppThemeDesign.contrast,
  ),
  AppThemePreset(
    id: "paper",
    name: "Papier",
    description: "Serifenschrift auf warmem Untergrund",
    swatch: Colors.brown,
    design: AppThemeDesign.paper,
    lightScaffoldOverride: Color(0xFFF4EEE4),
    lightSurfaceOverride: Color(0xFFFBF7F0),
    darkScaffoldOverride: Color(0xFF2B2622),
    darkSurfaceOverride: Color(0xFF3A342E),
  ),
  AppThemePreset(
    id: "terminal",
    name: "Terminal",
    description: "Feste Zeichenbreite, kantig, grün auf schwarz",
    swatch: Colors.green,
    design: AppThemeDesign.mono,
    lightScaffoldOverride: Color(0xFFF2F4F2),
    lightSurfaceOverride: Colors.white,
    darkScaffoldOverride: Color(0xFF0C0F0C),
    darkSurfaceOverride: Color(0xFF151A15),
  ),
  AppThemePreset(
    id: "ocean",
    name: "Ozean",
    description: "Blau, sonst wie das Original",
    swatch: Colors.blue,
  ),
  AppThemePreset(
    id: "forest",
    name: "Wald",
    description: "Grün, sonst wie das Original",
    swatch: Colors.green,
  ),
  AppThemePreset(
    id: "grape",
    name: "Traube",
    description: "Violett, sonst wie das Original",
    swatch: Colors.deepPurple,
  ),
  AppThemePreset(
    id: "bordeaux",
    name: "Bordeaux",
    description: "Dunkelrot, sonst wie das Original",
    swatch: Colors.red,
  ),
  AppThemePreset(
    id: "midnight",
    name: "Mitternacht",
    description: "Schwarzer Hintergrund im Dunkelmodus (spart Akku auf OLED)",
    swatch: Colors.deepOrange,
    pureBlackDark: true,
  ),
  AppThemePreset(
    id: "modern",
    name: "Modern",
    description: "Material 3 — flächiger, alles in einem Farbton",
    swatch: Colors.deepOrange,
    design: AppThemeDesign.material3,
    useMaterial3: true,
  ),
];

/// The preset with [id], falling back to the default for unknown ids.
AppThemePreset themePresetById(String? id) {
  for (final preset in appThemePresets) {
    if (preset.id == id) return preset;
  }
  return appThemePresets.first;
}
