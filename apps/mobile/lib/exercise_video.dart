import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import 'account.dart';
import 'app_theme.dart';

class ExerciseVideo extends StatefulWidget {
  final AccountController account;
  final String exerciseId;
  const ExerciseVideo({
    super.key,
    required this.account,
    required this.exerciseId,
  });
  @override
  State<ExerciseVideo> createState() => _ExerciseVideoState();
}

class _ExerciseVideoState extends State<ExerciseVideo> {
  VideoPlayerController? _player;
  bool _loading = true;
  String? _message;
  int _generation = 0;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final generation = ++_generation;
    final previous = _player;
    _player = null;
    setState(() {
      _loading = true;
      _message = null;
    });
    await previous?.dispose();
    VideoPlayerController? candidate;
    try {
      final media = await widget.account.authenticatedRequest(
        '/me/exercises/${widget.exerciseId}/video',
      );
      if (!mounted || generation != _generation) {
        return;
      }
      if (media['available'] != true) {
        setState(() {
          _loading = false;
          _message = 'The demonstration video has not been supplied yet.';
        });
        return;
      }
      final uri = Uri.parse(widget.account.api.baseUrl)
          .resolve(media['playbackPath'] as String);
      candidate = VideoPlayerController.networkUrl(uri);
      await candidate.initialize().timeout(const Duration(seconds: 20));
      if (!mounted || generation != _generation) {
        await candidate.dispose();
        return;
      }
      setState(() {
        _player = candidate;
        _loading = false;
      });
    } catch (_) {
      await candidate?.dispose();
      if (mounted && generation == _generation) {
        setState(() {
          _loading = false;
          _message = 'The video could not load. Retry to request a fresh playback link.';
        });
      }
    }
  }

  @override
  void dispose() {
    _generation++;
    _player?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return _videoPanel(
        const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 26,
              height: 26,
              child: CircularProgressIndicator(color: lime, strokeWidth: 2),
            ),
            SizedBox(height: 16),
            Text(
              'Loading demonstration…',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
        ),
      );
    }
    if (_message != null) {
      return _videoPanel(
        Column(
          children: [
            const Icon(Icons.ondemand_video_outlined, color: lime, size: 32),
            const SizedBox(height: 12),
            Text(
              _message!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white70,
                height: 1.5,
                fontSize: 13,
              ),
            ),
            TextButton(
              onPressed: _load,
              style: TextButton.styleFrom(foregroundColor: lime),
              child: const Text('Retry video'),
            ),
          ],
        ),
      );
    }
    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: _player!,
      builder: (context, value, _) {
        if (value.hasError) {
          return _videoPanel(
            Column(
              children: [
                const Text(
                  'Playback stopped. Refresh the link to retry.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70),
                ),
                TextButton(
                  onPressed: _load,
                  style: TextButton.styleFrom(foregroundColor: lime),
                  child: const Text('Retry video'),
                ),
              ],
            ),
          );
        }
        return Column(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: ColoredBox(
                color: Colors.black,
                child: AspectRatio(
                  aspectRatio: value.aspectRatio,
                  child: VideoPlayer(_player!),
                ),
              ),
            ),
            VideoProgressIndicator(
              _player!,
              allowScrubbing: true,
              colors: const VideoProgressColors(
                playedColor: forest,
                bufferedColor: Color(0xFFB5C6B8),
                backgroundColor: Color(0xFFE3E9E3),
              ),
            ),
            Row(
              children: [
                IconButton(
                  tooltip: value.isPlaying
                      ? 'Pause demonstration'
                      : 'Play demonstration',
                  onPressed: () async {
                    try {
                      if (value.isPlaying) {
                        await _player!.pause();
                      } else {
                        await _player!.play();
                      }
                    } catch (_) {
                      if (mounted) {
                        setState(
                          () => _message =
                              'Playback could not start. Please retry.',
                        );
                      }
                    }
                  },
                  icon: Icon(
                    value.isPlaying ? Icons.pause_circle : Icons.play_circle,
                    size: 40,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${_time(value.position)} / ${_time(value.duration)}',
                    style: const TextStyle(
                      color: muted,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  String _time(Duration value) =>
      '${value.inMinutes}:${(value.inSeconds % 60).toString().padLeft(2, '0')}';

  Widget _videoPanel(Widget child) => Container(
    width: double.infinity,
    margin: const EdgeInsets.symmetric(vertical: 12),
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      color: ink,
      borderRadius: BorderRadius.circular(18),
    ),
    child: Center(child: child),
  );
}
