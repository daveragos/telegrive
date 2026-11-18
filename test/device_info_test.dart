import 'package:flutter_test/flutter_test.dart';
import 'package:telegrive/infrastructure/telegram/device_info.dart';

void main() {
  group('DeviceInfo on a computer', () {
    test('names a Mac by its family', () {
      expect(DeviceInfo.macModel('MacBookPro18,3'), 'MacBook Pro');
      expect(DeviceInfo.macModel('MacBookAir10,1'), 'MacBook Air');
      expect(DeviceInfo.macModel('Macmini9,1'), 'Mac mini');
      expect(DeviceInfo.macModel('iMac21,1'), 'iMac');
      expect(DeviceInfo.macModel('Mac15,3'), 'Mac');
      expect(DeviceInfo.macModel('VirtualMac2,1'), 'Mac');
      expect(DeviceInfo.macModel(null), isNull);
    });

    test("takes Windows' name without the build", () {
      expect(DeviceInfo.windowsName('"Windows 11 Pro" 10.0 (Build 26100)'), 'Windows 11 Pro');
      expect(DeviceInfo.windowsName('10.0.26100'), isNull);
    });

    test("takes a Linux system's pretty name", () {
      expect(
        DeviceInfo.linuxName('NAME="Ubuntu"\nPRETTY_NAME="Ubuntu 24.04.1 LTS"\nID=ubuntu\n'),
        'Ubuntu 24.04.1 LTS',
      );
      expect(DeviceInfo.linuxName("PRETTY_NAME='Fedora Linux 41'\n"), 'Fedora Linux 41');
      expect(DeviceInfo.linuxName('PRETTY_NAME=Arch Linux\n'), 'Arch Linux');
      expect(DeviceInfo.linuxName('NAME=Gentoo\n'), isNull);
    });
  });
}
