# SwiftResearch

An LLM-powered autonomous research library. The LLM autonomously calls tools to search, fetch, and evaluate web content, generating evidence-based answers to user queries.

## Features

- **Agentic Architecture**: LLM autonomously decides which tools to call and when
- **Autonomous Collection**: Automatically executes search, page fetching, and link following
- **Semantic Termination**: LLM evaluates information sufficiency and terminates at the right time
- **Parallel Fetching**: Multiple URLs are fetched concurrently via FetchToolWithLinks
- **Structured Evaluation**: Dedicated evaluation tool with its own LLM session for reliable structured output

## Architecture

The LLM operates in an autonomous loop, calling tools as needed without explicit phase transitions:

```
ResearchAgent
    │
    ▼
AgentSession(model, tools: [...])
    │
    ├── WebSearchTool           # Web search (DuckDuckGo)
    ├── FetchToolWithLinks      # Page fetch + link extraction (parallel)
    └── EvaluateSufficiencyTool # Sufficiency evaluation (own Session)

LLM Autonomous Loop:
    1. Understand  ── Analyze query
    2. Search      ── Call WebSearchTool
    3. Fetch       ── Call FetchToolWithLinks
    4. Evaluate    ── Call EvaluateSufficiencyTool
       ├─ Insufficient → Return to 2 or 3
       └─ Sufficient   → Exit loop
    5. Answer      ── Generate response from collected content
```

## Requirements

- Swift 6.2+
- macOS 26+ / iOS 26+
- [Ollama](https://ollama.ai/) (Local LLM runtime) - for development/testing
- Apple FoundationModels (default, production)

## Installation

### Using Mint (Recommended)

```bash
mint install 1amageek/swift-research
```

### From Source

```bash
git clone https://github.com/1amageek/swift-research.git
cd swift-research
swift build
```

## Usage

### CLI

```bash
# Basic research
research "Features of OpenAI GPT-4.1"

# With URL limit and JSON output
research "Rust vs Go comparison" --limit 30 --format json

# Verbose mode with logging
research "Quantum computing trends" --verbose --log ./research.log

# Interactive mode (prompts for query)
research
```

### Options

| Option | Description | Default |
|--------|-------------|---------|
| `--limit <n>` | Maximum URLs to visit | 50 |
| `--format <type>` | Output format (text / json) | text |
| `--verbose` | Show detailed tool call info | false |
| `--log <path>` | Log file path | none |
| `--test-search` | Test search step only | false |
| `--test-fetch` | Test fetch step only | false |

**Ollama mode** (build with `USE_OTHER_MODELS=1`):

| Option | Description | Default |
|--------|-------------|---------|
| `--claude` | Use Claude API | false |
| `--model <name>` | Ollama model name | lfm2.5-thinking |
| `--base-url <url>` | Ollama server URL | http://127.0.0.1:11434 |
| `--timeout <sec>` | Request timeout | 300.0 |

### Testing Individual Steps

```bash
# Test search step (keyword → URL list)
research "Swift Concurrency" --test-search

# Test fetch step (URL → Markdown)
research "https://developer.apple.com/swift/" --test-fetch
```

### As a Library

```swift
import SwiftResearch
import SwiftAgent

let model = SystemLanguageModel()  // or OllamaLanguageModel

let agent = ResearchAgent(
    model: model,
    configuration: .init(maxURLs: 20)
)

let result = try await agent.research("Features of OpenAI GPT-4.1")
print(result.answer)
print("Sources: \(result.visitedURLs)")
```

## Build Options

```bash
# Apple FoundationModels (default, production)
swift build

# Ollama mode (development/testing)
USE_OTHER_MODELS=1 swift build
```

## Testing

### Test Suites

| Suite | Purpose | Requirements |
|-------|---------|--------------|
| AgentToolTests | Unit tests for tools | None |
| EvaluationModelTests | Unit tests for evaluation models | None |
| PromptTendencyTests | LLM response tendency analysis | Ollama |
| EvaluationBenchmarkTests | Quality & fact-check benchmarks | Ollama |

### Running Tests

```bash
# Unit tests (no Ollama required)
swift test --filter EvaluationModelTests

# Benchmark tests (requires Ollama)
USE_OTHER_MODELS=1 swift test --filter EvaluationBenchmarkTests

# All tests
USE_OTHER_MODELS=1 swift test
```

## Evaluation Framework

SwiftResearch includes a comprehensive evaluation framework for assessing research quality.

### Evaluation Pipeline

```
Research Execution
    │
    ├── Quality Evaluation (AdaptiveQualityStep)
    │   ├── Coverage          # Information completeness
    │   ├── Insight           # Depth of analysis
    │   ├── Instruction Following
    │   ├── Clarity           # Readability
    │   ├── Technical Accuracy
    │   └── Source Diversity
    │
    └── Fact Check (FactCheckOrchestratorStep)
        ├── Statement Extraction
        ├── Evidence Retrieval
        └── Verification (correct/incorrect/unknown)
```

### Benchmark Results (2026-01-24)

**Query**: "What is the current population of Tokyo?"
**Model**: lfm2.5-thinking (Ollama)

| Metric | Score | Baseline |
|--------|-------|----------|
| Overall | 92.8/100 | ≥70 |
| Quality | 88.0/100 | ≥60 |
| Factual Accuracy | 100% | - |

## Design Principles

### Agentic Architecture

The LLM autonomously decides the research strategy. There is no hardcoded orchestrator or phase transitions — the LLM reads its instructions and calls tools as needed.

### Tool Pattern for Structured Output

EvaluateSufficiencyTool creates its own LanguageModelSession internally, placing the JSON schema in Instructions rather than in conversation history. This significantly improves structured output reliability.

### Semantic Termination

Instead of fixed crawl limits, the LLM evaluates whether collected information is sufficient to answer the query. `maxURLs` serves as a safety limit to prevent runaway loops.

### @Generable Schema Definition

Tool arguments use `@Generable` macro with `@Guide(description:)` annotations, enabling the LLM to generate correctly formatted tool call arguments.

## Dependencies

- [SwiftAgent](https://github.com/1amageek/SwiftAgent) - Agent framework (Step, Tool, AgentSession)
- [Remark](https://github.com/1amageek/Remark) - HTML to Markdown conversion and link extraction
- [OpenFoundationModels-Ollama](https://github.com/1amageek/OpenFoundationModels-Ollama) - Ollama integration (optional)
- [OpenFoundationModels-Claude](https://github.com/1amageek/OpenFoundationModels-Claude) - Claude API integration (optional)

## License

MIT
