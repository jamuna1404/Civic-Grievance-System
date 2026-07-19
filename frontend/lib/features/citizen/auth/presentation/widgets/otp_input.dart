import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../../core/theme/app_spacing.dart';

/// A 6-box OTP entry field with auto-focus and auto-advance.
///
/// - Typing a digit advances focus to the next box.
/// - Backspace on an empty box moves focus back and clears the previous digit.
/// - Re-focusing a filled box selects its digit so typing overwrites it.
/// - [onChanged] fires with the current concatenated value; [onCompleted]
///   fires once all boxes are filled.
class OtpInput extends StatefulWidget {
  const OtpInput({
    super.key,
    required this.onChanged,
    this.onCompleted,
    this.hasError = false,
    this.length = 6,
  });

  final ValueChanged<String> onChanged;
  final ValueChanged<String>? onCompleted;
  final bool hasError;
  final int length;

  @override
  State<OtpInput> createState() => _OtpInputState();
}

class _OtpInputState extends State<OtpInput> {
  late final List<TextEditingController> _controllers;
  late final List<FocusNode> _focusNodes;

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(widget.length, (_) => TextEditingController());
    _focusNodes = List.generate(widget.length, (_) => FocusNode());
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  String get _value => _controllers.map((c) => c.text).join();

  void _emit() {
    final value = _value;
    widget.onChanged(value);
    if (value.length == widget.length) {
      _focusNodes[widget.length - 1].unfocus();
      widget.onCompleted?.call(value);
    }
  }

  void _onChanged(int index, String raw) {
    if (raw.isNotEmpty && index < widget.length - 1) {
      _focusNodes[index + 1].requestFocus();
    }
    _emit();
  }

  KeyEventResult _onKey(int index, FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.backspace &&
        _controllers[index].text.isEmpty &&
        index > 0) {
      _controllers[index - 1].clear();
      _focusNodes[index - 1].requestFocus();
      _emit();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Row(
      children: List.generate(widget.length, (index) {
        return Expanded(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: AppSpacing.xs),
            child: Focus(
              onKeyEvent: (node, event) => _onKey(index, node, event),
              child: TextField(
                controller: _controllers[index],
                focusNode: _focusNodes[index],
                autofocus: index == 0,
                textAlign: TextAlign.center,
                keyboardType: TextInputType.number,
                style: theme.textTheme.headlineSmall,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(1),
                ],
                // Select existing digit on focus so typing overwrites it.
                onTap: () => _controllers[index].selection = TextSelection(
                  baseOffset: 0,
                  extentOffset: _controllers[index].text.length,
                ),
                onChanged: (v) => _onChanged(index, v),
                decoration: InputDecoration(
                  counterText: '',
                  contentPadding:
                      const EdgeInsets.symmetric(vertical: AppSpacing.md),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: AppRadius.mdAll,
                    borderSide: BorderSide(
                      color: widget.hasError
                          ? scheme.error
                          : scheme.outlineVariant,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: AppRadius.mdAll,
                    borderSide: BorderSide(
                      color: widget.hasError ? scheme.error : scheme.primary,
                      width: 1.5,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      }),
    );
  }
}
