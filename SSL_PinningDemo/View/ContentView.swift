//
//  ContentView.swift
//  SSL_PinningDemo
//
//  Created by Piyush Sinroja on 1/24/24.
//

import SwiftUI

struct ContentView: View {
    
    @ObservedObject var viewModel = ViewModel()
    @State var isShowAlert: Bool = false
    
    var body: some View {
        VStack(alignment: .leading) {
            
            ForEach(viewModel.item, id: \.firstName){ user in
                LazyVStack(alignment: .leading) {
                    Text(user.firstName ?? "")
                    Text(user.lastName ?? "")
                }
                Divider()
            }
            Spacer()
        }
        .padding()
        .onAppear {
            Task {
                do {
                    try await viewModel.getUserList()
                } catch {
                    print("Error",error.localizedDescription)
                    isShowAlert = true
                }
            }
        }
        .alert("SSL Pinnig failed", isPresented: $isShowAlert) {
            Button("OK", role: .cancel) { }
        }
    }
}

#Preview {
    ContentView()
}

