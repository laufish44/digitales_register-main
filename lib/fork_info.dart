// Copyright (C) 2021 Michael Debertol
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

/// Who made this build and where its source lives.
///
/// This is a fork. The GPL requires that the source offered to users is the
/// source of the binary they are actually running, so the "Zum Quellcode" link
/// points here rather than at the original project — and the original is named
/// right next to it, which the licence also requires.
library;

/// The name shown in the about box.
const forkDisplayName = "Digitales Register";

/// The repository this build was made from.
///
/// Empty until the fork has a home; the about box then falls back to the
/// original project so the source is still reachable.
const forkSourceUrl = String.fromEnvironment("DR_SOURCE_URL");

/// Who maintains this fork.
const forkAuthor = "Laurin Feichter";

/// Line under the version in the about box.
const forkLegalese = "Copyright Michael Debertol und Simon Wachtler 2019-2022\n"
    "Änderungen dieser Version © 2026 $forkAuthor\n"
    "GNU General Public License v3";

/// The project this one is built on.
const upstreamName = "Michael Debertol";
const upstreamUrl = "https://github.com/miDeb/digitales_register";
const upstreamAuthorUrl = "https://blog.debertol.com";

/// Where "Zum Quellcode" goes.
String get sourceUrl => forkSourceUrl.isEmpty ? upstreamUrl : forkSourceUrl;

/// Whether this build knows its own repository.
bool get hasOwnSource => forkSourceUrl.isNotEmpty;
