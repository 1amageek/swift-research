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
- [Ollama](https://ollama.ai/) (Local LLM runtime)
- Optional: Apple FoundationModels (build with `USE_FOUNDATION_MODELS=1`)

## Installation

```bash
git clone https://github.com/1amageek/swift-research.git
cd swift-research
swift build
```

## Usage

### CLI

```bash
# Basic usage
.build/debug/research-cli "Features of OpenAI GPT-4.1"

# Output detailed logs to file
.build/debug/research-cli "Bus timetable from Fukuyama to Innoshima" --log /tmp/research.log

# Show help
.build/debug/research-cli --help
```

### Options

| Option | Description | Default |
|--------|-------------|---------|
| `--limit` | Maximum URLs to visit | 50 |
| `--model` | Ollama model name | lfm2.5-thinking |
| `--format` | Output format (text/json) | text |
| `--verbose` | Show detailed LLM I/O | false |
| `--log` | Log file path | none |

### As a Library

```swift
import SwiftResearch

let configuration = CrawlerConfiguration(
    modelName: "lfm2.5-thinking"
)

let orchestrator = SearchOrchestratorStep(
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

This aligns with the **modular pipeline** architecture pattern described in [Agentic RAG research](https://arxiv.org/abs/2501.09136), where specialized modules handle distinct tasks within the agent workflow.

### Structured vs Markdown

- **Structured (@Generable)**: Data for programmatic processing (bool flags, keyword arrays, link indices)
- **Markdown**: Human-readable analysis text, summaries, review content

### Parallel Processing with Shared Context

Phase 3 uses multiple workers (default: 4) to process URLs concurrently:

- **CrawlContext**: Thread-safe shared state using NSLock
- **Known Facts Sharing**: Each worker sees facts discovered by others, reducing duplicate extraction
- **Domain Learning**: Tracks which domains yield relevant content (2+ relevant pages)
- **Dynamic Queue**: Workers add DeepCrawl URLs to shared queue for other workers to process

### Hysteresis in LLM Decisions

DeepCrawl and sufficiency checks consider past results:

- **DeepCrawl**: Stop when consecutive irrelevant pages are encountered
- **Sufficiency Check**: Give up when no new relevant pages are found

## Evaluation Framework

SwiftResearch includes a comprehensive evaluation framework for assessing research quality:

### Components

- **Quality Evaluation**: Scores research output across multiple dimensions (Coverage, Insight, Clarity, Technical Accuracy, etc.)
- **Fact Checking**: Extracts verifiable statements and validates them against web sources
- **Task Construction**: Generates evaluation tasks based on personas and domains

### Running Evaluations

```bash
# Run evaluation framework test
swift run research-cli test-evaluation

# With custom model
swift run research-cli test-evaluation --model lfm2.5-thinking
```

### Benchmark Results

| Metric | Score |
|--------|-------|
| Overall Score | 80.2/100 |
| Quality Score | 67.0/100 |
| Factual Accuracy | 100% |

### Evaluation Architecture

```
EvaluationTask
    ↓
┌─────────────────────────────────┐
│  Research Execution             │
│  (SearchOrchestratorStep)       │
└─────────────────────────────────┘
    ↓
┌─────────────────────────────────┐
│  Quality Evaluation             │
│  - Dimension Generation         │
│  - Dimension Scoring            │
│  - Overall Assessment           │
└─────────────────────────────────┘
    ↓
┌─────────────────────────────────┐
│  Fact Checking                  │
│  - Statement Extraction         │
│  - Evidence Retrieval           │
│  - Verification                 │
└─────────────────────────────────┘
    ↓
EvaluationResult
```

## Dependencies

- [SwiftAgent](https://github.com/1amageek/SwiftAgent) - Agent framework
- [OpenFoundationModels-Ollama](https://github.com/1amageek/OpenFoundationModels-Ollama) - Ollama integration
- [Remark](https://github.com/1amageek/Remark) - Web page to Markdown conversion
- [Selenops](https://github.com/1amageek/Selenops) - Search engine integration

## License

MIT
