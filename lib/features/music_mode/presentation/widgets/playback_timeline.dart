import 'package:flutter/material.dart';

import '../../../player/application/local_audio_playback_controller.dart';

class PlaybackTimeline extends StatefulWidget {
  const PlaybackTimeline({
    super.key,
    required this.state,
    required this.onSeek,
  });

  final LocalAudioPlaybackState state;
  final ValueChanged<Duration> onSeek;

  @override
  State<PlaybackTimeline> createState() => _PlaybackTimelineState();
}

class _PlaybackTimelineState extends State<PlaybackTimeline> {
  Duration? _dragPosition;

  @override
  void didUpdateWidget(covariant PlaybackTimeline oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.state.currentEntry?.id != widget.state.currentEntry?.id) {
      _dragPosition = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final duration = widget.state.duration;
    final canSeek =
        widget.state.currentEntry != null && duration > Duration.zero;
    final position = _clampPosition(_dragPosition ?? widget.state.position);
    final maxMilliseconds = canSeek ? duration.inMilliseconds.toDouble() : 1.0;
    final value = canSeek ? position.inMilliseconds.toDouble() : 0.0;

    return Column(
      children: [
        Slider(
          value: value,
          max: maxMilliseconds,
          onChanged: canSeek
              ? (value) {
                  setState(() {
                    _dragPosition = Duration(milliseconds: value.round());
                  });
                }
              : null,
          onChangeEnd: canSeek
              ? (value) {
                  final target = Duration(milliseconds: value.round());
                  widget.onSeek(target);
                  setState(() {
                    _dragPosition = null;
                  });
                }
              : null,
        ),
        Row(
          children: [
            Text(formatDuration(position)),
            const Spacer(),
            Text(formatDuration(duration)),
          ],
        ),
      ],
    );
  }

  Duration _clampPosition(Duration position) {
    final duration = widget.state.duration;
    if (position < Duration.zero) return Duration.zero;
    if (duration > Duration.zero && position > duration) return duration;
    return position;
  }
}

String formatDuration(Duration duration) {
  final totalSeconds = duration.inSeconds;
  final hours = totalSeconds ~/ Duration.secondsPerHour;
  final minutes = (totalSeconds ~/ Duration.secondsPerMinute) % 60;
  final seconds = totalSeconds % Duration.secondsPerMinute;

  if (hours > 0) {
    return '$hours:${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }

  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}
