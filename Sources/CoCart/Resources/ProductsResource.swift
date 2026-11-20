import Foundation

/// The sort orders CoCart accepts for products. Sort by price with `.priceAsc` or
/// `.priceDesc`: CoCart rejects `price`. `.relevance` and `.rand` need CoCart Starter.
public enum ProductOrderBy: String, CaseIterable {
    case date, id, include, title, slug, name, alphabetical, popularity, sales, rating, relevance, rand
    case menuOrder = "menu_order"
    case reverseAlpha = "reverse_alpha"
    case reviewCount = "review_count"
    case byStock = "by_stock"
    case onSaleFirst = "on_sale_first"
    case featuredFirst = "featured_first"
    case priceAsc = "price_asc"
    case priceDesc = "price_desc"
}

/// Sort direction.
public enum SortOrder: String {
    case asc, desc
}

/// A product's stock status.
public enum StockStatus: String {
    case inStock = "instock"
    case outOfStock = "outofstock"
    case onBackorder = "onbackorder"
}

public final class ProductsResource {
    private let http: HTTPClient
    private let options: CoCartOptions

    init(http: HTTPClient, options: CoCartOptions) {
        self.http = http
        self.options = options
    }

    // MARK: - Listing

    /// List products. The list is under `products`, with `page`, `total_pages` and
    /// `total_products` alongside. Common params: `per_page`, `page`, `search`,
    /// `category`, `tag`, `brand`, `featured`, `on_sale`, `min_price`, `max_price`,
    /// `stock_status`, `orderby`, `order` and `_fields`.
    public func all(_ params: [String: String]? = nil) async throws -> CoCartResponse {
        try await http.get("products", queryParams: params)
    }

    /// Search products by keyword.
    public func search(_ term: String, params: [String: String] = [:]) async throws -> CoCartResponse {
        try await all(params.merging(["search": term]) { $1 })
    }

    /// Products in the category with this slug.
    public func byCategory(_ slug: String, params: [String: String] = [:]) async throws -> CoCartResponse {
        try await all(params.merging(["category": slug]) { $1 })
    }

    /// Products with the tag with this slug.
    public func byTag(_ slug: String, params: [String: String] = [:]) async throws -> CoCartResponse {
        try await all(params.merging(["tag": slug]) { $1 })
    }

    /// Featured products.
    public func featured(_ params: [String: String] = [:]) async throws -> CoCartResponse {
        try await all(params.merging(["featured": "true"]) { $1 })
    }

    /// Products on sale.
    public func onSale(_ params: [String: String] = [:]) async throws -> CoCartResponse {
        try await all(params.merging(["on_sale": "true"]) { $1 })
    }

    /// Products priced between `minPrice` and `maxPrice` (either may be left out).
    public func byPriceRange(minPrice: String? = nil, maxPrice: String? = nil,
                             params: [String: String] = [:]) async throws -> CoCartResponse {
        var merged = params
        if let minPrice { merged["min_price"] = minPrice }
        if let maxPrice { merged["max_price"] = maxPrice }
        return try await all(merged)
    }

    /// Products sorted by `field`. Sort by price with `.priceAsc` or `.priceDesc`.
    public func sortBy(_ field: ProductOrderBy, order: SortOrder = .asc,
                       params: [String: String] = [:]) async throws -> CoCartResponse {
        try await all(params.merging(["orderby": field.rawValue, "order": order.rawValue]) { $1 })
    }

    /// Products with this stock status.
    public func byStockStatus(_ status: StockStatus, params: [String: String] = [:]) async throws -> CoCartResponse {
        try await all(params.merging(["stock_status": status.rawValue]) { $1 })
    }

    /// A page of products.
    public func paginate(page: Int, perPage: Int = 10, params: [String: String] = [:]) async throws -> CoCartResponse {
        try await all(params.merging(["page": "\(page)", "per_page": "\(perPage)"]) { $1 })
    }

    // MARK: - Single product

    public func get(_ productID: Int, params: [String: String]? = nil) async throws -> CoCartResponse {
        try validateProductID(productID)
        return try await http.get("products/\(productID)", queryParams: params)
    }

    /// Get a single product by SKU. `GET /products/{id}` accepts either the
    /// numeric product/variation ID or the product's SKU in the same path segment.
    public func get(_ sku: String, params: [String: String]? = nil) async throws -> CoCartResponse {
        try validateProductID(sku)
        return try await http.get("products/\(sku)", queryParams: params)
    }

    /// Get a single product by slug (`GET products/{slug}`). Requires CoCart Starter.
    public func getBySlug(_ slug: String, params: [String: String]? = nil) async throws -> CoCartResponse {
        try requiresStarter("getBySlug")
        return try await http.get("products/\(encode(slug))", queryParams: params)
    }

    // MARK: - Variations

    /// A variable product's variations.
    public func variations(_ productID: Int, params: [String: String]? = nil) async throws -> CoCartResponse {
        try validateProductID(productID)
        return try await http.get("products/\(productID)/variations", queryParams: params)
    }

    /// A single variation. Requires CoCart Starter.
    public func variation(_ productID: Int, variationID: Int, params: [String: String]? = nil) async throws -> CoCartResponse {
        try validateProductID(productID)
        try validateProductID(variationID)
        try requiresStarter("variation")
        return try await http.get("products/\(productID)/variations/\(variationID)", queryParams: params)
    }

    // MARK: - Categories and tags

    /// Product categories.
    public func categories(_ params: [String: String]? = nil) async throws -> CoCartResponse {
        try await http.get("products/categories", queryParams: params)
    }

    /// A single category by ID. Requires CoCart Starter.
    public func category(_ id: Int, params: [String: String]? = nil) async throws -> CoCartResponse {
        try requiresStarter("category")
        return try await http.get("products/categories/\(id)", queryParams: params)
    }

    /// Product tags.
    public func tags(_ params: [String: String]? = nil) async throws -> CoCartResponse {
        try await http.get("products/tags", queryParams: params)
    }

    /// A single tag by ID. Requires CoCart Starter.
    public func tag(_ id: Int, params: [String: String]? = nil) async throws -> CoCartResponse {
        try requiresStarter("tag")
        return try await http.get("products/tags/\(id)", queryParams: params)
    }

    // MARK: - Attributes

    /// Product attributes.
    public func attributes(_ params: [String: String]? = nil) async throws -> CoCartResponse {
        try await http.get("products/attributes", queryParams: params)
    }

    /// A single attribute by ID.
    public func attribute(_ id: Int, params: [String: String]? = nil) async throws -> CoCartResponse {
        try await http.get("products/attributes/\(id)", queryParams: params)
    }

    /// An attribute's terms, e.g. every color.
    public func attributeTerms(_ id: Int, params: [String: String]? = nil) async throws -> CoCartResponse {
        try await http.get("products/attributes/\(id)/terms", queryParams: params)
    }

    /// A single term of an attribute.
    public func attributeTerm(_ id: Int, termID: Int, params: [String: String]? = nil) async throws -> CoCartResponse {
        try await http.get("products/attributes/\(id)/terms/\(termID)", queryParams: params)
    }

    /// A single attribute by slug, e.g. `color`. Requires CoCart Starter.
    public func attributeBySlug(_ slug: String, params: [String: String]? = nil) async throws -> CoCartResponse {
        try requiresStarter("attributeBySlug")
        return try await http.get("products/attributes/\(encode(slug))", queryParams: params)
    }

    /// An attribute's terms, by the attribute's slug. Requires CoCart Starter.
    public func attributeTermsBySlug(_ slug: String, params: [String: String]? = nil) async throws -> CoCartResponse {
        try requiresStarter("attributeTermsBySlug")
        return try await http.get("products/attributes/\(encode(slug))/terms", queryParams: params)
    }

    /// A single term by slug, of an attribute by slug. Requires CoCart Starter.
    public func attributeTermBySlug(_ attributeSlug: String, termSlug: String,
                                    params: [String: String]? = nil) async throws -> CoCartResponse {
        try requiresStarter("attributeTermBySlug")
        return try await http.get("products/attributes/\(encode(attributeSlug))/terms/\(encode(termSlug))",
                                  queryParams: params)
    }

    // MARK: - Brands

    /// Product brands. Requires CoCart Starter.
    public func brands(_ params: [String: String]? = nil) async throws -> CoCartResponse {
        try requiresStarter("brands")
        return try await http.get("products/brands", queryParams: params)
    }

    /// A single brand by ID. Requires CoCart Starter.
    public func brand(_ id: Int, params: [String: String]? = nil) async throws -> CoCartResponse {
        try requiresStarter("brand")
        return try await http.get("products/brands/\(id)", queryParams: params)
    }

    /// Products of the brand with this slug. Requires CoCart Starter.
    public func byBrand(_ slug: String, params: [String: String] = [:]) async throws -> CoCartResponse {
        try requiresStarter("byBrand")
        return try await all(params.merging(["brand": slug]) { $1 })
    }

    // MARK: - Reviews

    /// Product reviews.
    public func reviews(_ params: [String: String]? = nil) async throws -> CoCartResponse {
        try await http.get("products/reviews", queryParams: params)
    }

    /// The reviews of one product.
    public func productReviews(_ productID: Int, params: [String: String] = [:]) async throws -> CoCartResponse {
        try validateProductID(productID)
        return try await reviews(params.merging(["product": "\(productID)"]) { $1 })
    }

    /// The authenticated customer's product reviews (`GET products/reviews/mine`). Requires CoCart Starter.
    public func myReviews(_ params: [String: String]? = nil) async throws -> CoCartResponse {
        try requiresStarter("myReviews")
        return try await http.get("products/reviews/mine", queryParams: params)
    }

    /// Post a product review: `product_id`, `review`, `rating` (1–5), and for a guest
    /// `reviewer` and `reviewer_email`.
    public func createReview(_ review: [String: Any]) async throws -> CoCartResponse {
        try await http.post("products/reviews", body: review)
    }

    // MARK: - Shipping rates (CoCart Plus)

    /// Shipping rates for a product before it's added to the cart (CoCart Plus).
    /// `productID` may be a variation ID or a SKU.
    ///
    /// Sent without the cart key: the route prices a simulated cart and refuses one
    /// (`400 cocart_calculate_product_shipping_rates_cart_access_denied`). External and
    /// grouped products can't be priced (`400`).
    ///
    /// - Parameters:
    ///   - quantity: Quantity to price shipping for. Default 1.
    ///   - variation: A variable product's attributes, e.g. `["attribute_pa_color": "blue"]`.
    ///   - itemData: Custom item data, as sent when adding the item.
    public func shippingRates(_ productID: String, quantity: Int? = nil,
                              variation: [String: String] = [:],
                              itemData: [String: String] = [:]) async throws -> CoCartResponse {
        var query: [String: String] = [:]
        if let quantity { query["quantity"] = "\(quantity)" }
        variation.forEach { query["variation[\($0.key)]"] = $0.value }
        itemData.forEach { query["item_data[\($0.key)]"] = $0.value }
        return try await http.getRaw("\(options.namespace)/v2/products/\(encode(productID))/shipping-rates",
                                     queryParams: query, includeCartKey: false)
    }

    /// Shipping rates for a product by ID. See `shippingRates(_:quantity:variation:itemData:)`.
    public func shippingRates(_ productID: Int, quantity: Int? = nil,
                              variation: [String: String] = [:],
                              itemData: [String: String] = [:]) async throws -> CoCartResponse {
        try await shippingRates("\(productID)", quantity: quantity, variation: variation, itemData: itemData)
    }

    // MARK: - SEO (CoCart SEO Pack)

    /// SEO metadata, Open Graph, Twitter card and Schema.org data for a product (CoCart SEO Pack).
    public func seo(_ productID: Int) async throws -> CoCartResponse {
        try await http.get("products/\(productID)/seo")
    }

    /// SEO data for a product by slug (CoCart SEO Pack).
    public func seoBySlug(_ slug: String) async throws -> CoCartResponse {
        try await http.get("products/\(encode(slug))/seo")
    }

    // MARK: - Helpers

    private func requiresStarter(_ method: String) throws {
        if options.mainPlugin == .legacy {
            throw CoCartError.version("\(method)() is only available with CoCart Starter")
        }
    }

    private func encode(_ value: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#%")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}
