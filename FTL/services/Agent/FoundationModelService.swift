//
//  FoundationModelService.swift
//  FTL
//
//  Created by Hendrik Nicolas Carlo on 07/09/26.
//

 import Foundation
 import FoundationModels
 import Combine

 final class FoundationModelService{
     static var isAvailable: Bool {
         SystemLanguageModel.default.isAvailable
     }
     //Methods
//     static func generateWithTools(prompt: String, useCelsius: Bool = false) async throws -> String {
//         let session = LanguageModelSession(tools: [WeatherTool(useCelsius: useCelsius), GmailTool()])
//         let response = try await session.respond(to: prompt)
//         return response.content
//     }
 }
