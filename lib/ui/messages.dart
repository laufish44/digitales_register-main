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

import 'dart:convert';

import 'package:badges/badges.dart' as badge;
import 'package:dr/app_state.dart';
import 'package:dr/data.dart';
import 'package:dr/ui/animated_linear_progress_indicator.dart';
import 'package:dr/ui/attachment_actions.dart';
import 'package:dr/ui/last_fetched_overlay.dart';
import 'package:dr/ui/message_compose.dart';
import 'package:dr/ui/no_internet.dart';
import 'package:share_plus/share_plus.dart';
import 'package:dr/util.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:quill_delta/quill_delta.dart';
import 'package:quill_delta_viewer/quill_delta_viewer.dart';
import 'package:responsive_scaffold/responsive_scaffold.dart';

class MessagesPage extends StatelessWidget {
  final MessagesState? state;
  final bool noInternet;
  final bool composeEnabled;
  final void Function(MessageAttachmentFile message) onOpenFile;
  final void Function(MessageAttachmentFile message) onSaveFileAs;
  final void Function(MessageAttachmentFile message) onCopyFile;
  final void Function(Message message) onMarkAsRead;
  final VoidCallback onMessageSent;

  const MessagesPage({
    super.key,
    required this.state,
    required this.noInternet,
    required this.composeEnabled,
    required this.onOpenFile,
    required this.onSaveFileAs,
    required this.onCopyFile,
    required this.onMarkAsRead,
    required this.onMessageSent,
  });
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const ResponsiveAppBar(
        title: Text("Mitteilungen"),
      ),
      floatingActionButton: composeEnabled
          ? FloatingActionButton.extended(
              onPressed: () async {
                if (await showComposeMessage(context)) onMessageSent();
              },
              icon: const Icon(Icons.edit),
              label: const Text("Schreiben"),
            )
          : null,
      body: state == null
          ? noInternet
              ? const NoInternet()
              : const Center(child: CircularProgressIndicator())
          : LastFetchedOverlay(
              lastFetched: state!.lastFetched,
              noInternet: noInternet,
              child: Stack(
                children: <Widget>[
                  AnimatedLinearProgressIndicator(
                    show: state!.showMessage != null &&
                        !state!.messages.any((m) => m.id == state!.showMessage),
                  ),
                  if (state!.messages.isEmpty)
                    Center(
                      child: Text(
                        "Noch keine Mitteilungen",
                        style: Theme.of(context).textTheme.headlineMedium,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ListView.builder(
                    itemCount: state!.messages.length,
                    itemBuilder: (context, i) {
                      return MessageWidget(
                        message: state!.messages[i],
                        onOpenFile: onOpenFile,
                        onSaveFileAs: onSaveFileAs,
                        onCopyFile: onCopyFile,
                        onMarkAsRead: onMarkAsRead,
                        noInternet: noInternet,
                        expand: state!.messages[i].id == state!.showMessage,
                        composeEnabled: composeEnabled,
                        onMessageSent: onMessageSent,
                      );
                    },
                  ),
                ],
              ),
            ),
    );
  }
}

class MessageWidget extends StatefulWidget {
  final Message message;
  final void Function(MessageAttachmentFile message) onOpenFile;
  final void Function(MessageAttachmentFile message) onSaveFileAs;
  final void Function(MessageAttachmentFile message) onCopyFile;
  final void Function(Message message) onMarkAsRead;
  final bool noInternet;
  final bool expand;

  /// Whether replying and forwarding are offered.
  final bool composeEnabled;
  final VoidCallback onMessageSent;

  const MessageWidget({
    super.key,
    required this.message,
    required this.onOpenFile,
    required this.onSaveFileAs,
    required this.onCopyFile,
    required this.noInternet,
    required this.onMarkAsRead,
    required this.expand,
    required this.composeEnabled,
    required this.onMessageSent,
  });

  @override
  _MessageWidgetState createState() => _MessageWidgetState();
}

class _MessageWidgetState extends State<MessageWidget> {
  late final bool initiallyExpanded;
  @override
  void initState() {
    initiallyExpanded = widget.expand;
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    if (initiallyExpanded) {
      widget.onMarkAsRead(widget.message);
    }
    final textTheme = Theme.of(context).textTheme;
    return ExpansionTile(
      initiallyExpanded: initiallyExpanded,
      onExpansionChanged: (expanded) {
        if (expanded && widget.message.isNew) {
          widget.onMarkAsRead(widget.message);
        }
      },
      title: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              widget.message.subject,
              style: textTheme.titleMedium,
            ),
          ),
          // Only the message's own state decides this. It used to also show
          // for whatever message was opened from a notification, which marked
          // an already read message as new.
          if (widget.message.isNew)
            badge.Badge(
              badgeStyle: badge.BadgeStyle(
                shape: badge.BadgeShape.square,
                borderRadius: BorderRadius.circular(20),
                badgeColor: widget.message.needsAction
                    ? Colors.orange
                    : Theme.of(context).colorScheme.error,
              ),
              badgeContent: Text(
                // A message that was opened but still waits for an answer or a
                // signature stays flagged - saying "neu" would be misleading.
                widget.message.needsAction ? "offen" : "neu",
                style: const TextStyle(color: Colors.white),
              ),
            )
        ],
      ),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: 16,
          ).copyWith(
            bottom: 8,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text.rich(
                TextSpan(
                  children: [
                    const TextSpan(
                      text: "Gesendet: ",
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    TextSpan(
                        text: DateFormat("d.M.yy H:mm")
                            .format(widget.message.timeSent))
                  ],
                ),
              ),
              Text.rich(
                TextSpan(
                  children: [
                    const TextSpan(
                      text: "Von: ",
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    TextSpan(text: widget.message.fromName)
                  ],
                ),
              ),
              Text.rich(
                TextSpan(
                  children: [
                    const TextSpan(
                      text: "An: ",
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    TextSpan(text: widget.message.recipientString)
                  ],
                ),
              ),
              if (widget.message.needsAction)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    children: [
                      const Icon(Icons.pending_actions,
                          size: 18, color: Colors.orange),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          widget.message.responseRequired &&
                                  widget.message.response == null
                              ? "Diese Mitteilung erwartet eine Antwort. "
                                  "Bitte über die Website beantworten."
                              : "Diese Mitteilung muss noch unterschrieben "
                                  "werden. Bitte über die Website erledigen.",
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),
              const Divider(),
              renderMessage(widget.message.text, context),
              if (widget.message.attachments.isNotEmpty) ...[
                const Divider(),
                Text(
                  widget.message.attachments.length > 1
                      ? "Anhänge:"
                      : "Anhang:",
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
              ...[
                for (final attachment in widget.message.attachments)
                  [
                    AttachmentActions(
                      name: attachment.originalName,
                      // Without the file cached there is nothing to open, save
                      // or copy until it can be fetched.
                      enabled:
                          attachment.fileAvailable || !widget.noInternet,
                      onOpen: () => widget.onOpenFile(attachment),
                      onSaveAs: () => widget.onSaveFileAs(attachment),
                      onCopy: () => widget.onCopyFile(attachment),
                    ),
                    AnimatedLinearProgressIndicator(
                      show: attachment.downloading,
                    ),
                  ]
              ].intersperse(const Divider()),
              if (widget.composeEnabled) ...[
                const Divider(),
                Wrap(
                  spacing: 8,
                  children: [
                    if (widget.message.fromUserId != null)
                      TextButton.icon(
                        onPressed: () => _compose(ComposeMode.reply),
                        icon: const Icon(Icons.reply, size: 20),
                        label: const Text("Antworten"),
                      ),
                    TextButton.icon(
                      onPressed: () => _compose(ComposeMode.forward),
                      icon: const Icon(Icons.forward, size: 20),
                      label: const Text("Weiterleiten"),
                    ),
                    TextButton.icon(
                      onPressed: _share,
                      icon: const Icon(Icons.ios_share, size: 20),
                      label: const Text("Teilen / Drucken"),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _compose(ComposeMode mode) async {
    if (await showComposeMessage(context,
        mode: mode, source: widget.message)) {
      widget.onMessageSent();
    }
  }

  /// Hands the message to the system's share sheet, from where it can also be
  /// printed or saved as a PDF.
  Future<void> _share() async {
    final body = StringBuffer()
      ..writeln(widget.message.subject)
      ..writeln()
      ..writeln("Von: ${widget.message.fromName}")
      ..writeln("An: ${widget.message.recipientString}")
      ..writeln(
          "Gesendet: ${DateFormat("d.M.yy H:mm").format(widget.message.timeSent)}")
      ..writeln()
      ..writeln(plainTextOfMessage(widget.message.text));
    await shareText(
      text: body.toString(),
      subject: widget.message.subject,
      context: context,
    );
  }
}

Widget renderMessage(String msg, BuildContext context) {
  return QuillDeltaViewer(
      delta: Delta.fromJson(jsonDecode(msg)["ops"] as List));
}

/// Opens the system share sheet, which is also the route to printing and to
/// saving as a PDF on both Windows and Android.
Future<void> shareText({
  required String text,
  required String subject,
  required BuildContext context,
}) async {
  // iPads position the share sheet relative to the widget that opened it.
  final box = context.findRenderObject() as RenderBox?;
  await Share.share(
    text,
    subject: subject,
    sharePositionOrigin:
        box == null ? null : box.localToGlobal(Offset.zero) & box.size,
  );
}

/// The message body as plain text, for quoting, sharing and printing.
///
/// Messages are stored as Quill deltas; anything that is not a plain string
/// insert (an image, say) is skipped rather than shown as raw json.
String plainTextOfMessage(String msg) {
  try {
    final buffer = StringBuffer();
    for (final op in Delta.fromJson(jsonDecode(msg)["ops"] as List).toList()) {
      final data = op.data;
      if (data is String) buffer.write(data);
    }
    return buffer.toString().trim();
  } catch (_) {
    return "";
  }
}
