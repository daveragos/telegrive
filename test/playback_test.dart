import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:telegrive/core/files/file_kind.dart';
import 'package:telegrive/core/format/formatters.dart';
import 'package:telegrive/features/drive/domain/drive_models.dart';
import 'package:telegrive/features/player/data/playback.dart';
import 'package:telegrive/features/player/presentation/player_controls.dart';
import 'package:telegrive/infrastructure/storage/preferences.dart';
import 'package:video_player/video_player.dart';

void main() {
  group('Playback', () {
    test('next steps through the speeds and wraps to the slowest', () {
      final seen = <double>[];
      var speed = 0.75;
      for (var i = 0; i < 6; i++) {
        speed = Playback.next(speed);
        seen.add(speed);
      }
      expect(seen, [1, 1.25, 1.5, 1.75, 2, 0.75]);
    });

    test('next from a speed that is not offered picks the one above it', () {
      expect(Playback.next(1.1), 1.25);
    });

    test('sanitize keeps an offered speed and falls back to 1', () {
      expect(Playback.sanitize(null), 1);
      expect(Playback.sanitize(3), 1);
      expect(Playback.sanitize(1.5), 1.5);
    });

    test('skipStep is 10 s under ten minutes and 30 s from there', () {
      expect(
        Playback.skipStep(const Duration(minutes: 9, seconds: 59)),
        const Duration(seconds: 10),
      );
      expect(
        Playback.skipStep(const Duration(minutes: 10)),
        const Duration(seconds: 30),
      );
      expect(
        Playback.skipStep(const Duration(hours: 2)),
        const Duration(seconds: 30),
      );
      expect(Playback.skipStep(Duration.zero), const Duration(seconds: 10));
    });
  });

  group('Formatters', () {
    test('rate drops trailing zeros and appends the sign', () {
      expect(Formatters.rate(1), '1×');
      expect(Formatters.rate(1.25), '1.25×');
      expect(Formatters.rate(0.75), '0.75×');
      expect(Formatters.rate(2), '2×');
      expect(Formatters.rate(1.5), '1.5×');
    });

    test('length reads as a clock', () {
      expect(
        Formatters.length(const Duration(minutes: 42, seconds: 10)),
        '42:10',
      );
      expect(
        Formatters.length(const Duration(hours: 1, minutes: 2, seconds: 3)),
        '1:02:03',
      );
      expect(Formatters.length(const Duration(seconds: 5)), '0:05');
    });
  });

  group('Preferences', () {
    test('remembers a speed for audio apart from video', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = Preferences(await SharedPreferences.getInstance());
      expect(prefs.playbackSpeed(audio: true), 1.0);
      expect(prefs.playbackSpeed(audio: false), 1.0);

      await prefs.setPlaybackSpeed(1.5, audio: true);

      expect(prefs.playbackSpeed(audio: true), 1.5);
      expect(prefs.playbackSpeed(audio: false), 1.0);
    });
  });

  group('PlayerControls', () {
    final file = DriveFile(
      id: 'lecture',
      folderId: null,
      name: 'Lecture 7 — Thermodynamics.mp4',
      mimeType: 'video/mp4',
      kind: FileKind.video,
      size: 1200 * 1024 * 1024,
      createdAt: DateTime(2026, 9, 1),
      modifiedAt: DateTime(2026, 9, 1),
      partCount: 1,
      starred: false,
    );

    Future<void> pump(
      WidgetTester tester, {
      required Duration step,
      double speed = 1,
      void Function(bool forward)? onSkip,
      VoidCallback? onSpeed,
    }) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              backgroundColor: Colors.black,
              body: PlayerControls(
                file: file,
                value: const VideoPlayerValue(
                  duration: Duration(hours: 1, minutes: 12, seconds: 40),
                  position: Duration(minutes: 42, seconds: 10),
                  isInitialized: true,
                  isPlaying: true,
                ),
                onPlay: () {},
                onSkip: onSkip ?? (_) {},
                onSeek: (_) {},
                step: step,
                speed: speed,
                onSpeed: onSpeed ?? () {},
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('a 30 s step shows the 30 glyphs and says so', (tester) async {
      final skips = <bool>[];
      await pump(tester, step: const Duration(seconds: 30), onSkip: skips.add);

      expect(find.byIcon(Icons.replay_30_rounded), findsOneWidget);
      expect(find.byIcon(Icons.forward_30_rounded), findsOneWidget);
      expect(find.byTooltip('Back 30 seconds'), findsOneWidget);
      expect(find.byTooltip('Forward 30 seconds'), findsOneWidget);
      expect(find.text('42:10'), findsOneWidget);
      expect(find.text('1:12:40'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.forward_30_rounded));
      await tester.tap(find.byIcon(Icons.replay_30_rounded));
      expect(skips, [true, false]);
    });

    testWidgets('a 10 s step shows the 10 glyphs', (tester) async {
      await pump(tester, step: const Duration(seconds: 10));

      expect(find.byIcon(Icons.replay_10_rounded), findsOneWidget);
      expect(find.byIcon(Icons.forward_10_rounded), findsOneWidget);
      expect(find.byTooltip('Back 10 seconds'), findsOneWidget);
      expect(find.byTooltip('Forward 10 seconds'), findsOneWidget);
    });

    testWidgets('the speed button shows the speed and asks for the next', (
      tester,
    ) async {
      var taps = 0;
      await pump(
        tester,
        step: const Duration(seconds: 30),
        speed: 1.5,
        onSpeed: () => taps++,
      );

      expect(find.byTooltip('Playback speed'), findsOneWidget);
      await tester.tap(find.text('1.5×'));
      expect(taps, 1);
    });
  });
}
