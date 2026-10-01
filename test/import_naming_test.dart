import 'package:flutter_test/flutter_test.dart';
import 'package:telegrive/core/files/file_kind.dart';
import 'package:telegrive/features/import/data/import_naming.dart';

void main() {
  final date = DateTime(2023, 3, 3, 18, 4, 12);

  test('a file with a name of its own keeps it', () {
    expect(
      ImportNaming.nameFor(
        fileName: 'Lease 2023.pdf',
        hasOwnName: true,
        kind: FileKind.document,
        mimeType: 'application/pdf',
        date: date,
      ),
      'Lease 2023.pdf',
    );
    expect(
      ImportNaming.nameFor(
        fileName: 'Trip.mp4',
        hasOwnName: true,
        kind: FileKind.video,
        mimeType: 'video/mp4',
        date: date,
      ),
      'Trip.mp4',
    );
  });

  test('a photo is named after when it was sent', () {
    expect(
      ImportNaming.nameFor(
        fileName: 'photo_12.jpg',
        hasOwnName: false,
        kind: FileKind.image,
        mimeType: 'image/jpeg',
        date: date,
      ),
      'Photo 2023-03-03 18.04.12.jpg',
    );
  });

  test('a video or audio file without a name gets its kind and extension', () {
    expect(
      ImportNaming.nameFor(
        fileName: 'video_12.mp4',
        hasOwnName: false,
        kind: FileKind.video,
        mimeType: 'video/mp4',
        date: date,
      ),
      'Video 2023-03-03 18.04.12.mp4',
    );
    expect(
      ImportNaming.nameFor(
        fileName: 'audio_12.mp3',
        hasOwnName: false,
        kind: FileKind.audio,
        mimeType: 'audio/mpeg',
        date: date,
      ),
      'Audio 2023-03-03 18.04.12.mp3',
    );
  });

  test('another file without a name takes its extension from its type', () {
    expect(
      ImportNaming.nameFor(
        fileName: 'file_12',
        hasOwnName: false,
        kind: FileKind.document,
        mimeType: 'application/pdf',
        date: date,
      ),
      'File 2023-03-03 18.04.12.pdf',
    );
    expect(
      ImportNaming.nameFor(
        fileName: 'file_12.epub',
        hasOwnName: false,
        kind: FileKind.document,
        mimeType: 'application/pdf',
        date: date,
      ),
      'File 2023-03-03 18.04.12.epub',
    );
    expect(
      ImportNaming.nameFor(
        fileName: 'file_12',
        hasOwnName: false,
        kind: FileKind.other,
        mimeType: 'application/octet-stream',
        date: date,
      ),
      'File 2023-03-03 18.04.12',
    );
  });

  test('the same message always gives the same name', () {
    String name() => ImportNaming.nameFor(
      fileName: 'photo_12.jpg',
      hasOwnName: false,
      kind: FileKind.image,
      mimeType: 'image/jpeg',
      date: DateTime(2023, 3, 3, 18, 4, 12),
    );
    expect(name(), name());
  });
}
