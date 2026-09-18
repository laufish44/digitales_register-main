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

import 'package:built_redux/built_redux.dart';
import 'package:built_value/built_value.dart';

import 'package:dr/data.dart';
import 'package:dr/utc_date_time.dart';

part 'messages_actions.g.dart';

abstract class MessagesActions extends ReduxActions {
  factory MessagesActions() => _$MessagesActions();
  MessagesActions._();

  abstract final VoidActionDispatcher load;
  abstract final ActionDispatcher<List> loaded;
  abstract final ActionDispatcher<MessageAttachmentFile> downloadFile;
  abstract final ActionDispatcher<MessageAttachmentFile> fileAvailable;
  abstract final ActionDispatcher<MessageAttachmentFile> openFile;

  /// Downloads the attachment if needed, then asks where to put a copy.
  abstract final ActionDispatcher<MessageAttachmentFile> saveFileAs;

  /// Downloads the attachment if needed, then puts it on the clipboard.
  abstract final ActionDispatcher<MessageAttachmentFile> copyFile;

  abstract final ActionDispatcher<int> markAsRead;

  /// Carries the timestamp the server assigned when marking a message as read.
  abstract final ActionDispatcher<MarkedAsReadPayload> markedAsRead;
}

abstract class MarkedAsReadPayload
    implements Built<MarkedAsReadPayload, MarkedAsReadPayloadBuilder> {
  factory MarkedAsReadPayload(
      [void Function(MarkedAsReadPayloadBuilder)? updates]) = _$MarkedAsReadPayload;
  MarkedAsReadPayload._();

  int get id;
  UtcDateTime? get timeRead;
}
