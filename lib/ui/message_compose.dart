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

/// The screen for writing a new message.
///
/// Recipients are picked in two steps, exactly as on the website: first the
/// groups (a class, a teacher), then the individual people within them.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dr/api/message_compose_api.dart';
import 'package:dr/data.dart';
import 'package:dr/ui/messages.dart' show plainTextOfMessage;
import 'package:dr/util.dart' show getList, getMap;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

/// How the compose screen was opened.
enum ComposeMode { newMessage, reply, forward }

/// Opens the compose screen. Returns true if a message was sent.
///
/// For [ComposeMode.reply] the sender of [source] is preselected as recipient;
/// for [ComposeMode.forward] the subject and body are carried over and the
/// recipients are left empty.
Future<bool> showComposeMessage(
  BuildContext context, {
  ComposeMode mode = ComposeMode.newMessage,
  Message? source,
}) async {
  final sent = await Navigator.of(context).push<bool>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => MessageComposePage(mode: mode, source: source),
    ),
  );
  return sent ?? false;
}

class MessageComposePage extends StatefulWidget {
  const MessageComposePage({
    super.key,
    this.api = const MessageComposeApi(),
    this.mode = ComposeMode.newMessage,
    this.source,
  });

  final MessageComposeApi api;
  final ComposeMode mode;
  final Message? source;

  @override
  State<MessageComposePage> createState() => _MessageComposePageState();
}

class _MessageComposePageState extends State<MessageComposePage> {
  final searchController = TextEditingController();
  final subjectController = TextEditingController();
  final textController = TextEditingController();

  final selectedGroups = <RecipientGroup>[];
  List<RecipientGroup> searchResults = const [];
  List<RecipientDetailGroup> detailGroups = const [];

  MessageTypes? types;
  MessageSendType? selectedType;
  MessagePermission? selectedPermission;

  Timer? searchDebounce;
  bool searching = false;
  bool loadingDetails = false;
  bool sending = false;
  int step = 0;
  String? error;

  /// Files to send along: uploaded ones and, when forwarding, those of the
  /// original message — as the website does (#24).
  final attachments = <MessageAttachmentDraft>[];
  bool uploading = false;

  /// Whether the answered or forwarded message goes below the text, in
  /// italics, as in an e-mail (#24).
  bool includeQuote = true;

  @override
  void initState() {
    super.initState();
    unawaited(_loadTypes());
    _prefillFromSource();
  }

  /// Carries subject, body and recipients over when replying or forwarding.
  void _prefillFromSource() {
    final source = widget.source;
    if (source == null) return;

    final prefix = widget.mode == ComposeMode.reply ? "AW: " : "WG: ";
    final subject = source.subject;
    subjectController.text =
        subject.toLowerCase().startsWith(prefix.toLowerCase())
            ? subject
            : "$prefix$subject";

    if (widget.mode == ComposeMode.forward) {
      // The original's text goes below as a quote when sending (see
      // _quoteOps); its files come along, as on the website.
      attachments.addAll([
        for (final file in source.attachments)
          MessageAttachmentDraft.forwarded(
            sourceMessageId: source.id,
            sourceSubmissionId: file.id,
            name: file.originalName,
          ),
      ]);
    }

    if (widget.mode == ComposeMode.reply && source.fromUserId != null) {
      unawaited(_prefillRecipient(source.fromUserId!));
    }
  }

  Future<void> _prefillRecipient(int userId) async {
    final groups = await widget.api.initialRecipients([userId]);
    if (!mounted || groups.isEmpty) return;
    setState(() => selectedGroups.addAll(groups));
    // The recipients are known, so go straight to writing.
    await _goToStep2();
  }

  @override
  void dispose() {
    searchDebounce?.cancel();
    searchController.dispose();
    subjectController.dispose();
    textController.dispose();
    super.dispose();
  }

  Future<void> _loadTypes() async {
    final loaded = await widget.api.loadTypes();
    if (!mounted) return;
    setState(() {
      types = loaded;
      selectedType =
          loaded?.types.isNotEmpty ?? false ? loaded!.types.first : null;
      selectedPermission = loaded?.permissions.isNotEmpty ?? false
          ? loaded!.permissions.first
          : null;
    });
  }

  void _onSearchChanged(String value) {
    searchDebounce?.cancel();
    if (value.trim().length < 2) {
      setState(() => searchResults = const []);
      return;
    }
    searchDebounce = Timer(const Duration(milliseconds: 350), () async {
      setState(() => searching = true);
      final results = await widget.api.searchRecipients(value);
      if (!mounted) return;
      setState(() {
        searching = false;
        searchResults = results
            .where((r) => !selectedGroups.any((s) => s.sameAs(r)))
            .toList();
      });
    });
  }

  Future<void> _goToStep2() async {
    setState(() {
      loadingDetails = true;
      error = null;
    });
    final details = await widget.api.loadDetails(selectedGroups);
    if (!mounted) return;
    setState(() {
      loadingDetails = false;
      if (details == null) {
        error = "Die Empfänger konnten nicht geladen werden";
      } else {
        detailGroups = details.groups;
        step = 1;
      }
    });
  }

  int get _selectedRecipientCount => detailGroups.fold(
        0,
        (sum, g) => sum + g.details.where((d) => d.selected).length,
      );

  bool get _canSend =>
      subjectController.text.trim().isNotEmpty &&
      textController.text.trim().isNotEmpty &&
      _selectedRecipientCount > 0 &&
      selectedType != null &&
      selectedPermission != null &&
      !sending;

  String get _quoteTitle => widget.mode == ComposeMode.forward
      ? "Weitergeleitete Mitteilung:"
      : "Antwort auf die Mitteilung:";

  /// The original message as Quill operations, or null when it is not to be
  /// quoted.
  List<dynamic>? get _quote {
    final source = widget.source;
    if (source == null || !includeQuote) return null;
    try {
      return getList(getMap(jsonDecode(source.text))?["ops"]);
    } catch (_) {
      return [
        {"insert": "${plainTextOfMessage(source.text)}\n"}
      ];
    }
  }

  Future<void> _addFiles() async {
    final picked = await FilePicker.pickFiles(allowMultiple: true);
    if (picked == null || !mounted) return;
    setState(() {
      uploading = true;
      error = null;
    });
    for (final file in picked.files) {
      final path = file.path;
      if (path == null) continue;
      final result = await widget.api.uploadAttachment(File(path));
      if (!mounted) return;
      setState(() {
        if (result.attachment != null) {
          attachments.add(result.attachment!);
        } else {
          error = "${file.name}: ${result.error}";
        }
      });
    }
    if (mounted) setState(() => uploading = false);
  }

  Widget _attachmentSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final a in attachments)
              InputChip(
                avatar: Icon(a.isForwarded ? Icons.forward : Icons.attach_file,
                    size: 18),
                label: Text(a.name),
                onDeleted: () => setState(() => attachments.remove(a)),
              ),
          ],
        ),
        TextButton.icon(
          onPressed: uploading || sending ? null : _addFiles,
          icon: uploading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.attach_file),
          label: Text(uploading ? "Wird hochgeladen …" : "Datei anhängen"),
        ),
        if (widget.source != null && widget.mode != ComposeMode.newMessage)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(widget.mode == ComposeMode.forward
                ? "Ursprüngliche Mitteilung unten anfügen"
                : "Mitteilung, auf die du antwortest, unten anfügen"),
            subtitle: includeQuote
                ? Text(
                    "$_quoteTitle ${plainTextOfMessage(widget.source!.text)}",
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontStyle: FontStyle.italic),
                  )
                : null,
            value: includeQuote,
            onChanged: (value) => setState(() => includeQuote = value),
          ),
      ],
    );
  }

  Future<void> _send() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Mitteilung senden?"),
        content: Text(
          "Die Mitteilung geht an $_selectedRecipientCount "
          "${_selectedRecipientCount == 1 ? "Person" : "Personen"} "
          "und kann nicht zurückgenommen werden.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Abbrechen"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Senden"),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      sending = true;
      error = null;
    });
    final failure = await widget.api.send(
      recipients: detailGroups,
      subject: subjectController.text.trim(),
      text: textController.text.trim(),
      type: selectedType!,
      permission: selectedPermission!,
      attachments: attachments,
      quoteTitle: _quote == null ? null : _quoteTitle,
      quote: _quote,
    );
    if (!mounted) return;
    setState(() => sending = false);
    if (failure == null) {
      Navigator.pop(context, true);
    } else {
      setState(() => error = failure);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          step == 0
              ? "Empfänger wählen"
              : switch (widget.mode) {
                  ComposeMode.reply => "Antworten",
                  ComposeMode.forward => "Weiterleiten",
                  ComposeMode.newMessage => "Neue Mitteilung",
                },
        ),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => step == 1
              ? setState(() => step = 0)
              : Navigator.pop(context, false),
        ),
      ),
      body: Column(
        children: [
          if (error != null)
            MaterialBanner(
              backgroundColor: Theme.of(context).colorScheme.errorContainer,
              content: Text(error!),
              actions: [
                TextButton(
                  onPressed: () => setState(() => error = null),
                  child: const Text("OK"),
                ),
              ],
            ),
          // Keyed, so the fields keep their state and focus when the error
          // banner above comes or goes.
          Expanded(
            key: const ValueKey("compose"),
            child: step == 0 ? _buildStep1() : _buildStep2(),
          ),
        ],
      ),
      floatingActionButton: step == 0
          ? FloatingActionButton.extended(
              onPressed:
                  selectedGroups.isEmpty || loadingDetails ? null : _goToStep2,
              icon: loadingDetails
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.arrow_forward),
              label: const Text("Weiter"),
            )
          : ListenableBuilder(
              listenable: Listenable.merge([subjectController, textController]),
              builder: (context, _) => FloatingActionButton.extended(
                onPressed: _canSend ? _send : null,
                icon: sending
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send),
                label: const Text("Senden"),
              ),
            ),
    );
  }

  Widget _buildStep1() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            controller: searchController,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              labelText: "Empfänger suchen",
              hintText: "Name, Klasse, ...",
              prefixIcon: const Icon(Icons.search),
              suffixIcon: searching
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : null,
            ),
            onChanged: _onSearchChanged,
          ),
        ),
        if (selectedGroups.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final group in selectedGroups)
                    Chip(
                      label: Text(group.label),
                      onDeleted: () => setState(() {
                        selectedGroups.removeWhere((g) => g.sameAs(group));
                      }),
                    ),
                ],
              ),
            ),
          ),
        const Divider(),
        Expanded(
          child: searchResults.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      searchController.text.trim().length < 2
                          ? "Tippe mindestens zwei Zeichen, um zu suchen."
                          : searching
                              ? ""
                              : "Keine Empfänger gefunden.",
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : ListView.builder(
                  itemCount: searchResults.length,
                  itemBuilder: (context, index) {
                    final group = searchResults[index];
                    return ListTile(
                      title: Text(group.label),
                      subtitle:
                          group.sublabel == null ? null : Text(group.sublabel!),
                      trailing: const Icon(Icons.add),
                      onTap: () => setState(() {
                        selectedGroups.add(group);
                        searchResults = searchResults
                            .where((r) => !r.sameAs(group))
                            .toList();
                      }),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildStep2() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      children: [
        // No setState per keystroke: rebuilding the page (recipient list
        // included) on every letter made the keyboard slow to come back on
        // Android, and the second tap then selected text (#19). Only the send
        // button listens to the fields.
        TextField(
          controller: subjectController,
          textCapitalization: TextCapitalization.sentences,
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(labelText: "Betreff"),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: textController,
          textCapitalization: TextCapitalization.sentences,
          keyboardType: TextInputType.multiline,
          decoration: const InputDecoration(
            labelText: "Nachricht",
            alignLabelWithHint: true,
          ),
          minLines: 6,
          maxLines: 14,
        ),
        const SizedBox(height: 8),
        _attachmentSection(),
        const SizedBox(height: 8),
        if (types != null && types!.types.length > 1)
          DropdownButtonFormField<MessageSendType>(
            value: selectedType,
            decoration: const InputDecoration(labelText: "Art"),
            items: [
              for (final type in types!.types)
                DropdownMenuItem(value: type, child: Text(type.label)),
            ],
            onChanged: (value) => setState(() => selectedType = value),
          ),
        if (types != null && types!.permissions.length > 1) ...[
          const SizedBox(height: 12),
          DropdownButtonFormField<MessagePermission>(
            value: selectedPermission,
            decoration: const InputDecoration(labelText: "Sichtbarkeit"),
            items: [
              for (final permission in types!.permissions)
                DropdownMenuItem(
                    value: permission, child: Text(permission.label)),
            ],
            onChanged: (value) => setState(() => selectedPermission = value),
          ),
        ],
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: Text(
                "Empfänger ($_selectedRecipientCount)",
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            TextButton(
              onPressed: () => setState(() {
                for (final group in detailGroups) {
                  for (final detail in group.details) {
                    if (!detail.disabled) detail.selected = true;
                  }
                }
              }),
              child: const Text("Alle"),
            ),
            TextButton(
              onPressed: () => setState(() {
                for (final group in detailGroups) {
                  for (final detail in group.details) {
                    detail.selected = false;
                  }
                }
              }),
              child: const Text("Keine"),
            ),
          ],
        ),
        for (final group in detailGroups)
          ExpansionTile(
            title: Text(group.label),
            subtitle: Text(
              "${group.details.where((d) => d.selected).length} von ${group.details.length} ausgewählt",
            ),
            children: [
              for (final detail in group.details)
                CheckboxListTile(
                  dense: true,
                  title: Text(detail.label),
                  value: detail.selected,
                  onChanged: detail.disabled
                      ? null
                      : (value) =>
                          setState(() => detail.selected = value ?? false),
                ),
            ],
          ),
      ],
    );
  }
}
