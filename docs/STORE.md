# Supplement catalogue and saved cart

The mobile store is available from **Today → Supplement store** and **Profile → Supplement store**. Customers can search products/brands, filter categories, open product details, read ingredients/allergen information and save a cart to their account. A paid coaching membership is not required to browse or save physical products.

Practical example: a customer opens a protein powder, checks the pack size and ingredients, adds one pack, then reopens their cart the next day. Their saved quantity remains. If the owner changes the price or stock, refreshing the cart shows the current values and flags any unavailable quantity.

## Owner workflow

Sign into the existing web dashboard as an administrator and open **Supplement store**. Choose **Add product** and enter its name, brand, SKU, category, price, stock, pack/serving sizes, description and actual label ingredients. Optional fields include allergen information and a public Cloudinary product-image URL. Save as draft until ready; choose published to make it visible in the app. Archive to hide it from the catalogue while retaining existing cart references.

- Categories: protein, creatine, vitamins and other.
- Currency: INR. Prices are stored as integer paise. Entering ₹1,299.50 saves 129950 paise.
- Draft and archived products are excluded from customer catalogue/details. Published products with zero stock remain visible as out of stock.
- SKU is unique, 3–40 uppercase letters, digits, `_` or `-`. Stock is a whole number from 0 to 1,000,000. Price range is ₹0.01–₹100,000.00.
- Owner saves carry a revision and request reference. Repeating an uncertain save cannot create another product; stale edits conflict and require a reload.
- Only administrators can edit inventory. Trainers cannot change products or inspect customer carts. Owner catalogue management does not provide cart access.
- There are no automatically seeded or fictional sale products. The client must supply real product details, photos, prices and stock. Test fixtures exist only in local automated tests.

## Cart behavior

- Carts are saved to the signed-in customer, with at most 20 distinct products and 1–10 units per product. Setting quantity to zero removes the item, including when archived or out of stock.
- Add/update validates the current product visibility and stock. A cart is not an inventory reservation, so different customers can save the same remaining item.
- Refresh reads current prices and stock in one database snapshot. It does not silently remove unavailable products or change quantities. Where stock fell below the saved quantity, the decrease control can reduce to the remaining available units; removal always remains available after a successful refresh.
- Product subtotal is calculated by the server from current prices and quantities, including any flagged unavailable items still in the saved cart. Shipping/tax rules are not configured, so the subtotal is not a payable order total.
- Revision conflicts prevent another device's newer cart from being overwritten. Uncertain writes retain their request reference for safe retry while the store screen remains open. Confirmed client errors clear that pending request and refresh the authoritative cart.
- Failed reloads disable quantity changes and label the last loaded cart as stale. There is no offline mutation queue or persisted pending operation across app restarts.
- Switching accounts discards late responses from the previous account. Cart data persists in PostgreSQL rather than device profile storage. Account deletion cascades to its cart and operation references.

## Images and integration boundary

Product photos use optional HTTPS URLs on `res.cloudinary.com`, without URL credentials or custom ports. Broken or missing images show a neutral product placeholder. This feature does not need a Cloudinary signing key and does not add image uploading or change private progress-photo storage. Use public product photos only.

No new hosted service is required. Migration `014_store_catalogue.sql` adds products, carts, items and retry references to the existing PostgreSQL database, with RLS enabled and no public client policies. The existing NestJS backend remains the access boundary; the dashboard uses its existing HttpOnly staff cookie and Origin checks.

## API

| Method | Path | Access |
| --- | --- | --- |
| GET | `/api/v1/store/products?q=&category=&offset=0` | Customer; 20 products per page, optional search/category, bounded offset. |
| GET | `/api/v1/store/products/:id` | Customer; published product only. |
| GET | `/api/v1/me/cart` | Customer's own cart, current availability and subtotal. |
| PUT | `/api/v1/me/cart/:productId` | Customer; `{quantity,revision,requestId}`. Prices/customer IDs in the body are rejected. |
| GET | `/api/v1/me/store-orders` | Customer's own order request history. |
| PUT | `/api/v1/me/store-orders` | Customer submits current cart with `{cartRevision,requestId,confirmed:true}`. |
| GET | `/api/v1/staff/store/products` | Administrator; all visibility states, same search/pagination. |
| PUT | `/api/v1/staff/store/products/:id` | Administrator; complete product fields, expected revision and request ID. Use a new UUID and revision 0 to create. |
| GET | `/api/v1/staff/store/orders` | Administrator; order requests with customer identity and saved item/price snapshots. |
| PUT | `/api/v1/staff/store/orders/:id` | Administrator; revisioned `reviewed` or `closed` status update. |

## Remaining store features

Customers can now send a **non-binding order request** from a saved cart and view its status/history. The request stores the server's product, quantity and price snapshot for owner review. The owner can mark it reviewed or closed in the existing dashboard. The cart remains saved so the customer can continue browsing. Status changes are visible on refresh; push/email updates are not yet wired.

An order request is not a sale or confirmed order: it does not collect payment, reserve stock, confirm a final price, capture an address, calculate shipping/tax, or create a delivery. The owner must verify current stock and contact the customer separately before accepting any purchase. Checkout is disabled in the API and mobile UI. Address capture, shipping areas/fees, stock reservation, fulfilment, returns/refunds and provider-verified payment require client policy and provider setup before implementation.

The owner overview also shows active membership count, production-verified membership receipts and revenue, published catalogue count, and open store requests. Development/test membership receipts and store requests are excluded from verified revenue. Actual store sales/revenue reporting will require verified store payment records after checkout is implemented.

Migration `015_store_order_requests.sql` adds customer-owned request snapshots and an owner status audit trail. API routes are `GET/PUT /api/v1/me/store-orders` and `GET/PUT /api/v1/staff/store/orders`. Existing customer/owner authorization remains enforced in the API.

To use this on the hosted demo, deploy the updated API and dashboard, apply the normal startup migrations and install an APK built from this source. An owner can then add the client's products from the dashboard. Previously published builds do not include these screens or order requests.

## Verification

Verified locally on 9 November 2026: API and dashboard production builds, clean Flutter analysis, 124 API integration checks and 11 dashboard checks. The regression run passed all 87 existing Flutter tests; after correcting test-only compilation/finder issues, all seven new store tests passed in the focused run. Checks cover account isolation, owner access, price/stock changes, stale revisions, uncertain retry references, pagination, saved-cart reopening, narrow enlarged-text screens and disabled checkout. Migration 014 was also applied to the local development database. Hosted rollout, real product content and physical-device verification remain pending.

The 10 November order request, owner report and status screens compile in the API and dashboard; Flutter analysis is clean. No test suite was run for this latest change, migration 015 has not yet been applied to a hosted database, and the connected APK has not been rebuilt.
