import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:telegrive/infrastructure/media/desktop_media.dart';

void main() {
  test('a Mac makes a JPEG of a HEIC photo with its own image library', () async {
    final dir = await Directory.systemTemp.createTemp('system_jpeg');
    addTearDown(() => dir.delete(recursive: true));
    final jpeg = p.join(dir.path, 'photo.jpg');
    await File(jpeg).writeAsBytes(img.encodeJpg(img.Image(width: 1200, height: 800)..clear(img.ColorRgb8(30, 90, 200))));
    final heic = p.join(dir.path, 'photo.heic');
    final made = await Process.run('sips', ['-s', 'format', 'heic', jpeg, '--out', heic]);
    expect(made.exitCode, 0, reason: '${made.stderr}');

    final out = await DesktopMedia.systemJpeg(heic, side: 320, out: p.join(dir.path, 'out', 'small.jpg'));
    expect(out, isNotNull);
    final small = img.decodeJpg(await File(out!).readAsBytes())!;
    expect((small.width, small.height), (320, 213));

    expect(await DesktopMedia.systemJpeg(p.join(dir.path, 'missing.heic'), side: 320, out: p.join(dir.path, 'x.jpg')), isNull);
  }, skip: !Platform.isMacOS);
}
