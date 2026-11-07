import 'package:audio_service/audio_service.dart';

/// What the phone's lock screen / notification shades can do with "Listen": show a title, Play/Pause, Previous/Next
/// page and Stop. An interface so tests need no phone service.
abstract class MediaControls {
  /// Shows (or updates) the controls. The callbacks run when the user presses the button on the lock screen.
  Future<void> show({
    required String title,
    required String subtitle,
    required bool playing,
    required Future<void> Function() onPlay,
    required Future<void> Function() onPause,
    required Future<void> Function() onStop,
    required Future<void> Function() onNext,
    required Future<void> Function() onPrevious,
  });

  /// Removes them (and lets the phone stop the background service).
  Future<void> hide();
}

class _Handler extends BaseAudioHandler {
  Future<void> Function()? play_, pause_, stop_, next_, prev_;

  @override
  Future<void> play() async => await play_?.call();
  @override
  Future<void> pause() async => await pause_?.call();
  @override
  Future<void> stop() async {
    await stop_?.call();
    await super.stop();
  }

  @override
  Future<void> skipToNext() async => await next_?.call();
  @override
  Future<void> skipToPrevious() async => await prev_?.call();
}

/// The real thing, built on audio_service (a foreground "media" service: it keeps reading going with the screen off).
class AudioServiceControls implements MediaControls {
  _Handler? _handler;
  Future<_Handler?>? _starting;

  Future<_Handler?> _ensure() => _starting ??= () async {
    try {
      return await AudioService.init(
        builder: _Handler.new,
        config: const AudioServiceConfig(
          androidNotificationChannelId: 'app.folio.listen',
          androidNotificationChannelName: 'Reading aloud',
          androidNotificationOngoing: false,
          androidStopForegroundOnPause: false,
        ),
      );
    } catch (_) {
      return null; // lock-screen controls are a convenience: reading still works without them
    }
  }();

  @override
  Future<void> show({
    required String title,
    required String subtitle,
    required bool playing,
    required Future<void> Function() onPlay,
    required Future<void> Function() onPause,
    required Future<void> Function() onStop,
    required Future<void> Function() onNext,
    required Future<void> Function() onPrevious,
  }) async {
    final h = _handler ??= await _ensure();
    if (h == null) return;
    h
      ..play_ = onPlay
      ..pause_ = onPause
      ..stop_ = onStop
      ..next_ = onNext
      ..prev_ = onPrevious;
    h.mediaItem.add(MediaItem(id: 'folio-listen', title: title, album: subtitle, artist: subtitle));
    h.playbackState.add(
      PlaybackState(
        controls: [
          MediaControl.skipToPrevious,
          playing ? MediaControl.pause : MediaControl.play,
          MediaControl.stop,
          MediaControl.skipToNext,
        ],
        systemActions: const {MediaAction.play, MediaAction.pause, MediaAction.stop, MediaAction.skipToNext, MediaAction.skipToPrevious},
        androidCompactActionIndices: const [0, 1, 3],
        processingState: AudioProcessingState.ready,
        playing: playing,
      ),
    );
  }

  @override
  Future<void> hide() async {
    final h = _handler;
    if (h == null) return;
    h
      ..play_ = null
      ..pause_ = null
      ..stop_ = null
      ..next_ = null
      ..prev_ = null;
    try {
      await h.stop(); // ends the background service and removes the notification
    } catch (_) {}
  }
}
