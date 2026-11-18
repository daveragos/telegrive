import 'package:flutter_test/flutter_test.dart';
import 'package:telegrive/features/mount/data/drive_mount.dart';

void main() {
  final address = Uri.parse('http://127.0.0.1:50221/YrXrJpOKRPLmmH_Ejx5-152s/Telegrive/');

  test('a Mac\'s mount list says where the drive is', () {
    const listing = '''
/dev/disk3s1s1 on / (apfs, sealed, local, read-only, journaled)
devfs on /dev (devfs, local, nobrowse)
http://127.0.0.1:50221/YrXrJpOKRPLmmH_Ejx5-152s/Telegrive/ on /Volumes/Telegrive 1 (webdav, nodev, noexec, nosuid, mounted by sam)
''';
    expect(DriveMount.macMountPoint(listing, address), '/Volumes/Telegrive 1');
    expect(DriveMount.macMountPoint(listing, Uri.parse('http://127.0.0.1:1/other/Telegrive/')), isNull);
  });

  test('net use says which letter the drive has', () {
    const listing = '''
New connections will not be remembered.


Status       Local     Remote                    Network

-------------------------------------------------------------------------------
OK           Z:        \\\\nas\\media                Microsoft Windows Network
             T:        \\\\127.0.0.1@50221\\YrXrJpOKRPLmmH_Ejx5-152s\\Telegrive
                                                Web Client Network
The command completed successfully.
''';
    expect(DriveMount.windowsDriveLetter(listing, address), 'T:');
    expect(DriveMount.windowsDriveLetter(listing, Uri.parse('http://127.0.0.1:1/other/Telegrive/')), isNull);
  });
}
