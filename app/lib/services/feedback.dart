import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../core/analysis.dart';

/// Pitidos y voz. Los reproductores se crean en [init] (no al construir),
/// para no tocar plugins nativos hasta que la app arranca de verdad.
class FeedbackService {
  AudioPlayer? _rep, _warning, _stop;
  FlutterTts? _tts;

  Future<void> init() async {
    try {
      _rep = AudioPlayer();
      _warning = AudioPlayer();
      _stop = AudioPlayer();
      for (final (p, f) in [
        (_rep!, 'sounds/rep.wav'),
        (_warning!, 'sounds/warning.wav'),
        (_stop!, 'sounds/stop.wav'),
      ]) {
        await p.setPlayerMode(PlayerMode.lowLatency);
        await p.setReleaseMode(ReleaseMode.stop);
        await p.setVolume(1.0);
        await p.setSource(AssetSource(f));
      }
    } catch (_) {
      _rep = _warning = _stop = null; // Sin audio: la app sigue funcionando.
    }
    try {
      final tts = FlutterTts();
      await tts.setLanguage('es-ES');
      await tts.setSpeechRate(0.6);
      _tts = tts;
    } catch (_) {
      _tts = null;
    }
  }

  Future<void> onRep({
    required FatigueLevel level,
    required bool beepEachRep,
    required bool speak,
    required double velocity,
  }) async {
    try {
      final player = switch (level) {
        FatigueLevel.stop => _stop,
        FatigueLevel.warning => beepEachRep ? _warning : null,
        FatigueLevel.fresh || FatigueLevel.off => beepEachRep ? _rep : null,
      };
      if (player != null) {
        await player.stop();
        await player.resume();
      }
      if (speak && _tts != null) {
        // "85" se entiende mejor que "cero coma ochenta y cinco".
        await _tts!.speak((velocity * 100).round().toString());
      }
    } catch (_) {}
  }

  void dispose() {
    _rep?.dispose();
    _warning?.dispose();
    _stop?.dispose();
    _tts?.stop();
  }
}
