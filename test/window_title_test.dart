import 'package:flutter_test/flutter_test.dart';
import 'package:telegrive/app/desktop_window_title.dart';
import 'package:telegrive/features/drive/domain/drive_models.dart';

void main() {
  final work = DriveFolder(
    id: 'f1',
    parentId: null,
    name: 'Work',
    createdAt: DateTime(2026),
    modifiedAt: DateTime(2026),
  );
  final folders = {work.id: work};

  test('the window is named for the folder open in Files', () {
    expect(WindowTitle.at('/files/f1', folders), 'Work');
    expect(WindowTitle.at('/files', folders), 'Files');
    expect(WindowTitle.at('/files/gone', folders), 'Files');
  });

  test('a place takes the sidebar name, a page under it too', () {
    expect(WindowTitle.at('/photos', folders), 'Photos');
    expect(WindowTitle.at('/backup', folders), 'Folder sync');
    expect(WindowTitle.at('/settings/proxy', folders), 'Settings');
    expect(WindowTitle.at('/search', folders), 'Search');
  });

  test('Home and a file open on its own show the app name, and Private no folder', () {
    expect(WindowTitle.at('/home', folders), 'Telegrive');
    expect(WindowTitle.at('/viewer/x', folders), 'Telegrive');
    expect(WindowTitle.at('/private/f1', folders), 'Private');
  });
}
