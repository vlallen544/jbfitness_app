import 'package:flutter/material.dart';

import 'account.dart';
import 'app_theme.dart';
import 'stitch_ui.dart';
import 'workout_pages.dart' show requestId;

String storeMoney(num paise) => '₹${(paise / 100).toStringAsFixed(2)}';
const storeCategories = {
  'protein': 'Protein',
  'creatine': 'Creatine',
  'vitamins': 'Vitamins',
  'other': 'Other',
};

class StoreCart extends ChangeNotifier {
  final AccountController account;
  final String? _token;
  Map<String, dynamic>? data, pending;
  Map<String, dynamic>? pendingOrder;
  String? error;
  bool loading = false, sending = false, ready = false, _disposed = false;
  StoreCart(this.account) : _token = account.token;
  bool get current => !_disposed && account.token == _token;
  bool get busy => loading || sending;
  List<Map<String, dynamic>> get items =>
      (data?['items'] as List? ?? []).cast<Map<String, dynamic>>();
  int quantity(String id) =>
      items.where((item) => item['id'] == id).firstOrNull?['quantity']
          as int? ??
      0;
  int get count => data?['itemCount'] as int? ?? 0;
  Future<Map<String, dynamic>> request(
    String path, {
    String method = 'GET',
    Map<String, dynamic>? body,
  }) => account.api.request(path, token: _token, method: method, body: body);
  void _changed() {
    if (current) notifyListeners();
  }

  Future<void> load({bool clearError = true}) async {
    if (busy || !current) return;
    loading = true;
    ready = false;
    if (clearError) error = null;
    _changed();
    try {
      final result = await request('/me/cart');
      if (current) {
        data = result;
        ready = true;
      }
    } catch (e) {
      if (current) {
        error = e is ApiFailure
            ? e.message
            : 'Your cart could not load. Please refresh.';
      }
    } finally {
      loading = false;
      _changed();
    }
  }

  Future<bool> setQuantity(String id, int quantity) async {
    if (!current || busy || !ready || pending != null) return false;
    pending = {
      'id': id,
      'quantity': quantity,
      'revision': data!['revision'],
      'requestId': requestId(),
    };
    return retry();
  }

  Future<bool> retry() async {
    final change = pending;
    if (change == null || busy || !current) return false;
    sending = true;
    error = null;
    _changed();
    var saved = false;
    try {
      await request(
        '/me/cart/${change['id']}',
        method: 'PUT',
        body: {
          'quantity': change['quantity'],
          'revision': change['revision'],
          'requestId': change['requestId'],
        },
      );
      if (!current) return false;
      pending = null;
      saved = true;
    } catch (e) {
      if (current) {
        error = e is ApiFailure
            ? e.message
            : 'The cart change was not confirmed. Retry the same change.';
        if (e is ApiFailure && e.status >= 400 && e.status < 500) {
          pending = null;
        }
      }
    } finally {
      sending = false;
      _changed();
    }
    if (current) await load(clearError: saved);
    return saved;
  }

  Future<Map<String, dynamic>> submitOrderRequest() async {
    if (!current || busy || !ready || items.isEmpty ||
        data?['hasUnavailableItems'] == true) {
      throw StateError('Refresh the cart and make sure every item is available.');
    }
    pendingOrder ??= {
      'cartRevision': data!['revision'],
      'requestId': requestId(),
    };
    sending = true;
    error = null;
    _changed();
    try {
      final result = await request(
        '/me/store-orders',
        method: 'PUT',
        body: {
          ...pendingOrder!,
          'confirmed': true,
        },
      );
      if (!current) return result;
      pendingOrder = null;
      return result;
    } catch (e) {
      if (current) {
        error = e is ApiFailure
            ? e.message
            : 'The request was not confirmed. Retry the same request.';
        if (e is ApiFailure && e.status >= 400 && e.status < 500) {
          pendingOrder = null;
        }
      }
      rethrow;
    } finally {
      sending = false;
      _changed();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

class StoreProductImage extends StatelessWidget {
  final String? url;
  final double height;
  const StoreProductImage({super.key, this.url, this.height = 150});
  @override
  Widget build(BuildContext context) {
    Widget placeholder() => Container(
      height: height,
      alignment: Alignment.center,
      color: softRed,
      child: const Icon(Icons.inventory_2_outlined, size: 54, color: brandRed),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: url == null
          ? placeholder()
          : Image.network(
              url!,
              height: height,
              width: double.infinity,
              fit: BoxFit.contain,
              excludeFromSemantics: true,
              errorBuilder: (_, error, stack) => placeholder(),
            ),
    );
  }
}

class StorePage extends StatefulWidget {
  final AccountController account;
  const StorePage({super.key, required this.account});
  @override
  State<StorePage> createState() => _StorePageState();
}

class _StorePageState extends State<StorePage> with WidgetsBindingObserver {
  late final StoreCart _cart;
  final _search = TextEditingController();
  String _activeSearch = '';
  List<Map<String, dynamic>> _products = [];
  int? _next;
  String? _category, _error;
  bool _loading = false;
  @override
  void initState() {
    super.initState();
    _cart = StoreCart(widget.account);
    _cart.addListener(_update);
    WidgetsBinding.instance.addObserver(this);
    _cart.load();
    _load();
  }

  void _update() {
    if (mounted && _cart.current) setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cart.removeListener(_update);
    _cart.dispose();
    _search.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _cart.load();
      _load();
    }
  }

  Future<void> _load({bool more = false}) async {
    if (_loading || !_cart.current) return;
    if (!more) _activeSearch = _search.text.trim();
    setState(() {
      _loading = true;
      _error = null;
      if (!more) _products = [];
    });
    try {
      final query = Uri(
        queryParameters: {
          'q': _activeSearch,
          'category': ?_category,
          'offset': more ? '$_next' : '0',
        },
      );
      final result = await _cart.request('/store/products$query');
      if (mounted && _cart.current) {
        setState(() {
          final combined = [
            ...(more ? _products : <Map<String, dynamic>>[]),
            ...(result['products'] as List).cast<Map<String, dynamic>>(),
          ];
          _products = {
            for (final product in combined) product['id'] as String: product,
          }.values.toList();
          _next = result['nextOffset'] as int?;
        });
      }
    } catch (e) {
      if (mounted && _cart.current) {
        setState(
          () => _error = e is ApiFailure
              ? e.message
              : 'Products could not load. Please retry.',
        );
      }
    } finally {
      if (mounted && _cart.current) setState(() => _loading = false);
    }
  }

  Future<void> _openCart() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => StoreCartPage(cart: _cart)));
    if (mounted) _cart.load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Supplement store'),
      actions: [
          IconButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => StoreOrderHistoryPage(cart: _cart),
              ),
            ),
            tooltip: 'Order requests',
            icon: const Icon(Icons.receipt_long_outlined),
          ),
        IconButton(
          onPressed: _openCart,
          tooltip: 'Open cart',
          icon: Badge(
            label: Text('${_cart.count}'),
            isLabelVisible: _cart.count > 0,
            child: const Icon(Icons.shopping_bag_outlined),
          ),
        ),
      ],
    ),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const StitchPageHeading(
                title: 'Support your\neveryday routine.',
                eyebrow: 'JB Fitness store',
              ),
              const SizedBox(height: 12),
              const Text(
                'Explore products, check ingredients and save your picks for later.',
                style: TextStyle(color: muted, height: 1.6),
              ),
              const SizedBox(height: 18),
              TextField(
                controller: _search,
                maxLength: 100,
                enabled: !_loading,
                onSubmitted: (_) => _load(),
                decoration: InputDecoration(
                  labelText: 'Search products or brands',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: IconButton(
                    onPressed: _loading ? null : _load,
                    tooltip: 'Search store',
                    icon: const Icon(Icons.arrow_forward),
                  ),
                ),
              ),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  ChoiceChip(
                    label: const Text('All'),
                    selected: _category == null,
                    onSelected: _loading
                        ? null
                        : (_) {
                            setState(() => _category = null);
                            _load();
                          },
                  ),
                  for (final category in storeCategories.entries)
                    ChoiceChip(
                      label: Text(category.value),
                      selected: _category == category.key,
                      onSelected: _loading
                          ? null
                          : (_) {
                              setState(() => _category = category.key);
                              _load();
                            },
                    ),
                ],
              ),
              const SizedBox(height: 18),
              if (_loading) const LinearProgressIndicator(),
              if (_error != null) ...[
                Text(_error!, style: const TextStyle(color: brandRed)),
                TextButton(
                  onPressed: _loading ? null : _load,
                  child: const Text('Retry products'),
                ),
              ],
              if (!_loading && _error == null && _products.isEmpty)
                const StitchCard(
                  child: Text(
                    'No products in this view yet. Try another search or check back when the owner adds the catalogue.',
                  ),
                ),
              LayoutBuilder(
                builder: (context, constraints) {
                  final columns =
                      constraints.maxWidth >= 340 &&
                          MediaQuery.textScalerOf(context).scale(14) < 20
                      ? 2
                      : 1;
                  final width =
                      (constraints.maxWidth - (columns - 1) * 14) / columns;
                  return Wrap(
                    spacing: 14,
                    runSpacing: 14,
                    children: [
                      for (final product in _products)
                        SizedBox(
                          width: width,
                          child: StitchCard(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                StoreProductImage(
                                  url: product['imageUrl'] as String?,
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  product['brand'] as String,
                                  style: const TextStyle(
                                    color: muted,
                                    fontSize: 12,
                                  ),
                                ),
                                const SizedBox(height: 5),
                                Text(
                                  product['name'] as String,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 17,
                                  ),
                                ),
                                const SizedBox(height: 5),
                                Text(
                                  product['packSize'] as String,
                                  style: const TextStyle(color: muted),
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  storeMoney(product['pricePaise'] as num),
                                  style: const TextStyle(
                                    color: brandRed,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 19,
                                  ),
                                ),
                                const SizedBox(height: 5),
                                Text(
                                  (product['stock'] as int) > 0
                                      ? 'In stock'
                                      : 'Out of stock',
                                  style: const TextStyle(
                                    color: muted,
                                    fontSize: 12,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                OutlinedButton(
                                  onPressed: () => Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                      builder: (_) => StoreProductPage(
                                        cart: _cart,
                                        id: product['id'] as String,
                                      ),
                                    ),
                                  ),
                                  child: const Text('View product'),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
              if (_next != null && _products.isNotEmpty)
                TextButton(
                  onPressed: _loading ? null : () => _load(more: true),
                  child: const Text('Load more products'),
                ),
              const SizedBox(height: 20),
              const Text(
                'Checkout is not available yet. Your cart is a saved list; no payment is collected.',
                style: TextStyle(color: muted, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class StoreProductPage extends StatefulWidget {
  final StoreCart cart;
  final String id;
  const StoreProductPage({super.key, required this.cart, required this.id});
  @override
  State<StoreProductPage> createState() => _StoreProductPageState();
}

class _StoreProductPageState extends State<StoreProductPage> {
  Map<String, dynamic>? _product;
  String? _error;
  bool _loading = false;
  @override
  void initState() {
    super.initState();
    widget.cart.addListener(_update);
    _load();
  }

  @override
  void dispose() {
    widget.cart.removeListener(_update);
    super.dispose();
  }

  void _update() {
    if (mounted && widget.cart.current) setState(() {});
  }

  Future<void> _load() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await widget.cart.request('/store/products/${widget.id}');
      if (mounted && widget.cart.current) {
        setState(() => _product = result['product'] as Map<String, dynamic>);
      }
    } catch (e) {
      if (mounted && widget.cart.current) {
        setState(() {
          _product = null;
          _error = e is ApiFailure ? e.message : 'Product could not load.';
        });
      }
    } finally {
      if (mounted && widget.cart.current) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final product = _product,
        cart = widget.cart,
        quantity = cart.quantity(widget.id);
    final canAdd =
        !_loading &&
        product != null &&
        product['stock'] > quantity &&
        quantity < 10 &&
        cart.ready &&
        !cart.busy &&
        cart.pending == null;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Product details'),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            tooltip: 'Refresh product',
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                if (_loading) const LinearProgressIndicator(),
                if (_error != null) ...[
                  Text(_error!, style: const TextStyle(color: brandRed)),
                  TextButton(
                    onPressed: _load,
                    child: const Text('Retry product'),
                  ),
                ],
                if (product != null) ...[
                  StoreProductImage(
                    url: product['imageUrl'] as String?,
                    height: 240,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    product['brand'] as String,
                    style: const TextStyle(color: muted),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    product['name'] as String,
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(product['packSize'] as String),
                  const SizedBox(height: 14),
                  Text(
                    storeMoney(product['pricePaise'] as num),
                    style: const TextStyle(
                      color: brandRed,
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    product['stock'] > 0
                        ? '${product['stock']} in stock'
                        : 'Out of stock',
                    style: const TextStyle(color: muted),
                  ),
                  const SizedBox(height: 20),
                  _section(
                    'About this product',
                    product['description'] as String,
                  ),
                  _section('Ingredients', product['ingredients'] as String),
                  if ((product['allergenNotes'] as String).isNotEmpty)
                    _section(
                      'Allergen information',
                      product['allergenNotes'] as String,
                    ),
                  if ((product['servingSize'] as String).isNotEmpty)
                    _section('Serving size', product['servingSize'] as String),
                  if (quantity > 0)
                    Text(
                      '$quantity already in your cart',
                      style: const TextStyle(color: muted),
                    ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: canAdd
                        ? () async {
                            final saved = await cart.setQuantity(
                              widget.id,
                              quantity + 1,
                            );
                            if (saved && context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Saved to cart')),
                              );
                            }
                          }
                        : null,
                    icon: const Icon(Icons.add_shopping_cart),
                    label: Text(
                      product['stock'] == 0
                          ? 'Out of stock'
                          : quantity >= 10
                          ? 'Cart limit reached'
                          : 'Add to cart',
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => StoreCartPage(cart: cart),
                      ),
                    ),
                    child: const Text('View saved cart'),
                  ),
                  CartStatus(cart: cart),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _section(String title, String text) => Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
        ),
        const SizedBox(height: 8),
        SelectableText(text),
      ],
    ),
  );
}

class CartStatus extends StatelessWidget {
  final StoreCart cart;
  const CartStatus({super.key, required this.cart});
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (cart.busy) const LinearProgressIndicator(),
      if (cart.error != null)
        Text(cart.error!, style: const TextStyle(color: brandRed)),
      if (!cart.ready && cart.data != null)
        const Text(
          'Showing the last loaded cart. Refresh to confirm current prices and stock.',
          style: TextStyle(color: muted, fontSize: 12),
        ),
      if (!cart.ready && !cart.busy)
        TextButton(onPressed: cart.load, child: const Text('Reload cart')),
      if (cart.pending != null) ...[
        const Text(
          'This change was not confirmed. Retry uses the same reference to avoid applying it twice.',
          style: TextStyle(color: muted, fontSize: 12),
        ),
        TextButton(
          onPressed: cart.busy ? null : cart.retry,
          child: const Text('Retry same cart change'),
        ),
      ],
    ],
  );
}

class StoreCartPage extends StatefulWidget {
  final StoreCart cart;
  const StoreCartPage({super.key, required this.cart});
  @override
  State<StoreCartPage> createState() => _StoreCartPageState();
}

class _StoreCartPageState extends State<StoreCartPage>
    with WidgetsBindingObserver {
  bool _confirmed = false;
  String? _success;
  @override
  void initState() {
    super.initState();
    widget.cart.addListener(_update);
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.cart.load();
    });
  }

  @override
  void dispose() {
    widget.cart.removeListener(_update);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _update() {
    if (mounted && widget.cart.current) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) widget.cart.load();
  }

  @override
  Widget build(BuildContext context) {
    final cart = widget.cart,
        editable = cart.ready && !cart.busy && cart.pending == null;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Your cart'),
        actions: [
          IconButton(
            onPressed: cart.busy ? null : cart.load,
            tooltip: 'Refresh cart',
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                const StitchPageHeading(
                  title: 'Your picks,\nsaved for later.',
                  eyebrow: 'Shopping bag',
                ),
                const SizedBox(height: 16),
                CartStatus(cart: cart),
                if (cart.ready && cart.items.isEmpty)
                  const StitchCard(
                    child: Text(
                      'Your cart is empty. Browse the store and save a product you like.',
                    ),
                  ),
                for (final item in cart.items)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: StitchCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            item['name'] as String,
                            style: const TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '${item['brand']} · ${item['packSize']}',
                            style: const TextStyle(color: muted),
                          ),
                          const SizedBox(height: 8),
                          Text('${storeMoney(item['pricePaise'] as num)} each'),
                          const SizedBox(height: 8),
                          Text(
                            'Item total ${storeMoney(item['lineTotalPaise'] as num)}',
                            style: const TextStyle(
                              color: brandRed,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (item['available'] != true)
                            const Text(
                              'Unavailable at this quantity. Reduce the quantity or remove this item.',
                              style: TextStyle(color: brandRed),
                            ),
                          Wrap(
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 8,
                            children: [
                              IconButton(
                                onPressed:
                                    editable &&
                                        item['quantity'] > 1 &&
                                        item['status'] == 'published' &&
                                        item['stock'] > 0
                                    ? () => cart.setQuantity(
                                        item['id'] as String,
                                        item['stock'] < item['quantity']
                                            ? item['stock'] as int
                                            : (item['quantity'] as int) - 1,
                                      )
                                    : null,
                                tooltip: 'Decrease ${item['name']} quantity',
                                icon: const Icon(Icons.remove_circle_outline),
                              ),
                              Text('Qty ${item['quantity']}'),
                              IconButton(
                                onPressed:
                                    editable &&
                                        item['quantity'] < 10 &&
                                        item['status'] == 'published' &&
                                        item['stock'] > item['quantity']
                                    ? () => cart.setQuantity(
                                        item['id'] as String,
                                        (item['quantity'] as int) + 1,
                                      )
                                    : null,
                                tooltip: 'Increase ${item['name']} quantity',
                                icon: const Icon(Icons.add_circle_outline),
                              ),
                              TextButton(
                                onPressed: editable
                                    ? () => cart.setQuantity(
                                        item['id'] as String,
                                        0,
                                      )
                                    : null,
                                child: const Text('Remove'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                if (cart.data != null && cart.items.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(
                    'Product subtotal ${storeMoney(cart.data!['subtotalPaise'] as num)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 22,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'This is a request for the owner to review. It does not charge you, reserve stock or arrange delivery. Final price, tax and delivery must be confirmed separately.',
                    style: TextStyle(color: muted, fontSize: 12, height: 1.6),
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _confirmed,
                    onChanged: editable && cart.pendingOrder == null && cart.data?['hasUnavailableItems'] != true
                        ? (value) => setState(() => _confirmed = value ?? false)
                        : null,
                    title: const Text('I want the owner to review this request.'),
                    subtitle: const Text('No payment or delivery is arranged here.'),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                  if (_success != null)
                    StitchCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Request sent', style: TextStyle(fontWeight: FontWeight.w700)),
                          const SizedBox(height: 5),
                          Text(_success!, style: const TextStyle(color: muted)),
                          TextButton(
                            onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(builder: (_) => StoreOrderHistoryPage(cart: cart)),
                            ),
                            child: const Text('View request history'),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: editable && _confirmed && cart.data?['hasUnavailableItems'] != true
                        ? () async {
                            try {
                              final result = await cart.submitOrderRequest();
                              if (mounted) {
                                setState(() {
                                  _confirmed = false;
                                  _success = 'Reference ${result['id']}. The cart remains saved; the owner will review availability and final terms.';
                                });
                              }
                            } catch (_) {
                              if (mounted) setState(() {});
                            }
                          }
                        : null,
                    icon: cart.sending
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.outgoing_mail),
                    label: Text(cart.pendingOrder != null ? 'Retry same request' : 'Request this order'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class StoreOrderHistoryPage extends StatefulWidget {
  final StoreCart cart;
  const StoreOrderHistoryPage({super.key, required this.cart});
  @override
  State<StoreOrderHistoryPage> createState() => _StoreOrderHistoryPageState();
}

class _StoreOrderHistoryPageState extends State<StoreOrderHistoryPage> {
  List<Map<String, dynamic>> _orders = [];
  String? _error;
  bool _loading = true;
  @override
  void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final result = await widget.cart.request('/me/store-orders');
      if (mounted && widget.cart.current) setState(() => _orders = (result['orders'] as List).cast<Map<String, dynamic>>());
    } catch (e) {
      if (mounted) setState(() => _error = e is ApiFailure ? e.message : 'Order requests could not load.');
    } finally { if (mounted) setState(() => _loading = false); }
  }
  String _status(String value) => switch(value) { 'requested' => 'Waiting for owner review', 'reviewed' => 'Reviewed by owner', 'closed' => 'Closed', _ => value };
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Order requests'), actions: [IconButton(onPressed: _loading ? null : _load, tooltip: 'Refresh', icon: const Icon(Icons.refresh))]),
    body: SafeArea(child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 640), child: ListView(padding: const EdgeInsets.all(20), children: [
      const StitchPageHeading(title: 'Your requests,\nin one place.', eyebrow: 'Store history'),
      const SizedBox(height: 14),
      const Text('A request is not a paid order. Payment, stock and delivery are confirmed separately by the owner.', style: TextStyle(color: muted, height: 1.5)),
      if (_loading) const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
      if (_error != null) ...[Text(_error!, style: const TextStyle(color: brandRed)), TextButton(onPressed: _load, child: const Text('Retry'))],
      if (!_loading && _error == null && _orders.isEmpty) const Padding(padding: EdgeInsets.only(top: 18), child: StitchCard(child: Text('You have not sent an order request yet.'))),
      for (final order in _orders) Padding(padding: const EdgeInsets.only(top: 12), child: StitchCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [Expanded(child: Text('Request ${order['id'].toString().substring(0, 8).toUpperCase()}', style: const TextStyle(fontWeight: FontWeight.w700))), Chip(label: Text(_status(order['status'] as String)))]),
        Text(DateTime.parse(order['createdAt'] as String).toLocal().toString().substring(0, 16), style: const TextStyle(color: muted, fontSize: 12)),
        const Divider(height: 22),
        for (final item in (order['lineItems'] as List).cast<Map<String, dynamic>>()) Padding(padding: const EdgeInsets.only(bottom: 7), child: Text('${item['quantity']} × ${item['name']} · ${storeMoney((item['pricePaise'] as num) * (item['quantity'] as int))}')),
        const SizedBox(height: 4), Text('Request subtotal ${storeMoney(order['subtotalPaise'] as num)}', style: const TextStyle(color: brandRed, fontWeight: FontWeight.w700)),
        const SizedBox(height: 5), const Text('Final price and delivery are not confirmed.', style: TextStyle(color: muted, fontSize: 12)),
      ]))),
    ])))),
  );
}
