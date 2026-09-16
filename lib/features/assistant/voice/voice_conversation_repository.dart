import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api_client.dart';

/// Result of a Saaras speech-to-text call.
class VoiceTranscript {
  const VoiceTranscript(this.text, this.languageCode);
  final String text;
  final String? languageCode;
}

/// Proxies the backend Sarvam voice endpoints (the API key stays server-side):
///   POST /api/assistant/voice/stt  — recorded audio → transcript (+ language)
///   POST /api/assistant/voice/tts  — reply text → base64 WAV clips
class VoiceConversationRepository {
  VoiceConversationRepository(this._api);
  final ApiClient _api;

  /// Transcribes a recorded WAV file. Returns empty text when nothing was heard.
  Future<VoiceTranscript> transcribe(String filePath) async {
    final form = FormData.fromMap({
      'audio': await MultipartFile.fromFile(filePath, filename: 'utterance.wav'),
    });
    return _api.post<VoiceTranscript>(
      '/api/assistant/voice/stt',
      body: form,
      parse: (d) {
        final m = (d as Map).cast<String, dynamic>();
        return VoiceTranscript(
          (m['text'] as String? ?? '').trim(),
          m['languageCode'] as String?,
        );
      },
    );
  }

  /// Synthesizes [text] into decoded WAV byte clips, played back-to-back.
  /// [languageCode] is the language the reply should be spoken in.
  Future<List<List<int>>> synthesize(String text, String? languageCode) async {
    return _api.post<List<List<int>>>(
      '/api/assistant/voice/tts',
      body: {'text': text, 'languageCode': languageCode},
      parse: (d) {
        final m = (d as Map).cast<String, dynamic>();
        final audios = (m['audios'] as List?) ?? const [];
        return audios
            .map((a) => base64Decode(a as String))
            .map<List<int>>((bytes) => bytes)
            .toList();
      },
    );
  }
}

final voiceConversationRepositoryProvider = Provider(
    (ref) => VoiceConversationRepository(ref.watch(apiClientProvider)));
