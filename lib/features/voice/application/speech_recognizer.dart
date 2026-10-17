import 'package:meta/meta.dart';

/// Whether the speech engine could be used at all.
enum SpeechAvailability { available, permissionDenied, unavailable }

/// One recognition update from the engine.
@immutable
class SpeechResult {
  const SpeechResult({
    required this.text,
    required this.isFinal,
    this.confidence,
  });

  final String text;

  /// False while the engine is still refining the transcript.
  final bool isFinal;

  /// Engine-supplied confidence, or null when the platform does not report one.
  ///
  /// This is **not** the same as the parser's interpretation confidence and is
  /// never shown as a recognition accuracy figure.
  final double? confidence;
}

/// Seam between the app and whatever speech engine is in use.
///
/// Two implementations exist: [NativeSpeechRecognizer] (the on-device engine,
/// the default, works offline) and a deliberately-absent cloud audio engine.
/// The abstraction exists so the whole voice flow can be driven from a fake in
/// tests without a microphone or a network.
abstract class SpeechRecognizer {
  /// Stable id stored in settings, e.g. `native`.
  String get id;

  /// Shown in the voice settings screen.
  String get label;

  /// True when this engine sends data off the device.
  bool get requiresNetwork;

  bool get isListening;

  /// Prepares the engine and requests microphone permission if needed.
  Future<SpeechAvailability> initialize();

  /// Starts a listening session.
  ///
  /// [onPartial] is called for interim guesses, [onFinal] once when the session
  /// ends, and [onError] for non-fatal engine errors.
  Future<void> start({
    required String localeId,
    required Duration listenFor,
    required Duration pauseFor,
    required void Function(SpeechResult result) onPartial,
    required void Function(SpeechResult result) onFinal,
    required void Function(String message) onError,
    List<String> contextualPhrases = const <String>[],
  });

  /// Ends the session, emitting a final result.
  Future<void> stop();

  /// Ends the session without emitting a final result.
  Future<void> cancel();

  Future<void> dispose();
}

/// Raised when a recogniser is asked to work in an environment it cannot.
class SpeechUnavailableException implements Exception {
  const SpeechUnavailableException(this.message);

  final String message;

  @override
  String toString() => message;
}
