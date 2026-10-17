import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:justride_ui/app/theme/app_theme.dart';
import 'package:justride_ui/core/network/api_client.dart';
import 'package:justride_ui/core/services/backend_service.dart';
import 'package:justride_ui/core/services/help_service.dart';
import 'package:justride_ui/features/profile/screens/help_support_screen.dart';
import 'package:justride_ui/features/profile/screens/support_ticket_screen.dart';

Map<String, dynamic> ticket({String status = 'open', bool replied = false}) => {
      '_id': 'ticket-a',
      'ticket_number': 'TKT-TEST',
      'subject': 'Navigation freezes',
      'description': 'Directions freeze when my screen locks.',
      'category': 'navigation_issue',
      'status': status,
      'createdAt': '2026-10-18T08:00:00Z',
      'messages': [
        {
          '_id': 'm1',
          'sender_role': 'USER',
          'sender_id': 'rider',
          'body': 'Directions freeze when my screen locks.',
          'createdAt': '2026-10-18T08:00:00Z'
        },
        if (replied)
          {
            '_id': 'm2',
            'sender_role': 'ADMIN',
            'sender_id': 'support',
            'body': 'Please review background permissions.',
            'createdAt': '2026-10-18T08:05:00Z'
          },
      ],
    };

Future<void> reveal(WidgetTester tester, Finder finder, double delta) async {
  await tester.scrollUntilVisible(finder, delta,
      scrollable: find.byType(Scrollable).first);
  await tester.pumpAndSettle();
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() async {
    rootBundle.clear();
    SharedPreferences.setMockInitialValues({});
    await ApiClient.instance.clearAuth();
    await ApiClient.instance.saveAuthToken('test-only-session');
  });

  testWidgets(
      'offline search, category, guided checks and ticket handoff fit a compact phone',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 740);
    addTearDown(tester.view.reset);
    var requests = 0;
    await http.runWithClient(() async {
      await tester.pumpWidget(
          MaterialApp(theme: buildAppTheme(), home: const HelpSupportScreen()));
      final loading = tester
          .widget<FutureBuilder<List<HelpArticle>>>(
              find.byType(FutureBuilder<List<HelpArticle>>))
          .future!;
      await tester.runAsync(() async {
        await loading;
      });
      await tester.pumpAndSettle();
      final articles = await HelpService.loadArticles();
      expect(articles, hasLength(24));
      expect(articles.map((article) => article.id).toSet(), hasLength(24));
      await tester.enterText(find.byType(TextField), 'GPS inaccurate');
      await tester.pumpAndSettle();
      await reveal(tester, find.text('Why is my location inaccurate?'), 150);
      expect(find.text('Why is my location inaccurate?'), findsOneWidget);
      await reveal(tester, find.byType(TextField), -200);
      expect(requests, 0);
      await tester.enterText(find.byType(TextField), 'no-such-symptom');
      await tester.pumpAndSettle();
      await reveal(tester, find.textContaining('No matching answers.'), 150);
      expect(find.textContaining('No matching answers.'), findsOneWidget);
      await reveal(tester, find.byType(TextField), -200);
      await tester.tap(find.byTooltip('Clear search'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, 'Account'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'delete account');
      await tester.pumpAndSettle();
      await reveal(
          tester, find.text('How do I delete my account and ride data?'), 150);
      await tester.tap(find.text('How do I delete my account and ride data?'));
      await tester.pumpAndSettle();
      expect(find.byType(CheckboxListTile), findsNWidgets(3));
      await tester.ensureVisible(find.byType(CheckboxListTile).first);
      await tester.tap(find.byType(CheckboxListTile).first);
      await tester.pumpAndSettle();
      expect(
          tester
              .widget<CheckboxListTile>(find.byType(CheckboxListTile).first)
              .value,
          isTrue);
      await reveal(tester, find.text('Still need help'), 150);
      await tester.tap(find.text('Still need help'));
      await tester.pumpAndSettle();
      expect(find.byType(SupportTicketScreen), findsOneWidget);
      expect(
          tester
              .widget<TextFormField>(
                  find.widgetWithText(TextFormField, 'Subject'))
              .controller!
              .text,
          'How do I delete my account and ride data?');
      expect(requests, 0);
      expect(tester.takeException(), isNull);
    },
        () => MockClient((_) async {
              requests++;
              return http.Response('{"success":false}', 503);
            }));
  });

  testWidgets(
      'feedback failure is retryable and only confirmed votes are shown',
      (tester) async {
    var accepted = false;
    var votes = 0;
    await http.runWithClient(() async {
      await tester.pumpWidget(
          MaterialApp(theme: buildAppTheme(), home: const HelpSupportScreen()));
      final loading = tester
          .widget<FutureBuilder<List<HelpArticle>>>(
              find.byType(FutureBuilder<List<HelpArticle>>))
          .future!;
      await tester.runAsync(() async {
        await loading;
      });
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'gps inaccurate');
      await tester.pumpAndSettle();
      await reveal(tester, find.text('Why is my location inaccurate?'), 150);
      await tester.tap(find.text('Why is my location inaccurate?'));
      await tester.pumpAndSettle();
      await reveal(tester, find.text('Not helpful'), 150);
      await tester.tap(find.text('Not helpful'));
      await tester.pumpAndSettle();
      expect(
          find.textContaining('Feedback could not be sent.'), findsOneWidget);
      expect(votes, 1);
      accepted = true;
      await tester.tap(find.text('Not helpful'));
      await tester.pumpAndSettle();
      expect(votes, 2);
      expect(find.byIcon(Icons.thumb_down), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
        () => MockClient((request) async {
              expect(request.url.path, '/api/support/help-feedback');
              expect(jsonDecode(request.body),
                  {'article_id': 'gps-accuracy', 'helpful': false});
              votes++;
              return http.Response(
                  jsonEncode({'success': accepted}), accepted ? 200 : 503);
            }));
  });

  testWidgets(
      'ticket errors preserve draft; retry saves category and opens backend thread',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 900);
    addTearDown(tester.view.reset);
    var saves = 0;
    var replies = 0;
    await http.runWithClient(() async {
      await tester.pumpWidget(MaterialApp(
          theme: buildAppTheme(),
          home: const SupportTicketScreen(
              initialCategory: 'navigation_issue',
              helpArticleId: 'screen-lock')));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Subject'), 'Navigation freezes');
      await tester.enterText(find.widgetWithText(TextFormField, 'Description'),
          'Directions freeze when my screen locks.');
      await reveal(tester, find.text('Send support ticket'), 250);
      await tester.tap(find.text('Send support ticket'));
      await tester.pumpAndSettle();
      expect(find.text('Temporary ticket error'), findsOneWidget);
      expect(
          tester
              .widget<TextFormField>(
                  find.widgetWithText(TextFormField, 'Description'))
              .controller!
              .text,
          'Directions freeze when my screen locks.');
      await reveal(tester, find.text('Send support ticket'), 250);
      await tester.tap(find.text('Send support ticket'));
      await tester.pumpAndSettle();
      expect(find.text('TKT-TEST'), findsOneWidget);
      expect(find.text('OPEN'), findsOneWidget);
      await tester.enterText(find.widgetWithText(TextField, 'Reply to support'),
          'I checked the settings.');
      await reveal(tester, find.text('Send reply'), 150);
      await tester.tap(find.text('Send reply'));
      await tester.pumpAndSettle();
      expect(replies, 1);
      expect(find.text('IN PROGRESS'), findsOneWidget);
      expect(
          find.text('Please review background permissions.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
        () => MockClient((request) async {
              if (request.url.path == '/api/support/tickets') {
                saves++;
                final body = jsonDecode(request.body) as Map;
                expect(body['category'], 'navigation_issue');
                expect(body['help_article_id'], 'screen-lock');
                expect(body.containsKey('diagnostics'), isFalse);
                expect(body.containsKey('diagnostics_consent'), isFalse);
                expect(body['attachments'], isEmpty);
                if (saves == 1) {
                  return http.Response(
                      '{"success":false,"message":"Temporary ticket error"}',
                      503);
                }
                return http.Response(
                    jsonEncode({'success': true, 'data': ticket()}), 201);
              }
              if (request.method == 'POST') {
                expect(
                    request.url.path, '/api/support/tickets/ticket-a/messages');
                replies++;
              }
              return http.Response(
                  jsonEncode({
                    'success': true,
                    'data': ticket(status: 'in_progress', replied: true)
                  }),
                  200);
            }));
  });

  test(
      'diagnostic report includes only selected technical fields; corrupt cache is ignored',
      () async {
    SharedPreferences.setMockInitialValues({
      'justride_paired_device': jsonEncode({
        'firmware_version': '2.0',
        'email': 'private@example.invalid',
        'device_hash': 'secret'
      })
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('com.justride.app/diagnostics'),
            (call) async => {
                  'phone_model': 'Test phone',
                  'os_version': '16',
                  'imei': 'never-collect'
                });
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('com.justride.app/diagnostics'), null));
    final report =
        await HelpService.collectDiagnostics(errorCode: 'BLE_TIMEOUT');
    expect(report['firmware_version'], 'Cached: 2.0');
    expect(report['error_code'], 'BLE_TIMEOUT');
    expect(
        report.keys,
        everyElement(isIn([
          'app_version',
          'platform',
          'firmware_version',
          'phone_model',
          'os_version',
          'error_code'
        ])));
    expect(HelpService.formatDiagnostics(report), isNot(contains('secret')));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('justride_paired_device', '[]');
    expect(
        (await HelpService.collectDiagnostics())
            .containsKey('firmware_version'),
        isFalse);
  });

  test(
      'screenshots use authenticated multipart with the correct image MIME type',
      () async {
    await http.runWithClient(() async {
      final response = await BackendService.instance.uploadSupportScreenshot(
          bytes: [1, 2, 3], filename: 'support.png', contentType: 'image/png');
      expect(response.success, isTrue);
      expect(response.data!['url'],
          'https://res.cloudinary.com/test/image/upload/shot.png');
    },
        () => MockClient((request) async {
              expect(request.url.path, '/api/support/attachments');
              expect(
                  request.headers['Authorization'], 'Bearer test-only-session');
              expect(request.headers['content-type'],
                  startsWith('multipart/form-data;'));
              expect(request.body, contains('content-type: image/png'));
              expect(request.body,
                  contains('name="image"; filename="support.png"'));
              return http.Response(
                  '{"success":true,"data":{"url":"https://res.cloudinary.com/test/image/upload/shot.png"}}',
                  201);
            }));
  });
}
