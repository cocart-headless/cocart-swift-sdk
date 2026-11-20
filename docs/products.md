# Products API

The Products API lets you browse your store's catalog — listing products, searching, filtering by category or price, and reading product details. It is publicly accessible and does not require authentication, just like a customer browsing your store's shelves.

```swift
let products = client.products()
```

## List Products

```swift
let response = try await client.products().all()
let response = try await client.products().all(["per_page": "20", "page": "1"])

// The list is under `products`, with the page count alongside
let products = response.get("products") as? [[String: Any]] ?? []
let totalPages = response.getInt("total_pages")
```

Product responses carry a lot for headless pages (related products, embedded variations with price and stock, upsells, cross-sells, stock, extension meta). For a listing that needs less, ask for just those fields; CoCart then skips building the rest:

```swift
let response = try await client.products().all(["per_page": "20", "_fields": "id,name,slug,prices,images,add_to_cart"])
```

Prices are minor-unit strings under `prices` (`"1800"` for 18.00; see `CurrencyFormatter` in [Utilities](utilities.md)), image `src` is a dictionary of sizes (`thumbnail`, `medium`, `full`…), and `attributes` is keyed by attribute (`attribute_pa_color`).

## Parameters Reference

**Query parameters** are options you send alongside a request to filter or control the results. They are appended to the URL as `?key=value` pairs. The SDK handles this for you — just pass a dictionary with the parameters you want.

All list methods accept an optional `params` dictionary with these query parameters:

| Parameter | Type | Description |
|-----------|------|-------------|
| `page` | int | Page number (default: 1) |
| `per_page` | int | Items per page (default: 10, max: 100) |
| `search` | string | Search term |
| `category` | string | Filter by category slug |
| `tag` | string | Filter by tag slug |
| `brand` | string | Filter by brand slug (CoCart Starter) |
| `featured` | bool | Show only featured products |
| `on_sale` | bool | Show only products on sale |
| `min_price` | string | Minimum price |
| `max_price` | string | Maximum price |
| `stock_status` | string | Stock status (`instock`, `outofstock`, `onbackorder`) |
| `orderby` | string | Sort order: `date`, `id`, `menu_order`, `include`, `title`, `slug`, `name`, `alphabetical`, `reverse_alpha`, `popularity`, `sales`, `rating`, `review_count`, `by_stock`, `on_sale_first`, `featured_first`, `price_asc`, `price_desc`; `relevance` and `rand` need CoCart Starter. Sort by price with `price_asc` or `price_desc`: CoCart rejects `price` |
| `order` | string | Sort direction (`asc`, `desc`) |
| `_fields` | string | Comma-separated fields to return |

## Filtering Shortcuts

Each shortcut adds its filter to any others you pass in `params`:

```swift
let response = try await client.products().search("wireless headphones")
let response = try await client.products().byCategory("electronics", params: ["per_page": "20"])
let response = try await client.products().byTag("new-arrival")
let response = try await client.products().featured(["per_page": "4"])
let response = try await client.products().onSale()
let response = try await client.products().byPriceRange(minPrice: "10", maxPrice: "50")
let response = try await client.products().byStockStatus(.inStock)
let response = try await client.products().paginate(page: 2, perPage: 12)

// Cheapest first (CoCart rejects plain "price": use .priceAsc or .priceDesc)
let response = try await client.products().sortBy(.priceAsc)
let response = try await client.products().sortBy(.popularity, order: .desc)
```

## Single Product

### By ID or SKU

`get()` accepts either the numeric product/variation ID or the product's SKU — either one works the same way.

```swift
let response = try await client.products().get(123)

// Or by SKU
let response = try await client.products().get("PCT-2024")

print(response.getString("name"))
print(response.getString("prices.price")) // minor units, e.g. "1800"
print(response.getString("description"))
```

### By Slug

> Requires CoCart Starter.

```swift
let response = try await client.products().getBySlug("blue-hoodie")
```

## Variations

**Variations** are the specific versions of a variable product. For example, a T-shirt product might have variations for "Red / Small", "Red / Large", "Blue / Small", etc. Each variation has its own price, stock level, and SKU.

```swift
// All variations
let response = try await client.products().variations(123)

// A specific variation (CoCart Starter)
let response = try await client.products().variation(123, variationID: 456)
```

## Categories and Tags

```swift
let categories = try await client.products().categories(["per_page": "50"])
let category = try await client.products().category(20) // by ID (CoCart Starter)

let tags = try await client.products().tags()
let tag = try await client.products().tag(8)              // by ID (CoCart Starter)
```

To list the products in a category or with a tag, use `byCategory()` or `byTag()` with its slug (see [Filtering Shortcuts](#filtering-shortcuts)).

Categories, tags, attributes, attribute terms, reviews and variations come back as a list: read it with `toArray()`, or with an index in `get()`:

```swift
let categories = try await client.products().categories()
categories.toArray().count
categories.getString("0.name") // "Accessories"
```

## Attributes

**Attributes** are the properties that define product variations — things like "Color", "Size", or "Material". Each attribute has **terms** (the specific values), such as "Red", "Blue", "Green" for a "Color" attribute. Attributes are configured in WooCommerce under Products > Attributes.

```swift
// All attributes, and one by ID
let attributes = try await client.products().attributes()
let attribute = try await client.products().attribute(1)

// An attribute's terms (e.g. every color), and one term
let terms = try await client.products().attributeTerms(1)
let term = try await client.products().attributeTerm(1, termID: 5)

// The same by slug (CoCart Starter)
let color = try await client.products().attributeBySlug("color")
let colors = try await client.products().attributeTermsBySlug("color")
let blue = try await client.products().attributeTermBySlug("color", termSlug: "blue")
```

## Brands

> Requires CoCart Starter.

```swift
let brands = try await client.products().brands()
let brand = try await client.products().brand(5)          // by ID
let response = try await client.products().byBrand("nike") // products by brand slug
```

## Reviews

```swift
// All reviews
let response = try await client.products().reviews()

// One product's reviews
let response = try await client.products().productReviews(123)

// The authenticated customer's reviews (CoCart Starter)
let response = try await client.products().myReviews()

// Post a review
let response = try await client.products().createReview([
    "product_id": 123,
    "review": "Warm and well made.",
    "rating": 5,
    "reviewer": "Jane",                  // guests
    "reviewer_email": "jane@example.com",
])
```

## Shipping Rates for a Product

> Requires the CoCart Plus plugin.

Shipping rates for a product before it's added to the cart, priced for the store's (or the customer's) location. Pass a variation ID, or the parent with the variation's attributes:

```swift
let response = try await client.products().shippingRates(154, quantity: 2)
let response = try await client.products().shippingRates(134, variation: [
    "attribute_pa_color": "blue",
    "attribute_logo": "Yes",
])

for package in (response.get("packages") as? [String: [String: Any]] ?? [:]).values {
    for rate in (package["rates"] as? [String: [String: Any]] ?? [:]).values {
        print("\(rate["label"] ?? ""): \(rate["cost"] ?? "")") // cost in minor units
    }
}
```

The request is sent without the cart key: the route prices a simulated cart and refuses one (`400 cocart_calculate_product_shipping_rates_cart_access_denied`). External and grouped products can't be priced (`400 cocart_calculate_product_shipping_external_types_denied`, `cocart_calculate_product_shipping_grouped_types_denied`).

## SEO Data

> Requires the CoCart SEO Pack plugin.

```swift
let response = try await client.products().seo(123)
let response = try await client.products().seoBySlug("blue-hoodie")

print(response.getString("meta_data.meta_title"))
```

## Working with Responses

All methods return a `CoCartResponse`:

```swift
let response = try await client.products().get(123)

// Access nested data with dot notation
print(response.getString("name"))
print(response.getString("prices.price"))
print(response.getString("categories.0.name"))

// Full data as dictionary
let data = response.toDictionary()

// Decode into your own Codable model
let product = try response.decode(MyProduct.self)
```

See [Error Handling](error-handling.md) for handling API errors.
