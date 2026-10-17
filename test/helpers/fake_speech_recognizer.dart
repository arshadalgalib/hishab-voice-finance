import 'package:personal_finance_manager/features/voice/application/speech_recognizer.dart';

/// A scripted [SpeechRecognizer] for widget tests.
///
/// It never touches a microphone or a platform channel: [start] immediately
/// emits the transcript configured by the test. That lets the *real*
/// `VoiceController` and the *real* parser be driven end to end from the UI,
/// which is the point — the seam is the recogniser, nothing else.
class FakeSpeechRecognizer implements SpeechRecognizer {
  FakeSpeechRecognizer({
    this.availability = SpeechAvailability.available,
    this.transcript = '',
    this.partialText,
    this.throwOnStart = false,
    this.errorMessage,
  });

  SpeechAvailability availability;

  /// What the engine reports when the session ends.
  String transcript;

  /// Optional interim guess delivered before the final result.
  String? partialText;

  /// When true, [start] throws [SpeechUnavailableException], which mimics an
  /// engine that reported itself available but then failed to launch.
  bool throwOnStart;

  /// When set, the engine reports a non-fatal error instead of a transcript.
  String? errorMessage;

  int initializeCount = 0;
  int startCount = 0;
  bool _listening = false;

  List<String> lastContextualPhrases = const <String>[];

  @override
  String get id => 'fake';

  @override
  String get label => 'Fake recogniser';

  @override
  bool get requiresNetwork => false;

  @override
  bool get isListening => _listening;

  @override
  Future<SpeechAvailability> initialize() async {
    initializeCount++;
    return availability;
  }

  @override
  Future<void> start({
    required String localeId,
    required Duration listenFor,
    required Duration pauseFor,
    required void Function(SpeechResult result) onPartial,
    required void Function(SpeechResult result) onFinal,
    required void Function(String message) onError,
    List<String> contextualPhrases = const <String>[],
  }) async {
    startCount++;
    lastContextualPhrases = contextualPhrases;
    if (throwOnStart) {
      throw const SpeechUnavailableException('The engine could not start.');
    }
    _listening = true;
    final partial = partialText;
    if (partial != null) {
      onPartial(SpeechResult(text: partial, isFinal: false));
    }
    final error = errorMessage;
    if (error != null) {
      onError(error);
    } else {
      onFinal(SpeechResult(text: transcript, isFinal: true, confidence: 0.9));
    }
    _listening = false;
  }

  @override
  Future<void> stop() async {
    _listening = false;
  }

  @override
  Future<void> cancel() async {
    _listening = false;
  }

  @override
  Future<void> dispose() async {
    _listening = false;
  }
}
