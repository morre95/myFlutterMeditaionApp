import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:my_meditation_app/features/cloud/pcloud/application/pcloud_auth_controller.dart';
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
}

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

Widget _app(PCloudService service) {
  return MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => TextButton(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => PCloudBrowserScreen(
                service: service,
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
