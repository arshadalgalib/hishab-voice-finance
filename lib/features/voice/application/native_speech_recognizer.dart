import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import 'speech_recognizer.dart';

/// On-device speech recognition through `speech_to_text`.
///
/// This is the default engine and works entirely offline on Android when the
/// device has a Bengali / English offline language pack installed. The engine
/// itself decides whether to use on-device or network recognition; this class
/// does not force `onDevice`, because forcing it makes recognition fail on
/// devices without an offline pack. The UI states plainly when the *online*
/// interpreter is in use, which is the part under the app's control.
class NativeSpeechRecognizer implements SpeechRecognizer {
  NativeSpeechRecognizer([SpeechToText? speech])
    : _speech = speech ?? SpeechToText();

  final SpeechToText _speech;

  bool _initialized = false;
  void Function(String message)? _onError;
  void Function(SpeechResult result)? _onFinal;
  bool _finalDelivered = false;

  @override
  String get id => 'native';

  @override
  String get label => 'On-device recogniser';

  @override
  bool get requiresNetwork => false;

  @override
  bool get isListening => _speech.isListening;

  @override
  Future<SpeechAvailability> initialize() async {
    if (_initialized) return SpeechAvailability.available;
    try {
      final ok = await _speech.initialize(
        onError: _handleError,
        onStatus: _handleStatus,
      );
      if (ok) {
        _initialized = true;
        return SpeechAvailability.available;
      }
      return SpeechAvailability.unavailable;
    } catch (_) {
      return SpeechAvailability.unavailable;
    }
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
    final availability = await initialize();
    if (availability != SpeechAvailability.available) {
      throw const SpeechUnavailableException(
        'Speech recognition is not available on this device. '
        'You can still type the transaction.',
      );
    }

    _onError = onError;
    _onFinal = onFinal;
    _finalDelivered = false;

    final options = SpeechListenOptions(
      partialResults: true,
      cancelOnError: false,
      listenFor: listenFor,
      pauseFor: pauseFor,
      localeId: localeId,
      contextualPhrases: contextualPhrases.isEmpty ? null : contextualPhrases,
    );

    await _speech.listen(
      listenOptions: options,
      onResult: (SpeechRecognitionResult result) {
        final text = result.recognizedWords.trim();
        if (text.isEmpty) return;
        final speechResult = SpeechResult(
          text: text,
          isFinal: result.finalResult,
          confidence: result.confidence >= 0 ? result.confidence : null,
        );
        if (result.finalResult) {
          _finalDelivered = true;
          _onFinal?.call(speechResult);
        } else {
          onPartial(speechResult);
        }
      },
    );
  }

  @override
  Future<void> stop() async {
    try {
      await _speech.stop();
    } catch (_) {
      // Stopping an already finished session is not an error worth surfacing.
    }
  }

  @override
  Future<void> cancel() async {
    try {
      await _speech.cancel();
    } catch (_) {
      // See [stop].
    }
  }

  @override
  Future<void> dispose() => cancel();

  void _handleError(SpeechRecognitionError error) {
    // `no-match` and `speech-timeout` are ordinary ends of a session.
    if (error.errorMsg == 'error_no_match' ||
        error.errorMsg == 'error_speech_timeout') {
      if (!_finalDelivered) {
        _onFinal?.call(const SpeechResult(text: '', isFinal: true));
      }
      return;
    }
    _onError?.call(_friendly(error));
    if (!_finalDelivered) {
      _onFinal?.call(const SpeechResult(text: '', isFinal: true));
    }
  }

  void _handleStatus(String status) {
    // `done`/`notListening` end the session; a final result callback is
    // delivered separately, so nothing to do here beyond keeping state tidy.
  }

  static String _friendly(SpeechRecognitionError error) {
    switch (error.errorMsg) {
      case 'error_no_match':
        return 'I did not catch that. Try speaking again a little closer to the phone.';
      case 'error_speech_timeout':
        return 'No speech was detected. Tap the microphone and speak right away.';
      case 'error_audio_error':
        return 'The microphone is busy. Close other apps that are recording and try again.';
      case 'error_permission':
        return 'Microphone permission is needed to record by voice.';
      case 'error_busy':
        return 'The recogniser is busy. Wait a moment and try again.';
      case 'error_network':
        return 'Recognition needs a network connection right now.';
      default:
        return 'Speech recognition failed'
            '${error.permanent ? ' permanently' : ''}. You can type instead.';
    }
  }
}
