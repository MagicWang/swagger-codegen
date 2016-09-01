// AlamofireImplementations.swift
//
// Generated by swagger-codegen
// https://github.com/swagger-api/swagger-codegen
//

import Alamofire

class AlamofireRequestBuilderFactory: RequestBuilderFactory {
    func getBuilder<T>() -> RequestBuilder<T>.Type {
        return AlamofireRequestBuilder<T>.self
    }
}

// Store manager to retain its reference
private var managerStore: [String: Alamofire.Manager] = [:]

class AlamofireRequestBuilder<T>: RequestBuilder<T> {
    required init(method: String, URLString: String, parameters: [String : AnyObject]?, isBody: Bool) {
        super.init(method: method, URLString: URLString, parameters: parameters, isBody: isBody)
    }

    override func execute(completion: (response: Response<T>?, error: ErrorType?) -> Void) {
        let managerId = NSUUID().UUIDString
        // Create a new manager for each request to customize its request header
        let configuration = NSURLSessionConfiguration.defaultSessionConfiguration()
        configuration.HTTPAdditionalHeaders = buildHeaders()
        let manager = Alamofire.Manager(configuration: configuration)
        managerStore[managerId] = manager

        let encoding = isBody ? Alamofire.ParameterEncoding.JSON : Alamofire.ParameterEncoding.URL
        let xMethod = Alamofire.Method(rawValue: method)
        let fileKeys = parameters == nil ? [] : parameters!.filter { $1.isKindOfClass(NSURL) }
                                                           .map { $0.0 }

        if fileKeys.count > 0 {
            manager.upload(
                xMethod!, URLString, headers: nil,
                multipartFormData: { mpForm in
                    for (k, v) in self.parameters! {
                        switch v {
                        case let fileURL as NSURL:
                            mpForm.appendBodyPart(fileURL: fileURL, name: k)
                            break
                        case let string as NSString:
                            mpForm.appendBodyPart(data: string.dataUsingEncoding(NSUTF8StringEncoding)!, name: k)
                            break
                        case let number as NSNumber:
                            mpForm.appendBodyPart(data: number.stringValue.dataUsingEncoding(NSUTF8StringEncoding)!, name: k)
                            break
                        default:
                            fatalError("Unprocessable value \(v) with key \(k)")
                            break
                        }
                    }
                },
                encodingMemoryThreshold: Manager.MultipartFormDataEncodingMemoryThreshold,
                encodingCompletion: { encodingResult in
                    switch encodingResult {
                    case .Success(let uploadRequest, _, _):
                        if let onProgressReady = self.onProgressReady {
                            onProgressReady(uploadRequest.progress)
                        }
                        self.processRequest(uploadRequest, managerId, completion)
                    case .Failure(let encodingError):
                        completion(response: nil, error: encodingError)
                    }
                }
            )
        } else {
            let request = manager.request(xMethod!, URLString, parameters: parameters, encoding: encoding)
            if let onProgressReady = self.onProgressReady {
                onProgressReady(request.progress)
            }
            processRequest(request, managerId, completion)
        }

    }

    private func processRequest(request: Request, _ managerId: String, _ completion: (response: Response<T>?, error: ErrorType?) -> Void) {
        if let credential = self.credential {
            request.authenticate(usingCredential: credential)
        }

        let cleanupRequest = {
            managerStore.removeValueForKey(managerId)
        }

        let validatedRequest = request.validate()

        switch T.self {
        case is NSData.Type:
            validatedRequest.responseData({ (dataResponse) in
                cleanupRequest()

                if (dataResponse.result.isFailure) {
                    completion(
                        response: nil,
                        error: dataResponse.result.error
                    )
                    return
                }

                completion(
                    response: Response(
                        response: dataResponse.response!,
                        body: dataResponse.data as! T
                    ),
                    error: nil
                )
            })
        default:
            validatedRequest.responseJSON(options: .AllowFragments) { response in
                cleanupRequest()

                if response.result.isFailure {
                    completion(response: nil, error: response.result.error)
                    return
                }

                if () is T {
                    completion(response: Response(response: response.response!, body: () as! T), error: nil)
                    return
                }
                if let json: AnyObject = response.result.value {
                    let body = Decoders.decode(clazz: T.self, source: json)
                    completion(response: Response(response: response.response!, body: body), error: nil)
                    return
                } else if "" is T {
                    // swagger-parser currently doesn't support void, which will be fixed in future swagger-parser release
                    // https://github.com/swagger-api/swagger-parser/pull/34
                    completion(response: Response(response: response.response!, body: "" as! T), error: nil)
                    return
                }

                completion(response: nil, error: NSError(domain: "localhost", code: 500, userInfo: ["reason": "unreacheable code"]))
            }
        }
    }

    private func buildHeaders() -> [String: AnyObject] {
        var httpHeaders = Manager.defaultHTTPHeaders
        for (key, value) in self.headers {
            httpHeaders[key] = value
        }
        return httpHeaders
    }
}