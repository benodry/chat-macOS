//
//  MCPToolSelector.swift
//  HuggingChat-Mac
//
//  Created by MCP Integration on 12/22/24.
//

import Foundation
import NaturalLanguage

/// Intelligent tool selection based on user requests
class MCPToolSelector {
    
    private let tagger = NLTagger(tagSchemes: [.lemma, .nameType, .lexicalClass])
    
    // MARK: - Tool Selection
    
    /// Select the best tool for a given request
    func selectBestTool(
        for request: MCPToolRequest,
        from tools: [MCPTool],
        servers: [MCPServer]
    ) async -> MCPToolSelection? {
        
        let candidates = filterCandidates(tools: tools, servers: servers, request: request)
        
        guard !candidates.isEmpty else { return nil }
        
        let scoredCandidates = await scoreCandidates(candidates, for: request)
        
        return scoredCandidates.max(by: { $0.confidence < $1.confidence })
    }
    
    /// Get multiple tool suggestions ranked by relevance
    func suggestTools(
        for request: MCPToolRequest,
        from tools: [MCPTool],
        servers: [MCPServer]
    ) async -> [MCPToolSelection] {
        
        let candidates = filterCandidates(tools: tools, servers: servers, request: request)
        let scoredCandidates = await scoreCandidates(candidates, for: request)
        
        return Array(scoredCandidates
            .sorted(by: { $0.confidence > $1.confidence })
            .prefix(request.maxResults))
    }
    
    // MARK: - Private Methods
    
    private func filterCandidates(
        tools: [MCPTool],
        servers: [MCPServer],
        request: MCPToolRequest
    ) -> [(tool: MCPTool, server: MCPServer)] {
        
        let onlineServers = servers.filter { $0.status == .online }
        var candidates: [(tool: MCPTool, server: MCPServer)] = []
        
        for tool in tools {
            guard let server = onlineServers.first(where: { $0.id == tool.serverID }) else {
                continue
            }
            
            // Filter by preferred categories if specified
            if !request.preferredCategories.isEmpty &&
               !request.preferredCategories.contains(tool.category) {
                continue
            }
            
            candidates.append((tool: tool, server: server))
        }
        
        return candidates
    }
    
    private func scoreCandidates(
        _ candidates: [(tool: MCPTool, server: MCPServer)],
        for request: MCPToolRequest
    ) async -> [MCPToolSelection] {
        
        return await withTaskGroup(of: MCPToolSelection?.self) { group in
            var selections: [MCPToolSelection] = []
            
            for candidate in candidates {
                group.addTask {
                    return await self.scoreCandidate(candidate, for: request)
                }
            }
            
            for await selection in group {
                if let selection = selection {
                    selections.append(selection)
                }
            }
            
            return selections
        }
    }
    
    private func scoreCandidate(
        _ candidate: (tool: MCPTool, server: MCPServer),
        for request: MCPToolRequest
    ) async -> MCPToolSelection? {
        
        let tool = candidate.tool
        let server = candidate.server
        
        // Calculate various scoring factors
        let nameScore = calculateTextSimilarity(request.userQuery, tool.name)
        let descriptionScore = calculateTextSimilarity(request.userQuery, tool.description)
        let categoryScore = calculateCategoryScore(request, tool)
        let serverHealthScore = calculateServerHealthScore(server)
        
        // Context scoring if available
        let contextScore: Double
        if let context = request.context {
            contextScore = max(
                calculateTextSimilarity(context, tool.name),
                calculateTextSimilarity(context, tool.description)
            )
        } else {
            contextScore = 0.0
        }
        
        // Weighted final score
        let weights = ScoringWeights()
        let finalScore = (
            nameScore * weights.name +
            descriptionScore * weights.description +
            categoryScore * weights.category +
            serverHealthScore * weights.serverHealth +
            contextScore * weights.context
        ) / weights.total
        
        let reasoning = generateReasoning(
            tool: tool,
            server: server,
            scores: (nameScore, descriptionScore, categoryScore, serverHealthScore, contextScore),
            finalScore: finalScore
        )
        
        return MCPToolSelection(
            tool: tool,
            server: server,
            confidence: finalScore,
            reasoning: reasoning
        )
    }
    
    // MARK: - Scoring Functions
    
    private func calculateTextSimilarity(_ text1: String, _ text2: String) -> Double {
        let normalizedText1 = normalizeText(text1)
        let normalizedText2 = normalizeText(text2)
        
        // Exact match bonus
        if normalizedText1.contains(normalizedText2) || normalizedText2.contains(normalizedText1) {
            return 1.0
        }
        
        // Keyword intersection
        let words1 = Set(normalizedText1.components(separatedBy: .whitespacesAndNewlines))
        let words2 = Set(normalizedText2.components(separatedBy: .whitespacesAndNewlines))
        
        let intersection = words1.intersection(words2)
        let union = words1.union(words2)
        
        guard !union.isEmpty else { return 0.0 }
        
        return Double(intersection.count) / Double(union.count)
    }
    
    private func calculateCategoryScore(_ request: MCPToolRequest, _ tool: MCPTool) -> Double {
        if request.preferredCategories.contains(tool.category) {
            return 1.0
        }
        
        // Infer category from query
        let inferredCategories = inferCategoriesFromQuery(request.userQuery)
        return inferredCategories.contains(tool.category) ? 0.8 : 0.3
    }
    
    private func calculateServerHealthScore(_ server: MCPServer) -> Double {
        switch server.status {
        case .online: return 1.0
        case .unknown: return 0.5
        case .offline: return 0.1
        case .error: return 0.0
        }
    }
    
    private func inferCategoriesFromQuery(_ query: String) -> Set<MCPToolCategory> {
        let normalizedQuery = normalizeText(query)
        var categories: Set<MCPToolCategory> = []
        
        let categoryKeywords: [MCPToolCategory: [String]] = [
            .search: ["search", "find", "look", "query", "discover"],
            .fileSystem: ["file", "folder", "directory", "save", "load", "read", "write"],
            .web: ["web", "website", "url", "http", "download", "fetch", "scrape"],
            .database: ["database", "sql", "query", "table", "record", "data"],
            .api: ["api", "request", "call", "endpoint", "service"],
            .ai: ["ai", "ml", "model", "predict", "analyze", "generate"],
            .utility: ["convert", "transform", "calculate", "utility", "helper"]
        ]
        
        for (category, keywords) in categoryKeywords {
            if keywords.contains(where: { normalizedQuery.contains($0) }) {
                categories.insert(category)
            }
        }
        
        return categories
    }
    
    private func normalizeText(_ text: String) -> String {
        return text.lowercased()
            .components(separatedBy: .punctuationCharacters)
            .joined(separator: " ")
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
    
    private func generateReasoning(
        tool: MCPTool,
        server: MCPServer,
        scores: (name: Double, description: Double, category: Double, serverHealth: Double, context: Double),
        finalScore: Double
    ) -> String {
        var reasons: [String] = []
        
        if scores.name > 0.7 {
            reasons.append("High name relevance")
        }
        
        if scores.description > 0.6 {
            reasons.append("Strong description match")
        }
        
        if scores.category > 0.8 {
            reasons.append("Perfect category fit")
        } else if scores.category > 0.6 {
            reasons.append("Good category match")
        }
        
        if scores.serverHealth == 1.0 {
            reasons.append("Server online and healthy")
        } else if scores.serverHealth < 0.5 {
            reasons.append("Server health concerns")
        }
        
        if scores.context > 0.5 {
            reasons.append("Relevant to context")
        }
        
        let reasonText = reasons.isEmpty ? "Basic compatibility" : reasons.joined(separator: ", ")
        return "\(reasonText). Confidence: \(String(format: "%.1f", finalScore * 100))%"
    }
}

// MARK: - Supporting Types

private struct ScoringWeights {
    let name: Double = 0.3
    let description: Double = 0.25
    let category: Double = 0.2
    let serverHealth: Double = 0.15
    let context: Double = 0.1
    
    var total: Double {
        return name + description + category + serverHealth + context
    }
}
