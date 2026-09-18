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

import 'package:dr/actions/app_actions.dart';
import 'package:dr/app_state.dart';
import 'package:dr/search.dart';
import 'package:flutter/material.dart';
import 'package:flutter_built_redux/flutter_built_redux.dart';

/// Search over everything the app has loaded.
class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _controller = TextEditingController();
  final _selected = <SearchCategory>{};
  var _query = "";

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          autofocus: true,
          textInputAction: TextInputAction.search,
          decoration: const InputDecoration(
            hintText: "Suchen …",
            border: InputBorder.none,
          ),
          style: Theme.of(context).primaryTextTheme.titleLarge,
          onChanged: (value) => setState(() => _query = value),
        ),
        actions: [
          if (_query.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.clear),
              tooltip: "Leeren",
              onPressed: () {
                _controller.clear();
                setState(() => _query = "");
              },
            ),
        ],
      ),
      body: Column(
        children: [
          SizedBox(
            height: 52,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              children: [
                for (final category in SearchCategory.values)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: FilterChip(
                      label: Text(category.label),
                      selected: _selected.contains(category),
                      onSelected: (selected) => setState(() {
                        if (selected) {
                          _selected.add(category);
                        } else {
                          _selected.remove(category);
                        }
                      }),
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: StoreConnection<AppState, AppActions, AppState>(
              connect: (state) => state,
              builder: (context, state, actions) =>
                  _results(context, state, actions),
            ),
          ),
        ],
      ),
    );
  }

  Widget _results(BuildContext context, AppState state, AppActions actions) {
    if (_query.trim().length < 2) {
      return const _Hint(
        icon: Icons.search,
        text: "Mindestens zwei Zeichen eingeben.\n\n"
            "Gesucht wird in allem, was die App schon geladen hat: "
            "Mitteilungen, Einträge, Noten, Fächer, Stundenplan und Absenzen. "
            "Was du in dieser Sitzung noch nicht geöffnet hast, ist noch nicht "
            "dabei.",
      );
    }

    final results = Search.run(state, _query, categories: _selected);
    if (results.isEmpty) {
      return const _Hint(
        icon: Icons.search_off,
        text: "Nichts gefunden.",
      );
    }

    return ListView.builder(
      itemCount: results.length,
      itemBuilder: (context, index) {
        final result = results[index];
        // A header whenever the category changes, so the list stays readable
        // without grouping everything up front.
        final isFirstOfCategory =
            index == 0 || results[index - 1].category != result.category;
        final tile = ListTile(
          leading: Icon(_iconFor(result.category)),
          title: Text(result.title),
          subtitle: Text(result.subtitle),
          // `showMessage` pops this page itself and then opens the messages
          // list, so there is no pop here.
          onTap: result.messageId == null
              ? null
              : () => actions.routingActions.showMessage(result.messageId!),
        );
        if (!isFirstOfCategory) return tile;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text(
                result.category.label,
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            tile,
          ],
        );
      },
    );
  }

  static IconData _iconFor(SearchCategory category) {
    switch (category) {
      case SearchCategory.message:
        return Icons.mail_outline;
      case SearchCategory.entry:
        return Icons.assignment_outlined;
      case SearchCategory.grade:
        return Icons.grade_outlined;
      case SearchCategory.subject:
        return Icons.book_outlined;
      case SearchCategory.lesson:
        return Icons.schedule;
      case SearchCategory.absence:
        return Icons.hotel;
    }
  }
}

class _Hint extends StatelessWidget {
  const _Hint({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: theme.disabledColor),
            const SizedBox(height: 16),
            Text(
              text,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}
