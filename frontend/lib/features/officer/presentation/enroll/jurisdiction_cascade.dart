import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_buttons.dart';
import '../../data/cascade.dart';
import '../../data/officer_models.dart';
import '../../data/officer_repository.dart';

/// Sequential jurisdiction pickers that cascade per the department's own
/// boundary hierarchy. Each level's options are filtered by the parent chosen
/// in the level above. Only the levels down to the designation's own level are
/// shown. The final (narrowest) selection is reported via [onSelected].
class JurisdictionCascade extends ConsumerStatefulWidget {
  const JurisdictionCascade({
    super.key,
    required this.departmentId,
    required this.designation,
    required this.levels,
    required this.onSelected,
    this.initialBoundaryId,
  });

  final String departmentId;
  final DesignationOption designation;
  final List<BoundaryLevel> levels;
  final void Function(int boundaryId, String boundaryName) onSelected;
  final int? initialBoundaryId;

  @override
  ConsumerState<JurisdictionCascade> createState() => _JurisdictionCascadeState();
}

class _JurisdictionCascadeState extends ConsumerState<JurisdictionCascade> {
  late final List<BoundaryLevel> _cascade;

  /// Selected option per cascade index (null until chosen).
  late List<BoundaryOption?> _selected;

  /// Loaded options per cascade index.
  late List<List<BoundaryOption>> _options;
  late List<bool> _loading;

  /// Index of the first cascade level that actually has boundary data. Upper
  /// levels with no seeded boundaries (e.g. a declared "Region" a department
  /// skips) are omitted so the cascade doesn't dead-end. Null while probing.
  int? _startIndex;
  bool _probing = true;
  bool _noData = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cascade = cascadeLevelsFor(widget.levels, widget.designation);
    _selected = List.filled(_cascade.length, null);
    _options = List.generate(_cascade.length, (_) => []);
    _loading = List.filled(_cascade.length, false);
    if (_cascade.isEmpty) {
      _probing = false;
    } else {
      _probeStart();
    }
  }

  /// Query levels broadest-first until one returns boundaries; that becomes the
  /// first picker.
  Future<void> _probeStart() async {
    try {
      for (var i = 0; i < _cascade.length; i++) {
        final opts = await ref.read(officerRepositoryProvider).boundaries(
              widget.departmentId,
              levelName: _cascade[i].levelName,
            );
        if (!mounted) return;
        if (opts.isNotEmpty) {
          setState(() {
            _startIndex = i;
            _options[i] = opts;
            _probing = false;
          });
          return;
        }
      }
      // No level had any boundaries.
      if (mounted) {
        setState(() {
          _noData = true;
          _probing = false;
        });
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _probing = false;
        });
      }
    }
  }

  Future<void> _loadOptions(int index) async {
    setState(() {
      _loading[index] = true;
      _error = null;
    });
    try {
      final parentId =
          index == _startIndex ? null : _selected[index - 1]?.boundaryId;
      final opts = await ref.read(officerRepositoryProvider).boundaries(
            widget.departmentId,
            levelName: _cascade[index].levelName,
            parentId: parentId,
          );
      if (!mounted) return;
      setState(() => _options[index] = opts);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading[index] = false);
    }
  }

  void _onSelect(int index, BoundaryOption? option) {
    setState(() {
      _selected[index] = option;
      // Clear deeper levels.
      for (var i = index + 1; i < _cascade.length; i++) {
        _selected[i] = null;
        _options[i] = [];
      }
    });

    if (option == null) return;

    final isLast = index == _cascade.length - 1;
    if (isLast) {
      widget.onSelected(option.boundaryId, option.boundaryName);
    } else {
      _loadOptions(index + 1);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_cascade.isEmpty) {
      return Text(
        'This designation’s level isn’t defined in the department hierarchy.',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.error,
        ),
      );
    }

    if (_probing) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null && _startIndex == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _error!,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          SecondaryButton(
            label: 'Retry Loading Areas',
            icon: Icons.refresh,
            expand: false,
            onPressed: () {
              setState(() {
                _error = null;
                _probing = true;
              });
              _probeStart();
            },
          ),
        ],
      );
    }

    if (_noData || _startIndex == null) {
      return Text(
        'No jurisdiction areas are configured for this department yet. '
        'Please contact your department administrator.',
        style: theme.textTheme.bodyMedium
            ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
      );
    }

    final start = _startIndex!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = start; i < _cascade.length; i++) ...[
          _LevelPicker(
            label: _cascade[i].displayLabel,
            enabled: i == start || _selected[i - 1] != null,
            loading: _loading[i],
            options: _options[i],
            value: _selected[i],
            onChanged: (opt) => _onSelect(i, opt),
          ),
          if (i < _cascade.length - 1) const SizedBox(height: AppSpacing.lg),
        ],
        if (_error != null) ...[
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: Text(
                  _error!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              TextButton.icon(
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Retry'),
                onPressed: () {
                  // Find the index of the first level where selection is complete
                  // but options failed.
                  int retryIndex = -1;
                  for (var i = 0; i < _cascade.length; i++) {
                    if (_loading[i]) return; // currently loading, skip
                    if (i > 0 &&
                        _selected[i - 1] != null &&
                        _selected[i] == null &&
                        _options[i].isEmpty) {
                      retryIndex = i;
                      break;
                    }
                  }
                  if (retryIndex != -1) {
                    _loadOptions(retryIndex);
                  }
                },
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _LevelPicker extends StatelessWidget {
  const _LevelPicker({
    required this.label,
    required this.enabled,
    required this.loading,
    required this.options,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool enabled;
  final bool loading;
  final List<BoundaryOption> options;
  final BoundaryOption? value;
  final ValueChanged<BoundaryOption?> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.textTheme.labelLarge),
        const SizedBox(height: AppSpacing.sm),
        if (loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
            child: LinearProgressIndicator(),
          )
        else if (enabled && options.isEmpty)
          Text(
            'No areas found for this selection.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          )
        else
          DropdownButtonFormField<BoundaryOption>(
            value: value,
            isExpanded: true,
            decoration: InputDecoration(hintText: 'Select $label'),
            items: [
              for (final o in options)
                DropdownMenuItem(value: o, child: Text(o.boundaryName)),
            ],
            onChanged: enabled ? onChanged : null,
          ),
      ],
    );
  }
}
