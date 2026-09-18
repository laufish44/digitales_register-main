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

part of 'middleware.dart';

final _certificateMiddleware =
    MiddlewareBuilder<AppState, AppStateBuilder, AppActions>()
      ..add(CertificateActionsNames.load, _loadCertificate);

Future<void> _loadCertificate(
    MiddlewareApi<AppState, AppStateBuilder, AppActions> api,
    ActionHandler next,
    Action<void> action) async {
  if (api.state.noInternet) return;
  await next(action);
  final dynamic response =
      await wrapper.send("student/certificate", method: "GET");
  if (response == null) return;

  final html = response as String;
  if (looksLikeLoginPage(html)) {
    // The server answers unknown paths with the login page. "v2/student/
    // certificate" no longer exists on every installation, and the web app does
    // not use it any more either, so showing the raw login markup would just
    // confuse the user.
    log("certificate endpoint returned the login page");
    await api.actions.certificateActions.unavailable();
    return;
  }
  await api.actions.certificateActions.loaded(html);
}

/// Whether a server response is really the login page.
///
/// The register serves it for unknown routes and for expired sessions, with a
/// 200 status, so the content has to be inspected.
@visibleForTesting
bool looksLikeLoginPage(String html) {
  const markers = [
    "Anmelden mit Username",
    "{{error_spid}}",
    'ng-app="loginApp"',
    "Passwort vergessen",
  ];
  var hits = 0;
  for (final marker in markers) {
    if (html.contains(marker)) hits++;
  }
  // Two independent markers keep a certificate that merely mentions one of
  // these words from being mistaken for the login page.
  return hits >= 2;
}
