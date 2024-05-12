//
//  ViewModel.swift
//  SSL_PinningDemo
//
//  Created by Piyush Sinroja on 1/24/24.
//

import Foundation
import SwiftUI

class ViewModel: ObservableObject {
 
    @Published var item : [User] = [User]()
    
    @MainActor
    func getUserList()  async throws {
        let users: UserResponse = try await APIManagerAsync.shared.request(type: APIEndPointAsync.users)
        self.item = users.data ?? []
    }
}
