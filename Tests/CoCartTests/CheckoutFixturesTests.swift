import XCTest
@testable import CoCart

/// Replays the shared checkout fixtures (Tests/Fixtures/checkout, copied from cocart-js's
/// packages/checkout/tests/fixtures): the same request/response data every CoCart SDK runs,
/// so all of them are tested the same way.
final class CheckoutFixturesTests: XCTestCase {

    private var directory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/checkout")
    }

    func testEveryCheckoutFixture() async throws {
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        XCTAssertEqual(files.count, 53)

        var failures: [String] = []
        for file in files {
            do {
                if let failure = try await run(Data(contentsOf: file)) {
                    failures.append("\(file.deletingPathExtension().lastPathComponent): \(failure)")
                }
            } catch {
                failures.append("\(file.deletingPathExtension().lastPathComponent): \(error)")
            }
        }
        XCTAssertTrue(failures.isEmpty, failures.joined(separator: "\n"))
    }

    // MARK: - Running one fixture

    /// Runs a fixture; returns what didn't match, or `nil`.
    private func run(_ json: Data) async throws -> String? {
        let fixture = try JSONSerialization.jsonObject(with: json) as! [String: Any]
        let exchanges = fixture["exchanges"] as! [[String: Any]]

        // The response bodies as written in the fixture, so their keys keep their order.
        let tree = OrderedJSON(json)
        var responses: [(Int, Data)] = []
        for (index, exchange) in exchanges.enumerated() {
            let status = (exchange["response"] as! [String: Any])["status"] as! Int
            responses.append((status, tree.raw(at: ["exchanges", index, "response", "body"])))
        }

        var seen: [[String: Any]] = []
        MockURLProtocol.requestHandler = { request in
            var query: [String: String] = [:]
            for item in URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? [] {
                query[item.name] = item.value ?? ""
            }
            let body: Any = request.httpBody.flatMap { $0.isEmpty ? nil : try? JSONSerialization.jsonObject(with: $0) } ?? NSNull()
            var path = request.url!.path
            if path.hasPrefix("/wp-json/") { path.removeFirst("/wp-json/".count) }
            seen.append(["method": request.httpMethod ?? "", "path": path, "query": query, "body": body])

            let (status, data) = seen.count <= responses.count ? responses[seen.count - 1] : (500, Data("{}".utf8))
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
            return (response, data)
        }
        defer { MockURLProtocol.requestHandler = nil }

        let options = CoCartOptions()
        let auth = AuthManager(options: options, storage: MemoryStorage())
        let http = HTTPClient(siteURL: "https://store.example.com", options: options, auth: auth, session: makeMockSession())

        var outcome: Any?
        var thrown: CoCartError?
        var unknownOutcome: CheckoutOutcomeUnknownError?
        do {
            outcome = try await call(http, fixture["call"] as! [String: Any])
        } catch let error as CoCartError {
            thrown = error
        } catch let error as CheckoutOutcomeUnknownError {
            unknownOutcome = error
        }

        let wantedRequests = exchanges.map { $0["request"]! }
        if !same(wantedRequests, seen) {
            return "requests: wanted \(wantedRequests), sent \(seen)"
        }

        let expect = fixture["expect"] as! [String: Any]
        if let error = expect["error"] as? [String: Any] {
            // With `checkoutId`, it's the checkout-outcome-unknown error, carrying that checkout_id.
            if let checkoutId = error["checkoutId"] {
                guard let unknownOutcome else {
                    return "error: wanted CheckoutOutcomeUnknownError, got \(String(describing: thrown))"
                }
                if !same(checkoutId, unknownOutcome.checkoutId) {
                    return "error.checkoutId: wanted \(checkoutId), got \(unknownOutcome.checkoutId)"
                }
                return same(error["code"], unknownOutcome.errorCode)
                    ? nil : "error: wanted \(error["code"] ?? ""), got \(String(describing: unknownOutcome.errorCode))"
            }
            return same(error["code"], thrown?.errorCode) ? nil : "error: wanted \(error["code"] ?? ""), got \(String(describing: thrown ?? unknownOutcome.map { $0 as Error }))"
        }
        if let thrown { return "threw \(thrown)" }
        if let unknownOutcome { return "threw \(unknownOutcome)" }

        if let wanted = expect["result"] as? [String: Any] {
            guard let result = outcome as? CheckoutResult else { return "not a CheckoutResult" }
            for (key, value) in wanted where !same(value, field(result, key)) {
                return "\(key): wanted \(value), got \(String(describing: field(result, key)))"
            }
        }
        if let wanted = expect["value"], let status = outcome as? CheckoutStatus {
            let got: [String: Any] = [
                "checkoutId": status.checkoutId, "code": status.code, "message": status.message,
                "orderId": status.orderId ?? NSNull(),
                "orderKey": status.orderKey ?? NSNull(), "orderNumber": status.orderNumber ?? NSNull(),
                "orderStatus": status.orderStatus ?? NSNull(),
            ]
            if !same(wanted, got) { return "value: wanted \(wanted), got \(got)" }
        } else if let wanted = expect["value"] {
            let cards = (outcome as? [SavedPaymentMethod] ?? []).map { card -> [String: Any] in
                [
                    "id": card.id, "gatewayId": card.gatewayId, "label": card.label, "type": card.type,
                    "expires": card.expires ?? NSNull(), "isDefault": card.isDefault,
                    "supportsSubscriptions": card.supportsSubscriptions,
                ]
            }
            if !same(wanted, cards) { return "value: wanted \(wanted), got \(cards)" }
        }
        if let wanted = expect["responseBody"] {
            guard let response = (outcome as? CheckoutResult)?.response ?? outcome as? CoCartResponse else {
                return "no response"
            }
            let body: Any = response.toArray().isEmpty ? response.toDictionary() : response.toArray()
            if !same(wanted, body) { return "responseBody: wanted \(wanted), got \(body)" }
        }
        return nil
    }

    private func call(_ http: HTTPClient, _ call: [String: Any]) async throws -> Any {
        let args = call["args"] as! [Any]
        func obj(_ i: Int) -> [String: Any] { i < args.count ? args[i] as? [String: Any] ?? [:] : [:] }
        func num(_ i: Int) -> Int { args[i] as! Int }
        func str(_ i: Int) -> String { args[i] as! String }

        if call["target"] as? String == "account" {
            return try await AccountResource(http: http).updateSubscriptionPaymentMethod(num(0), obj(1))
        }

        let checkout = CheckoutResource(http: http)
        switch call["method"] as! String {
        case "getCheckout":
            let params = obj(0)
            return try await checkout.get(currency: params["currency"] as? String, formatted: params["formatted"] as? Bool,
                                          thumb: params["thumb"] as? Bool)
        case "updateCheckout": return try await checkout.update(obj(0))
        case "placeOrder": return try await checkout.placeOrder(obj(0))
        case "getCheckoutConfig": return try await checkout.getConfig()
        case "getCheckoutStatus": return try await checkout.getStatus(args[0] as? String ?? "")
        case "getPaymentMethods": return try await checkout.getPaymentMethods()
        case "getSavedPaymentMethods":
            return try await checkout.getSavedPaymentMethods(gateway: args.first as? String)
        case "searchAddresses":
            let input = obj(0)
            return try await checkout.searchAddresses(input["query"] as! String, country: input["country"] as? String,
                                                      type: input["type"] as? String, provider: input["provider"] as? String)
        case "getAddressDetails":
            let input = obj(0)
            return try await checkout.getAddressDetails(input["address_id"] as! String, provider: input["provider"] as! String)
        case "getOrderReceived":
            let params = obj(2)
            return try await checkout.getOrderReceived(num(0), str(1), formatted: params["formatted"] as? Bool,
                                                       metaKeys: params["meta_keys"] as? [String])
        case "payForOrder": return try await checkout.payForOrder(num(0), str(1), obj(2))
        case "confirmReturn":
            let overrides = obj(1)
            return try await checkout.confirmReturn(str(0), orderId: overrides["orderId"] as? Int,
                                                    orderKey: overrides["orderKey"] as? String)
        case let method:
            throw CoCartError.validation("unknown method \(method)")
        }
    }

    private func field(_ result: CheckoutResult, _ key: String) -> Any? {
        switch key {
        case "code": return result.code.rawValue
        case "object": return result.object
        case "isComplete": return result.isComplete
        case "isAwaitingPayment": return result.isAwaitingPayment
        case "needsConfirmation": return result.needsConfirmation
        case "needsRedirect": return result.needsRedirect
        case "isPending": return result.isPending
        case "isFailed": return result.isFailed
        case "orderId": return result.orderId
        case "orderKey": return result.orderKey
        case "orderNumber": return result.orderNumber
        case "orderStatus": return result.orderStatus
        case "subscriptionId": return result.subscriptionId
        case "redirectUrl": return result.redirectUrl
        case "clientSecret": return result.clientSecret
        case "intentType": return result.intentType
        case "paymentMethodType": return result.paymentMethodType
        case "message": return result.message
        case "errorCode": return result.errorCode
        case "gatewayErrorCode": return result.gatewayErrorCode
        case "gatewayMessage": return result.gatewayMessage
        case "actionType": return result.actionType
        case "actionData": return result.actionData
        default: return "unknown result key \(key)"
        }
    }

    /// Compares two JSON values, `nil` being `null`.
    private func same(_ a: Any?, _ b: Any?) -> Bool {
        func normalize(_ value: Any?) -> NSObject? {
            let wrapped: [String: Any] = ["v": value ?? NSNull()]
            guard let data = try? JSONSerialization.data(withJSONObject: wrapped),
                  let back = try? JSONSerialization.jsonObject(with: data) as? NSDictionary else { return nil }
            return back
        }
        guard let left = normalize(a), let right = normalize(b) else { return false }
        return left.isEqual(right)
    }
}

/// Finds a value's text inside a JSON document, so it can be sent with its keys in the
/// order they were written (a dictionary has none).
private struct OrderedJSON {
    private let bytes: [UInt8]

    init(_ data: Data) { bytes = [UInt8](data) }

    /// The text at a path of object keys and array indexes.
    func raw(at path: [Any]) -> Data {
        var start = skipSpace(0)
        for step in path {
            start = child(of: start, step)
        }
        return Data(bytes[start..<end(of: start)])
    }

    private func skipSpace(_ i: Int) -> Int {
        var i = i
        while i < bytes.count, [0x20, 0x0A, 0x0D, 0x09].contains(bytes[i]) { i += 1 }
        return i
    }

    /// The index just past the value starting at `i`.
    private func end(of i: Int) -> Int {
        switch bytes[i] {
        case UInt8(ascii: "\""):
            var j = i + 1
            while bytes[j] != UInt8(ascii: "\"") { j += bytes[j] == UInt8(ascii: "\\") ? 2 : 1 }
            return j + 1
        case UInt8(ascii: "{"), UInt8(ascii: "["):
            var depth = 0
            var j = i
            repeat {
                switch bytes[j] {
                case UInt8(ascii: "\""): j = end(of: j) - 1
                case UInt8(ascii: "{"), UInt8(ascii: "["): depth += 1
                case UInt8(ascii: "}"), UInt8(ascii: "]"): depth -= 1
                default: break
                }
                j += 1
            } while depth > 0
            return j
        default:
            var j = i
            while j < bytes.count, !",}] \n\r\t".utf8.contains(bytes[j]) { j += 1 }
            return j
        }
    }

    /// The start of an object's member or an array's element.
    private func child(of i: Int, _ step: Any) -> Int {
        var j = skipSpace(i + 1)
        var index = 0
        while bytes[j] != UInt8(ascii: "}") && bytes[j] != UInt8(ascii: "]") {
            var matches = false
            if bytes[i] == UInt8(ascii: "{") {
                let keyEnd = end(of: j)
                let key = try? JSONSerialization.jsonObject(with: Data(bytes[j..<keyEnd]), options: .fragmentsAllowed) as? String
                matches = key == step as? String
                j = skipSpace(skipSpace(keyEnd) + 1)
            } else {
                matches = index == step as? Int
            }
            if matches { return j }
            j = skipSpace(end(of: j))
            if bytes[j] == UInt8(ascii: ",") { j = skipSpace(j + 1) }
            index += 1
        }
        fatalError("no \(step) in fixture")
    }
}
