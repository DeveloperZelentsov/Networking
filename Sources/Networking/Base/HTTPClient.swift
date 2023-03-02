
import Foundation

public protocol HTTPClient: AnyObject {
    func sendRequest<T: Decodable>(session: URLSession,
                                   endpoint: any Endpoint,
                                   responseModel: T.Type) async -> Result<T, HTTPRequestError>
}

public extension HTTPClient { 

    func sendRequest<T: Decodable>(
        session: URLSession = .shared,
        endpoint: any Endpoint,
        responseModel: T.Type
    ) async -> Result<T, HTTPRequestError> {
            guard let url = endpoint.url else {
                return .failure(.invalidURL)
            }
            var request: URLRequest = .init(url: url, timeoutInterval: 10)
            request.httpMethod = endpoint.method.rawValue
            request.allHTTPHeaderFields = endpoint.header
            request.httpBody = endpoint.body?.data
            return await dataTask(with: session, and: request, responseModel: responseModel)
    }
    
    /// A helper method that makes a request from a prepared URLRequest.
    func dataTask<T: Decodable>(
        with session: URLSession,
        and request: URLRequest,
        responseModel: T.Type
    ) async -> Result<T, HTTPRequestError> {
        return await withCheckedContinuation({ continuation in
            let task = session.dataTask(with: request) { [weak self] data, response, error in
                guard let strongSelf = self else { return continuation.resume(returning: .failure(.noResponse)) }
                return continuation.resume(returning: strongSelf.handlingDataTask(data: data,
                                                                                  response: response,
                                                                                  error: error,
                                                                                  responseModel: responseModel))
            }
            task.resume()
        })
    }
    
    /// A helper method that handles the response from a request.
    func handlingDataTask<T: Decodable>(
        data: Data?,
        response: URLResponse?,
        error: Error?,
        responseModel: T.Type
    ) -> Result<T, HTTPRequestError> {
        if let error = error {
            return .failure(.request(localizedDiscription: error.localizedDescription))
        }
        guard let responseCode = (response as? HTTPURLResponse)?.statusCode else {
            return .failure(.noResponse)
        }
        
        switch responseCode {
        case 200...299:
            if let emptyModel = EmptyResponse() as? T {
                return .success(emptyModel)
            }
            if responseModel is Data.Type {
                return .success(responseModel as! T)
            }
            if let decodeData = data?.decode(model: responseModel) {
                return .success(decodeData)
            } else {
                return .failure(.decode)
            }
        case 400:
            if let decodeData = data?.decode(model: ValidatorErrorResponse.self) {
                return .failure(.validator(error: decodeData))
            }
            return .failure(.unexpectedStatusCode(code: responseCode,
                                                  localized: responseCode.localStatusCode))
        case 401: return .failure(.unauthorizate)
        default: return .failure(.unexpectedStatusCode(code: responseCode,
                                                       localized: responseCode.localStatusCode))
        }
    }
}
