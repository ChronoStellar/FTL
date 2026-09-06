//
//  TestView.swift
//  FTL
//
//  Created by Hendrik Nicolas Carlo on 04/09/26.
//

import SwiftUI

struct TestView: View {
    var body: some View {
        TabView {
            Tab("Received", systemImage: "tray.and.arrow.down.fill") {
//                ReceivedView()
            }
            .badge(2)


            Tab("Sent", systemImage: "tray.and.arrow.up.fill") {
//                SentView()
            }


            Tab("Account", systemImage: "person.crop.circle.fill") {
//                AccountView()
            }
            .badge("!")
        }
       }
}

#Preview {
    TestView()
}
