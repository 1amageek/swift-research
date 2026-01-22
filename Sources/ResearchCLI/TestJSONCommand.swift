import Foundation
import ArgumentParser
import SwiftResearch

#if USE_OTHER_MODELS
import OpenFoundationModels
import OpenFoundationModelsOllama

extension ResearchCLI {
    struct TestJSON: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "test-json",
            abstract: "Test JSON structured output"
        )

        @Option(name: .long, help: "Ollama model name")
        var model: String = "gpt-oss:20b"

        @Option(name: .long, help: "Number of iterations per test type")
        var iterations: Int = 3

        func run() async throws {
            print("=== JSON Structured Output Test ===")
            print("Model: \(model)")
            print("Iterations per test: \(iterations)")
            print("")

            let config = OllamaConfiguration(timeout: 300)
            let ollamaModel = OllamaLanguageModel(configuration: config, modelName: model)

            var results: [TestResult] = []

            // Test 1: DimensionGenerationResponse
            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            print("TEST 1: DimensionGenerationResponse")
            print("Schema: {\"dimensions\": [...]}")
            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            for i in 1...iterations {
                let result = await testDimensionGeneration(model: ollamaModel, iteration: i)
                results.append(result)
            }

            // Test 2: DimensionScoreResponse
            print("\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            print("TEST 2: DimensionScoreResponse")
            print("Schema: {\"score\": N, \"reasoning\": ..., \"evidence\": [...], \"suggestions\": [...]}")
            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            for i in 1...iterations {
                let result = await testDimensionScore(model: ollamaModel, iteration: i)
                results.append(result)
            }

            // Test 3: StatementExtractionResponse
            print("\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            print("TEST 3: StatementExtractionResponse")
            print("Schema: {\"statements\": [...]}")
            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            for i in 1...iterations {
                let result = await testStatementExtraction(model: ollamaModel, iteration: i)
                results.append(result)
            }

            // Test 4: Shared Session (multiple calls)
            print("\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            print("TEST 4: Shared Session (simulates evaluation framework)")
            print("Multiple calls on same session")
            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            let sharedResults = await testSharedSession(model: ollamaModel, calls: 5)
            results.append(contentsOf: sharedResults)

            // Test 5: Long Context Accumulation
            print("\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            print("TEST 5: Long Context Accumulation")
            print("7 sequential calls with long prompts on same session")
            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            let longContextResults = await testLongContextAccumulation(model: ollamaModel)
            results.append(contentsOf: longContextResults)

            // Summary
            print("\n")
            print("═══════════════════════════════════════")
            print("SUMMARY")
            print("═══════════════════════════════════════")

            let successes = results.filter { $0.success }.count
            let failures = results.filter { !$0.success }.count
            print("Total: \(results.count), Success: \(successes), Failure: \(failures)")
            print("")

            // Failure analysis
            let failedResults = results.filter { !$0.success }
            if !failedResults.isEmpty {
                print("FAILURE PATTERNS:")
                print("─────────────────")
                for result in failedResults {
                    print("\n[\(result.testName)] Iteration \(result.iteration)")
                    print("Error: \(result.error ?? "unknown")")
                    if let raw = result.rawOutput {
                        print("Raw output (first 500 chars):")
                        print("---")
                        print(String(raw.prefix(500)))
                        print("---")
                        analyzeOutput(raw)
                    }
                }
            }
        }

        static let systemInstruction = """
            You are a JSON output assistant.
            Always respond with a JSON object.
            Never output an array directly - wrap arrays in object properties.
            """

        func testDimensionGeneration(model: OllamaLanguageModel, iteration: Int) async -> TestResult {
            print("\n[Iteration \(iteration)]")
            let session = LanguageModelSession(model: model, tools: [], instructions: Self.systemInstruction)

            let prompt = """
            Generate task-specific quality evaluation dimensions for the following research task.

            Task:
            - Objective: What is the current population of Tokyo?
            - Domain: technology
            - Requirements: Accurate information; Current data; Clear explanation
            - Expected format: report
            - Difficulty: medium

            General dimensions (already included):
            - Coverage: Information completeness
            - Insight: Depth of analysis
            - Instruction-following: Adherence to requirements
            - Clarity: Communication quality

            Generate up to 3 ADDITIONAL task-specific dimensions that would be important
            for evaluating research output for THIS specific task.

            Examples of task-specific dimensions:
            - "Technical Accuracy" for technical tasks
            - "Source Diversity" for comparative analysis
            - "Practical Applicability" for how-to guides
            - "Temporal Coverage" for time-sensitive topics

            Do NOT repeat the general dimensions. Focus on what makes this task unique.
            """

            do {
                let response = try await session.respond(to: prompt, generating: DimensionGenerationResponse.self)
                print("✅ Success: \(response.content.dimensions.count) dimensions")
                return TestResult(testName: "DimensionGeneration", iteration: iteration, success: true, rawOutput: nil, error: nil)
            } catch {
                print("❌ Failed: \(error)")
                let raw = await getRawOutput(model: model, prompt: prompt)
                return TestResult(testName: "DimensionGeneration", iteration: iteration, success: false, rawOutput: raw, error: "\(error)")
            }
        }

        func testDimensionScore(model: OllamaLanguageModel, iteration: Int) async -> TestResult {
            print("\n[Iteration \(iteration)]")
            let session = LanguageModelSession(model: model, tools: [], instructions: Self.systemInstruction)

            let prompt = """
            Evaluate the following research output on "Accuracy" from 1-10.

            Output: Tokyo's population is approximately 14 million.
            """

            do {
                let response = try await session.respond(to: prompt, generating: DimensionScoreResponse.self)
                print("✅ Success: score=\(response.content.score)")
                return TestResult(testName: "DimensionScore", iteration: iteration, success: true, rawOutput: nil, error: nil)
            } catch {
                print("❌ Failed: \(error)")
                let raw = await getRawOutput(model: model, prompt: prompt)
                return TestResult(testName: "DimensionScore", iteration: iteration, success: false, rawOutput: raw, error: "\(error)")
            }
        }

        func testStatementExtraction(model: OllamaLanguageModel, iteration: Int) async -> TestResult {
            print("\n[Iteration \(iteration)]")
            let session = LanguageModelSession(model: model, tools: [], instructions: Self.systemInstruction)

            let prompt = """
            Extract 2 verifiable factual statements from the following text.

            Text: Tokyo's population is approximately 14 million, making it Japan's largest city.
            """

            do {
                let response = try await session.respond(to: prompt, generating: StatementExtractionResponse.self)
                print("✅ Success: \(response.content.statements.count) statements")
                return TestResult(testName: "StatementExtraction", iteration: iteration, success: true, rawOutput: nil, error: nil)
            } catch {
                print("❌ Failed: \(error)")
                let raw = await getRawOutput(model: model, prompt: prompt)
                return TestResult(testName: "StatementExtraction", iteration: iteration, success: false, rawOutput: raw, error: "\(error)")
            }
        }

        func testSharedSession(model: OllamaLanguageModel, calls: Int) async -> [TestResult] {
            print("\n[Using single shared session for \(calls) calls]")
            let session = LanguageModelSession(model: model, tools: [], instructions: Self.systemInstruction)
            var results: [TestResult] = []

            let dimensions = ["Accuracy", "Timeliness", "Source Quality", "Completeness", "Clarity"]

            for i in 1...calls {
                print("\n[Call \(i)/\(calls)]")

                let prompt = """
                Evaluate the following research output on "\(dimensions[i-1])" dimension from 1-10.

                Research output:
                Tokyo's population is approximately 14 million people as of 2024.
                The metropolitan area has over 37 million residents.
                This makes it one of the largest urban areas in the world.
                """

                do {
                    let response = try await session.respond(to: prompt, generating: DimensionScoreResponse.self)
                    print("✅ Success: score=\(response.content.score)")
                    results.append(TestResult(testName: "SharedSession", iteration: i, success: true, rawOutput: nil, error: nil))
                } catch {
                    print("❌ Failed: \(error)")
                    let raw = await getRawOutput(model: model, prompt: prompt)
                    results.append(TestResult(testName: "SharedSession", iteration: i, success: false, rawOutput: raw, error: "\(error)"))
                }
            }

            return results
        }

        func testLongContextAccumulation(model: OllamaLanguageModel) async -> [TestResult] {
            print("\n[Using single session for 7 long-context calls]")
            let session = LanguageModelSession(model: model, tools: [], instructions: Self.systemInstruction)
            var results: [TestResult] = []

            let researchOutput = """
            # Tokyo Population Analysis

            ## Current Population
            As of 2024, Tokyo's population stands at approximately 13.96 million people within the 23 special wards, making it Japan's most populous prefecture. The greater Tokyo metropolitan area, including surrounding prefectures, houses over 37 million residents.

            ## Historical Trends (2014-2024)
            The population has shown interesting patterns over the past decade:
            - 2014: 13.35 million
            - 2016: 13.51 million
            - 2018: 13.82 million
            - 2020: 13.99 million (peak before pandemic effects)
            - 2022: 13.84 million (temporary decline)
            - 2024: 13.96 million (recovery phase)

            ## Key Factors Affecting Population
            1. **Urbanization**: Continued migration from rural areas seeking employment and educational opportunities
            2. **Aging Demographics**: Declining birth rate affecting overall population growth trajectory
            3. **COVID-19 Impact**: Temporary outflow during 2020-2021 as remote work enabled suburban migration
            4. **Economic Opportunities**: Tokyo remains Japan's economic hub attracting young professionals

            ## Regional Distribution
            The 23 special wards show varying population densities:
            - Setagaya: 940,000 (highest population)
            - Nerima: 750,000
            - Ota: 730,000
            - Edogawa: 700,000
            - Adachi: 690,000

            ## Sources
            - Tokyo Metropolitan Government Statistics Bureau
            - Japan National Census Data
            - Statistics Bureau of Japan
            - Ministry of Internal Affairs and Communications

            ## Conclusion
            Tokyo's population has remained relatively stable over the past decade, with minor fluctuations due to global events. The long-term trend shows modest growth driven by internal migration despite Japan's overall population decline. The metropolitan area continues to be a major global urban center with significant economic and cultural influence.
            """

            let dimensions = [
                ("Coverage", "How comprehensively the output addresses all aspects of the task"),
                ("Insight", "Depth of analysis and understanding demonstrated"),
                ("Instruction Following", "Adherence to task requirements and constraints"),
                ("Clarity", "Quality of communication and presentation"),
                ("Source Credibility", "Reliability and authority of cited sources"),
                ("Data Granularity", "Level of detail in statistical information"),
                ("Temporal Relevance", "Currency and timeliness of information")
            ]

            for (i, (name, description)) in dimensions.enumerated() {
                print("\n[Call \(i+1)/\(dimensions.count): \(name)]")

                let rubricDescription = """
                  Score 1: Missing most key aspects, no evidence of dimension
                  Score 3: Covers some aspects superficially
                  Score 5: Covers main aspects adequately
                  Score 7: Comprehensive coverage with good detail
                  Score 10: Exhaustive coverage of all aspects with exceptional quality
                """

                let prompt = """
                Evaluate the following research output on the "\(name)" dimension.

                Task:
                - Objective: What is the current population of Tokyo and how has it changed over the past decade?
                - Requirements: Accurate statistics; Historical comparison; Reliable sources; Clear explanation

                Dimension: \(name)
                Description: \(description)

                Rubric:
                \(rubricDescription)

                Research Output:
                ---
                \(researchOutput)
                ---

                Carefully evaluate the research output against the rubric.
                Provide:
                1. A score from 1-10
                2. Detailed reasoning for the score
                3. Specific evidence (quotes or references) from the output
                4. Suggestions for improvement
                """

                do {
                    let response = try await session.respond(to: prompt, generating: DimensionScoreResponse.self)
                    print("✅ Success: score=\(response.content.score)")
                    results.append(TestResult(testName: "LongContext", iteration: i+1, success: true, rawOutput: nil, error: nil))
                } catch {
                    print("❌ Failed: \(error)")
                    let raw = await getRawOutput(model: model, prompt: prompt)
                    results.append(TestResult(testName: "LongContext", iteration: i+1, success: false, rawOutput: raw, error: "\(error)"))
                }
            }

            return results
        }

        func getRawOutput(model: OllamaLanguageModel, prompt: String) async -> String? {
            let session = LanguageModelSession(model: model, tools: [], instructions: Self.systemInstruction)
            do {
                let response = try await session.respond(to: prompt)
                return response.content
            } catch {
                return "Failed to get raw: \(error)"
            }
        }

        func analyzeOutput(_ output: String) {
            let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
            print("Analysis:")

            if trimmed.hasPrefix("{") {
                print("  - Starts with '{' (object) ✓")
            } else if trimmed.hasPrefix("[") {
                print("  - Starts with '[' (ARRAY) ⚠️")
            } else if trimmed.hasPrefix("```") {
                print("  - Starts with markdown code block ⚠️")
            } else {
                let firstChars = String(trimmed.prefix(20)).replacingOccurrences(of: "\n", with: "\\n")
                print("  - Starts with: \"\(firstChars)...\" ⚠️")
            }

            if trimmed.contains("```json") || trimmed.contains("```") {
                print("  - Contains markdown code fence ⚠️")
            }
            if trimmed.contains("<think>") || trimmed.contains("[thinking]") {
                print("  - Contains thinking markers ⚠️")
            }
        }
    }

    struct TestResult {
        let testName: String
        let iteration: Int
        let success: Bool
        let rawOutput: String?
        let error: String?
    }
}

#else

extension ResearchCLI {
    struct TestJSON: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "test-json",
            abstract: "Test JSON structured output (requires USE_OTHER_MODELS=1)"
        )

        func run() async throws {
            print("This test requires USE_OTHER_MODELS=1")
            print("Run: USE_OTHER_MODELS=1 swift run research-cli test-json")
        }
    }
}

#endif
