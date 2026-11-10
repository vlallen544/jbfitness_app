import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jbfitness/account.dart';
import 'package:jbfitness/app_theme.dart';
import 'package:jbfitness/store_page.dart';

import 'support/accounts.dart';

Map<String, dynamic> productFixture({int stock = 5}) => {
  'id': 'product-one',
  'sku': 'JB-TEST-1KG',
  'name': 'Protein powder',
  'brand': 'Label brand',
  'category': 'protein',
  'packSize': '1 kg',
  'servingSize': '30 g',
  'description': 'A product description from the owner.',
  'ingredients': 'Whey protein, cocoa.',
  'allergenNotes': 'Contains milk.',
  'imageUrl': null,
  'pricePaise': 129950,
  'stock': stock,
  'status': 'published',
  'revision': 1,
};
Map<String, dynamic> cartFixture({
  int quantity = 0,
  int revision = 0,
  bool available = true,
}) => {
  'revision': revision,
  'items': quantity == 0
      ? []
      : [
          {
            ...productFixture(),
            'quantity': quantity,
            'lineTotalPaise': 129950 * quantity,
            'available': available,
          },
        ],
  'itemCount': quantity,
  'subtotalPaise': 129950 * quantity,
  'checkoutEnabled': false,
  'currency': 'INR',
  'hasUnavailableItems': !available,
};
AccountController storeAccount(
  Future<http.Response> Function(http.Request) handler,
) =>
    AccountController(
        store: MemorySessionStore(),
        api: AccountApi(client: MockClient(handler)),
      )
      ..booting = false
      ..token = 'fixture-session'
      ..user = Map<String, dynamic>.from(sampleUser);

void main() {
  Future<void> reveal(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(
      finder,
      200,
      maxScrolls: 40,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
  }

  test('uncertain cart writes retry the identical request, and conflicts reload authoritative data', () async {
    final bodies = <Map<String, dynamic>>[];
    var quantity = 0, revision = 0, failCode = 503;
    final account = storeAccount((request) async {
      if (request.method == 'PUT') {
        bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
        if (failCode > 0) {
          return jsonResponse({'message': 'Change not confirmed'}, failCode);
        }
        quantity = bodies.last['quantity'] as int;
        revision++;
        return jsonResponse({'saved': true, 'revision': revision});
      }
      return jsonResponse(cartFixture(quantity: quantity, revision: revision));
    });
    final cart = StoreCart(account);
    addTearDown(cart.dispose);
    addTearDown(account.dispose);
    await cart.load();
    expect(await cart.setQuantity('product-one', 2), false);
    expect(cart.count, 0);
    expect(cart.pending, isNotNull);
    failCode = 0;
    expect(await cart.retry(), true);
    expect(bodies[0], bodies[1]);
    expect(cart.count, 2);
    expect(cart.pending, isNull);
    failCode = 409;
    quantity = 1;
    revision = 3;
    expect(await cart.setQuantity('product-one', 3), false);
    expect(cart.pending, isNull);
    expect(cart.count, 1);
    expect(cart.data!['revision'], 3);
    expect(cart.error, 'Change not confirmed');
  });

  test(
    'late cart responses never apply to a different signed-in account',
    () async {
      final response = Completer<http.Response>();
      final account = storeAccount((_) => response.future),
          cart = StoreCart(account);
      addTearDown(cart.dispose);
      addTearDown(account.dispose);
      final loading = cart.load();
      account.token = 'new-account-session';
      response.complete(jsonResponse(cartFixture(quantity: 2)));
      await loading;
      expect(cart.data, isNull);
      expect(cart.current, false);
      expect(await cart.setQuantity('product-one', 1), false);
    },
  );

  testWidgets(
    'browse details and ingredients, save cart, adjust quantity, reopen and remove',
    (tester) async {
      var quantity = 0, revision = 0;
      final account = storeAccount((request) async {
        if (request.method == 'PUT') {
          quantity = (jsonDecode(request.body) as Map)['quantity'] as int;
          revision++;
          return jsonResponse({'saved': true, 'revision': revision});
        }
        if (request.url.path.endsWith('/me/cart')) {
          return jsonResponse(
            cartFixture(quantity: quantity, revision: revision),
          );
        }
        if (request.url.path.endsWith('/product-one')) {
          return jsonResponse({
            'product': productFixture(),
            'checkoutEnabled': false,
          });
        }
        return jsonResponse({
          'products': [productFixture()],
          'nextOffset': null,
          'checkoutEnabled': false,
        });
      });
      addTearDown(account.dispose);
      Widget screen(Key key) => MaterialApp(
        theme: fitnessTheme(),
        home: StorePage(key: key, account: account),
      );
      await tester.pumpWidget(screen(const ValueKey('first')));
      await tester.pumpAndSettle();
      await reveal(tester, find.text('View product'));
      await tester.tap(find.text('View product'));
      await tester.pumpAndSettle();
      await reveal(tester, find.text('Whey protein, cocoa.'));
      expect(find.text('Contains milk.'), findsOneWidget);
      await reveal(tester, find.text('Add to cart'));
      await tester.tap(find.text('Add to cart'));
      await tester.pumpAndSettle();
      expect(quantity, 1);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      await reveal(tester, find.text('View saved cart'));
      await tester.tap(find.text('View saved cart'));
      await tester.pumpAndSettle();
      await reveal(tester, find.byTooltip('Increase Protein powder quantity'));
      await tester.tap(find.byTooltip('Increase Protein powder quantity'));
      await tester.pumpAndSettle();
      expect(quantity, 2);
      await reveal(tester, find.text('Checkout coming soon'));
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Checkout coming soon'),
            )
            .onPressed,
        isNull,
      );
      expect(find.text('Product subtotal ₹2599.00'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(screen(const ValueKey('reopen')));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Open cart'));
      await tester.pumpAndSettle();
      await reveal(tester, find.text('Qty 2'));
      await reveal(tester, find.text('Remove'));
      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();
      expect(quantity, 0);
      expect(find.textContaining('Your cart is empty'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'narrow enlarged store supports search and filters with out-of-stock details',
    (tester) async {
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final queries = <Map<String, String>>[];
      final account = storeAccount((request) async {
        if (request.url.path.endsWith('/me/cart')) {
          return jsonResponse(cartFixture());
        }
        if (request.url.path.endsWith('/product-one')) {
          return jsonResponse({'product': productFixture(stock: 0)});
        }
        queries.add(request.url.queryParameters);
        return jsonResponse({
          'products': [productFixture(stock: 0)],
          'nextOffset': null,
        });
      });
      addTearDown(account.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: fitnessTheme(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.6)),
            child: child!,
          ),
          home: StorePage(account: account),
        ),
      );
      await tester.pumpAndSettle();
      await reveal(tester, find.byType(TextField));
      await tester.enterText(find.byType(TextField), 'Protein');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(queries.last['q'], 'Protein');
      await reveal(tester, find.widgetWithText(ChoiceChip, 'Protein'));
      await tester.tap(find.widgetWithText(ChoiceChip, 'Protein'));
      await tester.pumpAndSettle();
      expect(queries.last['category'], 'protein');
      expect(queries.last['offset'], '0');
      await reveal(tester, find.text('View product'));
      await tester.tap(find.text('View product'));
      await tester.pumpAndSettle();
      await reveal(tester, find.widgetWithText(FilledButton, 'Out of stock'));
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Out of stock'),
            )
            .onPressed,
        isNull,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'loading more keeps the submitted search and merges repeated product IDs',
    (tester) async {
      final queries = <Map<String, String>>[];
      final account = storeAccount((request) async {
        if (request.url.path.endsWith('/me/cart')) {
          return jsonResponse(cartFixture());
        }
        queries.add(request.url.queryParameters);
        return jsonResponse({
          'products': [productFixture()],
          'nextOffset': queries.length == 1 ? 20 : null,
        });
      });
      addTearDown(account.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: fitnessTheme(),
          home: StorePage(account: account),
        ),
      );
      await tester.pumpAndSettle();
      await reveal(tester, find.byType(TextField));
      await tester.enterText(find.byType(TextField), 'Unsubmitted new search');
      tester.testTextInput.hide();
      await tester.pumpAndSettle();
      await reveal(tester, find.text('Load more products'));
      await tester.tap(find.text('Load more products'));
      await tester.pumpAndSettle();
      expect(queries.last['q'], '');
      expect(queries.last['offset'], '20');
      expect(find.text('View product'), findsOneWidget);
    },
  );

  testWidgets('stock reduction lets a customer reduce to the available units', (
    tester,
  ) async {
    var quantity = 3, revision = 1;
    final account = storeAccount((request) async {
      if (request.method == 'PUT') {
        quantity = (jsonDecode(request.body) as Map)['quantity'] as int;
        revision++;
        return jsonResponse({'saved': true, 'revision': revision});
      }
      final data = cartFixture(
        quantity: quantity,
        revision: revision,
        available: quantity <= 1,
      );
      (data['items'] as List).first['stock'] = 1;
      return jsonResponse(data);
    });
    final cart = StoreCart(account);
    addTearDown(cart.dispose);
    addTearDown(account.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: fitnessTheme(),
        home: StoreCartPage(cart: cart),
      ),
    );
    await tester.pumpAndSettle();
    await reveal(tester, find.byTooltip('Decrease Protein powder quantity'));
    expect(
      tester
          .widget<IconButton>(
            find.byWidgetPredicate(
              (widget) =>
                  widget is IconButton &&
                  widget.tooltip == 'Increase Protein powder quantity',
            ),
          )
          .onPressed,
      isNull,
    );
    await tester.tap(find.byTooltip('Decrease Protein powder quantity'));
    await tester.pumpAndSettle();
    expect(quantity, 1);
    expect(find.text('Qty 1'), findsOneWidget);
  });

  testWidgets(
    'empty catalogue is explicit and failed cart refresh marks old totals stale',
    (tester) async {
      var fail = false;
      final account = storeAccount((request) async {
        if (request.url.path.endsWith('/me/cart')) {
          return fail
              ? jsonResponse({'message': 'Cart unavailable'}, 503)
              : jsonResponse(cartFixture(quantity: 1));
        }
        return jsonResponse({'products': [], 'nextOffset': null});
      });
      addTearDown(account.dispose);
      await tester.pumpWidget(MaterialApp(home: StorePage(account: account)));
      await tester.pumpAndSettle();
      await reveal(tester, find.textContaining('No products in this view yet'));
      await tester.tap(find.byTooltip('Open cart'));
      await tester.pumpAndSettle();
      fail = true;
      await tester.tap(find.byTooltip('Refresh cart'));
      await tester.pumpAndSettle();
      expect(find.text('Cart unavailable'), findsOneWidget);
      expect(
        find.textContaining('Showing the last loaded cart'),
        findsOneWidget,
      );
      await reveal(tester, find.text('Remove'));
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Remove'))
            .onPressed,
        isNull,
      );
    },
  );
}
