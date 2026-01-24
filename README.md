# SwiftResearch

An LLM-powered, objective-driven research assistant. Autonomously collects information based on user objectives and generates structured reports.

## Features

- **Objective-Driven**: Just input your goal, and the LLM plans the research strategy
- **Autonomous Collection**: Automatically executes search, content review, and deep crawl decisions
- **Adaptive Termination**: LLM evaluates information sufficiency and terminates at the right time
- **Parallel Processing**: Multiple workers process URLs concurrently for faster results
- **Knowledge Sharing**: Workers share discovered facts to avoid duplicate information extraction
- **Domain Learning**: Automatically prioritizes domains that yield relevant content

## Architecture

Operates through a 5-phase orchestration flow with parallel processing:

```
Phase 1: Objective Analysis
    Analyze objective, generate search keywords and success criteria
    ↓
Phase 2: Search & Fetch
    Search with keywords, retrieve URL list
    ↓
Phase 3: Parallel Content Review
    ┌─────────────────────────────────────────┐
    │  CrawlContext (Shared State)            │
    │  - URL Queue (thread-safe)              │
    │  - Known Facts (shared between workers) │
    │  - Relevant Domains (learned)           │
    └─────────────────────────────────────────┘
         ↓           ↓           ↓           ↓
    ┌────────┐  ┌────────┐  ┌────────┐  ┌────────┐
    │Worker 0│  │Worker 1│  │Worker 2│  │Worker 3│
    └────────┘  └────────┘  └────────┘  └────────┘
    - Each worker: fetch → LLM review → add DeepCrawl URLs
    - Share discovered facts to improve review accuracy
    ↓
Phase 4: Sufficiency Check
    Evaluate if collected information meets the objective
    Return to Phase 2 with additional keywords if insufficient
    ↓
Phase 5: Response Building
    Synthesize collected information into final report
```

## Requirements

- Swift 6.2+
- macOS 26+ / iOS 26+
- [Ollama](https://ollama.ai/) (Local LLM runtime) - for development/testing
- Apple FoundationModels (default, production)

## Installation

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
| `--verbose` | Show detailed LLM I/O | false |
| `--log <path>` | Log file path | none |
| `--test-search` | Test search step only | false |
| `--test-fetch` | Test fetch step only | false |

**Ollama mode** (build with `USE_OTHER_MODELS=1`):

| Option | Description | Default |
|--------|-------------|---------|
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

let configuration = CrawlerConfiguration(
    researchConfiguration: ResearchConfiguration(llmSupportsConcurrency: false)
)

let orchestrator = SearchOrchestratorStep(
    model: model,
    configuration: configuration,
    verbose: true
)

let query = SearchQuery(
    objective: "Features of OpenAI GPT-4.1",
    maxVisitedURLs: 50
)

let result = try await orchestrator.run(query)
print(result.responseMarkdown)
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

### Components

- **Quality Evaluation**: Scores research output across multiple dimensions
- **Fact Checking**: Extracts verifiable statements and validates them against web sources
- **Task Construction**: Generates evaluation tasks based on personas and domains

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

**Quality Dimensions**:

| Dimension | Score |
|-----------|-------|
| Coverage | 5/10 |
| Insight | 7/10 |
| Instruction Following | 10/10 |
| Clarity | 10/10 |
| Technical Accuracy | 10/10 |
| Source Diversity | 10/10 |

## Design Principles

### Step-Based Modular Architecture

All components implement the `Step` protocol from [SwiftAgent](https://github.com/1amageek/SwiftAgent), enabling:

- **Composability**: Each Step can be used independently or combined into larger workflows
- **Reusability**: Other agents can incorporate these Steps into their own pipelines
- **Testability**: Individual Steps can be tested in isolation
- **Extensibility**: Replace any Step with a custom implementation

```swift
// Each Step has typed Input and Output
public struct SearchStep: Step {
    typealias Input = KeywordSearchInput
    typealias Output = [URL]
}

public struct SearchOrchestratorStep: Step {
    typealias Input = SearchQuery
    typealias Output = AggregatedResult
}

// Compose Steps in your own agent
let searchStep = SearchStep(searchEngine: .duckDuckGo)
let urls = try await searchStep.run(KeywordSearchInput(keyword: "swift concurrency"))
```

### Structured vs Markdown

- **Structured (@Generable)**: Data for programmatic processing (bool flags, keyword arrays, link indices)
- **Markdown**: Human-readable analysis text, summaries, review content

### Parallel Processing with Shared Context

Phase 3 uses multiple workers (default: 4) to process URLs concurrently:

- **CrawlContext**: Thread-safe shared state using Mutex
- **Known Facts Sharing**: Each worker sees facts discovered by others
- **Domain Learning**: Tracks which domains yield relevant content
- **Dynamic Queue**: Workers add DeepCrawl URLs to shared queue

## Dependencies

- [SwiftAgent](https://github.com/1amageek/SwiftAgent) - Agent framework
- [OpenFoundationModels-Ollama](https://github.com/1amageek/OpenFoundationModels-Ollama) - Ollama integration
- [Remark](https://github.com/1amageek/Remark) - Web page to Markdown conversion
- [Selenops](https://github.com/1amageek/Selenops) - Search engine integration

## License

MIT
