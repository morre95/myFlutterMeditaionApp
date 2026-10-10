import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:my_meditation_app/features/cloud/pcloud/application/pcloud_auth_controller.dart';
import 'package:my_meditation_app/features/cloud/pcloud/application/pcloud_download_controller.dart';
import 'package:my_meditation_app/features/cloud/pcloud/application/pcloud_download_store.dart';
import 'package:my_meditation_app/features/cloud/pcloud/application/pcloud_service.dart';
import 'package:my_meditation_app/features/library/presentation/pcloud_browser_screen.dart';

void main() {
  setUp(PCloudBrowserScreen.resetRememberedPath);

  testWidgets('back steps up one folder, Done leaves the browser', (
    tester,
  ) async {
    await tester.pumpWidget(_app(_service()));
    await _openBrowser(tester);

    await tester.tap(find.text('Sleep'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Deep'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, 'Deep'), findsOneWidget);

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, 'Sleep'), findsOneWidget);

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.text('Browse pCloud'), findsOneWidget);
  });

  testWidgets('reopening lands in the folder the user left from', (
    tester,
  ) async {
    await tester.pumpWidget(_app(_service()));
    await _openBrowser(tester);

    await tester.tap(find.text('Sleep'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    await _openBrowser(tester);

    expect(find.widgetWithText(AppBar, 'Sleep'), findsOneWidget);
  });

  testWidgets('backing out to the root is remembered too', (tester) async {
    await tester.pumpWidget(_app(_service()));
    await _openBrowser(tester);

    await tester.tap(find.text('Sleep'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    await _openBrowser(tester);

    expect(find.widgetWithText(AppBar, 'pCloud'), findsOneWidget);
  });

  testWidgets(
    'shows download progress, cancel, retry, and offline availability',
    (tester) async {
      await tester.runAsync(() async {
        final root = await Directory.systemTemp.createTemp('browser-dl-');
        final transfers = <StreamController<List<int>>>[];
        var offline = false;
        final service = PCloudService(
          session: const _FakeSession(),
          client: MockClient.streaming((request, _) async {
            if (offline) throw http.ClientException('Network is unreachable');
            if (request.url.path == '/listfolder') {
              return _json({
                'result': 0,
                'metadata': {
                  'contents': [
                    {'name': 'rain.mp3', 'isfolder': false, 'fileid': 100},
                  ],
                },
              });
            }
            if (request.url.path == '/getfilelink') {
              return _json({
                'result': 0,
                'hosts': ['c1.pcloud.com'],
                'path': '/dl/rain.mp3',
              });
            }
            final bytes = StreamController<List<int>>();
            transfers.add(bytes);
            return http.StreamedResponse(bytes.stream, 200, contentLength: 4);
          }),
        );
        final downloads = PCloudDownloadController(
          service: service,
          store: PCloudDownloadStore(directory: root),
        );
        await tester.pumpWidget(_app(service, downloads: downloads));
        await _openBrowser(tester);
        expect(find.text('Not downloaded'), findsOneWidget);

        await tester.tap(find.byTooltip('Download rain.mp3'));
        await _pumpWhile(tester, () => transfers.isEmpty);
        transfers.last.add([1, 2]);
        await _pumpUntil(tester, find.text('Downloading 50%'));
        expect(find.byType(LinearProgressIndicator), findsOneWidget);

        await tester.tap(find.byTooltip('Cancel download'));
        await _pumpUntil(tester, find.byTooltip('Download rain.mp3'));

        offline = true;
        await tester.tap(find.byTooltip('Download rain.mp3'));
        await _pumpUntil(
          tester,
          find.text(
            'Download of rain.mp3 failed. Check your connection and retry.',
          ),
        );

        offline = false;
        await tester.tap(find.byTooltip('Retry download'));
        await _pumpWhile(tester, () => transfers.length < 2);
        transfers.last.add([1, 2, 3, 4]);
        await transfers.last.close();
        await _pumpUntil(tester, find.text('Available offline'));
        expect(find.byTooltip('Download rain.mp3'), findsNothing);

        await tester.pumpWidget(const SizedBox.shrink());
        await root.delete(recursive: true);
      });
    },
  );
}

/// Polls frames while real file and stream work inside `runAsync` completes.
Future<void> _pumpUntil(WidgetTester tester, Finder finder) async {
  await _pumpWhile(tester, () => finder.evaluate().isEmpty);
  expect(finder, findsOneWidget);
}

/// Polls frames until [waiting] turns false, bounded so a missing transfer
/// fails the test instead of hanging it.
Future<void> _pumpWhile(WidgetTester tester, bool Function() waiting) async {
  for (var i = 0; i < 200 && waiting(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await tester.pump();
  }
}

http.StreamedResponse _json(Map<String, Object> body) =>
    http.StreamedResponse(Stream.value(utf8.encode(jsonEncode(body))), 200);

/// Folder tree: pCloud > Sleep > Deep, with one audio file inside Deep.
PCloudService _service() {
  final client = MockClient((request) async {
    final folderId = request.url.queryParameters['folderid'];
    final contents = switch (folderId) {
      '0' => [
        {'name': 'Sleep', 'isfolder': true, 'folderid': 42},
      ],
      '42' => [
        {'name': 'Deep', 'isfolder': true, 'folderid': 43},
      ],
      _ => [
        {'name': 'rain.mp3', 'isfolder': false, 'fileid': 100},
      ],
    };
    return http.Response(
      jsonEncode({
        'result': 0,
        'metadata': {'contents': contents},
      }),
      200,
    );
  });
  return PCloudService(session: const _FakeSession(), client: client);
}

Widget _app(PCloudService service, {PCloudDownloadController? downloads}) {
  return MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => TextButton(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => PCloudBrowserScreen(
                service: service,
                downloads: downloads,
                onAddFile: (_) async => true,
              ),
            ),
          ),
          child: const Text('Browse pCloud'),
        ),
      ),
    ),
  );
}

Future<void> _openBrowser(WidgetTester tester) async {
  await tester.tap(find.text('Browse pCloud'));
  await tester.pumpAndSettle();
}

class _FakeSession implements PCloudSessionProvider {
  const _FakeSession();

  @override
  String? get authToken => 'tok';

  @override
  String? get apiHost => 'api.pcloud.com';
}
