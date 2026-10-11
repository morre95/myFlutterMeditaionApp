import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:my_meditation_app/features/cloud/pcloud/application/pcloud_auth_controller.dart';
import 'package:my_meditation_app/features/cloud/pcloud/application/pcloud_download_controller.dart';
import 'package:my_meditation_app/features/cloud/pcloud/application/pcloud_download_store.dart';
import 'package:my_meditation_app/features/cloud/pcloud/application/pcloud_service.dart';
import 'package:my_meditation_app/features/library/application/device_sound_catalog.dart';
import 'package:my_meditation_app/features/library/application/local_audio_library.dart';
import 'package:my_meditation_app/features/library/presentation/device_storage_screen.dart';
import 'package:my_meditation_app/shared/domain/audio_source.dart';

const _rain = AudioSource(
  id: 'pcloud:100',
  kind: AudioSourceKind.pCloud,
  displayName: 'rain.mp3',
  reference: '100',
);

/// Polls frames while real file I/O inside `runAsync` completes.
Future<void> _pumpUntil(
  WidgetTester tester,
  Finder finder, {
  Matcher expected = findsWidgets,
}) async {
  for (var i = 0; i < 200 && !expected.matches(finder, {}); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await tester.pump();
  }
  expect(finder, expected);
}

void main() {
  late Directory root;
  late File original;
  late Set<String> activeSoundIds;

  Future<DeviceSoundCatalog> storeSounds() async {
    root = await Directory.systemTemp.createTemp('device-storage-screen-');
    original = await File('${root.path}/waves.wav').writeAsBytes([1, 2, 3]);
    final library = LocalAudioLibrary(
      directory: Directory('${root.path}/sounds'),
    );
    await library.importSources([
      AudioSource(
        id: 'original',
        kind: AudioSourceKind.localFile,
        displayName: 'waves.wav',
        reference: original.path,
      ),
    ]);
    final store = PCloudDownloadStore(
      directory: Directory('${root.path}/pcloud_downloads'),
    );
    await store.save(_rain, Stream.value(List.filled(2048, 0)));
    final downloads = PCloudDownloadController(
      service: PCloudService(
        session: const _FakeSession(),
        client: MockClient((_) async => http.Response('{}', 200)),
      ),
      store: store,
    );
    await downloads.load();
    activeSoundIds = {};
    return DeviceSoundCatalog(
      library: library,
      downloads: downloads,
      isInActiveSession: (sound) => activeSoundIds.contains(sound.id),
    );
  }

  Future<void> open(WidgetTester tester, DeviceSoundCatalog catalog) async {
    await tester.pumpWidget(
      MaterialApp(home: DeviceStorageScreen(catalog: catalog)),
    );
    await _pumpUntil(tester, find.text('waves.wav'));
  }

  Future<void> remove(WidgetTester tester, String name) async {
    await tester.tap(find.byTooltip('Remove $name'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
    await tester.pump();
  }

  testWidgets('shows each stored sound with its size', (tester) async {
    await tester.runAsync(() async {
      final catalog = await storeSounds();
      await open(tester, catalog);

      expect(find.text('Imported · 3 B'), findsOneWidget);
      expect(find.text('pCloud download · 2.0 KB'), findsOneWidget);
      await root.delete(recursive: true);
    });
  });

  testWidgets('Remove deletes only the device copy', (tester) async {
    await tester.runAsync(() async {
      final catalog = await storeSounds();
      await open(tester, catalog);

      await remove(tester, 'waves.wav');
      await _pumpUntil(tester, find.text('waves.wav'), expected: findsNothing);

      expect(find.text('rain.mp3'), findsOneWidget);
      expect(await original.readAsBytes(), [1, 2, 3]);
      await root.delete(recursive: true);
    });
  });

  testWidgets('explains that an active session must end before removal', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final catalog = await storeSounds();
      await open(tester, catalog);
      activeSoundIds = {_rain.id};

      await remove(tester, 'rain.mp3');
      await _pumpUntil(
        tester,
        find.text(
          'rain.mp3 is playing in an active session. '
          'End the session before removing it.',
        ),
      );

      expect(find.text('rain.mp3'), findsOneWidget);
      await root.delete(recursive: true);
    });
  });
}

class _FakeSession implements PCloudSessionProvider {
  const _FakeSession();

  @override
  String? get authToken => 'tok';

  @override
  String? get apiHost => 'api.pcloud.com';
}
