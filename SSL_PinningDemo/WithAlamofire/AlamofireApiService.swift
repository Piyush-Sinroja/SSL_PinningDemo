//
//  AlamofireApiService.swift
//  SwiftStarterApp
//
//  Created by Piyush Sinroja on 22/11/23.
//

import UIKit
import Reachability
import Alamofire

//typealias AFResultSuccess<T> = (_ response: T) -> Void
//typealias AFResultFail = (_ failResponseDic: [String: Any], _ error: Error?) -> Void
typealias AFResultHandler<T> = (Result<T, Error>) -> Void

enum ApiResponseErrorEnum {
    ///
    static let errorRequestTimeout = NSError(domain: "", code: NSURLErrorTimedOut, userInfo: [NSLocalizedDescriptionKey: Constant.Common.strReqTimeOut])
    ///
    static let errorNoInternet = NSError(domain: "", code: NSURLErrorTimedOut, userInfo: [NSLocalizedDescriptionKey: Constant.Common.internetAlertMsg])
    ///
    static let errorSomethingwentwrong = NSError(domain: "", code: 0, userInfo: [NSLocalizedDescriptionKey: Constant.Common.somethingWrong])
}

struct Certificates {

    static let certificate: SecCertificate = Certificates.certificate(filename: "typicode")

    private static func certificate(filename: String) -> SecCertificate {
        let filePath = Bundle.main.path(forResource: filename, ofType: "cer")!
        let data = try? Data(contentsOf: URL(fileURLWithPath: filePath))
        let certificate = SecCertificateCreateWithData(nil, data! as CFData)!

        return certificate
    }
}

/// ApiManager for call webservice class
final class AlamofireApiService: NSObject {

    // MARK: - Variables

    //
    var isInternetAvailable: Bool = true
    ///
    fileprivate var reachability: Reachability?
    ///
    private let session: Session
    /// request time out seconds
    private static let timeoutIntervalForRequest = 30.0
    /// Time Interval in second for resource time out
    private static let timeoutIntervalForResource = 30.0
    ///
    private static let sharedApiService: AlamofireApiService = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = AlamofireApiService.timeoutIntervalForResource
        configuration.timeoutIntervalForResource = AlamofireApiService.timeoutIntervalForResource

        let certificates = [
            "typicode":
                PinnedCertificatesTrustEvaluator(certificates: [Certificates.certificate],
                                                 acceptSelfSignedCertificates: false,
                                                 performDefaultValidation: true,
                                                 validateHost: true)]
        let serverTrustPolicy = ServerTrustManager(allHostsMustBeEvaluated: true, evaluators: certificates)

        let session = Alamofire.Session(configuration: configuration, serverTrustManager: serverTrustPolicy)
        return AlamofireApiService(session: session)
    }()

    class func shared() -> AlamofireApiService {
        return sharedApiService
    }

    // MARK: - Init
    private init(session: Session) {
        self.session = session
        super.init()
        do {
            reachability = try Reachability.init()
            NotificationCenter.default.addObserver(self, selector: #selector(self.reachabilityChanged(_:)), name: Notification.Name.reachabilityChanged, object: reachability)
            try reachability?.startNotifier()
        } catch let error {
            Logger.log("Unable to start reachability notifier: \(error.localizedDescription)")
        }
    }

    // MARK: - Request Methods

    /// requestFor API Calling methods. We can call any rest API With this common API calling method.
    /// - Parameters:
    ///   - modelType: model type
    ///   - apiType: ApiTypeConfiguration
    ///   - param: parameter dictionary
    ///   - completion: generic success or fail completion handler
    func requestFor<T: Codable>(modelType: T.Type, apiType: ApiTypeConfiguration, param: Parameters? = nil, completion: @escaping AFResultHandler<T>) {
        
        AlamofireApiService.sharedApiService.session.request(apiType.apiUrlStr, method: apiType.httpMethod, parameters: param, encoding: apiType.encoding, headers: apiType.headers).validate().responseData { response in
            switch response.result {
                case .success(let data):
                    do {
                        let userResponse = try JSONDecoder().decode(modelType, from: data)
                        completion(.success(userResponse))
                    } catch {
                        let resError = self.getError(encodingError: nil)
                        completion(.failure(resError))
                    }
                case .failure(let error):
                    if error.isServerTrustEvaluationError {
                        print("network is compromised by any proxy app or MITM.")
                    }
                    print(error.localizedDescription)
                    print(error._code)
                    self.alamofireApiResponseErrorPrint(error: error)
                    let resError = self.getError(encodingError: error.underlyingError) // underlyingError convert AFError to Error
                    completion(.failure(resError))
            }
        }
    }
    
    /// async request API Calling methods. We can call any rest API With this common API calling method.
    /// - Parameters:
    ///   - modelType: model type
    ///   - apiType: ApiTypeConfiguration
    ///   - param: parameter dictionary
    /// - Returns: generic success or fail
    func asyncRequestFor<T: Codable>(modelType: T.Type, apiType: ApiTypeConfiguration, param: Parameters? = nil) async throws -> T {
        try await withUnsafeThrowingContinuation { continuation in
            AlamofireApiService.sharedApiService.session.request(apiType.apiUrlStr, method: apiType.httpMethod, parameters: param, encoding: JSONEncoding.default, headers: apiType.headers).validate().responseData { response in
                switch response.result {
                    case .success(let data):
                        do {
                            let userResponse = try JSONDecoder().decode(modelType, from: data)
                            continuation.resume(returning: userResponse)
                        } catch {
                            let resError = self.getError(encodingError: nil)
                            continuation.resume(throwing: resError)
                        }
                    case .failure(let error):
                        print(error.localizedDescription)
                        print(error._code)
                        self.alamofireApiResponseErrorPrint(error: error)
                        let resError = self.getError(encodingError: error.underlyingError) // underlyingError convert AFError to Error
                        continuation.resume(throwing: resError)
                }
            }
        }
    }

    /// Custom Multipart API Calling methods. We can call any rest API With this common API calling method.
    /// - Parameters:
    ///   - modelType: generic model type
    ///   - apiType: ApiTypeConfiguration
    ///   - parameter: Parameters dic
    ///   - images: array of images if wish to upload images
    ///   - imageKeysArray: array image keys if wish to upload images
    ///   - completion: generic success or fail completion handler
    func multipartRequest<T: Codable>(modelType: T.Type, apiType: ApiTypeConfiguration, parameter: Parameters?, arrImages: [UIImage] = [], arrImageKeys: [String] = [], arrVideosData: [Data] = [], arrVideoKeys: [String] = [], fileUploadData: Data? = nil, fileType: String = "", completion: @escaping AFResultHandler<T>) {

        AlamofireApiService.sharedApiService.session.upload(multipartFormData: { multipartFormData in

            if let param = parameter {
                for (key, value) in (param) {
                    guard let data = "\(value)".data(using: String.Encoding.utf8) else { continue }
                    multipartFormData.append(data, withName: key as String)
                }
            }

            if !arrImages.isEmpty, arrImageKeys.count == arrImages.count {
                for (index, image) in arrImages.enumerated() {
                    let imageKey = arrImageKeys[index]
                    guard let data = image.jpegData(compressionQuality: 1.0) else {
                        continue
                    }
                    let imageName = "Image_\(Date().timeIntervalSince1970).jpg"
                    multipartFormData.append(data, withName: imageKey, fileName: imageName, mimeType: MimeType.jpg.rawValue)
                }
            }

            if !arrVideosData.isEmpty, arrVideoKeys.count == arrVideosData.count {
                for (index, dataVideo) in arrVideosData.enumerated() {
                    let videoKey = arrVideoKeys[index]
                    let videoName = "Video_\(Date().timeIntervalSince1970).mp4"
                    multipartFormData.append(dataVideo, withName: videoKey, fileName: videoName, mimeType: MimeType.videoMp4.rawValue)
                }
            }

            if let fileData = fileUploadData, !fileData.isEmpty {
                let itemName = String(format: "File_\(Date().timeIntervalSince1970).\(fileType)")
                multipartFormData.append(fileData, withName: "file", fileName: itemName, mimeType: fileType)
            }

        }, to: apiType.apiUrlStr, usingThreshold: UInt64.init(), method: apiType.httpMethod, headers: apiType.headers).validate().responseData { response in
            switch response.result {
                case .success(let data):
                    do {
                        let result = try JSONDecoder().decode(modelType, from: data)
                        completion(.success(result))
                    } catch {
                        let resError = self.getError(encodingError: nil)
                        completion(.failure(resError))
                    }
                case .failure(let error):
                    print(error.localizedDescription)
                    print(error._code)
                    self.alamofireApiResponseErrorPrint(error: error)
                    let resError = self.getError(encodingError: error.underlyingError) // underlyingError convert AFError to Error
                    completion(.failure(resError))
            }
        }
        .uploadProgress(queue: .main, closure: { progress in
            //Current upload progress of file
            print("Upload Progress: \(progress.fractionCompleted)")
        })
    }

    /// download request
    /// - Parameters:
    ///   - fileName: file name
    ///   - apiType: ApiTypeConfiguration
    ///   - param: Parameters dic
    ///   - progressHandler: progress completion handler
    ///   - completionHandler: success or fail completion handler
    func downloadRequest(fileName: String, apiType: ApiTypeConfiguration, param: Parameters? = nil, progressHandler: @escaping (_ progress: Double) -> Void, completionHandler: @escaping (String?, Error?) -> Void) {
        let fileUrl = getSaveFileUrl(fileName: fileName)
        let destination: DownloadRequest.Destination = { _, _ in
            return (fileUrl, [.removePreviousFile, .createIntermediateDirectories])
        }
       // let destination = DownloadRequest.suggestedDownloadDestination(options: [.removePreviousFile, .createIntermediateDirectories])
        AlamofireApiService.sharedApiService.session.download(apiType.apiUrlStr, method: apiType.httpMethod, parameters: nil, headers: apiType.headers, to: destination).downloadProgress(closure: { progress in
            progressHandler(progress.fractionCompleted)
        }).response { response in
            switch response.result {
                case .success(let url):
                    let filePath = url?.path
                    completionHandler(filePath, nil)
                case .failure(let error):
                    self.alamofireApiResponseErrorPrint(error: error)
                    let resError = self.getError(encodingError: error.underlyingError) // underlyingError convert AFError to Error
                    completionHandler(nil, resError)
            }
        }
    }

    // MARK: - Helper Methods

    /// get save file url
    /// - Parameter fileName: fileName string
    /// - Returns: filepath url
    private func getSaveFileUrl(fileName: String) -> URL {
        let documentsURL = FileManage.documentsDirectory()
        let fileURL = documentsURL.appendingPathComponent(fileName)
        Logger.log("fileURL \(fileURL)")
        return fileURL
    }

    ///
    private func createBodyWithParameters(parameters: [String: Any]) -> Data? {
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: parameters, options: .prettyPrinted)
            return jsonData
        } catch let error as NSError {
            print(error)
            return nil
        }
    }

    // MARK: - Cancel All Task
    func cancelAllTask() {
      AlamofireApiService.sharedApiService.session.session.getTasksWithCompletionHandler({ dataTasks, uploadTasks, downloadTasks in
        dataTasks.forEach { $0.cancel() }
        uploadTasks.forEach { $0.cancel() }
        downloadTasks.forEach { $0.cancel() }
      })
    }

    // MARK: - Fail Response

    /// get Error
    /// - Parameter encodingError: A type representing an error value that can be thrown.
    /// - Returns: A type representing an error value that can be thrown.
    func getError(encodingError: Error?) -> Error {
        if encodingError?.errorCode == NSURLErrorTimedOut {
            return ApiResponseErrorEnum.errorRequestTimeout
        } else if encodingError?.errorCode == NSURLErrorNotConnectedToInternet || encodingError?.errorCode == 404 {
            return ApiResponseErrorEnum.errorNoInternet
        } else if let encodingError {
            return encodingError
        } else {
            return ApiResponseErrorEnum.errorSomethingwentwrong
        }
    }

    /// alamofire api response error
    /// - Parameter error: AFError is the error type returned by Alamofire. It encompasses a few different types of errors, each with their own associated reasons.
    func alamofireApiResponseErrorPrint(error: AFError) {
        switch error {
            case .createUploadableFailed(let error):
                debugPrint("Create Uploadable Failed, description: \(error.localizedDescription)")
            case .createURLRequestFailed(let error):
                debugPrint("Create URL Request Failed, description: \(error.localizedDescription)")
            case .downloadedFileMoveFailed(let error, let source, let destination):
                debugPrint("Downloaded File Move Failed, description: \(error.localizedDescription)")
                debugPrint("Source: \(source), Destination: \(destination)")
            case .explicitlyCancelled:
                debugPrint("Explicitly Cancelled - \(error.localizedDescription)")
            case .invalidURL(let url):
                debugPrint("Invalid URL: \(url) - \(error.localizedDescription)")
            case .multipartEncodingFailed(let reason):
                debugPrint("Multipart encoding failed, description: \(error.localizedDescription)")
                debugPrint("Failure Reason: \(reason)")
            case .parameterEncodingFailed(let reason):
                debugPrint("Parameter encoding failed, description: \(error.localizedDescription)")
                debugPrint("Failure Reason: \(reason)")
            case .parameterEncoderFailed(let reason):
                debugPrint("Parameter Encoder Failed, description: \(error.localizedDescription)")
                debugPrint("Failure Reason: \(reason)")
            case .requestAdaptationFailed(let error):
                debugPrint("Request Adaptation Failed, description: \(error.localizedDescription)")
            case .requestRetryFailed(let retryError, let originalError):
                debugPrint("Request Retry Failed")
                debugPrint("Original error description: \(originalError.localizedDescription)")
                debugPrint("Retry error description: \(retryError.localizedDescription)")
            case .responseValidationFailed(let reason):
                debugPrint("Response validation failed, description: \(error.localizedDescription)")
                switch reason {
                    case .dataFileNil, .dataFileReadFailed:
                        debugPrint("Downloaded file could not be read")
                    case .missingContentType(let acceptableContentTypes):
                        debugPrint("Content Type Missing: \(acceptableContentTypes)")
                    case .unacceptableContentType(let acceptableContentTypes, let responseContentType):
                        debugPrint("Response content type: \(responseContentType) was unacceptable: \(acceptableContentTypes)")
                    case .unacceptableStatusCode(let code):
                        debugPrint("Response status code was unacceptable: \(code)")
                    default: break
                }
            case .responseSerializationFailed(let reason):
                debugPrint("Response serialization failed: \(error.localizedDescription)")
                debugPrint("Failure Reason: \(reason)")
            case .serverTrustEvaluationFailed(let reason):
                debugPrint("Server Trust Evaluation Failed, description: \(error.localizedDescription)")
                debugPrint("Failure Reason: \(reason)")
            case .sessionDeinitialized:
                debugPrint("Session Deinitialized, description: \(error.localizedDescription)")
            case .sessionInvalidated(let error):
                debugPrint("Session Invalidated, description: \(error?.localizedDescription ?? "")")
            case .sessionTaskFailed(let error):
                debugPrint("Session Task Failed, description: \(error.localizedDescription)")
            case .urlRequestValidationFailed(let reason):
                debugPrint("Url Request Validation Failed, description: \(error.localizedDescription)")
                debugPrint("Failure Reason: \(reason)")
        }
    }
}

// MARK: - Rechability
extension AlamofireApiService {
    /// reachabilityChanged
    @objc func reachabilityChanged(_ notification: Notification) {
        if let reachability = notification.object as? Reachability {
            switch reachability.connection {
                case .wifi, .cellular:
                    Logger.log(".wifi, .cellular")
                    AlamofireApiService.sharedApiService.isInternetAvailable = true
                    Logger.log("Reachable via WiFi or Cellular")
                case .none:
                    Logger.log("none")
                    AlamofireApiService.sharedApiService.isInternetAvailable = false
                    Logger.log("Network not reachable")
                case .unavailable:
                    Logger.log("unavailable")
                    AlamofireApiService.sharedApiService.isInternetAvailable = false
            }
        } else {
            Logger.log("no reachability")
            AlamofireApiService.sharedApiService.isInternetAvailable = false
        }
    }
}

extension Error {
    var errorCode: Int? {
        return (self as NSError).code
    }
}
