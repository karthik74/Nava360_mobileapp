import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';

import '../core/api_client.dart';

/// Kannada text-to-speech, fully self-hosted (AI4Bharat Indic-TTS behind our
/// own `/api/tts`). No device TTS engine and no third-party TTS API involved.
///
/// Resolution order per [speak] call:
///   1. Bundled asset — pre-generated phrases shipped in assets/tts/ with a
///      manifest.json mapping sha256(phrase text) → asset path (instant,
///      offline, no bytes downloaded).
///   2. Local cache — previously fetched audio in the app cache dir, keyed by
///      sha256(text + gender).
///   3. Network — POST /api/tts on the configured backend (30 s timeout, one
///      retry); the MP3 is cached for next time. Cold synthesis on the
///      CPU-only server runs ~50 ms/char, so sentence-sized chunks take a
///      few seconds each — the next chunk is prefetched while one plays.
///
/// A new [speak] always stops current playback first. Offline with a cache
/// miss returns false (logged in debug) so the UI can react; never throws.
class TtsService {
  TtsService._()
      : _player = _JustAudioPlayer(),
        _fetchBytes = _defaultFetcher,
        _loadManifest = _defaultManifestLoader,
        _cacheDir = _defaultCacheDir;

  /// Injectable constructor for tests: fake player, manifest, cache dir and
  /// network so the resolution order is verifiable without platform channels.
  @visibleForTesting
  TtsService.test({
    required TtsAudioPlayer player,
    required Future<Uint8List> Function(String text, String gender) fetchBytes,
    required Future<Map<String, String>> Function() loadManifest,
    required Future<Directory> Function() cacheDir,
  })  : _player = player,
        _fetchBytes = fetchBytes,
        _loadManifest = loadManifest,
        _cacheDir = cacheDir;

  static final TtsService instance = TtsService._();

  static const String manifestAsset = 'assets/tts/manifest.json';

  final TtsAudioPlayer _player;
  final Future<Uint8List> Function(String text, String gender) _fetchBytes;
  final Future<Map<String, String>> Function() _loadManifest;
  final Future<Directory> Function() _cacheDir;

  Map<String, String>? _manifest;

  /// Bumped by stop()/speak() so an in-flight chunked playback notices it was
  /// barged in on and aborts between chunks.
  int _generation = 0;

  /// Speaks [text]; returns false when no audio could be resolved (offline
  /// AND not bundled/cached) so callers may show a hint. Never throws.
  ///
  /// Long texts (assistant replies) are split into sentence chunks under the
  /// server's 500-char limit and spoken sequentially — the model also sounds
  /// better on sentence-sized inputs.
  Future<bool> speak(String text, {String gender = 'female'}) async {
    final t = sanitizeForTts(text);
    if (t.isEmpty) return false;

    await stop();
    final gen = ++_generation;

    final chunks = chunkText(t);
    var spokeAny = false;
    // Pipeline: while a chunk plays (several seconds of audio), the next one
    // is already resolving — network synthesis roughly keeps pace with
    // playback, so only the first chunk is ever waited on in silence.
    var next = _resolveChunk(chunks.first, gender);
    for (var i = 0; i < chunks.length; i++) {
      final source = await next;
      if (gen != _generation) break; // stopped or replaced mid-reply
      if (i + 1 < chunks.length) next = _resolveChunk(chunks[i + 1], gender);
      if (source == null) return spokeAny;
      await source.playOn(_player);
      spokeAny = true;
    }
    return spokeAny;
  }

  /// Resolves ONE chunk (asset → cache → network) to something playable
  /// WITHOUT playing it, so the next chunk can be prepared while the current
  /// one is speaking. Returns null when no audio could be obtained.
  Future<_TtsSource?> _resolveChunk(String text, String gender) async {
    // 1. Bundled asset (pre-generated common phrases).
    try {
      _manifest ??= await _loadManifest();
      final asset = _manifest![_sha256(text)];
      if (asset != null) return _TtsSource.asset(asset);
    } catch (e) {
      debugPrint('TtsService: bundled-asset path failed: $e');
    }

    // 2. Local cache.
    File? cacheFile;
    try {
      cacheFile = await _cacheFileFor(text, gender);
      if (await cacheFile.exists() && await cacheFile.length() > 0) {
        return _TtsSource.file(cacheFile.path);
      }
    } catch (e) {
      debugPrint('TtsService: cache lookup failed: $e');
    }

    // 3. Network (30 s timeout, one retry), then cache the result. The cache
    // dir is the app temp dir — if even that is unwritable there is no way to
    // hand bytes to the player, so fail soft.
    if (cacheFile == null) return null;
    try {
      final bytes = await _fetchWithRetry(text, gender);
      if (bytes.isEmpty) throw ApiException('empty TTS response');
      // Write-then-rename: a killed app never leaves a truncated MP3 that
      // would be replayed as a cache hit forever.
      final part = File('${cacheFile.path}.part');
      await part.writeAsBytes(bytes, flush: true);
      await part.rename(cacheFile.path);
      return _TtsSource.file(cacheFile.path);
    } catch (e) {
      debugPrint('TtsService: network TTS failed: $e');
      return null;
    }
  }

  /// Stops any current playback (and aborts a chunked reply between chunks).
  Future<void> stop() async {
    _generation++;
    await _player.stop();
  }

  // ── text preparation ──────────────────────────────────────────────────────

  /// Emoji/pictographs/ZWJ — the voice can't say them, and the synthesis
  /// model crashes outright on fragments made only of symbols. Mirrors the
  /// server-side sanitizer (tts-service/app.py) so cache keys line up.
  static final RegExp _noiseChars = RegExp(
      r'[\u{1F000}-\u{1FAFF}\u{2190}-\u{21FF}\u{2300}-\u{27BF}'
      r'\u{2B00}-\u{2BFF}\u{FE0E}\u{FE0F}\u{200D}]',
      unicode: true);

  @visibleForTesting
  static String sanitizeForTts(String text) {
    var t = text.replaceAll(_noiseChars, ' ');
    t = t.replaceAll(RegExp(r'[-_=*#|•]{2,}'), ' '); // markdown table plumbing
    t = t.replaceAllMapped(RegExp(r'[:;]\s*([.!?])'), (m) => m[1]!);
    t = t.replaceAllMapped(RegExp(r'([.!?])(\s*[.!?])+'), (m) => m[1]!);
    t = t.replaceAllMapped(RegExp(r'\s+([.,!?])'), (m) => m[1]!);
    t = t.replaceAll(RegExp(r'\s{2,}'), ' ');
    return t.trim();
  }

  /// Server caps requests at 500 chars, but latency dictates a much smaller
  /// chunk: cold synthesis runs ~50 ms/char on the CPU-only server, so a
  /// sentence-sized chunk is ready in a few seconds (450 chars would sit
  /// silent for ~20 s before the first word). Playback of one chunk covers
  /// the synthesis of the next.
  static const int _maxChunkChars = 200;

  /// Greedily packs whole sentences into chunks of at most [_maxChunkChars];
  /// a single over-long sentence is hard-split at word boundaries.
  @visibleForTesting
  static List<String> chunkText(String text) {
    if (text.length <= _maxChunkChars) return [text];
    final chunks = <String>[];
    var current = StringBuffer();
    void flush() {
      final s = current.toString().trim();
      if (s.isNotEmpty) chunks.add(s);
      current = StringBuffer();
    }

    for (var sentence in text.split(RegExp(r'(?<=[.!?।])\s+'))) {
      while (sentence.length > _maxChunkChars) {
        var cut = sentence.lastIndexOf(' ', _maxChunkChars);
        if (cut <= 0) cut = _maxChunkChars;
        flush();
        chunks.add(sentence.substring(0, cut).trim());
        sentence = sentence.substring(cut).trim();
      }
      if (current.length + sentence.length + 1 > _maxChunkChars) flush();
      current.write(current.isEmpty ? sentence : ' $sentence');
    }
    flush();
    return chunks;
  }

  Future<Uint8List> _fetchWithRetry(String text, String gender) async {
    try {
      return await _fetchBytes(text, gender);
    } catch (_) {
      return await _fetchBytes(text, gender); // exactly one retry
    }
  }

  Future<File> _cacheFileFor(String text, String gender) async {
    final dir = await _cacheDir();
    final cache = Directory('${dir.path}${Platform.pathSeparator}tts_cache');
    if (!await cache.exists()) await cache.create(recursive: true);
    final key = _sha256('$text|$gender');
    return File('${cache.path}${Platform.pathSeparator}$key.mp3');
  }

  static String _sha256(String s) => sha256.convert(utf8.encode(s)).toString();

  // ── default (production) wiring ───────────────────────────────────────────

  static Future<Uint8List> _defaultFetcher(String text, String gender) {
    // Base URL/JWT come from the app's ApiClient (Env.apiBaseUrl) — nothing
    // hardcoded here. Cold synthesis takes ~50 ms/char server-side (~10 s for
    // a full chunk) plus transfer on mobile data, so give it a real budget.
    return ApiClient.instance
        .postBytes('/api/tts',
            body: {'text': text, 'gender': gender, 'format': 'mp3'},
            receiveTimeout: const Duration(seconds: 30))
        .timeout(const Duration(seconds: 35));
  }

  static Future<Map<String, String>> _defaultManifestLoader() async {
    try {
      final raw = await rootBundle.loadString(manifestAsset);
      return (jsonDecode(raw) as Map<String, dynamic>)
          .map((k, v) => MapEntry(k, v as String));
    } catch (_) {
      return const {}; // no bundled phrases — cache/network still work
    }
  }

  static Future<Directory> _defaultCacheDir() => getTemporaryDirectory();
}

/// A resolved, ready-to-play piece of audio: either a bundled asset or a
/// local file (cache hit or freshly fetched network audio).
class _TtsSource {
  const _TtsSource.asset(String this._asset) : _file = null;
  const _TtsSource.file(String this._file) : _asset = null;

  final String? _asset;
  final String? _file;

  Future<void> playOn(TtsAudioPlayer player) =>
      _asset != null ? player.playAsset(_asset) : player.playFile(_file!);
}

/// Thin playback seam so unit tests can observe what would be played without
/// touching just_audio's platform channels. play* methods complete when the
/// audio FINISHES (or is stopped) — chunked replies rely on that to speak
/// pieces sequentially.
abstract class TtsAudioPlayer {
  Future<void> playAsset(String assetPath);
  Future<void> playFile(String path);
  Future<void> stop();
}

class _JustAudioPlayer implements TtsAudioPlayer {
  final AudioPlayer _player = AudioPlayer();

  @override
  Future<void> playAsset(String assetPath) async {
    final duration = await _player.setAsset(assetPath);
    debugPrint('TtsService: playing asset $assetPath '
        '(${duration?.inMilliseconds ?? '?'} ms)');
    await _player.play(); // completes at end of audio or on stop()
  }

  @override
  Future<void> playFile(String path) async {
    final duration = await _player.setFilePath(path);
    debugPrint('TtsService: playing ${duration?.inMilliseconds ?? '?'} ms '
        'of audio from cache/network');
    await _player.play(); // completes at end of audio or on stop()
  }

  @override
  Future<void> stop() async {
    try {
      await _player.stop();
    } catch (_) {/* nothing playing */}
  }
}
