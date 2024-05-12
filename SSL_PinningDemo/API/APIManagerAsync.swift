//
//  A.swift
//  SSL_PinningDemo
//
//  Created by Piyush Sinroja on 1/24/24.
//

import Foundation
import Security
import CommonCrypto

enum NetworkError: Error {
    case badRequest
    case serverError(String)
    case decodingError(Error)
    case invalidResponse
    case invalidURL
    case unauthorized
    case postParametersEncodingFalure(description: String)
}

extension NetworkError: LocalizedError {
    var errorDescription: String? {
        switch self {
            case .badRequest:
                return NSLocalizedString("Unable to perform request", comment: "badRequestError")
            case .serverError(let errorMessage):
                return NSLocalizedString(errorMessage, comment: "serverError")
            case .decodingError:
                return NSLocalizedString("Unable to decode.", comment: "decodingError")
            case .invalidResponse:
                return NSLocalizedString("Invalid response", comment: "invalidResponse")
            case .invalidURL:
                return NSLocalizedString("Invalid URL", comment: "invalidURL")
            case .unauthorized:
                return NSLocalizedString("Unauthorized", comment: "unauthorized")
            case .postParametersEncodingFalure(let description):
                return "APIError - post parameters failure -> \(description)"
        }
    }
}

enum HTTPMethodAsync {
    case get
    case post
    case delete
    
    var name: String {
        switch self {
            case .get:
                return "GET"
            case .post:
                return "POST"
            case .delete:
                return "DELETE"
        }
    }
}

struct Resource<T: Codable> {
    let url: URL?
    var method: HTTPMethodAsync = .get
}

class APIManagerAsync: NSObject, URLSessionDelegate {

    static let shared = APIManagerAsync()

//    private let session: URLSession
            
    var isCertificatePinning: Bool = true
    var isEnableSSLPinning: Bool = true

    var hardcodedPublicKey:String = "mpwy9JWgtoFkA7Td66lQye91NEGNbioHVB8aExjRYmE="
    
    let rsa2048Asn1Header:[UInt8] = [
        0x30, 0x82, 0x01, 0x22, 0x30, 0x0d, 0x06, 0x09, 0x2a, 0x86, 0x48, 0x86,
        0xf7, 0x0d, 0x01, 0x01, 0x01, 0x05, 0x00, 0x03, 0x82, 0x01, 0x0f, 0x00
    ]
    
    private func sha256(data : Data) -> String {
        var keyWithHeader = Data(rsa2048Asn1Header)
        keyWithHeader.append(data)
        
        var hash = [UInt8](repeating: 0,  count: Int(CC_SHA256_DIGEST_LENGTH))
        keyWithHeader.withUnsafeBytes {
            _ = CC_SHA256($0, CC_LONG(keyWithHeader.count), &hash)
        }
        return Data(hash).base64EncodedString()
    }
    
    
//    private init() {
//        let configuration = URLSessionConfiguration.default
//        
//        // add the default header
//        configuration.httpAdditionalHeaders = ["Content-Type": "application/json"]
//        
//        // get the token from the Keychain
//        let token: String? = "" // Keychain.get("jwttoken")
//        
//        if let token {
//            configuration.httpAdditionalHeaders?["Authorization"] = "Bearer \(token)"
//        }
//        
//
//        self.session = URLSession(configuration: configuration)
//    }
        
    func request<T: Codable>(type: APIEndPointAsync) async throws -> T {
        guard let url = type.url else {
            throw NetworkError.invalidURL
        }
        
        var request = URLRequest(url: url)
        
        switch type.method {
            case .get:

            var urlComponents = URLComponents(url: url, resolvingAgainstBaseURL: false)
            
            let queryItems = type.params?.compactMap {
                return URLQueryItem(name: "\($0)", value: "\($1)")
            }
            urlComponents?.queryItems = queryItems
            
            guard let url = urlComponents?.url else {
                throw NetworkError.badRequest

            }
            request = URLRequest(url: url)
            request.httpMethod = type.method.name
                
            case .post:
                do {
                    guard let body = type.body else {
                        throw NetworkError.badRequest
                    }
                    request.httpMethod = type.method.name
                    request.httpBody = try JSONEncoder().encode(body)
                } catch {
                    throw NetworkError.postParametersEncodingFalure(description: "\(error)")
                }
            
            case .delete:
                request.httpMethod = type.method.name
        }

        let sessionObj = URLSession(configuration: .ephemeral, delegate: self, delegateQueue: nil)

        let (data, response) = try await sessionObj.data(for: request)
        
        if let httpResponse = response as? HTTPURLResponse {
            switch httpResponse.statusCode {
                case 401:
                    throw NetworkError.unauthorized
                default: break
            }
        }
        
        do {
            let result = try JSONDecoder().decode(T.self, from: data)
            return result
        } catch {
            throw NetworkError.decodingError(error)
        }
    }
    
    static var commonHeaders: [String: String] {
        return [
            "Content-Type": "application/json"
        ]
    }
}

extension APIManagerAsync {
    //MARK:- URLSessionDelegate
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if isEnableSSLPinning {

            guard let serverTrust = challenge.protectionSpace.serverTrust else {
                completionHandler(.cancelAuthenticationChallenge,nil)
                return
            }

            //extarct certificate from each api
            if self.isCertificatePinning {
                //compare certificates remote and local
                guard let certificates = SecTrustCopyCertificateChain(serverTrust) as? [SecCertificate],
                      let certificate = certificates.first  else {
                    completionHandler(.cancelAuthenticationChallenge,nil)
                    return
                }
               
                let isSecuredServer = SecTrustEvaluateWithError(serverTrust, nil)
                let remoteCertiData:NSData  = SecCertificateCopyData(certificate)

                guard let pathToCertificate = Bundle.main.path(forResource: "certificate", ofType: "cer") else{
                    fatalError("no local path found")
                }

                let localCertiData = NSData(contentsOfFile: pathToCertificate)
                if isSecuredServer && remoteCertiData.isEqual(to:localCertiData! as Data)  {
                    print("Certificate   Pinning Completed Successfully")
                    completionHandler(.useCredential, URLCredential.init(trust: serverTrust))
                } else {
                    completionHandler(.cancelAuthenticationChallenge,nil)
                }
            } else {
                //compare Keys
                
                if let certificates = SecTrustCopyCertificateChain(serverTrust) as? [SecCertificate],
                   let certificate = certificates.first {
                    let serverPublicKey = SecCertificateCopyKey(certificate)
                    let serverPublicKeyData = SecKeyCopyExternalRepresentation(serverPublicKey!, nil)
                    let data: Data = serverPublicKeyData! as Data
                    let serverHashKey = sha256(data: data)
                    print("Pulic Key",serverHashKey)
                    
                    if serverHashKey == self.hardcodedPublicKey {
                        print("public key Pinning Completed Successfully")
                        completionHandler(.useCredential, URLCredential.init(trust: serverTrust))
                    } else {
                        completionHandler(.cancelAuthenticationChallenge,nil)
                    }
                }
            }
        } else {
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }
}
