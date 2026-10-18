import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/widgets/common.dart';
import '../../files/presentation/file_actions.dart';
import '../../files/presentation/file_tiles.dart';
import '../../lock/data/app_lock.dart';
import '../data/private_space.dart';

/// The private folders, from Settings › Private, behind the phone's lock.
class PrivateScreen extends ConsumerWidget {
  const PrivateScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final folders = ref.watch(privateTopFoldersProvider);
    return PrivateGate(
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Private'),
          actions: [
            // Trash lists what is in Private only while it is open, so
            // the way to it from here is the one that shows it.
            IconButton(
              tooltip: 'Trash',
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: () => context.push('/trash'),
            ),
            IconButton(
              tooltip: 'Lock',
              icon: const Icon(Icons.lock_outline_rounded),
              onPressed: () => ref.read(privateSpaceProvider.notifier).lock(),
            ),
          ],
        ),
        body: AsyncView(
          value: folders,
          data: (folders) => folders.isEmpty
              ? const EmptyState(
                  title: 'Nothing is private yet',
                  message:
                      'In Files, open a folder\'s menu and pick Move to Private. '
                      'It then shows only here.',
                )
              : ListView(
                  padding: const EdgeInsets.only(bottom: Space.xl),
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        Space.gutter,
                        Space.xs,
                        Space.gutter,
                        Space.s,
                      ),
                      child: Text(
                        'These folders show only here, on every phone signed in. '
                        'Telegram still shows their files in your channel.',
                        style: context.text.bodySmall,
                      ),
                    ),
                    for (final folder in folders)
                      FolderListTile(
                        folder: folder,
                        onTap: () => context.push('/private/${folder.id}'),
                        onMore: () => FileActions.showFolderSheet(context, ref, folder),
                      ),
                  ],
                ),
        ),
      ),
    );
  }
}

/// Keeps [child], a page of Private, behind the phone's lock. While
/// Private is closed it says so with Unlock, and asks once on arrival.
/// Private closes once none of these is left; and when it closes while
/// pages of it are open, by the app going to the background say, the
/// first of them takes away everything opened over it, a photo or a file
/// included, so nothing private is on screen when the app comes back.
class PrivateGate extends ConsumerStatefulWidget {
  const PrivateGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<PrivateGate> createState() => _PrivateGateState();
}

class _PrivateGateState extends ConsumerState<PrivateGate> {
  late final PrivateSpace _space;
  ModalRoute<Object?>? _route;

  /// Whether this page asked for the lock on arrival, or had no need to:
  /// a page opened while Private is open, which closes later, waits for
  /// Unlock rather than asking by itself.
  late bool _asked;

  @override
  void initState() {
    super.initState();
    _space = ref.read(privateSpaceProvider.notifier);
    _asked = ref.read(privateSpaceProvider);
    _space.enter(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route ??= ModalRoute.of(context);
  }

  @override
  void dispose() {
    // Nothing may change while screens are being taken down, so closing
    // Private with the last page waits for the end of the frame.
    final space = _space;
    WidgetsBinding.instance.addPostFrameCallback((_) => space.leave(this));
    super.dispose();
  }

  Future<void> _unlock() async {
    final lock = ref.read(appLockProvider.notifier);
    if (!await lock.canConfirm()) {
      if (mounted) {
        showSnack(
          context,
          'Set up a fingerprint, face or screen lock on this phone to use Private.',
        );
      }
      return;
    }
    await _space.unlock();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<bool>(privateSpaceProvider, (was, open) {
      final route = _route;
      if (was != true || open || route == null || !_space.isFirst(this)) return;
      if (route.isCurrent) return;
      Navigator.of(context).popUntil((r) => r == route || r.isFirst);
    });
    if (ref.watch(privateSpaceProvider)) return widget.child;
    if (!_asked) {
      _asked = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && (_route?.isCurrent ?? true)) _unlock();
      });
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Private')),
      body: EmptyState(
        icon: Icons.lock_outline_rounded,
        title: 'Private is locked',
        message: 'It opens with this phone\'s fingerprint, face or screen lock.',
        action: FilledButton(onPressed: _unlock, child: const Text('Unlock')),
      ),
    );
  }
}
