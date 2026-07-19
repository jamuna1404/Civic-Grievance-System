import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/routing/app_router.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_buttons.dart';
import '../../../../core/widgets/step_progress_indicator.dart';
import '../application/complaint_draft_controller.dart';
import '../application/speech_service.dart';

/// Step 2 of 3 — describe the issue, by typing or by voice.
///
/// Voice transcription populates the *same* text field so the citizen can
/// review and correct it before continuing (transcription is imperfect).
class DescriptionStepScreen extends ConsumerStatefulWidget {
  const DescriptionStepScreen({super.key});

  @override
  ConsumerState<DescriptionStepScreen> createState() =>
      _DescriptionStepScreenState();
}

class _DescriptionStepScreenState extends ConsumerState<DescriptionStepScreen>
    with SingleTickerProviderStateMixin {
  late final TextEditingController _controller;
  late final AnimationController _pulse;
  late final SpeechService _speech;

  bool _listening = false;
  bool _disposed = false;
  double _soundLevel = 0;

  /// Text present when the current dictation began, so transcribed words are
  /// appended to (not replacing) anything already there.
  String _textBeforeListening = '';

  @override
  void initState() {
    super.initState();
    _speech = ref.read(speechServiceProvider);
    _controller = TextEditingController(
      text: ref.read(complaintDraftProvider).description,
    );
    _controller.addListener(_onTextChanged);
    // Runs only while recording (started in _startRecording), so the screen is
    // static when idle.
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    // Best-effort: make sure the recognizer isn't left running. This may fire
    // the onDone callback synchronously (fakes) or later (real engine), so the
    // callback guards against a disposed [_pulse] via [_disposed].
    _speech.stop();
    _pulse.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    ref.read(complaintDraftProvider.notifier).setDescription(_controller.text);
    setState(() {}); // refresh Next enabled-state
  }

  bool get _canContinue => _controller.text.trim().isNotEmpty;

  Future<void> _toggleRecording() async {
    if (_listening) {
      await _stopRecording();
    } else {
      await _startRecording();
    }
  }

  Future<void> _startRecording() async {
    final available = await _speech.initialize();
    if (!available) {
      if (mounted) _showMicPermissionDialog();
      return;
    }

    _textBeforeListening = _controller.text;
    ref.read(complaintDraftProvider.notifier).markVoiceUsed();
    setState(() => _listening = true);
    _pulse.repeat(reverse: true);

    await _speech.start(
      onResult: (words, isFinal) {
        final base = _textBeforeListening.trim();
        final combined = base.isEmpty ? words : '$base $words';
        _controller.value = TextEditingValue(
          text: combined,
          selection: TextSelection.collapsed(offset: combined.length),
        );
      },
      onLevel: (level) {
        if (mounted) setState(() => _soundLevel = level);
      },
      onDone: () {
        if (_disposed) return;
        _pulse.stop();
        if (mounted) setState(() => _listening = false);
      },
    );
  }

  Future<void> _stopRecording() async {
    await _speech.stop();
    if (_disposed) return;
    _pulse.stop();
    if (mounted) setState(() => _listening = false);
  }

  void _showMicPermissionDialog() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Microphone access needed'),
        content: const Text(
          'CivicRoute needs microphone access to transcribe your spoken '
          'description.\n\nPlease enable microphone access for CivicRoute in '
          'your device Settings, then try again. You can also type the '
          'description instead.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        // Default leading back button pops to Step 1; draft (photos + text)
        // is preserved in complaintDraftProvider.
        title: const Text('Register Complaint'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.all(AppSpacing.lg),
              child: StepProgressIndicator(
                currentStep: 2,
                totalSteps: 3,
                label: 'Description',
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Describe the issue',
                      style: theme.textTheme.titleLarge,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'Type it, or tap the mic to speak — you can edit the '
                      'transcribed text before continuing.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    TextField(
                      controller: _controller,
                      minLines: 5,
                      maxLines: 8,
                      textCapitalization: TextCapitalization.sentences,
                      keyboardType: TextInputType.multiline,
                      decoration: const InputDecoration(
                        hintText:
                            'e.g. The street light near the bus stop on Anna '
                            'Salai has been off for a week.',
                        alignLabelWithHint: true,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    if (_listening)
                      _RecordingIndicator(
                        pulse: _pulse,
                        soundLevel: _soundLevel,
                        onStop: _stopRecording,
                      )
                    else
                      _MicButton(onTap: _toggleRecording),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: PrimaryButton(
                label: 'Next',
                icon: Icons.arrow_forward,
                onPressed: _canContinue
                    ? () => context.push(AppRoutes.complaintLocation)
                    : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Idle mic affordance shown when not recording.
class _MicButton extends StatelessWidget {
  const _MicButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Align(
      alignment: Alignment.center,
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: const Icon(Icons.mic_none_outlined, size: 20),
        label: const Text('Speak instead'),
        style: OutlinedButton.styleFrom(
          foregroundColor: theme.colorScheme.primary,
        ),
      ),
    );
  }
}

/// Active-recording state: pulsing mic, live waveform, and a Stop button.
class _RecordingIndicator extends StatelessWidget {
  const _RecordingIndicator({
    required this.pulse,
    required this.soundLevel,
    required this.onStop,
  });

  final Animation<double> pulse;
  final double soundLevel;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: scheme.errorContainer.withValues(alpha: 0.35),
        borderRadius: AppRadius.lgAll,
        border: Border.all(color: scheme.error.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          // Pulsing mic
          AnimatedBuilder(
            animation: pulse,
            builder: (context, child) {
              final t = pulse.value;
              return Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: scheme.error.withValues(alpha: 0.15 + 0.25 * t),
                ),
                child: Icon(Icons.mic, color: scheme.error),
              );
            },
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Listening…',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: scheme.error,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                SizedBox(
                  height: 24,
                  child: _Waveform(animation: pulse, soundLevel: soundLevel),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          FilledButton.tonalIcon(
            onPressed: onStop,
            icon: const Icon(Icons.stop, size: 18),
            label: const Text('Stop'),
          ),
        ],
      ),
    );
  }
}

/// Lightweight animated bars. Amplitude is modulated by the live [soundLevel]
/// so the waveform reacts to speech, with the [animation] driving motion.
class _Waveform extends StatelessWidget {
  const _Waveform({required this.animation, required this.soundLevel});

  final Animation<double> animation;
  final double soundLevel;

  static const _bars = 14;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.error;
    // Normalize the platform sound level (~0..10, sometimes negative) to 0..1.
    final level = (soundLevel.abs() / 10).clamp(0.15, 1.0);

    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: List.generate(_bars, (i) {
            final phase = (animation.value + i / _bars) * 2 * math.pi;
            final amplitude = (0.4 + 0.6 * (0.5 + 0.5 * math.sin(phase))) * level;
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 1.5),
                child: Container(
                  height: 4 + 20 * amplitude,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}
