import Testing
import Foundation
@testable import SwiftResearch

@Suite("MemoryStorage Tests")
struct MemoryStorageTests {

    @Test("Store and retrieve content")
    func storeAndRetrieve() async throws {
        let storage = MemoryStorage()

        let content = CrawledContent(
            url: URL(string: "https://example.com")!,
            title: "Example",
            description: "An example page",
            markdown: "# Example\n\nThis is an example.",
            links: []
        )

        await storage.store(content)

        let retrieved = await storage.get(by: content.id)
        #expect(retrieved != nil)
        #expect(retrieved?.title == "Example")
    }

    @Test("Get all contents")
    func getAllContents() async throws {
        let storage = MemoryStorage()

        let content1 = CrawledContent(
            url: URL(string: "https://example.com/1")!,
            title: "Page 1",
            description: nil,
            markdown: "# Page 1",
            links: []
        )

        let content2 = CrawledContent(
            url: URL(string: "https://example.com/2")!,
            title: "Page 2",
            description: nil,
            markdown: "# Page 2",
            links: []
        )

        await storage.store(content1)
        await storage.store(content2)

        let allContents = await storage.getAll()
        #expect(allContents.count == 2)
    }

    @Test("Track visited URLs")
    func trackVisitedURLs() async throws {
        let storage = MemoryStorage()
        let url = URL(string: "https://example.com")!

        let hasVisitedBefore = await storage.hasVisited(url)
        #expect(hasVisitedBefore == false)

        await storage.markAsVisited(url)

        let hasVisitedAfter = await storage.hasVisited(url)
        #expect(hasVisitedAfter == true)
    }

    @Test("Clear storage")
    func clearStorage() async throws {
        let storage = MemoryStorage()

        let content = CrawledContent(
            url: URL(string: "https://example.com")!,
            title: "Example",
            description: nil,
            markdown: "# Example",
            links: []
        )

        await storage.store(content)
        await storage.markAsVisited(URL(string: "https://example.com")!)

        await storage.clear()

        let count = await storage.count
        let visitedCount = await storage.visitedCount
        #expect(count == 0)
        #expect(visitedCount == 0)
    }
}
