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

/// A column whose rows fade and collapse away instead of blinking out of
/// existence.
///
/// Flutter cannot animate a widget that simply stops being built, so the rows
/// that disappeared from the incoming list are kept for the length of the
/// animation and shrunk to nothing first. The list is driven by the redux
/// store, which means the widget has to work out for itself what changed — it
/// gets a new list, not a notification.
library;

import 'package:flutter/material.dart';

/// One row, identified by something stable across rebuilds.
class VanishingItem {
  const VanishingItem({required this.id, required this.child});

  /// Must identify the same row across rebuilds; rows are matched by it.
  final String id;

  final Widget child;
}

class VanishingList extends StatefulWidget {
  const VanishingList({
    super.key,
    required this.items,
    this.duration = const Duration(milliseconds: 260),
    this.curve = Curves.easeOutCubic,
  });

  final List<VanishingItem> items;
  final Duration duration;
  final Curve curve;

  @override
  State<VanishingList> createState() => _VanishingListState();
}

class _VanishingListState extends State<VanishingList> {
  /// What is on screen, including rows on their way out.
  late List<VanishingItem> _shown = List.of(widget.items);

  /// Rows that are collapsing; they are dropped once that is done.
  final _leaving = <String>{};

  @override
  void didUpdateWidget(VanishingList oldWidget) {
    super.didUpdateWidget(oldWidget);

    final incoming = {for (final item in widget.items) item.id: item};

    // Walk the current order, keeping departing rows where they were so the
    // ones below them do not jump up before the animation has run.
    final next = <VanishingItem>[];
    for (final item in _shown) {
      next.add(incoming[item.id] ?? item);
    }
    for (final item in widget.items) {
      if (!_shown.any((shown) => shown.id == item.id)) next.add(item);
    }

    final gone = [
      for (final item in next)
        if (!incoming.containsKey(item.id) && !_leaving.contains(item.id))
          item.id,
    ];

    _shown = next;
    if (gone.isEmpty) return;

    // Mark them only on the next frame: the row has to be laid out at its full
    // height once before it is told to collapse, or there is nothing to
    // animate from.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _leaving.addAll(gone));
      Future<void>.delayed(widget.duration, () {
        if (!mounted) return;
        setState(() {
          _shown = _shown.where((item) => !gone.contains(item.id)).toList();
          _leaving.removeAll(gone);
        });
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final item in _shown)
          _VanishingRow(
            key: ValueKey(item.id),
            leaving: _leaving.contains(item.id),
            duration: widget.duration,
            curve: widget.curve,
            child: item.child,
          ),
      ],
    );
  }
}

class _VanishingRow extends StatelessWidget {
  const _VanishingRow({
    super.key,
    required this.leaving,
    required this.duration,
    required this.curve,
    required this.child,
  });

  final bool leaving;
  final Duration duration;
  final Curve curve;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: duration,
      curve: curve,
      alignment: Alignment.topCenter,
      // Align with a height factor is what actually shrinks the row: the child
      // keeps its own size and is clipped, so it can still be seen fading out
      // while the space it takes up collapses.
      child: Align(
        alignment: Alignment.topCenter,
        heightFactor: leaving ? 0 : 1,
        child: AnimatedOpacity(
          duration: duration,
          curve: curve,
          opacity: leaving ? 0 : 1,
          // Sliding a little to the side reads as "done and away" rather than
          // "something went wrong and vanished".
          child: AnimatedSlide(
            duration: duration,
            curve: curve,
            offset: leaving ? const Offset(0.15, 0) : Offset.zero,
            child: child,
          ),
        ),
      ),
    );
  }
}
