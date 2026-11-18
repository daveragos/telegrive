// Writes the Windows tray icon: the mark at each size the notification area
// asks for, from 16 pixels at 100% to 32 at 200%, in one .ico file.
//
//   dart run tool/icon/tray_ico.dart tool/icon/out/mark.png assets/brand/tray.ico

import 'dart:io';

import 'package:image/image.dart' as img;

void main(List<String> args) {
  final [from, to] = args;
  final mark = img.decodePng(File(from).readAsBytesSync())!;
  img.Image sized(int size) =>
      img.copyResize(mark, width: size, height: size, interpolation: img.Interpolation.average);
  final icon = sized(16);
  for (final size in [20, 24, 32, 40, 48, 64]) {
    icon.addFrame(sized(size));
  }
  File(to).writeAsBytesSync(img.encodeIco(icon));
}
