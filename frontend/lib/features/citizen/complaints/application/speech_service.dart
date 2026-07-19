import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// Abstraction over on-device speech-to-text so the description screen can be
/// tested with a fake and doesn't depend on platform channels directly.
abstract class SpeechService {
  /// Prepares the recognizer and requests microphone permission.
  /// Returns false if unavailable or permission was denied.
  Future<bool> initialize();

  /// Begins listening. [onResult] fires with partial and final transcripts;
  /// [onLevel] reports mic sound level (for a live waveform); [onDone] fires
  /// when the engine stops on its own (silence timeout / end of speech).
  Future<void> start({
    required void Function(String recognizedWords, bool isFinal) onResult,
    void Function(double level)? onLevel,
    required void Function() onDone,
  });

  Future<void> stop();

  bool get isListening;
}

/// Real implementation backed by the `speech_to_text` package.
class SpeechToTextService implements SpeechService {
  final SpeechToText _speech = SpeechToText();
  bool _available = false;
  void Function()? _onDone;

  @override
  bool get isListening => _speech.isListening;

  @override
  Future<bool> initialize() async {
    _available = await _speech.initialize(
      onStatus: (status) {
        // 'done' / 'notListening' mean the engine finished a session.
        if (status == 'done' || status == 'notListening') {
          _onDone?.call();
        }
      },
      onError: (_) => _onDone?.call(),
    );
    return _available;
  }

  @override
  Future<void> start({
    required void Function(String recognizedWords, bool isFinal) onResult,
    void Function(double level)? onLevel,
    required void Function() onDone,
  }) async {
    _onDone = onDone;
    await _speech.listen(
      onResult: (result) =>
          onResult(result.recognizedWords, result.finalResult),
      onSoundLevelChange: onLevel,
      listenOptions: SpeechListenOptions(
        partialResults: true,
        cancelOnError: true,
        listenFor: const Duration(minutes: 1),
        pauseFor: const Duration(seconds: 4),
      ),
    );
  }

  @override
  Future<void> stop() => _speech.stop();
}

final speechServiceProvider = Provider<SpeechService>(
  (ref) => SpeechToTextService(),
);
