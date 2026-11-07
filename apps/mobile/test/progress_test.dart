import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jbfitness/account.dart';
import 'package:jbfitness/app_theme.dart';
import 'package:jbfitness/progress_page.dart';

import 'support/accounts.dart';

final photo = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
);
Map<String, dynamic> record(
  String id,
  String date,
  num weight, {
  List<Map<String, dynamic>> photos = const [],
}) => {
  'id': id,
  'date': date,
  'measurements': {
    'weight': weight,
    'waist': null,
    'chest': null,
    'arms': null,
    'thighs': null,
  },
  'revision': 1,
  'photos': photos,
};
AccountController account(
  Future<http.Response> Function(http.Request) handler,
) =>
    AccountController(
        store: MemorySessionStore('session'),
        api: AccountApi(client: MockClient(handler)),
      )
      ..booting = false
      ..token = 'session';
Finder field(String label) => find.byWidgetPredicate(
  (w) => w is TextField && w.decoration?.labelText == label,
);
Future<void> reveal(WidgetTester tester, Finder target) async {
  if (target.evaluate().isEmpty) {
    tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position
        .jumpTo(0);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      target,
      200,
      maxScrolls: 60,
      scrollable: find.byType(Scrollable).first,
    );
  }
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
}

Future<void> tap(WidgetTester tester, Finder target) async {
  await reveal(tester, target);
  await tester.tap(target);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'progress compares actual dated values and keeps missing measurements unknown',
    (tester) async {
      final controller = account(
        (r) async => jsonResponse({
          'today': '2026-11-07',
          'canEdit': true,
          'records': [
            record('recent', '2026-11-07', 79),
            record('old', '2026-11-01', 80.5),
          ],
        }),
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: fitnessTheme(),
          home: ProgressPage(account: controller),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('79 kg'), findsOneWidget);
      await reveal(tester, find.text('Weight (kg): 80.5 → 79 (-1.5)'));
      expect(
        find.text('Waist (cm): not recorded on both dates'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'blank optional values stay null, invalid weights cannot save and success closes',
    (tester) async {
      Map<String, dynamic>? saved;
      final controller = account((r) async {
        saved = jsonDecode(r.body);
        return jsonResponse({'id': 'record'}, 201);
      });
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: fitnessTheme(),
          home: Builder(
            builder: (context) => Scaffold(
              body: FilledButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => ProgressEditor(
                      account: controller,
                      today: '2026-11-07',
                      canEdit: true,
                    ),
                  ),
                ),
                child: const Text('Open record'),
              ),
            ),
          ),
        ),
      );
      await tap(tester, find.text('Open record'));
      await tester.enterText(field('Weight (kg)'), '0');
      await tap(tester, find.text('Save measurements'));
      expect(saved, isNull);
      await reveal(tester, field('Weight (kg)'));
      await tester.enterText(field('Weight (kg)'), '80.25');
      await tap(tester, find.text('Save measurements'));
      expect(saved?['date'], '2026-11-07');
      expect(saved?['measurements']['weight'], 80.25);
      expect(saved?['measurements']['waist'], isNull);
      expect(find.text('Open record'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'uncertain saves preserve payload and reference on a narrow screen with enlarged text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final bodies = <Map<String, dynamic>>[];
      final controller = account((r) async {
        bodies.add(jsonDecode(r.body));
        return jsonResponse({'message': 'Temporary failure'}, 503);
      });
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: fitnessTheme(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.6)),
            child: child!,
          ),
          home: ProgressEditor(
            account: controller,
            today: '2026-11-07',
            canEdit: true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await reveal(tester, field('Weight (kg)'));
      await tester.enterText(field('Weight (kg)'), '82');
      await tap(tester, find.text('Save measurements'));
      await tap(tester, find.text('Retry measurement save'));
      expect(bodies.length, 2);
      expect(bodies.first, bodies.last);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'selected photos require explicit upload and authenticated bytes load only after saving',
    (tester) async {
      var uploaded = false, reads = 0;
      final controller = account((r) async {
        if (r.method == 'POST') {
          expect(r.headers['Content-Type'], startsWith('multipart/form-data'));
          expect(latin1.decode(r.bodyBytes), contains('name="angle"'));
          uploaded = true;
          return jsonResponse({'id': 'photo'}, 201);
        }
        if (r.url.path.endsWith('/photos/photo')) {
          reads++;
          expect(r.headers['Authorization'], 'Bearer session');
          return http.Response.bytes(
            photo,
            200,
            headers: {'Content-Type': 'image/png'},
          );
        }
        return jsonResponse({
          'records': [
            record(
              'record',
              '2026-11-07',
              80,
              photos: uploaded
                  ? [
                      {'id': 'photo', 'angle': 'front'},
                    ]
                  : [],
            ),
          ],
        });
      });
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: fitnessTheme(),
          home: ProgressEditor(
            account: controller,
            record: record('record', '2026-11-07', 80),
            today: '2026-11-07',
            canEdit: true,
            pickPhoto: (_) async => photo,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tap(tester, find.text('Choose progress photo'));
      expect(uploaded, false);
      expect(reads, 0);
      await tap(tester, find.text('Save private photo'));
      expect(uploaded, true);
      expect(reads, 1);
      expect(find.text('Remove selected photo'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'expired members can inspect history and delete a photo with confirmation',
    (tester) async {
      var deleted = false;
      final controller = account((r) async {
        if (r.method == 'DELETE') {
          deleted = true;
          return jsonResponse({'deleted': true});
        }
        return http.Response.bytes(
          photo,
          200,
          headers: {'Content-Type': 'image/png'},
        );
      });
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: fitnessTheme(),
          home: ProgressEditor(
            account: controller,
            record: record(
              'record',
              '2026-11-07',
              80,
              photos: [
                {'id': 'photo', 'angle': 'front'},
              ],
            ),
            today: '2026-11-07',
            canEdit: false,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Save measurements'), findsNothing);
      expect(find.text('Choose progress photo'), findsNothing);
      await tap(tester, find.text('Delete front photo'));
      expect(deleted, false);
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(deleted, true);
      expect(find.text('Delete front photo'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
