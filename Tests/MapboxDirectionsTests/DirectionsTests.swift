import XCTest
import OHHTTPStubs
@testable import MapboxDirections

let BogusToken = "pk.feedCafeDadeDeadBeef-BadeBede.FadeCafeDadeDeed-BadeBede"
let BadResponse = """
<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01 Transitional//EN" "http://www.w3.org/TR/html4/loose.dtd">
<HTML><HEAD><META HTTP-EQUIV="Content-Type" CONTENT="text/html; charset=iso-8859-1">
<TITLE>ERROR: The request could not be satisfied</TITLE>
</HEAD><BODY>
<H1>413 ERROR</H1>
<H2>The request could not be satisfied.</H2>
<HR noshade size="1px">
Bad request.

<BR clear="all">
<HR noshade size="1px">
<PRE>
Generated by cloudfront (CloudFront)
Request ID: RAf2XH13mMVxQ96Z1cVQMPrd-hJoVA6LfaWVFDbdN2j-J1VkzaPvZg==
</PRE>
<ADDRESS>
</ADDRESS>
</BODY></HTML>
"""

class DirectionsTests: XCTestCase {
    override func setUp() {
        // Make sure tests run in all time zones
        NSTimeZone.default = TimeZone(secondsFromGMT: 0)!
    }
    override func tearDown() {
        OHHTTPStubs.removeAllStubs()
        super.tearDown()
    }
    
    func testConfiguration() {
        let directions = Directions(accessToken: BogusToken)
        XCTAssertEqual(directions.accessToken, BogusToken)
        XCTAssertEqual(directions.apiEndpoint.absoluteString, "https://api.mapbox.com")
    }
    
    let maximumCoordinateCount = 795
    
    func testGETRequest() {
        // Bumps right up against MaximumURLLength
        let coordinates = Array(repeating: CLLocationCoordinate2D(latitude: 0, longitude: 0), count: maximumCoordinateCount)
        let options = RouteOptions(coordinates: coordinates)
        
        let directions = Directions(accessToken: BogusToken)
        let url = directions.url(forCalculating: options, httpMethod: "GET")
        XCTAssertLessThanOrEqual(url.absoluteString.count, MaximumURLLength, "maximumCoordinateCount is too high")
        
        var components = URLComponents(string: url.absoluteString)
        XCTAssertEqual(components?.queryItems?.count, 7)
        XCTAssertTrue(components?.path.contains(coordinates.compactMap { $0.stringForRequestURL }.joined(separator: ";")) ?? false)
        
        let request = directions.urlRequest(forCalculating: options)
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.url, url)
    }
    
    func testPOSTRequest() {
        let coordinates = Array(repeating: CLLocationCoordinate2D(latitude: 0, longitude: 0), count: maximumCoordinateCount + 1)
        let options = RouteOptions(coordinates: coordinates)
        
        let directions = Directions(accessToken: BogusToken)
        let request = directions.urlRequest(forCalculating: options)
        
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.query, "access_token=\(BogusToken)")
        XCTAssertNotNil(request.httpBody)
        var components = URLComponents()
        components.query = String(data: request.httpBody ?? Data(), encoding: .utf8)
        XCTAssertEqual(components.queryItems?.count, 7)
        XCTAssertEqual(components.queryItems?.first { $0.name == "coordinates" }?.value,
                       coordinates.compactMap { $0.stringForRequestURL }.joined(separator: ";"))
    }
    
    func testKnownBadResponse() {
        let pass = "The operation couldn’t be completed. The request is too large."
        
        OHHTTPStubs.stubRequests(passingTest: { (request) -> Bool in
            return request.url!.absoluteString.contains("https://api.mapbox.com/directions")
        }) { (_) -> OHHTTPStubsResponse in
            return OHHTTPStubsResponse(data: BadResponse.data(using: .utf8)!, statusCode: 413, headers: ["Content-Type" : "text/html"])
        }
        let expectation = XCTestExpectation(description: "Async callback")
        let one = CLLocation(coordinate: CLLocationCoordinate2D(latitude: 0.0, longitude: 0.0))
        let two = CLLocation(coordinate: CLLocationCoordinate2D(latitude: 2.0, longitude: 2.0))
        
        let directions = Directions(accessToken: BogusToken)
        let opts = RouteOptions(locations: [one, two])
        directions.calculate(opts, completionHandler: { (waypoints, routes, error) in
            expectation.fulfill()
            XCTAssertNil(routes, "Unexpected route response")
            XCTAssertNotNil(error, "No error returned")
            XCTAssertNil(error?.userInfo[NSUnderlyingErrorKey])
            XCTAssertEqual(error?.localizedDescription, pass, "Wrong type of error received")
        })
        wait(for: [expectation], timeout: 2.0)
    }
    
    func testUnknownBadResponse() {
        let pass = "The operation couldn’t be completed. server error"
        
        OHHTTPStubs.stubRequests(passingTest: { (request) -> Bool in
            return request.url!.absoluteString.contains("https://api.mapbox.com/directions")
        }) { (_) -> OHHTTPStubsResponse in
            let message = "Enhance your calm, John Spartan."
            return OHHTTPStubsResponse(data: message.data(using: .utf8)!, statusCode: 420, headers: ["Content-Type" : "text/plain"])
        }
        let expectation = XCTestExpectation(description: "Async callback")
        let one = CLLocation(coordinate: CLLocationCoordinate2D(latitude: 0.0, longitude: 0.0))
        let two = CLLocation(coordinate: CLLocationCoordinate2D(latitude: 2.0, longitude: 2.0))
        
        let directions = Directions(accessToken: BogusToken)
        let opts = RouteOptions(locations: [one, two])
        directions.calculate(opts, completionHandler: { (waypoints, routes, error) in
            expectation.fulfill()
            XCTAssertNil(routes, "Unexpected route response")
            XCTAssertNotNil(error, "No error returned")
            XCTAssertNil(error?.userInfo[NSUnderlyingErrorKey])
            XCTAssertEqual(error?.localizedDescription, pass, "Wrong type of error received")
        })
        wait(for: [expectation], timeout: 2.0)
    }
    
    func testRateLimitErrorParsing() {
        let json = ["message" : "Hit rate limit"]
        
        let url = URL(string: "https://api.mapbox.com")!
        let headerFields = ["X-Rate-Limit-Interval" : "60", "X-Rate-Limit-Limit" : "600", "X-Rate-Limit-Reset" : "1479460584"]
        let response = HTTPURLResponse(url: url, statusCode: 429, httpVersion: nil, headerFields: headerFields)
        
        let error: NSError? = nil
        
        let resultError = Directions.informativeError(describing: json, response: response, underlyingError: error)
        
        XCTAssertEqual(resultError.localizedFailureReason, "More than 600 requests have been made with this access token within a period of 1 minute.")
        XCTAssertEqual(resultError.localizedRecoverySuggestion, "Wait until November 18, 2016 at 9:16:24 AM GMT before retrying.")
    }
}