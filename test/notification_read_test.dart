import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:justride_ui/app/theme/app_theme.dart';
import 'package:justride_ui/core/models/app_models.dart';
import 'package:justride_ui/features/profile/screens/notifications_screen.dart';

Map<String, dynamic> item(String id, String title, bool read) => {
      '_id': id,
      'title': title,
      'message': 'Notification details',
      'type': 'ACCOUNT_NOTIFICATION',
      'is_read': read,
      'createdAt': '2026-10-17T08:00:00Z',
    };

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('backend snake-case read state is retained', () {
    expect(NotificationModel.fromJson(item('a', 'Read', true)).isRead, isTrue);
    expect(
        NotificationModel.fromJson(item('b', 'Unread', false)).isRead, isFalse);
  });

  testWidgets('single and bulk reads persist when the screen reloads',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 800);
    addTearDown(tester.view.reset);
    final rows = [
      item('a', 'First unread', false),
      item('b', 'Second unread', false),
      item('c', 'Already read', true)
    ];
    final patches = <String>[];
    await http.runWithClient(() async {
      Future<void> open() async {
        await tester.pumpWidget(MaterialApp(
            theme: buildAppTheme(), home: const NotificationsScreen()));
        await tester.pumpAndSettle();
      }

      FontWeight? weight(String title) =>
          tester.widget<Text>(find.text(title)).style!.fontWeight;
      await open();
      expect(weight('Already read'), FontWeight.w400);
      expect(weight('First unread'), FontWeight.w700);
      await tester.tap(find.text('First unread'));
      await tester.pumpAndSettle();
      expect(patches, ['/api/notifications/a/read']);
      expect(weight('First unread'), FontWeight.w400);
      await tester.tap(find.text('MARK ALL READ'));
      await tester.pumpAndSettle();
      expect(patches.last, '/api/notifications/read-all/read');
      expect(rows.every((row) => row['is_read'] == true), isTrue);
      expect(weight('Second unread'), FontWeight.w400);
      await tester.pumpWidget(const SizedBox());
      await open();
      expect(weight('First unread'), FontWeight.w400);
      expect(weight('Second unread'), FontWeight.w400);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
        () => MockClient((request) async {
              if (request.method == 'PATCH') {
                patches.add(request.url.path);
                for (final row in rows) {
                  if (request.url.path.endsWith('/read-all/read') ||
                      request.url.path.endsWith('/${row['_id']}/read')) {
                    row['is_read'] = true;
                  }
                }
                return http.Response('{"success":true}', 200);
              }
              return http.Response(
                  jsonEncode({
                    'success': true,
                    'data': rows,
                    'unread_count':
                        rows.where((row) => row['is_read'] == false).length
                  }),
                  200);
            }));
  });

  testWidgets(
      'failed bulk read stays unread, reports failure and permits retry without duplicate requests',
      (tester) async {
    var calls = 0;
    var isRead = false;
    final retryResponse = Completer<http.Response>();
    await http.runWithClient(() async {
      await tester.pumpWidget(MaterialApp(
          theme: buildAppTheme(), home: const NotificationsScreen()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('MARK ALL READ'));
      await tester.pumpAndSettle();
      expect(find.text('Unable to save read status'), findsOneWidget);
      expect(tester.widget<Text>(find.text('Unread notice')).style!.fontWeight,
          FontWeight.w700);
      await tester.tap(find.text('MARK ALL READ'));
      await tester.pump();
      await tester.tap(find.text('MARK ALL READ'));
      await tester.pump();
      expect(calls,
          2); // One failed request and one retry, despite the double tap.
      isRead = true;
      retryResponse.complete(http.Response('{"success":true}', 200));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.text('Unread notice')).style!.fontWeight,
          FontWeight.w400);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
        () => MockClient((request) async {
              if (request.method == 'PATCH') {
                calls++;
                if (calls == 1) {
                  return http.Response(
                      '{"success":false,"message":"Unable to save read status"}',
                      503);
                }
                return retryResponse.future;
              }
              return http.Response(
                  jsonEncode({
                    'success': true,
                    'data': [item('a', 'Unread notice', isRead)]
                  }),
                  200);
            }));
  });
}
