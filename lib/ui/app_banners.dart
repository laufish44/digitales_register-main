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

/// Banners at the top of the app instead of dialogs in its way: a new
/// version, and notices from the remote config. Both can be ignored — the app
/// stays usable underneath.
library;

import 'package:dr/main.dart';
import 'package:dr/remote_config.dart';
import 'package:dr/ui/update_dialog.dart';
import 'package:dr/update/update_service.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

void _hide() => scaffoldMessengerKey?.currentState?.hideCurrentMaterialBanner();

/// "Version X ist da" with a button that installs it right away.
void showUpdateBanner(UpdateInfo info) {
  final messenger = scaffoldMessengerKey?.currentState;
  if (messenger == null) return;
  messenger.showMaterialBanner(
    MaterialBanner(
      leading: const Icon(Icons.system_update),
      content: Text("Version ${info.version} ist da."),
      actions: [
        TextButton(onPressed: _hide, child: const Text("Später")),
        if (info.notes != null && info.notes!.trim().isNotEmpty)
          TextButton(
            onPressed: () {
              _hide();
              final context = navigatorKey?.currentContext;
              if (context != null) showUpdateDialog(context, info);
            },
            child: const Text("Neuigkeiten"),
          ),
        if (info.build != null)
          FilledButton(
            onPressed: () {
              _hide();
              final context = navigatorKey?.currentContext;
              if (context != null) {
                showUpdateDialog(context, info, startRightAway: true);
              }
            },
            child: const Text("Aktualisieren"),
          ),
      ],
    ),
  );
}

/// Shows [notices] one after the other; each is marked as seen once closed,
/// so it does not come back.
void showRemoteNotices(List<RemoteNotice> notices) {
  final messenger = scaffoldMessengerKey?.currentState;
  if (messenger == null) return;
  for (final notice in notices) {
    void close() {
      RemoteConfig.markSeen(notice.id);
      _hide();
    }

    messenger.showMaterialBanner(
      MaterialBanner(
        leading: const Icon(Icons.campaign_outlined),
        content: Text.rich(
          TextSpan(children: [
            if (notice.title != null)
              TextSpan(
                text: "${notice.title}\n",
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            TextSpan(text: notice.text),
          ]),
        ),
        actions: [
          if (notice.url != null)
            TextButton(
              onPressed: () {
                launchUrl(Uri.parse(notice.url!),
                    mode: LaunchMode.externalApplication);
                close();
              },
              child: const Text("Öffnen"),
            ),
          TextButton(onPressed: close, child: const Text("OK")),
        ],
      ),
    );
  }
}
