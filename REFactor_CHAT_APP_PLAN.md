# Chat macOS App Refactor & Extension Plan

This document captures actionable phases to: (1) decouple from Hugging Face backend, (2) add multi‑provider model support (local + OpenAI/LiteLLM/Gemini/Bedrock), (3) integrate MCP tooling, (4) develop core logic in Swift (VS Code + SPM) while keeping macOS UI, and (5) manage repo forking & dependency updates.

---
## High‑Level Goals
1. Provider‑agnostic architecture: swap Hugging Face API with pluggable providers.
2. Local + remote model parity (conversation persistence, streaming, tool use).
3. MCP tool discovery & invocation seamlessly inside chat loops.
4. Clean separation of UI (macOS SwiftUI/AppKit) and Core Engine (Swift Package).
5. Sustainable maintenance: version pinning, upgrade cadence, branching workflow.

---
## Phase Overview (Revised Ordering)
| Phase | Focus | Deliverables | Risk |
|-------|-------|-------------|------|
| 0a | Domain Model & IDs | Normalized `ChatMessage`, `ChatConversation`, stable IDs, `GenerationConfig`, `TokenEvent` | Low |
| 0b | Provider Protocol Scaffold | `ChatProvider`, `ProviderKind`, `ProviderCapabilities`, adapter stubs | Low |
| 1 | OpenAI-Compatible Base Provider | Generic OpenAI-style provider (LiteLLM / direct) + provider selection UI (basic) | Low |
| 2 | Local Conversation Persistence | JSON store (protocol-driven) + integration into send pipeline | Medium |
| 3 | Multi Remote Expansion | Gemini & Bedrock via OpenAI facade (or gateway), capability flags | Medium |
| 4 | Local MLX Provider | Local model provider unified under protocol | Medium |
| 5 | MCP Integration (Tools) | MCP client, tool call loop orchestration | Medium/High |
| 6 | UX & Cleanup | Enhanced picker UI, tool output rendering, export/import | Low |
| 7 | Hardening & Upgrades | Retries, logging, tests, CI, dependency governance | Medium |

---
## Detailed Action Items
### Phase 0a – Domain Model & ID Stabilization
- [ ] Define value types (Codable):
  - `ChatRole` (user, assistant, system, tool)
  - `ChatMessage { id(UUID), remoteId:String?, role:ChatRole, content:String, createdAt, updatedAt, metadata:MessageMetadata }`
  - `ChatConversation { id(UUID), remoteId:String?, provider:ProviderKind, modelId:String, title:String, createdAt, updatedAt, messages:[ChatMessage] }`
  - `GenerationConfig { temperature:Double?, maxTokens:Int?, topP:Double?, topK:Int?, presencePenalty:Double?, frequencyPenalty:Double?, reasoningBudget:Int? }`
  - `TokenEvent` (token, reasoning, webSearchUpdate, webSearchSources, toolCall, toolResult, completed, error)
- [ ] Adapter: Map existing HF `Conversation` & `Message` into normalized structures.
- [ ] Stabilize identity: stop generating ephemeral UUIDs for remote conversations; keep remote id separately.

### Phase 0b – Provider Protocol Scaffold
- [ ] `ProviderKind` enum (huggingFace, openAI, gemini, bedrock, local)
- [ ] `ProviderCapabilities { supportsTools, supportsReasoning, supportsStreaming, maxContextTokens }`
- [ ] `ChatProvider` protocol:
  - `var kind: ProviderKind { get }`
  - `func capabilities() -> ProviderCapabilities`
  - `func listModels() async throws -> [ModelInfo]`
  - `func send(messages:[ChatMessage], model: ModelInfo, config: GenerationConfig, stream: @escaping (TokenEvent)->Void) async throws -> ChatMessage`
- [ ] `ConversationStore` protocol (`create/load/save/append/delete`).
- [ ] JSON implementation (`JSONConversationStore`) with injectable root path (testability).
- [ ] Add mock provider for unit tests.

### Phase 1 – OpenAI-Compatible Base Provider
- [ ] Implement generic `OpenAICompatibleProvider` (configurable baseURL + apiKey) for any OpenAI-spec endpoint (LiteLLM, Together, Fireworks, etc.).
- [ ] Basic provider selection UI (HF vs OpenAI) – minimal toggle initially.
- [ ] Streaming normalization (SSE / JSONL) → `TokenEvent.token`.
- [ ] Integrate `GenerationConfig` (optional params filtered to supported ones).

### Phase 2 – Local Conversation Persistence
- [ ] JSON-backed `ConversationStore` (file-per-conversation; atomic writes).
- [ ] Incremental append strategy: buffer streaming tokens in memory; flush final assistant message on completion.
- [ ] HF conversations: maintain cached local mirror (read-only) for unified UI.
- [ ] UI labeling: Remote (HF) vs Local (OpenAI, Gemini, Bedrock, LocalModel).
- [ ] Migration placeholder: (Later) import historical HF conversations into local store (Phase 5+ optional).

### Phase 3 – Multi Remote Provider Expansion (Gemini & Bedrock)
- [ ] Extend OpenAI-compatible layer to support Gemini & Bedrock via facade (prefer gateway to avoid custom auth early).
- [ ] Capability flags per model (reasoning, tool use, max context).
- [ ] Add provider configuration UI (baseURL, key, providerKind).
- [ ] Conversation creation for non-HF providers is local-only (stateless remote APIs).

### Phase 4 – Local MLX Provider
- [ ] Implement `LocalMLXProvider` (wrap local inference APIs once architecture stable).
- [ ] Uniform token streaming via same `TokenEvent` channel.
- [ ] Optional auto-fallback setting.

### Phase 5 – MCP Tooling
- [ ] Add `MCPClient` (connect via stdio / TCP / UNIX socket) with:
  - `connect()`, `listTools()`, `invoke(toolName:arguments:)` (JSON in/out).
  - Keep a cache of tool schemas & validation.
- [ ] Settings:
  - Toggle: Enable MCP Tools
  - Connection fields: protocol (stdio/socket), path/host/port
  - Refresh Tools button.
- [ ] Provider integration:
  - If provider supports tool calls (OpenAI function calling, future Claude tools), include tool definitions in request.
  - Parse tool calls in responses → invoke MCP → append tool result messages → send follow-up (autonomous loop up to N rounds, default 2–3).
- [ ] UI:
  - Inline tool execution status (spinner + result block)
  - Collapsible tool output (truncate large JSON with expand option)
- [ ] Error policy: timeout per tool, fallback to assistant note on failure.

### Phase 6 – UX & Cleanup
- [ ] Conversation title heuristic (first user message slice) for local sessions.
- [ ] Disable / hide HF login flows if provider != huggingFace.
- [ ] Guard analytics + remote-only calls behind provider type check.
- [ ] Add manual refresh models button per provider.
- [ ] Provide export/import of local conversations (zip JSON files).

### Phase 7 – Hardening & Maintenance
- [ ] Add retry logic with exponential backoff for network providers.
- [ ] Add token count / cost estimation (if OpenAI-compatible returns usage) to message metadata.
- [ ] Logging abstraction (structured) with log level setting.
- [ ] Basic unit tests: provider stubs, MCP client mock, persistence read/write, tool call loop termination.
- [ ] Add CI job: build + test + swift-format lint.

---
## MCP Integration Specification (Phase 5)
| Aspect | Approach |
|--------|----------|
| Discovery | `initialize` handshake → fetch tool list (JSON-RPC). |
| Tool Schema | Stored as JSON Schema; pass trimmed schema to model providers. |
| Invocation | Sequential (no parallel calls initially), each with timeout (default 15s). |
| Loop Control | Max tool iterations per user prompt (default 3). |
| Security | Optional allowlist of tool names; sanitize large outputs (truncate > 8KB). |
| Extensibility | Future: add streaming tool outputs if MCP server supports incremental events. |

---
## Swift Development in VS Code
1. Extract core logic into SPM package (`ChatCore`).
2. Keep macOS UI app (SwiftUI/AppKit) referencing package (Xcode workspace).
3. VS Code workflow:
   - Edit providers, MCP client, persistence in `ChatCore`.
   - Run: `swift test` / `swift build`.
4. Debug CLI Harness (add small CLI target to simulate conversation + tool calls for rapid iteration outside the app).
5. Use official Swift extension + CodeLLDB.

### Sample Package Layout
```
ChatCore/
  Package.swift
  Sources/ChatCore/
    Providers/
    MCP/
    Persistence/
    Models/
    ConversationEngine.swift
  Tests/ChatCoreTests/
```

### Sample `Package.swift` (conceptual)
```swift
// swift-tools-version: 5.10
import PackageDescription

let package = Package(
  name: "ChatCore",
  platforms: [.macOS(.v14)],
  products: [ .library(name: "ChatCore", targets: ["ChatCore"]) ],
  dependencies: [
    // Add JSON schema validator or WebSocket lib if needed
  ],
  targets: [
    .target(name: "ChatCore", dependencies: []),
    .testTarget(name: "ChatCoreTests", dependencies: ["ChatCore"])    
  ]
)
```

### Suggested VS Code `tasks.json` (for the SPM package)
```jsonc
{
  "version": "2.0.0",
  "tasks": [
    { "label": "Swift: Build", "type": "shell", "command": "swift build", "group": "build", "problemMatcher": [] },
    { "label": "Swift: Test", "type": "shell", "command": "swift test", "group": "test", "problemMatcher": [] },
    { "label": "Swift: Format (dry-run)", "type": "shell", "command": "swift format --mode=lint .", "problemMatcher": [] }
  ]
}
```
(Place in `.vscode/tasks.json` inside the SPM package root—not required in this proxy repo.)

---
## Repository & Fork Strategy
| Decision | Recommendation |
|----------|----------------|
| Fork now? | Yes—fork `huggingface/chat-macOS` before invasive changes for easier upstream rebases. |
| Branching | Long-lived `refactor/providers` branch → PR into your `main` once Phase 2 stable. |
| Sync Upstream | Periodic upstream fetch (`upstream/main`) merge or rebase before each major phase. |
| Core Package | Optionally separate repo (`chat-core`) if you anticipate reuse (CLI, other platforms). Start inside fork; extract later if needed. |
| Issue Tracking | Create GitHub issues per phase milestone + checklist. |

### Fork Workflow Steps
1. Fork upstream on GitHub.
2. Clone fork locally: `git clone git@github.com:<you>/chat-macOS.git`.
3. Add upstream remote: `git remote add upstream git@github.com:huggingface/chat-macOS.git`.
4. Create working branch: `git checkout -b refactor/providers`.
5. Implement Phases 0–2; open PR inside your fork for review history.
6. Periodically: `git fetch upstream && git rebase upstream/main` (resolve conflicts early).

---
## Dependency (Package) Update Strategy
### Categories
- Swift Packages (MLXLLM, WhisperKit, Sparkle, etc.)
- System toolchains (Swift version alignment with Xcode)
- External MCP server dependencies (separate runtime environment)

### Strategy
1. Baseline Inventory: `swift package show-dependencies --format json` (or inspect `Package.resolved`).
2. Pin: Commit `Package.resolved` to ensure reproducibility.
3. Scheduled Updates: Monthly `swift package update` on a dedicated `deps/update-YYYY-MM` branch.
4. Selective Upgrades: For security advisories or bug fixes, bump individually.
5. CI Guardrails:
   - Build + test matrix for current & next Swift toolchain (if feasible).
   - Run `swift build -c release` to catch optimization issues.
6. Audit & Security:
   - (Optional) Integrate Dependabot (GitHub) for Swift ecosystem.
   - Manual review of release notes before merging mass updates.
7. Rollback Plan: If regression, revert that single dependency commit (thanks to isolated branch). 
8. Tooling Enhancements:
   - Add `make deps-update` script (runs update + opens summary diff). 
   - Add a simple script to diff public API using `swift-docc` or `swift symbolgraph-extract` (optional).

### Version Policy
- Patch: Auto-merge if tests green.
- Minor: Manual review; ensure no deprecated API removals.
- Major: Create spike branch; run manual exploratory testing (UI + streaming + local model load + MCP path). 

---
## Risk & Mitigation Snapshot
| Risk | Mitigation |
|------|------------|
| Dual code paths complexity | Time-box Hugging Face path removal after Phase 3 if no longer needed. |
| Streaming inconsistencies | Centralize token event normalization at provider layer. |
| Tool call recursion runaway | Enforce max tool iterations per prompt. |
| Large tool output UI freeze | Truncate & lazy-expand. |
| Dependency drift | Monthly scheduled update branch + CI gates. |
| Fork divergence | Rebase upstream before each phase merge. |

---
## Minimal Definition of Done (Incremental)
MVP Slice A (after Phase 1):
- Start app without HF login; converse via OpenAI-compatible backend.
- Streaming tokens appear; final assistant message persisted (local store behind feature flag, optional until Phase 2 complete).

MVP Slice B (after Phase 2):
- Local conversations list (create, reopen) for OpenAI provider.
- HF remote conversations still viewable; selection doesn’t break normalized engine.

MVP Slice C (after Phase 3):
- Gemini & Bedrock selectable (through facade) with per-provider API keys.
- Unified persistence & model list (capabilities visible in UI tooltip or label).

Full MVP (after Phase 5):
- MCP tool call loop succeeds for at least one tool invocation round trip.
- Switching providers retains local history; HF unaffected.
- Unit tests (providers, persistence, token stream normalization) pass in CI.

---
## Stretch Goals (Post-MVP)
- Conversation search (inverted index over local JSON/SQLite).
- Embeddings provider abstraction for semantic recall.
- Multi-window or tabbed conversations.
- Tool marketplace / dynamic enable/disable per conversation.
- Shared memory context window summarization (rolling summary message injection).

---
## Quick Start Next Steps
1. Fork repo & create `refactor/providers` branch.
2. Add `ChatCore` package + protocol skeleton (Phase 0).
3. Implement `OpenAICompatibleProvider` pointed at existing LiteLLM proxy; manual test with a single conversation.
4. Add local persistence for non-HF providers.
5. Iterate to MLX provider & remove `isLocalGeneration` branching.
6. Begin MCP client spike (list & invoke one dummy tool) before full tool loop.

---
## Reference Checklist (Condensed & Revised)
- [ ] Phase 0a: Normalized models & IDs
- [ ] Phase 0b: Provider protocol + capabilities + mock provider
- [ ] Phase 1: OpenAI-compatible provider + basic UI toggle
- [ ] Phase 2: JSON conversation store + integration
- [ ] Phase 3: Gemini & Bedrock expansion
- [ ] Phase 4: Local MLX provider
- [ ] Phase 5: MCP client + tool loop
- [ ] Phase 6: Enhanced UX (picker, export/import, labels)
- [ ] Phase 7: Hardening (retries, logging, tests, CI, deps)

## Implementation Status (Live Tracking)
| Item | Status | Notes |
|------|--------|-------|
| Normalized Models | Done | `CoreModels.swift` in ChatCore |
| Provider Protocol | Done | `ProviderProtocols.swift` with capabilities |
| JSON Conversation Store | Done | `JSONConversationStore` implemented (final-write only; incremental append deferred) |
| OpenAI Provider | Done | `OpenAICompatibleProvider` basic streaming |
| Local Conversation Mgmt UI | Partial | Create/rename/delete implemented (sidebar); export/import stubs added |
| Gemini / Bedrock | In Progress | GeminiProvider & BedrockProvider scaffolds added |
| Local MLX Provider | Pending | After multi-remote stable |
| MCP Client | Pending | JSON-RPC loop later |
| Tool Loop | Pending | Autonomous cap (max iterations) |
| Tests (Core) | Partial | Some tests added (delta, mock provider) |
| CI Setup | Pending | Add after initial tests land |

Update this table as each PR/commit lands.

---
Questions / Changes? Append below and iterate.
