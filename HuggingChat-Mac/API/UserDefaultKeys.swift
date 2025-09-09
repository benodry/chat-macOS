//
//  UserDefaultKeys.swift
//  HuggingChat-Mac
//
//  Created by Cyril Zakka on 1/22/25.
//

import Foundation

enum UserDefaultsKeys {
    static let userLoggedIn = "userLoggedIn"
    static let baseURL = "baseURL"
    static let models = "models"
    static let activeModel = "active_model"
    static let activeProvider = "active_provider"
    static let openAIBaseURL = "openai_base_url"
    static let openAIAPIKey = "openai_api_key"
    
    // Gemini Configuration
    static let geminiAPIKey = "gemini_api_key"
    
    // Bedrock Configuration
    static let bedrockAccessKey = "bedrock_access_key"
    static let bedrockSecretKey = "bedrock_secret_key"
    static let bedrockRegion = "bedrock_region"
}
