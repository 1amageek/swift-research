import Foundation
import SwiftAgent
import RemarkKit

/// A tool for fetching content from URLs with link extraction.
///
/// Extends the standard URL fetch functionality to also extract
/// and return links found within the page content.
public struct FetchToolWithLinks: Tool, Sendable {
    public typealias Arguments = FetchWithLinksInput
    public typealias Output = FetchWithLinksOutput

    public static let name = "WebFetch"
    public var name: String { Self.name }

    public static let description = """
    Fetch content from a URL and extract links found in the page.
    Returns the page content as Markdown along with a list of links.
    Use this to read web pages and discover related content through links.
    """

    public var description: String { Self.description }

    public var parameters: GenerationSchema {
        FetchWithLinksInput.generationSchema
    }

    public init() {}

    public func call(arguments: FetchWithLinksInput) async throws -> FetchWithLinksOutput {
        // Use RemarkKit to fetch the page
        guard let url = URL(string: arguments.url) else {
            return FetchWithLinksOutput(
                success: false,
                content: "",
                links: [],
                url: arguments.url,
                message: "Invalid URL format"
            )
        }

        do {
            let remark = try await Remark.fetch(from: url)
            let markdown = remark.markdown

            // Extract links from the markdown content
            let links = extractLinks(from: markdown, baseURL: arguments.url)

            return FetchWithLinksOutput(
                success: true,
                content: markdown,
                links: links,
                url: arguments.url,
                message: "Successfully fetched page with \(links.count) links"
            )
        } catch {
            return FetchWithLinksOutput(
                success: false,
                content: "",
                links: [],
                url: arguments.url,
                message: "Failed to fetch: \(error.localizedDescription)"
            )
        }
    }

    /// Extracts links from Markdown content.
    private func extractLinks(from markdown: String, baseURL: String) -> [PageLink] {
        var links: [PageLink] = []
        let pattern = "\\[([^\\]]+)\\]\\(([^)]+)\\)"

        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return links
        }

        let range = NSRange(markdown.startIndex..., in: markdown)
        let matches = regex.matches(in: markdown, options: [], range: range)

        let baseURLObject = URL(string: baseURL)

        for match in matches {
            guard match.numberOfRanges >= 3,
                  let textRange = Range(match.range(at: 1), in: markdown),
                  let urlRange = Range(match.range(at: 2), in: markdown) else {
                continue
            }

            let text = String(markdown[textRange])
            var urlString = String(markdown[urlRange])

            // Skip non-http links, anchors, and javascript
            guard !urlString.hasPrefix("#"),
                  !urlString.hasPrefix("javascript:"),
                  !urlString.hasPrefix("mailto:") else {
                continue
            }

            // Convert relative URLs to absolute
            if !urlString.hasPrefix("http://") && !urlString.hasPrefix("https://") {
                if let base = baseURLObject {
                    if let absoluteURL = URL(string: urlString, relativeTo: base) {
                        urlString = absoluteURL.absoluteString
                    }
                }
            }

            // Avoid duplicates
            if !links.contains(where: { $0.url == urlString }) {
                links.append(PageLink(url: urlString, text: text))
            }
        }

        return links
    }
}

// MARK: - Input/Output Types

/// Input for fetch with links operation.
@Generable
public struct FetchWithLinksInput: Sendable {
    @Guide(description: "The URL to fetch content from")
    public let url: String
}

/// A link found within a page.
public struct PageLink: Sendable, Equatable {
    /// The URL of the link.
    public let url: String

    /// The anchor text of the link.
    public let text: String

    public init(url: String, text: String) {
        self.url = url
        self.text = text
    }
}

/// Output for fetch with links operation.
public struct FetchWithLinksOutput: Sendable {
    /// Whether the fetch was successful.
    public let success: Bool

    /// The page content as Markdown.
    public let content: String

    /// Links found in the page.
    public let links: [PageLink]

    /// The original URL.
    public let url: String

    /// A message about the operation.
    public let message: String

    public init(success: Bool, content: String, links: [PageLink], url: String, message: String) {
        self.success = success
        self.content = content
        self.links = links
        self.url = url
        self.message = message
    }
}

extension FetchWithLinksOutput: CustomStringConvertible {
    public var description: String {
        let status = success ? "Success" : "Failed"
        var output = """
        WebFetch [\(status)]
        URL: \(url)
        \(message)
        """

        if success {
            // Truncate content if too long
            let maxContentLength = 2000
            let truncatedContent = content.count > maxContentLength
                ? String(content.prefix(maxContentLength)) + "\n...[truncated]"
                : content

            output += "\n\n## Content\n\(truncatedContent)"

            if !links.isEmpty {
                output += "\n\n## Links (\(links.count) found)"
                for (index, link) in links.prefix(20).enumerated() {
                    output += "\n\(index + 1). [\(link.text)](\(link.url))"
                }
                if links.count > 20 {
                    output += "\n... and \(links.count - 20) more links"
                }
            }
        }

        return output
    }
}

extension FetchWithLinksOutput: PromptRepresentable {
    public var promptRepresentation: Prompt {
        Prompt(description)
    }
}
