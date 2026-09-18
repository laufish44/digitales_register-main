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

/// Containers for the extra calculations.
///
/// These connect to the store on their own instead of being threaded through
/// the existing view models: the dashboard and grades view models are
/// `built_value` classes, and the results here (lists of records) are not
/// built types, so they cannot be fields there.
library;

import 'package:dr/actions/app_actions.dart';
import 'package:dr/app_state.dart';
import 'package:dr/data.dart';
import 'package:dr/ui/insights.dart';
import 'package:flutter/material.dart';
import 'package:flutter_built_redux/flutter_built_redux.dart';

/// The trend/target card for one subject.
class GradeTrendContainer extends StatelessWidget {
  const GradeTrendContainer({
    super.key,
    required this.subjectName,
    required this.grades,
  });

  final String subjectName;
  final List<GradeAll> grades;

  @override
  Widget build(BuildContext context) {
    return StoreConnection<AppState, AppActions, _GradeTrendViewModel>(
      builder: (context, vm, actions) {
        if (!vm.enabled) return const SizedBox.shrink();
        return GradeTrendCard(
          subjectName: subjectName,
          grades: grades,
          // The stored target is per subject, so switching between subjects
          // shows each one's own goal instead of resetting the slider.
          target: vm.target,
          onTargetChanged: (value) => actions.settingsActions.setGradeTarget(
            MapEntry(subjectName, value),
          ),
        );
      },
      connect: (state) => _GradeTrendViewModel(
        enabled: state.settingsState.showGradeTrends,
        target: state.settingsState.gradeTargets[subjectName],
      ),
    );
  }
}

class _GradeTrendViewModel {
  const _GradeTrendViewModel({required this.enabled, required this.target});

  final bool enabled;

  /// Scaled by 100, null when nothing was set for this subject.
  final int? target;

  @override
  bool operator ==(Object other) =>
      other is _GradeTrendViewModel &&
      other.enabled == enabled &&
      other.target == target;

  @override
  int get hashCode => Object.hash(enabled, target);
}
