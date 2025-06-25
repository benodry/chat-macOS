//
//  NetworkService.swift
//  HuggingChat-Mac
//
//  Created by Cyril Zakka on 8/23/24.
//

// swift-format-ignore-file
import Combine
import Foundation

public enum DateDecodingStrategy {
    case formatted(DateFormatter)
}

final class NetworkService {
    private static let defaultBaseURL = "https://huggingface.co"
    fileprivate static var BASE_URL: String {
        get {
            UserDefaults.standard.string(forKey: "baseURL") ?? defaultBaseURL
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "baseURL")
        }
    }
    
    static func resetToDefaultURL() {
        BASE_URL = defaultBaseURL
    }
    
    // Helper method to update BASE_URL
    static func updateBaseURL(_ newURL: String) {
        BASE_URL = newURL
    }
//    fileprivate static let BASE_URL: String = "http://192.168.1.111:5173"
//    fileprivate static let BASE_URL: String = "https://dc7a-83-83-23-99.ngrok-free.app"


    static func loginChat() -> AnyPublisher<LoginChat, HFError> {
        let endpoint = URL(string: "\(BASE_URL)/chat/login?callback=huggingchat://login/callback")!
        var request = URLRequest(url: endpoint)

        var headers: [String: String] = [:]
        headers["Accept"] = "*/*"
        headers["Referer"] = "\(BASE_URL)/chat/login"

        request.httpMethod = "GET"  // Changed from POST to GET
        request.allHTTPHeaderFields = headers
        request.httpShouldHandleCookies = true
        // Remove httpBody since it's now a GET request
        
        print("🔐 Using GET method for /chat/login OAuth initiation")
        
        return resolveRequest(request)
    }
    
    static func validateSignIn(code: String, state: String) -> AnyPublisher<Void, HFError> {
        var headers: [String: String] = [:]
        headers["Accept"] = "*/*"
        headers["Referer"] = "\(BASE_URL)/"

        var request = URLRequest(url: URL(string: "\(BASE_URL)/chat/login/callback?code=\(code)&state=\(state)")!)
        request.allHTTPHeaderFields = headers
        request.httpShouldHandleCookies = true  // CRITICAL: Enable cookie handling to receive auth cookies
        
        print("🔐 validateSignIn: Processing OAuth callback with code=\(code.prefix(10))... state=\(state.prefix(10))...")
        
        // Log cookies before OAuth callback
        let cookiesBeforeAuth = HTTPCookieStorage.shared.cookies ?? []
        print("🍪 Cookies BEFORE OAuth callback (\(cookiesBeforeAuth.count)):")
        for cookie in cookiesBeforeAuth.filter({ $0.domain.contains("huggingface") }) {
            print("   \(cookie.name) = \(cookie.value.prefix(20))... (domain: \(cookie.domain))")
        }

        return sendRequest(request)
        .flatMap { data -> AnyPublisher<Void, HFError> in
            // Log cookies after OAuth callback
            print("🔐 OAuth callback completed, checking for new cookies...")
            
            let cookiesAfterAuth = HTTPCookieStorage.shared.cookies ?? []
            print("🍪 Cookies AFTER OAuth callback (\(cookiesAfterAuth.count)):")
            for cookie in cookiesAfterAuth.filter({ $0.domain.contains("huggingface") }) {
                print("   \(cookie.name) = \(cookie.value.prefix(20))... (domain: \(cookie.domain))")
            }
            
            // Check specifically for hf-chat token
            if let hfChatCookie = cookiesAfterAuth.first(where: { $0.name == "hf-chat" }) {
                print("✅ Found hf-chat cookie after OAuth: \(hfChatCookie.value.prefix(20))...")
            } else {
                print("❌ No hf-chat cookie found after OAuth callback")
                
                // Try to find it in a different domain pattern
                let allCookiesWithChat = cookiesAfterAuth.filter { $0.name.contains("chat") || $0.name.contains("token") }
                print("🔍 Alternative cookies containing 'chat' or 'token': \(allCookiesWithChat.count)")
                for cookie in allCookiesWithChat {
                    print("   \(cookie.name) = \(cookie.value.prefix(20))... (domain: \(cookie.domain))")
                }
            }
            
            // CRITICAL: Immediately validate the token by trying to get user info
            print("🔍 Validating obtained token by fetching user info...")
            return NetworkService.getCurrentUser()
                .map { user -> Void in
                    print("✅ Token validation successful! User: \(user.username) (\(user.email))")
                    DispatchQueue.main.async {
                        HuggingChatSession.shared.currentUser = user
                        UserDefaults.standard.setValue(true, forKey: "userLoggedIn")
                    }
                    return Void()
                }
                .catch { error -> AnyPublisher<Void, HFError> in
                    print("❌ Token validation failed: \(error.localizedDescription)")
                    print("🔧 This suggests the OAuth callback succeeded but the token is not working")
                    return Fail(outputType: Void.self, failure: error).eraseToAnyPublisher()
                }
                .eraseToAnyPublisher()
        }.toNetworkError()
    }

    static func createConversation(base: BaseConversation) -> AnyPublisher<Conversation, HFError> {
        AnalyticsService.shared.createConversation(model: base.id)
        let endpoint = "\(BASE_URL)/chat/conversation"
        let headers = ["Content-Type": "application/json"]
        var request = URLRequest(url: URL(string: endpoint)!)
        request.httpMethod = "POST"
        request.allHTTPHeaderFields = headers
        request.httpShouldHandleCookies = true  // Use automatic cookie handling from OAuth

        do {
            let jsonData = try JSONEncoder().encode(base.toNewConversation())
            request.httpBody = jsonData
            return resolveRequest(request, decoder: JSONDecoder.ISO8601())
                .flatMap({ (newConversation: NewConversation) in
                    return getConversation(id: newConversation.id).eraseToAnyPublisher()
                }).eraseToAnyPublisher()
        } catch {
            return Fail(outputType: Conversation.self, failure: HFError.encodeError(error)).eraseToAnyPublisher()
        }
    }

    static func getConversation(id: String) -> AnyPublisher<Conversation, HFError> {
        let endpoint = "\(BASE_URL)/chat/api/conversation/\(id)"
        let request = URLRequest(url: URL(string: endpoint)!)
        return resolveRequest(request, decoder: JSONDecoder.ISO8601Millisec())
    }
    
    static func getMyAssistants() -> AnyPublisher<[Assistant], HFError> {
        let endpoint = "\(BASE_URL)/chat/api/user/assistants"
        let request = URLRequest(url: URL(string: endpoint)!)
        return resolveRequest(request, decoder: JSONDecoder.ISO8601Millisec())
    }
    
    static func getAssistants(page: Int = 0) -> AnyPublisher<AssistantResponse, HFError> {
        let endpoint = "\(BASE_URL)/chat/api/assistants?p=\(page)"
        let request = URLRequest(url: URL(string: endpoint)!)
        return resolveRequest(request, decoder: JSONDecoder.ISO8601Millisec())
    }
    
    static func getAssistant(id: String) -> AnyPublisher<Assistant, HFError> {
        let endpoint = "\(BASE_URL)/chat/api/assistant/\(id)"
        let request = URLRequest(url: URL(string: endpoint)!)
        return resolveRequest(request, decoder: JSONDecoder.ISO8601Millisec())
    }
    
    static func deleteConversation(id: String) -> AnyPublisher<Void, HFError> {
        let endpoint = "\(BASE_URL)/chat/conversation/\(id)"
        var request = URLRequest(url: URL(string: endpoint)!)
        request.httpMethod = "DELETE"
        request.httpShouldHandleCookies = true  // Use automatic cookie handling from OAuth
        return sendRequest(request).map { _ in Void() }.eraseToAnyPublisher()
    }
    
    static func editConversationTitle(conversation: Conversation) -> AnyPublisher<Void, HFError> {
        let endpoint = "\(BASE_URL)/chat/conversation/\(conversation.id)"
        let headers = ["Content-Type": "application/json"]
        var request = URLRequest(url: URL(string: endpoint)!)
        request.httpMethod = "PATCH"
        request.allHTTPHeaderFields = headers
        request.httpShouldHandleCookies = true  // Use automatic cookie handling from OAuth
        
        do {
            let jsonData = try JSONEncoder().encode(conversation.toTitleEditionBody())
            request.httpBody = jsonData
            return sendRequest(request).map { _ in Void() }.eraseToAnyPublisher()
        } catch {
            return Fail(outputType: Void.self, failure: HFError.encodeError(error)).eraseToAnyPublisher()
        }
    }

    static func getConversations() -> AnyPublisher<[Conversation], HFError> {
        let endpoint = "\(BASE_URL)/chat/api/conversations"
        var request = URLRequest(url: URL(string: endpoint)!)
        request.httpShouldHandleCookies = true  // Use automatic cookie handling from OAuth
        return resolveRequest(request, decoder: JSONDecoder.ISO8601Millisec())
    }

    static func getModels() -> AnyPublisher<[LLMModel], HFError> {
        let endpoint = "\(BASE_URL)/chat/api/models"
        let request = URLRequest(url: URL(string: endpoint)!)
        return resolveRequest(request, decoder: JSONDecoder.ISO8601())
    }
    
    static func shareConversation(id: String) -> AnyPublisher<SharedConversation, HFError> {
        let endpoint = "\(BASE_URL)/chat/conversation/\(id)/share"
        let headers = ["Content-Type": "application/json"]
        var request = URLRequest(url: URL(string: endpoint)!)
        request.httpMethod = "POST"
        request.allHTTPHeaderFields = headers
        addAuthCookies(to: &request)
        
        return resolveRequest(request, decoder: JSONDecoder())
    }
    
    static func getCurrentUser() -> AnyPublisher<HuggingChatUser, HFError> {
        print("👤 NetworkService.getCurrentUser")
        guard let hfChatToken = HuggingChatSession.getHfChatToken() else {
            print("❌ Missing hf-chat token")
            return Fail(outputType: HuggingChatUser.self, failure: HFError.missingHFToken).eraseToAnyPublisher()
        }
        print("✅ hf-chat token found: \(hfChatToken.prefix(20))...")
        
        let endpoint = "\(BASE_URL)/chat/api/user"
        print("📍 User endpoint: \(endpoint)")
        
        var request = URLRequest(url: URL(string: endpoint)!)
        // Use GET method as confirmed by the working test script
        
        // Add comprehensive browser-like headers for /chat/api/user endpoint
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        request.setValue("\(BASE_URL)/chat/", forHTTPHeaderField: "Referer")
        request.setValue("no-cache, no-store, must-revalidate", forHTTPHeaderField: "Cache-Control")
        request.setValue("no-cache", forHTTPHeaderField: "Pragma")
        request.setValue("\(Date().timeIntervalSince1970)", forHTTPHeaderField: "X-Cache-Bust")
        
        // Let OAuth cookies be handled automatically by URLSession
        print("🍪 Using automatic cookie handling from OAuth flow")
        
        print("🌐 Using GET method for /chat/api/user")
        
        return resolveRequest(request)
    }
    
    static func getDocumentsDirectory() -> URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return paths[0]
    }
    
    private static func resolveRequest<T: Decodable>(_ request: URLRequest, decoder: JSONDecoder = JSONDecoder()) -> AnyPublisher<T, HFError> {
        print("🔄 NetworkService.resolveRequest for type: \(T.self)")
        return sendRequest(request)
        .tryMap { data in
            print("📥 resolveRequest received data")
            guard let data = data else {
                print("❌ resolveRequest: No data received")
                throw HFError.unknown
            }
            
            print("📦 resolveRequest: Data size \(data.count) bytes")

            do {
                print("🔍 Attempting to decode as \(T.self)")
                let models = try decoder.decode(T.self, from: data)
                print("✅ Successfully decoded \(T.self)")
                return models
            } catch {
                print("❌ Decode Error for \(T.self): \(error)")
                if let jsonString = String(data: data, encoding: .utf8) {
                    print("📄 Failed JSON: \(jsonString.prefix(500))")
                }
                throw HFError.decodeError(error)
            }
        }.toNetworkError().eraseToAnyPublisher()
    }
    
    static func sendRequest(_ request: URLRequest) -> AnyPublisher<Data?, HFError> {
        var req = request
        req.setValue(UserAgentBuilder.userAgent, forHTTPHeaderField: "User-Agent")
        req.setValue(self.BASE_URL, forHTTPHeaderField: "Origin")
        
        // DEBUG: Log request details
        print("🌐 NetworkService.sendRequest")
        print("📍 URL: \(req.url?.absoluteString ?? "nil")")
        print("🔧 Method: \(req.httpMethod ?? "GET")")
        print("📋 Headers: \(req.allHTTPHeaderFields ?? [:])")
        
        // DEBUG: Check which cookies will be sent with this request
        if let url = req.url {
            let cookiesForRequest = HTTPCookieStorage.shared.cookies(for: url) ?? []
            print("🍪 Cookies that will be sent with this request (\(cookiesForRequest.count)):")
            for cookie in cookiesForRequest {
                print("   \(cookie.name) = \(cookie.value.prefix(20))...")
                print("     domain: \(cookie.domain), path: \(cookie.path)")
                print("     secure: \(cookie.isSecure), httpOnly: \(cookie.isHTTPOnly)")
                
                // Check if this cookie matches the current URL
                let domainMatches = url.host?.hasSuffix(cookie.domain) ?? false || cookie.domain.hasPrefix(".")
                let pathMatches = url.path.hasPrefix(cookie.path)
                print("     domainMatches: \(domainMatches), pathMatches: \(pathMatches)")
            }
        }
        
        let publisher = Deferred {
            Future<Data?, HFError> { promise in
                let task = URLSession.shared.dataTask(with: req) { (data, response, error) in
                    
                    // DEBUG: Log response details
                    if let error = error {
                        print("❌ Network Error: \(error.localizedDescription)")
                        promise(.failure(HFError.networkError(error)))
                        return
                    }
                    
                    guard let response = response else {
                        print("❌ No Response received")
                        promise(.failure(.noResponse))
                        return
                    }

                    guard let httpResponse = response as? HTTPURLResponse else {
                        print("❌ Not HTTP Response: \(response)")
                        promise(.failure(.notHTTPResponse(response, data)))
                        return
                    }
                    
                    // DEBUG: Log response status and headers
                    print("📊 HTTP Status: \(httpResponse.statusCode)")
                    print("📋 Response Headers: \(httpResponse.allHeaderFields)")
                    
                    // DEBUG: Check for Set-Cookie headers and verify cookie storage
                    if let url = req.url {
                        if let setCookieHeaders = httpResponse.allHeaderFields["Set-Cookie"] as? String {
                            print("🍪 Set-Cookie header received: \(setCookieHeaders)")
                        }
                        
                        // Check what cookies are now available for this URL
                        let currentCookies = HTTPCookieStorage.shared.cookies(for: url) ?? []
                        print("🍪 Cookies now available for \(url.host ?? "unknown") (\(currentCookies.count)):")
                        for cookie in currentCookies {
                            print("   \(cookie.name) = \(cookie.value.prefix(20))... (domain: \(cookie.domain))")
                        }
                        
                        // Check for hf-chat specifically
                        if let hfChatCookie = currentCookies.first(where: { $0.name == "hf-chat" }) {
                            print("✅ hf-chat cookie available after response: \(hfChatCookie.value.prefix(20))...")
                        }
                    }
                    
                    // DEBUG: Log response body for debugging
                    if let data = data {
                        let dataSize = data.count
                        print("📦 Response Data Size: \(dataSize) bytes")
                        
                        if let responseString = String(data: data, encoding: .utf8) {
                            if dataSize < 1000 {
                                print("📄 Response Body: \(responseString)")
                            } else {
                                print("📄 Response Body (first 500 chars): \(String(responseString.prefix(500)))")
                            }
                        }
                    } else {
                        print("📦 No response data")
                    }

                    guard httpResponse.statusCode >= 200 && httpResponse.statusCode < 300 else {
                        print("❌ HTTP Error \(httpResponse.statusCode)")
                        if let data = data, let errorString = String(data: data, encoding: .utf8) {
                            print("💬 Error Response: \(errorString)")
                        }
                        promise(.failure(.httpError(httpResponse.statusCode, data)))
                        return
                    }
                    
                    print("✅ Request successful")
                    promise(.success(data))
                }

                task.resume()
            }
        }

        return publisher.eraseToAnyPublisher()
    }
    
    // DEPRECATED: Helper method to add authentication cookies to requests manually
    // NOTE: This is now deprecated - all requests should use httpShouldHandleCookies = true
    // to automatically get fresh OAuth tokens from HTTPCookieStorage
    @available(*, deprecated, message: "Use automatic cookie handling (httpShouldHandleCookies = true) instead")
    internal static func addAuthCookies(to request: inout URLRequest) {
        guard let hfChatToken = HuggingChatSession.getHfChatToken() else {
            print("⚠️ No hf-chat token available for request")
            return
        }
        
        let cookieHeader = "hf-chat=\(hfChatToken)"
        request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        print("🍪 Added auth cookie to request: hf-chat=\(hfChatToken.prefix(20))...")
    }
}

final class PostStream: NSObject, URLSessionDelegate, URLSessionDataDelegate {
    private let BASE_URL: String = NetworkService.BASE_URL
    private let sessionConfiguration: URLSessionConfiguration = URLSessionConfiguration.default..{
        $0.requestCachePolicy = .reloadIgnoringLocalCacheData
        $0.httpCookieStorage = HTTPCookieStorage.shared  // Use shared cookie storage for OAuth tokens
        $0.httpShouldSetCookies = true
        $0.httpCookieAcceptPolicy = .always
    }
    private lazy var session: URLSession = URLSession(configuration: sessionConfiguration, delegate: self, delegateQueue: .main)
    
    private let encoder = JSONEncoder()..{
        $0.keyEncodingStrategy = .convertToSnakeCase
    }
    
    private var _update: PassthroughSubject<Data, HFError> = PassthroughSubject<Data, HFError>()

    func postPrompt(reqBody: PromptRequestBody, conversationId: String) -> AnyPublisher<Data, HFError> {
        let endpoint = "\(BASE_URL)/chat/conversation/\(conversationId)"
        
        let boundary = UUID().uuidString
        var request = URLRequest(url: URL(string: endpoint)!)
        
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue(UserAgentBuilder.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("\(BASE_URL)", forHTTPHeaderField: "Origin")
        
        // CRITICAL: Use automatic cookie handling for message sending to get fresh OAuth tokens
        request.httpShouldHandleCookies = true
        
        var data = Data()
        
        // Add the files. Add tools Document Parser if supported.
        // TODO: Limit to 10MB per file otherwise error out
        if let filePaths = reqBody.files {
            for (_, filePath) in filePaths.enumerated() {
                let fileURL = URL(fileURLWithPath: filePath)
                let filename = fileURL.lastPathComponent
                do {
                    let fileData = try Data(contentsOf: fileURL)
                    let base64String = fileData.base64EncodedString()
                    
                    data.append("--\(boundary)\r\n".data(using: .utf8)!)
                    data.append("Content-Disposition: form-data; name=\"files\"; filename=\"base64;\(filename)\"\r\n".data(using: .utf8)!)
                    data.append("Content-Type: \(mimeType(for: fileURL))\r\n\r\n".data(using: .utf8)!)
                    data.append(base64String.data(using: .utf8)!)
                    data.append("\r\n".data(using: .utf8)!)
                } catch {
                    print("Error reading file: \(error)")
                }
            }
        }
        
        // Create a cleaned request body without files for JSON
        var cleanedReqBody = reqBody
        cleanedReqBody.files = nil
        
        // Add the JSON part
        do {
            let jsonData = try encoder.encode(cleanedReqBody)
            data.append("--\(boundary)\r\n".data(using: .utf8)!)
            data.append("Content-Disposition: form-data; name=\"data\"\r\n".data(using: .utf8)!)
            data.append("Content-Type: application/json\r\n\r\n".data(using: .utf8)!)
            data.append(jsonData)
            data.append("\r\n".data(using: .utf8)!)
        } catch {
            return Fail(outputType: Data.self, failure: HFError.encodeError(error)).eraseToAnyPublisher()
        }
        
        // Add the final boundary
        data.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = data

        let task = self.session.dataTask(with: request)
        task.delegate = self
        
        return _update.eraseToAnyPublisher().handleEvents(receiveRequest: { _ in
            task.resume()
        })
        .eraseToAnyPublisher()
    }
    
    func mimeType(for url: URL) -> String {
        let pathExtension = url.pathExtension
        
        switch pathExtension.lowercased() {
        case "jpg", "jpeg":
            return "image/jpeg"
        case "png":
            return "image/png"
        case "gif":
            return "image/gif"
        case "pdf":
            return "application/pdf"
        default:
            return "application/octet-stream"
        }
    }


    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        _update.send(data)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            _update.send(completion: .failure(HFError.networkError(error)))
            return
        }
        
        guard let response = task.response else {
            _update.send(completion: .failure(.noResponse))
            return
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            _update.send(completion: .failure(.notHTTPResponse(response, nil)))
            return
        }
        
        if httpResponse.statusCode == 429 {
            _update.send(completion: .failure(.httpTooManyRequest))
            return
        }

        guard httpResponse.statusCode >= 200 && httpResponse.statusCode < 300 else {
            _update.send(completion: .failure(.httpError(httpResponse.statusCode, nil)))
            return
        }
        
        _update.send(completion: .finished)
    }
}

