import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telegrive/app/theme/app_theme.dart';
import 'package:telegrive/features/photos/presentation/album_actions.dart';

void main() {
  testWidgets('an empty album fills its place in the grid, its icon centred', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Center(
            child: SizedBox(
              width: 160,
              height: 200,
              // As in the albums grid: the cover above the name, the column
              // lined up at the start.
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Expanded(child: AlbumCover(album: null)),
                  const Text('Trip'),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    expect(tester.getSize(find.byType(AlbumCover)).width, 160);
    final icon = tester.getCenter(find.byIcon(Icons.photo_library_outlined));
    expect(icon.dx, closeTo(tester.getCenter(find.byType(AlbumCover)).dx, 0.5));
  });
}
