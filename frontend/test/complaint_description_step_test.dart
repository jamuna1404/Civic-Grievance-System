import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:civicroute/features/citizen/complaints/application/complaint_draft_controller.dart';
import 'package:civicroute/features/citizen/complaints/application/speech_service.dart';
import 'package:civicroute/features/citizen/complaints/presentation/description_step_screen.dart';

/// Fake recognizer: [available] gates permission; [emit] pushes a transcript
/// as if speech were recognized.
class _FakeSpeech implements SpeechService {
  _FakeSpeech({this.available = true});

  final bool available;
  bool _listening = false;
  void Function(String, bool)? _onResult;
  void Function()? _onDone;

  @override
  bool get isListening => _listening;

  @override
  Future<bool> initialize() async => available;

  @override
  Future<void> start({
    required void Function(String recognizedWords, bool isFinal) onResult,
    void Function(double level)? onLevel,
    required void Function() onDone,
  }) async {
    _listening = true;
    _onResult = onResult;
    _onDone = onDone;
  }

  @override
  Future<void> stop() async {
    _listening = false;
    _onDone?.call();
  }

  void emit(String words, {bool isFinal = true}) =>
      _onResult?.call(words, isFinal);
}

ProviderContainer _container(_FakeSpeech speech) => ProviderContainer(
      overrides: [speechServiceProvider.overrideWithValue(speech)],
    );

Widget _host(ProviderContainer container) => UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: DescriptionStepScreen()),
    );

VoidCallback? _nextOnPressed(WidgetTester tester) {
  final btn =
      tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Next'));
  return btn.onPressed;
}

void main() {
  testWidgets('Next is disabled until the field has text', (tester) async {
    final container = _container(_FakeSpeech());
    addTearDown(container.dispose);
    await tester.pumpWidget(_host(container));
    await tester.pumpAndSettle();

    final disabled =
        tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Next'));
    expect(disabled.onPressed, isNull);

    await tester.enterText(find.byType(TextField), 'Pothole on 2nd street');
    await tester.pump();

    final enabled =
        tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Next'));
    expect(enabled.onPressed, isNotNull);
  });

  testWidgets('seeds the field from the existing draft description',
      (tester) async {
    final container = _container(_FakeSpeech());
    addTearDown(container.dispose);
    container
        .read(complaintDraftProvider.notifier)
        .setDescription('Broken drain cover');

    await tester.pumpWidget(_host(container));
    await tester.pumpAndSettle();

    expect(find.text('Broken drain cover'), findsOneWidget);
  });

  testWidgets('voice transcription fills the same editable field',
      (tester) async {
    final speech = _FakeSpeech();
    final container = _container(speech);
    addTearDown(container.dispose);
    await tester.pumpWidget(_host(container));
    await tester.pumpAndSettle();

    // Start recording.
    await tester.tap(find.text('Speak instead'));
    await tester.pump();
    expect(find.text('Listening…'), findsOneWidget);
    expect(find.text('Stop'), findsOneWidget);

    // Recognized speech lands in the text field…
    speech.emit('the street light is off');
    await tester.pump();
    expect(
      find.widgetWithText(TextField, 'the street light is off'),
      findsOneWidget,
    );

    // …and the draft is updated, enabling Next.
    expect(
      container.read(complaintDraftProvider).description,
      'the street light is off',
    );
    expect(_nextOnPressed(tester), isNotNull);

    // Stop returns to the idle mic state.
    await tester.tap(find.text('Stop'));
    await tester.pump();
    expect(find.text('Listening…'), findsNothing);
    expect(find.text('Speak instead'), findsOneWidget);
  });

  testWidgets('transcription appends to text already typed', (tester) async {
    final speech = _FakeSpeech();
    final container = _container(speech);
    addTearDown(container.dispose);
    await tester.pumpWidget(_host(container));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Near the market:');
    await tester.pump();

    await tester.tap(find.text('Speak instead'));
    await tester.pump();
    speech.emit('garbage not collected');
    await tester.pump();

    expect(
      find.text('Near the market: garbage not collected'),
      findsOneWidget,
    );
  });

  testWidgets('denied mic permission shows an explanation dialog',
      (tester) async {
    final container = _container(_FakeSpeech(available: false));
    addTearDown(container.dispose);
    await tester.pumpWidget(_host(container));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Speak instead'));
    await tester.pumpAndSettle();

    expect(find.text('Microphone access needed'), findsOneWidget);
  });
}
