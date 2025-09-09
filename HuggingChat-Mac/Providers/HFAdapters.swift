import Foundation
import ChatCore
import CryptoKit

// MARK: - Stable UUID derivation from remote id (deterministic)
private func stableUUID(from remoteId: String) -> UUID {
    let digest = SHA256.hash(data: Data(remoteId.utf8))
    let bytes = Array(digest.prefix(16))
    return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7], bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
}

extension Message {
    func toChatMessage() -> ChatMessage {
        ChatMessage(
            id: stableUUID(from: id),
            remoteId: id,
            role: ChatRole(rawValue: author.rawValue) ?? .assistant,
            content: content,
            createdAt: createdAt,
            updatedAt: updatedAt,
            metadata: MessageMetadata()
        )
    }
}

extension Conversation {
    func toChatConversation(provider: ProviderKind) -> ChatConversation? {
        // serverId is remote id
        let convId = stableUUID(from: serverId)
        let msgs = messages.map { $0.toChatMessage() }
        return ChatConversation(
            id: convId,
            remoteId: serverId,
            provider: provider,
            modelId: modelId,
            title: title,
            createdAt: updatedAt, // HF API lacks explicit createdAt; approximate
            updatedAt: updatedAt,
            messages: msgs
        )
    }
}

// Adapter utilities for arrays (future use)
extension Array where Element == Conversation {
    func toChatConversations(provider: ProviderKind) -> [ChatConversation] { compactMap { $0.toChatConversation(provider: provider) } }
}