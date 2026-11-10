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

/// A text or a link a teacher attached to a test, a homework or a lesson.
///
/// The register sends these next to files ("gradeGroupSubmissions" and
/// "lessonContentSubmissions" with `type` "text" or "link"); files keep their
/// own widget with open, save and copy.
library;

import 'package:dr/ui/link_text.dart';
import 'package:dr/ui/messages.dart' show plainTextOfMessage;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// The text of a text attachment: a Quill delta like a message, or plain
/// text should the register ever send that.
String teacherAttachmentText(String? text) {
  if (text == null || text.trim().isEmpty) return "";
  final plain = plainTextOfMessage(text);
  return plain.isNotEmpty || text.trimLeft().startsWith("{") ? plain : text;
}

class TeacherAttachment extends StatelessWidget {
  const TeacherAttachment({
    super.key,
    required this.type,
    this.title,
    this.text,
    this.link,
  });

  /// "text" or "link".
  final String? type;
  final String? title;
  final String? text;
  final String? link;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLink = type == "link";
    final body = isLink ? (link ?? "") : teacherAttachmentText(text);
    final heading = title?.trim().isNotEmpty == true
        ? title!.trim()
        : (isLink ? "Link" : "Text");
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(
            isLink ? Icons.link : Icons.notes,
            size: 20,
            color: Colors.grey,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                heading,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              if (isLink && body.isNotEmpty)
                InkWell(
                  onTap: () => launchUrl(
                    Uri.parse(body.toLowerCase().startsWith("www.")
                        ? "https://$body"
                        : body),
                    mode: LaunchMode.externalApplication,
                  ),
                  child: Text(
                    body,
                    style: TextStyle(
                      color: theme.colorScheme.primary,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                )
              else if (body.isNotEmpty)
                LinkText(body),
            ],
          ),
        ),
      ],
    );
  }
}
