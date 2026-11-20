import Foundation

/// What a call that takes payment did: `result.code` (CoCart Plus 2.0). Open-ended, so a
/// value a store or gateway adds still comes through as it is.
///
/// - `orderPlaced`: paid, nothing to pay, or held for review or offline payment.
/// - `actionRequired`: the customer must do something first, e.g. 3D Secure. See `actionType`.
/// - `paymentPending`: the gateway hasn't confirmed the payment yet.
/// - `paymentFailed`: the gateway declined the payment. See `errorCode`.
/// - `paymentMethodChanged`: a subscription's payment method changed.
public struct PaymentResultCode: RawRepresentable, Hashable, ExpressibleByStringLiteral, CustomStringConvertible {
    /// The value as the API sends it, e.g. `action_required`.
    public let rawValue: String

    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.rawValue = value }

    public var description: String { rawValue }

    public static let orderPlaced: PaymentResultCode = "order_placed"
    public static let actionRequired: PaymentResultCode = "action_required"
    public static let paymentPending: PaymentResultCode = "payment_pending"
    public static let paymentFailed: PaymentResultCode = "payment_failed"
    public static let paymentMethodChanged: PaymentResultCode = "payment_method_changed"
}

/// The outcome of a call that takes payment: placing an order, paying for an unpaid order,
/// returning from an off-site step, or changing a subscription's payment method (CoCart Plus 2.0).
///
/// Read from the response's `result`. A declined card is a result (`isFailed`), not an error:
/// errors are kept for requests the store refuses before it tries to take payment.
///
/// Printing a result (`print`, `debugPrint`, `dump`, string interpolation) never shows
/// `clientSecret`, `orderKey`, `actionData` or the response, and shows `redirectUrl` with its
/// query values hidden: they can all carry the order key or the payment's secret.
public struct CheckoutResult {
    /// `result.code`: `order_placed`, `action_required`, `payment_pending`, `payment_failed`, or
    /// `payment_method_changed` for a subscription. A response without one reads as `payment_failed`.
    public let code: PaymentResultCode
    /// The document returned: `order`, or `subscription` after a subscription's payment method change.
    public let object: String?
    /// The order's ID, when the document is an order.
    public let orderId: Int?
    /// The order's key, needed to view or pay for it as a guest.
    public let orderKey: String?
    /// The order number, for display. Can differ from the ID.
    public let orderNumber: String?
    /// The order's status code, e.g. `processing`, `on-hold` or `pending`.
    public let orderStatus: String?
    /// The subscription's ID, when the document is a subscription.
    public let subscriptionId: Int?
    /// Where to send the customer: the off-site step when `needsRedirect`, otherwise the page
    /// to show once the payment is done (the order-received page, or the gateway's own). Only
    /// ever an https or http address.
    public let redirectUrl: String?
    /// For an in-app step (3D Secure), or a payment the customer makes in the app: give it to
    /// the gateway's SDK.
    public let clientSecret: String?
    /// `payment_intent` or `setup_intent`, alongside `clientSecret`.
    public let intentType: String?
    /// The Stripe payment method to pay with when `isAwaitingPayment`: `cashapp`, `wechat_pay`,
    /// `boleto`, `oxxo` or `multibanco`.
    public let paymentMethodType: String?
    /// A message for the customer, for every code: why a payment failed, or that the order was
    /// received. Plain text.
    public let message: String?
    /// CoCart's code for why the payment failed: `card_declined`, `insufficient_funds`… or `payment_failed`.
    public let errorCode: String?
    /// The gateway's own error code, for logging.
    public let gatewayErrorCode: String?
    /// The gateway's own message, for logging. Plain text.
    public let gatewayMessage: String?
    /// What the customer must do, as the gateway integration names it, e.g.
    /// `stripe_confirm_payment` or `stripe_voucher_payment`.
    public let actionType: String?
    /// What the action needs, e.g. `client_secret` or `redirect`.
    public let actionData: [String: Any]?
    /// The raw response: the order, or the subscription.
    public let response: CoCartResponse

    /// Paid, nothing to pay, or held for review or offline payment: the order is placed (or
    /// the subscription's payment method changed).
    public var isComplete: Bool {
        (code == .orderPlaced || code == .paymentMethodChanged) && actionType == nil
    }

    /// The order is placed but not paid yet: the customer pays outside the checkout. With
    /// `clientSecret`, pay in the app with the gateway's SDK for `paymentMethodType` (Cash App
    /// Pay, WeChat Pay, a Boleto, OXXO or Multibanco voucher); otherwise `actionType` says what
    /// to show (`stripe_blik_confirmation_pending`: approve in the banking app; bank transfer
    /// instructions…). The gateway's webhook marks the order paid, so don't place it again.
    public var isAwaitingPayment: Bool { code == .orderPlaced && actionType != nil }

    /// The card needs an in-app step (3D Secure): confirm `clientSecret` with the gateway's
    /// SDK, then make the same call again.
    public var needsConfirmation: Bool { code == .actionRequired && clientSecret != nil }

    /// The payment needs an off-site step: send the customer to `redirectUrl`, then call
    /// `confirmReturn(_:)` when they come back.
    public var needsRedirect: Bool {
        code == .actionRequired && clientSecret == nil && Self.webUrl(actionData?["redirect"]) != nil
    }

    /// The gateway hasn't confirmed the payment yet. Confirm again shortly, or check the order.
    public var isPending: Bool { code == .paymentPending }

    /// The payment was declined or couldn't be taken. Show `message`; the order can be paid again.
    public var isFailed: Bool { code == .paymentFailed }

    /// Reads the document a call that takes payment returns, with what the payment did in `result`.
    public static func from(_ response: CoCartResponse) -> CheckoutResult {
        let data = response.toDictionary()
        let result = data["result"] as? [String: Any] ?? [:]
        let action = result["action"] as? [String: Any]
        let actionData = action?["data"] as? [String: Any]
        let error = result["error"] as? [String: Any]
        let object = text(data["object"])
        let isOrder = object != "subscription"
        let code = PaymentResultCode(text(result["code"]) ?? PaymentResultCode.paymentFailed.rawValue)
        let status = data["status"] as? [String: Any]
        let number = text(data["number"]) ?? integer(data["number"]).map(String.init)
        let offSite = webUrl(actionData?["redirect"])

        return CheckoutResult(
            code: code,
            object: object,
            orderId: isOrder ? integer(data["id"]) : nil,
            orderKey: isOrder ? text(data["key"]) : nil,
            orderNumber: isOrder ? number : nil,
            orderStatus: isOrder ? text(status?["code"]) : nil,
            subscriptionId: isOrder ? nil : integer(data["id"]),
            redirectUrl: code == .actionRequired
                ? offSite ?? webUrl(result["redirect_url"])
                : webUrl(result["redirect_url"]) ?? offSite,
            clientSecret: text(actionData?["client_secret"]),
            intentType: text(actionData?["intent_type"]),
            paymentMethodType: text(actionData?["payment_method_type"]),
            message: text(result["message"]),
            errorCode: text(error?["code"]),
            gatewayErrorCode: text(error?["gateway_code"]),
            gatewayMessage: text(error?["gateway_message"]),
            actionType: text(action?["type"]),
            actionData: actionData,
            response: response
        )
    }

    private static func text(_ value: Any?) -> String? {
        guard let value = value as? String, !value.isEmpty else { return nil }
        return value
    }

    /// A whole number, sent as a number or as a numeric string.
    private static func integer(_ value: Any?) -> Int? {
        if let number = value as? Int { return number }
        if let string = value as? String { return Int(string) }
        return nil
    }

    /// A web address the customer can be sent to: https or http only. Anything else
    /// (`javascript:`, `data:`, another app's link, a relative path) is left out, so a
    /// response can't make the app run script or open another app.
    static func webUrl(_ value: Any?) -> String? {
        guard let url = text(value),
              url.range(of: #"^https?://[^\s/?#]"#, options: [.regularExpression, .caseInsensitive]) != nil
        else { return nil }
        return url
    }
}

// MARK: - Printing without secrets

extension CheckoutResult: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    /// The fields that are safe to print: never `clientSecret`, `orderKey`, `actionData` or the
    /// response, and `redirectUrl` with its query values hidden.
    private var printableFields: [(String, Any)] {
        var fields: [(String, Any)] = [("code", code.rawValue)]
        func add(_ label: String, _ value: Any?) {
            if let value { fields.append((label, value)) }
        }
        add("object", object)
        add("orderId", orderId)
        add("orderKey", orderKey.map { _ in "***" })
        add("orderNumber", orderNumber)
        add("orderStatus", orderStatus)
        add("subscriptionId", subscriptionId)
        add("redirectUrl", redirectUrl.map(HTTPClient.redactQuery))
        add("clientSecret", clientSecret.map { _ in "***" })
        add("intentType", intentType)
        add("paymentMethodType", paymentMethodType)
        add("message", message)
        add("errorCode", errorCode)
        add("gatewayErrorCode", gatewayErrorCode)
        add("gatewayMessage", gatewayMessage)
        add("actionType", actionType)
        return fields
    }

    public var description: String {
        let fields = printableFields.map { label, value in
            value is String ? "\(label): \"\(value)\"" : "\(label): \(value)"
        }
        return "CheckoutResult(\(fields.joined(separator: ", ")))"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(self, children: printableFields.map { (label: Optional($0.0), value: $0.1) },
               displayStyle: .struct)
    }
}

/// How a checkout ended, from `checkout().getStatus(_:)`. The order fields are `nil` unless the
/// order was placed or needs payment.
public struct CheckoutStatus: Equatable {
    public let checkoutId: String
    /// `order_placed` (show the order), `payment_required` (the order was placed but isn't paid:
    /// pay it with `payForOrder`), `in_progress` (ask again in a few seconds) or `not_placed`
    /// (place the order again).
    public let code: String
    /// A message for the customer.
    public let message: String
    public let orderId: Int?
    public let orderKey: String?
    public let orderNumber: String?
    /// The order's status code, e.g. `processing` or `pending`.
    public let orderStatus: String?
}

/// `placeOrder(_:)` sent the order but how it ended isn't known: no answer came back (the
/// connection dropped, the request timed out, or a proxy gave up waiting), or another request
/// is still taking payment for the same cart (`409 cocart_payment_in_progress`). Don't place it
/// again blindly: `checkout().getStatus(error.checkoutId)` tells how it ended.
public struct CheckoutOutcomeUnknownError: Error, LocalizedError {
    /// The `checkout_id` the order was sent with.
    public let checkoutId: String
    /// The error the request failed with.
    public let underlying: CoCartError

    /// The API error code of the underlying error, e.g. `cocart_payment_in_progress`, or `nil`
    /// when no answer came back.
    public var errorCode: String? { underlying.errorCode }

    public var errorDescription: String? { underlying.errorDescription }
}

/// A logged-in customer's saved payment method, from `CheckoutResource.getSavedPaymentMethods(gateway:)`.
public struct SavedPaymentMethod: Equatable {
    /// Pay with it as `wc-{gatewayId}-payment-token` in `payment_data`, or pass it as
    /// `token_id` to change a subscription's card.
    public let id: Int
    /// The payment method (gateway) it belongs to, e.g. `stripe`.
    public let gatewayId: String
    /// The method as the customer sees it, e.g. "Visa ending in 4242".
    public let label: String
    /// `CC`, `eCheck`…
    public let type: String
    /// `MM/YYYY`, or `nil` when it has no expiry.
    public let expires: String?
    public let isDefault: Bool
    /// The gateway can charge subscription renewals with it.
    public let supportsSubscriptions: Bool
}

/// Turns a `payment_data` dictionary into the `{key, value}` pairs the API takes, sorted by
/// key (a dictionary has no order). A list passes through as it is.
public func paymentDataPairs(_ data: Any) -> Any {
    guard let map = data as? [String: Any] else { return data }
    return map.keys.sorted().map { ["key": $0, "value": map[$0] as Any] as [String: Any] }
}

func withPaymentDataPairs(_ input: [String: Any]) -> [String: Any] {
    guard let data = input["payment_data"] else { return input }
    var body = input
    body["payment_data"] = paymentDataPairs(data)
    return body
}

/// A query for `formatted`, `meta_keys` and any other values given, as strings, or `nil` when
/// there are none. A list is comma-joined and a `Bool` is `"true"` or `"false"`.
func documentQuery(_ params: [String: Any?]) -> [String: String]? {
    var query: [String: String] = [:]
    for (key, value) in params {
        guard let value else { continue }
        query[key] = queryValue(value)
    }
    return query.isEmpty ? nil : query
}

private func queryValue(_ value: Any) -> String {
    switch value {
    case let list as [Any]: return list.map(queryValue).joined(separator: ",")
    case let flag as Bool: return flag ? "true" : "false"
    default: return "\(value)"
    }
}
