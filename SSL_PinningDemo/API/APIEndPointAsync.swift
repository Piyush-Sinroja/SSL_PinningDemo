//
//  APIEndPointAsync.swift
//  SSL_PinningDemo
//
//  Created by Piyush Sinroja on 1/24/24.
//

import Foundation

protocol EndPointTypeAsync {
    var path: String { get }
    var baseURL: String { get }
    var url: URL? { get }
    var method: HTTPMethodAsync { get }
    var body: Encodable? { get }
    var headers: [String: String]? { get }
    var params: [String: Any]? { get }
}


enum APIEndPointAsync {
    case users // GET
    case usersWithID(params: [String: Any]) // GET With Params
}

extension APIEndPointAsync: EndPointTypeAsync {
    var path: String {
        switch self {
        case .users:
            return "users"
        case .usersWithID:
            return "users"
        }
    }

    var baseURL: String {
        switch self {
        case .users:
            return Constant.API.baseURL
        case .usersWithID:
            return Constant.API.baseURL
        }
    }

    var url: URL? {
        return URL(string: "\(baseURL)\(path)")
    }

    var method: HTTPMethodAsync {
        switch self {
        case .users:
            return .get
        case .usersWithID:
            return .get
        }
    }

    var body: Encodable? {
        switch self {
        case .users:
            return nil
        case .usersWithID:
            return nil
        }
    }

    var params: [String: Any]? {
        switch self {
        case .users:
            return nil
        case .usersWithID(params: let params):
            return params
        }
    }

    var headers: [String: String]? {
        APIManagerAsync.commonHeaders
    }
}
