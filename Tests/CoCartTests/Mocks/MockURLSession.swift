import Foundation
@testable import CoCart

final class MockURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: CoCartError.network("No mock handler"))
            return
        }
        do {
            // URLSession moves httpBody into httpBodyStream before handing the request
            // to a URLProtocol. Reconstitute httpBody so test handlers can read it normally.
            var resolved = request
            if resolved.httpBody == nil, let stream = resolved.httpBodyStream {
                stream.open()
                var data = Data()
                let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 4096)
                while stream.hasBytesAvailable {
                    let count = stream.read(buffer, maxLength: 4096)
                    if count > 0 { data.append(buffer, count: count) }
                }
                buffer.deallocate()
                stream.close()
                resolved.httpBody = data
            }
            let (response, data) = try handler(resolved)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

func makeMockSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    return URLSession(configuration: config)
}

func mockResponse(url: String = "https://example.com",
                  statusCode: Int = 200,
                  json: [String: Any] = [:],
                  headers: [String: String] = [:]) {
    MockURLProtocol.requestHandler = { request in
        let data = try JSONSerialization.data(withJSONObject: json)
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: url)!,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        )!
        return (response, data)
    }
}
