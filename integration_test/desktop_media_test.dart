// Runs inside the macOS, Windows or Linux app, where Flutter's decoder and
// mpv are real, so needs a desktop and two short videos to probe, one of
// them 4K HEVC in mkv, which the phones' players don't all open:
//
//   ffmpeg -f lavfi -i testsrc=duration=4:size=640x360:rate=25 -pix_fmt yuv420p /tmp/sample.mp4
//   ffmpeg -f lavfi -i testsrc2=duration=6:size=3840x2160:rate=30 -c:v libx265 -pix_fmt yuv420p /tmp/uhd.mkv
//   flutter test integration_test/desktop_media_test.dart -d macos \
//     --dart-define=SAMPLE_VIDEO=/tmp/sample.mp4 --dart-define=SAMPLE_UHD=/tmp/uhd.mkv

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path/path.dart' as p;
import 'package:telegrive/infrastructure/media/desktop_media.dart';

const _sampleVideo = String.fromEnvironment('SAMPLE_VIDEO');
const _sampleUhd = String.fromEnvironment('SAMPLE_UHD');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;

  setUpAll(MediaKit.ensureInitialized);

  setUp(() async => dir = await Directory.systemTemp.createTemp('desktop_media'));
  tearDown(() => dir.delete(recursive: true));

  testWidgets('a photo gets a small JPEG preview and its date taken', (tester) async {
    await tester.runAsync(() async {
      final photo = img.Image(width: 2400, height: 1600)..clear(img.ColorRgb8(200, 120, 40));
      photo.exif.exifIfd[0x9003] = img.IfdValueAscii('2024:05:06 07:08:09');
      final path = p.join(dir.path, 'photo.jpg');
      await File(path).writeAsBytes(img.encodeJpg(photo));

      final out = await DesktopMedia.photoThumbnail(path, out: p.join(dir.path, 'thumb.jpg'));
      expect(out, isNotNull);
      final thumb = img.decodeJpg(await File(out!).readAsBytes())!;
      expect(thumb.width, 320);
      expect(thumb.height, 213);
      expect(await File(out).length(), lessThan(200 * 1024));

      expect(await DesktopMedia.photoTakenAt(path), DateTime(2024, 5, 6, 7, 8, 9));
    });
  });

  testWidgets('a PDF gets its first page as a small JPEG preview', (tester) async {
    await tester.runAsync(() async {
      final path = p.join(dir.path, 'letter.pdf');
      await File(path).writeAsBytes(_letterWithRedBox());

      final out = await DesktopMedia.pdfThumbnail(path, out: p.join(dir.path, 'page.jpg'));
      expect(out, isNotNull);
      final page = img.decodeJpg(await File(out!).readAsBytes())!;
      expect(page.width, 247);
      expect(page.height, 320);
      expect(page.getPixel(2, 2).r, greaterThan(240));
      expect(page.getPixel(2, 2).g, greaterThan(240));
      final middle = page.getPixel(123, 160);
      expect(middle.r, greaterThan(200));
      expect(middle.g, lessThan(60));

      final notPdf = p.join(dir.path, 'not.pdf');
      await File(notPdf).writeAsString('not a PDF');
      expect(await DesktopMedia.pdfThumbnail(notPdf, out: p.join(dir.path, 'none.jpg')), isNull);
    });
  });

  testWidgets('a video says how long it runs and gives a frame', (tester) async {
    await tester.runAsync(() async {
      final probed = await DesktopMedia.probe(_sampleVideo, frameOut: p.join(dir.path, 'frame.jpg'));
      expect(probed.seconds, 4);
      expect(probed.frame, isNotNull);
      final frame = img.decodeJpg(await File(probed.frame!).readAsBytes())!;
      expect(frame.width, 320);
      expect(frame.height, 180);
    });
  }, skip: _sampleVideo.isEmpty);

  testWidgets('a 4K HEVC video in mkv gives a frame its preview size', (tester) async {
    await tester.runAsync(() async {
      final probed = await DesktopMedia.probe(_sampleUhd, frameOut: p.join(dir.path, 'frame.jpg'));
      expect(probed.seconds, 6);
      final frame = img.decodeJpg(await File(probed.frame!).readAsBytes())!;
      expect(frame.width, 320);
      expect(frame.height, 180);
      // A real picture, not a blank one.
      expect({for (final px in frame) px.luminance}.length, greaterThan(100));
    });
  }, skip: _sampleUhd.isEmpty);
}

/// A Letter-sized page, white, with a red box over its middle.
List<int> _letterWithRedBox() {
  const content = '1 0 0 rg 100 100 412 592 re f';
  const objects = [
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R >>',
    '<< /Length 29 >>\nstream\n$content\nendstream',
  ];
  final pdf = StringBuffer('%PDF-1.4\n');
  final offsets = <int>[];
  for (final (i, object) in objects.indexed) {
    offsets.add(pdf.length);
    pdf.write('${i + 1} 0 obj\n$object\nendobj\n');
  }
  final xref = pdf.length;
  pdf.write('xref\n0 ${objects.length + 1}\n0000000000 65535 f \n');
  for (final offset in offsets) {
    pdf.write('${offset.toString().padLeft(10, '0')} 00000 n \n');
  }
  pdf.write('trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\nstartxref\n$xref\n%%EOF\n');
  return ascii.encode(pdf.toString());
}
