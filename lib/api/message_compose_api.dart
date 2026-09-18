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

/// Writing a message, mirroring what the web app's compose dialog does.
///
/// The flow the server expects is three steps:
///  1. `getRecipients` turns a search string into *recipient groups*
///     (a class, a teacher, a parent group, ...), each identified by
///     `{id, type}`.
///  2. `getRecipientsDetails` expands the chosen groups into the individual
///     people, each with a `selected` and a `disabled` flag.
///  3. `sendMessage` takes that (possibly edited) structure back, plus the
///     message itself.
///
/// The groups and details are passed through untouched: the server invented
/// them and only it needs to understand every field. This app only reads the
/// few keys it has to display or toggle, which keeps it working even when the
/// server adds fields.
///
/// This is deliberately a plain service rather than redux state: the whole
/// flow is transient, lives only while the compose screen is open, and none of
/// it is worth persisting.
library;

import 'dart:convert';
import 'dart:developer';

import 'package:dr/middleware/middleware.dart';
import 'package:dr/util.dart';

/// A group of recipients as the server describes it.
class RecipientGroup {
  RecipientGroup(this.raw);

  final Map<dynamic, dynamic> raw;

  Object? get id => raw["id"];
  Object? get type => raw["type"];

  /// A human readable label. The server is not consistent about which key
  /// holds it, so the likely candidates are tried in turn.
  String get label {
    for (final key in const ["name", "title", "label", "fullName", "text"]) {
      final value = raw[key];
      if (value is String && value.trim().isNotEmpty) return value;
    }
    return id?.toString() ?? "Unbekannt";
  }

  /// An extra line of context, e.g. the class or the role.
  String? get sublabel {
    for (final key in const ["typeName", "description", "roleName", "info"]) {
      final value = raw[key];
      if (value is String && value.trim().isNotEmpty) return value;
    }
    return null;
  }

  bool sameAs(RecipientGroup other) =>
      id == other.id && type == other.type;
}

/// One expanded group with the individual people in it.
class RecipientDetailGroup {
  RecipientDetailGroup(this.raw)
      : details = (getList(raw["details"]) ?? const [])
            .map((dynamic d) => RecipientDetail(getMap(d) ?? {}))
            .toList();

  final Map<dynamic, dynamic> raw;
  final List<RecipientDetail> details;

  String get label {
    for (final key in const ["name", "title", "label", "typeName"]) {
      final value = raw[key];
      if (value is String && value.trim().isNotEmpty) return value;
    }
    return "Empfänger";
  }

  /// The group, with the current selection written back into it.
  Map<dynamic, dynamic> toJson() => {
        ...raw,
        "details": details.map((d) => d.toJson()).toList(),
      };
}

class RecipientDetail {
  RecipientDetail(this.raw)
      : selected = raw["selected"] == true,
        disabled = raw["disabled"] == true;

  final Map<dynamic, dynamic> raw;
  bool selected;
  final bool disabled;

  String get label {
    for (final key in const ["name", "fullName", "title", "label"]) {
      final value = raw[key];
      if (value is String && value.trim().isNotEmpty) return value;
    }
    return raw["id"]?.toString() ?? "Unbekannt";
  }

  Map<dynamic, dynamic> toJson() => {...raw, "selected": selected};
}

/// A message type ("Mitteilung", "Entschuldigung", ...).
class MessageSendType {
  MessageSendType(this.raw);

  final Map<dynamic, dynamic> raw;

  Object? get typeId => raw["typeId"] ?? raw["id"];
  bool get signatureRequired => raw["signatureRequired"] == true;
  bool get responseRequired => raw["responseRequired"] == true;

  String get label {
    for (final key in const ["name", "title", "label", "typeName"]) {
      final value = raw[key];
      if (value is String && value.trim().isNotEmpty) return value;
    }
    return typeId?.toString() ?? "Standard";
  }
}

/// Who may see the message.
class MessagePermission {
  MessagePermission(this.raw);

  final Map<dynamic, dynamic> raw;

  Object? get id => raw["id"];

  String get label {
    for (final key in const ["name", "title", "label"]) {
      final value = raw[key];
      if (value is String && value.trim().isNotEmpty) return value;
    }
    return id?.toString() ?? "Standard";
  }
}

class MessageTypes {
  MessageTypes({required this.types, required this.permissions});

  final List<MessageSendType> types;
  final List<MessagePermission> permissions;
}

class MessageComposeApi {
  const MessageComposeApi();

  /// The available message types and visibility options.
  Future<MessageTypes?> loadTypes() async {
    final dynamic response =
        await sendApiRequest("api/message/getTypes", args: const {});
    final map = getMap(response);
    if (map == null) return null;
    return MessageTypes(
      types: (getList(map["types"]) ?? const [])
          .map((dynamic t) => MessageSendType(getMap(t) ?? {}))
          .toList(),
      permissions: (getList(map["permissions"]) ?? const [])
          .map((dynamic p) => MessagePermission(getMap(p) ?? {}))
          .toList(),
    );
  }

  /// Turns user ids into recipient groups, used when replying.
  ///
  /// The web app calls this with the sender of the message being answered.
  Future<List<RecipientGroup>> initialRecipients(List<int> userIds) async {
    if (userIds.isEmpty) return const [];
    final dynamic response = await sendApiRequest(
      "api/message/getInitialRecipients",
      args: {"initialRecipientIds": userIds},
    );
    return (getList(response) ?? const [])
        .map((dynamic r) => RecipientGroup(getMap(r) ?? {}))
        .toList();
  }

  /// Searches for recipients. The web app only queries from two characters on.
  Future<List<RecipientGroup>> searchRecipients(String filter) async {
    if (filter.trim().length < 2) return const [];
    final dynamic response = await sendApiRequest(
      "api/message/getRecipients",
      args: {"filter": filter},
    );
    return (getList(response) ?? const [])
        .map((dynamic r) => RecipientGroup(getMap(r) ?? {}))
        .toList();
  }

  /// Expands the chosen groups into individual recipients.
  Future<({int total, List<RecipientDetailGroup> groups})?> loadDetails(
    List<RecipientGroup> groups,
  ) async {
    final dynamic response = await sendApiRequest(
      "api/message/getRecipientsDetails",
      args: {"recipientGroups": groups.map((g) => g.raw).toList()},
    );
    final map = getMap(response);
    if (map == null) return null;
    return (
      total: getInt(map["recipientsNumber"]) ?? 0,
      groups: (getList(map["recipientsDetails"]) ?? const [])
          .map((dynamic d) => RecipientDetailGroup(getMap(d) ?? {}))
          .toList(),
    );
  }

  /// Sends the message. Returns null on success, or a message to show.
  Future<String?> send({
    required List<RecipientDetailGroup> recipients,
    required String subject,
    required String text,
    required MessageSendType type,
    required MessagePermission permission,
  }) async {
    final dynamic response = await sendApiRequest(
      "api/message/sendMessage",
      args: {
        "recipientsDetails": recipients.map((r) => r.toJson()).toList(),
        "message": <String, Object?>{
          "subject": subject,
          // The web app stores the body as a Quill delta, and the message list
          // renders it as one, so a plain paragraph has to be wrapped as well.
          "text": json.encode({
            "ops": [
              {"insert": text.endsWith("\n") ? text : "$text\n"}
            ]
          }),
          "signatureRequired": type.signatureRequired,
          "responseRequired": type.responseRequired,
          "responseType": type.typeId,
          "permission": permission.id,
          "submissions": const <Object>[],
        },
      },
    );
    final map = getMap(response);
    if (map == null) return "Keine Antwort vom Server";
    if (map["success"] == true) return null;
    final error = getString(map["error"]);
    log("sendMessage failed: $error");
    return error == null
        ? "Die Mitteilung konnte nicht gesendet werden"
        : "Die Mitteilung wurde abgelehnt ($error)";
  }
}
