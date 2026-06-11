//
//----------------------------------------------
// Original project: WWDCCodeExtractor
//
// Follow me on Mastodon: https://iosdev.space/@StewartLynch
// Follow me on Threads: https://www.threads.net/@stewartlynch
// Follow me on Bluesky: https://bsky.app/profile/stewartlynch.bsky.social
// Follow me on X: https://x.com/StewartLynch
// Follow me on LinkedIn: https://linkedin.com/in/StewartLynch
// Email: slynch@createchsol.com
// Subscribe on YouTube: https://youTube.com/@StewartLynch
// Buy me a ko-fi:  https://ko-fi.com/StewartLynch
//----------------------------------------------
// Copyright © 2026 CreaTECH Solutions (Stewart Lynch). All rights reserved.

import Foundation

struct CodeExtractionResult {
  var markdown: String
  var snippetCount: Int
  var suggestedFilename: String
}

struct CodeSnippet {
  var time: String
  var title: String
  var link: URL
  var code: String
}

enum CodeTabExtractorError: LocalizedError {
  case invalidURL
  case unsupportedURL
  case videoPageUnavailable
  case requestFailed(Int)
  case missingCodeTab

  var errorDescription: String? {
    switch self {
    case .invalidURL:
      "Enter a valid Apple Developer video URL."
    case .unsupportedURL:
      "The URL does not look like an Apple Developer video page."
    case .videoPageUnavailable:
      "Apple Developer redirected that URL away from a video page. Check the event and session number."
    case .requestFailed(let statusCode):
      "Apple Developer returned HTTP \(statusCode)."
    case .missingCodeTab:
      "No Code tab snippets were found for that video."
    }
  }
}

struct CodeTabExtractor {
  func extractMarkdown(from urlString: String) async throws -> CodeExtractionResult {
    let videoURL = try normalizedVideoURL(from: urlString)
    let html = try await fetchHTML(from: videoURL)
    let title = extractSessionTitle(from: html) ?? "Apple Developer Video"
    let snippets = extractSnippets(from: html, baseURL: videoURL)

    guard !snippets.isEmpty else {
      throw CodeTabExtractorError.missingCodeTab
    }

    return CodeExtractionResult(
      markdown: renderMarkdown(title: title, sourceURL: videoURL, snippets: snippets),
      snippetCount: snippets.count,
      suggestedFilename: suggestedFilename(for: videoURL)
    )
  }

  private func normalizedVideoURL(from urlString: String) throws -> URL {
    var normalized = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
    if !normalized.hasPrefix("http://") && !normalized.hasPrefix("https://") {
      normalized = "https://\(normalized)"
    }

    guard var components = URLComponents(string: normalized) else {
      throw CodeTabExtractorError.invalidURL
    }

    guard components.host == "developer.apple.com",
      components.path.contains("/videos/play/")
    else {
      throw CodeTabExtractorError.unsupportedURL
    }

    components.scheme = "https"
    components.query = nil
    components.fragment = nil

    if !components.path.hasSuffix("/") {
      components.path += "/"
    }

    guard let url = components.url else {
      throw CodeTabExtractorError.invalidURL
    }
    return url
  }

  private func fetchHTML(from url: URL) async throws -> String {
    var request = URLRequest(url: url)
    request.setValue("Mozilla/5.0 WWDCCodeExtractor", forHTTPHeaderField: "User-Agent")

    let (data, response) = try await URLSession.shared.data(for: request)
    if let httpResponse = response as? HTTPURLResponse,
      !(200..<300).contains(httpResponse.statusCode)
    {
      throw CodeTabExtractorError.requestFailed(httpResponse.statusCode)
    }

    guard response.url?.path.contains("/videos/play/") == true else {
      throw CodeTabExtractorError.videoPageUnavailable
    }

    return String(decoding: data, as: UTF8.self)
  }

  private func extractSessionTitle(from html: String) -> String? {
    guard let h1 = firstMatch(in: html, pattern: #"<h1[^>]*>(.*?)</h1>"#) else {
      return nil
    }
    return cleanHTMLText(h1).trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private func extractSnippets(from html: String, baseURL: URL) -> [CodeSnippet] {
    let pattern = #"<li\s+class=\"sample-code-main-container\"[^>]*>.*?<p>(.*?)</p>.*?<pre\s+class=\"code-source\"><code>(.*?)</code></pre>.*?</li>"#
    let matches = matches(in: html, pattern: pattern)

    return matches.compactMap { match in
      guard match.count == 2 else { return nil }

      let headingHTML = match[0]
      let heading = cleanHTMLText(headingHTML).singleSpaced()
      let link = extractHref(from: headingHTML)
        .flatMap { URL(string: $0, relativeTo: baseURL)?.absoluteURL }
        ?? baseURL
      let timeAndTitle = splitHeading(heading)

      return CodeSnippet(
        time: timeAndTitle.time,
        title: timeAndTitle.title,
        link: link,
        code: cleanCodeHTML(match[1])
      )
    }
  }

  private func splitHeading(_ heading: String) -> (time: String, title: String) {
    let parts = heading.components(separatedBy: " - ")
    guard let time = parts.first, parts.count > 1 else {
      return ("", heading)
    }
    return (time, parts.dropFirst().joined(separator: " - "))
  }

  private func renderMarkdown(title: String, sourceURL: URL, snippets: [CodeSnippet]) -> String {
    var lines = [
      "# WWDC Code Tab",
      "",
      "Source: \(sourceURL.absoluteString)",
      "Session: \(title)",
      "",
      "Extracted \(snippets.count) code snippets from the Code tab.",
      ""
    ]

    for (index, snippet) in snippets.enumerated() {
      let headingTitle = snippet.time.isEmpty
        ? "\(index + 1). \(snippet.title)"
        : "\(index + 1). \(snippet.time) - \(snippet.title)"

      lines.append("## \(headingTitle)")
      lines.append("")
      lines.append("Video link: \(snippet.link.absoluteString)")
      lines.append("")
      lines.append("```swift")
      lines.append(snippet.code)
      lines.append("```")
      lines.append("")
    }

    return lines.joined(separator: "\n")
  }

  private func suggestedFilename(for url: URL) -> String {
    let components = url.pathComponents
    guard let event = components.first(where: { $0.hasPrefix("wwdc") }),
      let session = components.last(where: { $0.allSatisfy(\.isNumber) })
    else {
      return "WWDC-Code.md"
    }

    return "\(event.uppercased())-\(session)-Code.md"
  }

  private func extractHref(from html: String) -> String? {
    firstMatch(in: html, pattern: #"href=\"([^\"]+)\""#)
  }

  private func cleanHTMLText(_ html: String) -> String {
    decodeHTMLEntities(stripTags(from: html))
  }

  private func cleanCodeHTML(_ html: String) -> String {
    decodeHTMLEntities(stripTags(from: html))
      .trimmingCharacters(in: CharacterSet(charactersIn: "\n"))
  }

  private func stripTags(from html: String) -> String {
    html.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
  }

  private func decodeHTMLEntities(_ text: String) -> String {
    var result = ""
    var index = text.startIndex

    while index < text.endIndex {
      if text[index] == "&", let semicolon = text[index...].firstIndex(of: ";") {
        let entity = String(text[text.index(after: index)..<semicolon])
        if let decoded = decodeEntity(entity) {
          result.append(decoded)
          index = text.index(after: semicolon)
          continue
        }
      }

      result.append(text[index])
      index = text.index(after: index)
    }

    return result
  }

  private func decodeEntity(_ entity: String) -> String? {
    switch entity {
    case "amp":
      return "&"
    case "lt":
      return "<"
    case "gt":
      return ">"
    case "quot":
      return "\""
    case "apos", "#39":
      return "'"
    case "nbsp":
      return " "
    default:
      if entity.hasPrefix("#x"),
        let scalarValue = UInt32(entity.dropFirst(2), radix: 16),
        let scalar = UnicodeScalar(scalarValue)
      {
        return String(scalar)
      }
      if entity.hasPrefix("#"),
        let scalarValue = UInt32(entity.dropFirst(), radix: 10),
        let scalar = UnicodeScalar(scalarValue)
      {
        return String(scalar)
      }
      return nil
    }
  }

  private func firstMatch(in text: String, pattern: String) -> String? {
    matches(in: text, pattern: pattern).first?.first
  }

  private func matches(in text: String, pattern: String) -> [[String]] {
    guard let regex = try? NSRegularExpression(
      pattern: pattern,
      options: [.dotMatchesLineSeparators, .caseInsensitive]
    ) else {
      return []
    }

    let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
    return regex.matches(in: text, range: nsRange).map { result in
      (1..<result.numberOfRanges).compactMap { index in
        guard let range = Range(result.range(at: index), in: text) else { return nil }
        return String(text[range])
      }
    }
  }
}

private extension String {
  func singleSpaced() -> String {
    components(separatedBy: .whitespacesAndNewlines)
      .filter { !$0.isEmpty }
      .joined(separator: " ")
  }
}
