//
//  URLSession.swift
//  Ryu
//
//  Created by Francesco on 07/12/24.
//

import Foundation

extension URLSession {
    func syncRequest(with request: URLRequest, timeout: TimeInterval = 30) -> (Data?, URLResponse?, Error?) {
        var data: Data?
        var response: URLResponse?
        var error: Error?
        
        let semaphore = DispatchSemaphore(value: 0)
        
        let task = self.dataTask(with: request) { (responseData, urlResponse, responseError) in
            data = responseData
            response = urlResponse
            error = responseError
            semaphore.signal()
        }
        
        task.resume()
        
        // Add timeout to prevent deadlocks
        if semaphore.wait(timeout: .now() + timeout) == .timedOut {
            task.cancel()
            error = NSError(domain: "URLSession", code: -1, userInfo: [NSLocalizedDescriptionKey: "Request timed out"])
        }
        
        return (data, response, error)
    }
}
