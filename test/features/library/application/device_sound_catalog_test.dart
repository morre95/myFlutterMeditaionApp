import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:my_meditation_app/features/cloud/pcloud/application/pcloud_auth_controller.dart';
import 'package:my_meditation_app/features/cloud/pcloud/application/pcloud_download_controller.dart';
import 'package:my_meditation_app/features/cloud/pcloud/application/pcloud_download_store.dart';
import 'package:my_meditation_app/features/cloud/pcloud/application/pcloud_service.dart';
import 'package:my_meditation_app/features/library/application/device_sound_catalog.dart';
import 'package:my_meditation_app/features/library/application/local_audio_library.dart';
import 'package:my_meditation_app/shared/domain/audio_source.dart';

const _rain = AudioSource(
  id: 'pcloud:100',
  kind: AudioSourceKind.pCloud,
  displayName: 'rain.mp3',
  reference: '100',
);

/// Real temporary storage holding one import and one pCloud download.
class _Device {
  _Device._(this.root, this.original, this.imported);

  static Future<_Device> create() async {
    final root = await Directory.systemTemp.createTemp('device-sounds-');
    final original = await File(
      '${root.path}/waves.wav',
    ).writeAsBytes([1, 2, 3]);
    final imported =
        (await LocalAudioLibrary(
              directory: Directory('${root.path}/sounds'),
            ).importSources([
              AudioSource(
                id: 'original',
                kind: AudioSourceKind.localFile,
                displayName: 'waves.wav',
                reference: original.path,
              ),
            ]))
            .single;
    await PCloudDownloadStore(
      directory: Directory('${root.path}/pcloud_downloads'),
    ).save(_rain, Stream.value([1, 2, 3, 4, 5]));
    return _Device._(root, original, imported);
  }

  final Directory root;
  final File original;
  final AudioSource imported;
  int cloudRequests = 0;
  Set<String> activeSoundIds = {};

  /// A freshly started app on this storage.
  Future<DeviceSoundCatalog> launch() async {
    final downloads = PCloudDownloadController(
      service: PCloudService(
        session: const _FakeSession(),
        client: MockClient((_) async {
          cloudRequests++;
          return http.Response('{}', 200);
        }),
      ),
      store: PCloudDownloadStore(
        directory: Directory('${root.path}/pcloud_downloads'),
      ),
    );
    await downloads.load();
    return DeviceSoundCatalog(
      library: LocalAudioLibrary(directory: Directory('${root.path}/sounds')),
      downloads: downloads,
      isInActiveSession: (sound) => activeSoundIds.contains(sound.id),
    );
  }
}

void main() {
  late _Device device;
  setUp(() async => device = await _Device.create());
  tearDown(() => device.root.delete(recursive: true));

  test('lists imports and pCloud downloads with their stored sizes', () async {
    final catalog = await device.launch();

    final sounds = await catalog.load();

    expect(
      {for (final sound in sounds) sound.displayName: sound.storedSize},
      {'waves.wav': 3, 'rain.mp3': 5},
    );
  });
}

class _FakeSession implements PCloudSessionProvider {
  const _FakeSession();

  @override
  String? get authToken => 'tok';

  @override
  String? get apiHost => 'api.pcloud.com';
}
