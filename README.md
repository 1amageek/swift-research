# SwiftResearch

An LLM-powered, objective-driven research assistant. Autonomously collects information based on user objectives and generates structured reports.

## Features

- **Objective-Driven**: Just input your goal, and the LLM plans the research strategy
- **Autonomous Collection**: Automatically executes search, content review, and deep crawl decisions
- **Adaptive Termination**: LLM evaluates information sufficiency and terminates at the right time
- **History-Based Decisions**: Considers past results (hysteresis) in DeepCrawl and sufficiency checks

## Architecture

Operates through a 5-phase orchestration flow:

```
Phase 1: Objective Analysis
    Analyze objective, generate search keywords and success criteria
    ↓
Phase 2: Search & Fetch
    Search with keywords, retrieve URL list
    ↓
Phase 3: Content Review
    Review each page, extract relevant information
    Execute DeepCrawl (follow links) when necessary
    ↓
Phase 4: Sufficiency Check
    Evaluate if collected information meets the objective
    Return to Phase 2 with additional keywords if insufficient
    ↓
Phase 5: Response Building
    Synthesize collected information into final report
```

## Requirements

- Swift 6.0+
- macOS 15+ / iOS 18+
- [Ollama](https://ollama.ai/) (Local LLM runtime)

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
| `--model` | Ollama model name | gpt-oss:20b |
| `--format` | Output format (text/json) | text |
| `--verbose` | Show detailed LLM I/O | false |
| `--log` | Log file path | none |

### As a Library

```swift
import SwiftResearch

let configuration = CrawlerConfiguration(
    modelName: "gpt-oss:20b"
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

### Hysteresis in LLM Decisions

DeepCrawl and sufficiency checks consider past results:

- **DeepCrawl**: Stop when consecutive irrelevant pages are encountered
- **Sufficiency Check**: Give up when no new relevant pages are found

## Dependencies

- [SwiftAgent](https://github.com/1amageek/SwiftAgent) - Agent framework
- [OpenFoundationModels-Ollama](https://github.com/1amageek/OpenFoundationModels-Ollama) - Ollama integration
- [Remark](https://github.com/1amageek/Remark) - Web page to Markdown conversion
- [Selenops](https://github.com/1amageek/Selenops) - Search engine integration

## License

MIT
