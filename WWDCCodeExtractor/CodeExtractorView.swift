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


import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct CodeExtractorView: View {
  @State private var viewModel = CodeExtractorViewModel()
  @FocusState private var isURLFieldFocused: Bool

  var body: some View {
    VStack(spacing: 0) {
      VStack(alignment: .leading, spacing: 14) {
        Text("WWDC Code Extractor")
          .font(.title2)
          .fontWeight(.semibold)

        HStack(spacing: 8) {
          TextField("https://developer.apple.com/videos/play/wwdc2025/245", text: $viewModel.videoURLString)
            .textFieldStyle(.roundedBorder)
            .focused($isURLFieldFocused)
            .onSubmit {
              Task { await viewModel.generateMarkdown() }
            }

          Button {
            Task { await viewModel.generateMarkdown() }
          } label: {
            if viewModel.isGenerating {
              ProgressView()
                .controlSize(.small)
                .frame(width: 18, height: 18)
            } else {
              Label("Generate", systemImage: "doc.text.magnifyingglass")
            }
          }
          .disabled(viewModel.isGenerating || viewModel.videoURLString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
          .keyboardShortcut(.return, modifiers: .command)
        }

        HStack {
          if let statusMessage = viewModel.statusMessage {
            Label(statusMessage, systemImage: viewModel.statusSymbolName)
              .foregroundStyle(viewModel.statusForegroundStyle)
              .lineLimit(2)
          } else {
            Text("Paste an Apple Developer video URL that has a Code tab.")
              .foregroundStyle(.secondary)
          }

          Spacer()

          if let snippetCount = viewModel.snippetCount {
            Text("\(snippetCount) snippets")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
        .font(.callout)
      }
      .padding(20)

      Divider()

      TextEditor(text: $viewModel.markdown)
        .font(.system(.body, design: .monospaced))
        .scrollContentBackground(.hidden)
        .background(Color(nsColor: .textBackgroundColor))
        .disabled(viewModel.markdown.isEmpty)

      Divider()

      HStack {
        Button {
          viewModel.copyMarkdown()
        } label: {
          Label("Copy", systemImage: "doc.on.doc")
        }
        .disabled(viewModel.markdown.isEmpty)

        Button {
          viewModel.saveMarkdown()
        } label: {
          Label("Save Markdown...", systemImage: "square.and.arrow.down")
        }
        .disabled(viewModel.markdown.isEmpty)

        Button {
          viewModel.clear()
          isURLFieldFocused = true
        } label: {
          Label("Clear", systemImage: "xmark.circle")
        }
        .disabled(viewModel.isGenerating || !viewModel.canClear)
        .keyboardShortcut("k", modifiers: .command)

        Spacer()

        if viewModel.isGenerating {
          Text("Fetching Apple Developer page...")
            .foregroundStyle(.secondary)
        } else if let suggestedFilename = viewModel.suggestedFilename, !viewModel.markdown.isEmpty {
          Text(suggestedFilename)
            .foregroundStyle(.secondary)
        }
      }
      .font(.callout)
      .padding(12)
    }
    .task {
      isURLFieldFocused = true
    }
  }
}

@Observable
@MainActor
final class CodeExtractorViewModel {
  var videoURLString = ""
  var markdown = ""
  var isGenerating = false
  var statusMessage: String?
  var statusKind = StatusKind.idle
  var snippetCount: Int?
  var suggestedFilename: String?

  private let extractor = CodeTabExtractor()

  var canClear: Bool {
    !videoURLString.isEmpty
      || !markdown.isEmpty
      || statusMessage != nil
      || snippetCount != nil
      || suggestedFilename != nil
  }

  var statusSymbolName: String {
    switch statusKind {
    case .idle:
      "info.circle"
    case .success:
      "checkmark.circle"
    case .failure:
      "exclamationmark.triangle"
    }
  }

  var statusForegroundStyle: AnyShapeStyle {
    switch statusKind {
    case .idle:
      AnyShapeStyle(.secondary)
    case .success:
      AnyShapeStyle(.green)
    case .failure:
      AnyShapeStyle(.red)
    }
  }

  func generateMarkdown() async {
    let trimmedURLString = videoURLString.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedURLString.isEmpty else { return }

    isGenerating = true
    statusKind = .idle
    statusMessage = "Fetching Code tab..."
    snippetCount = nil

    do {
      let result = try await extractor.extractMarkdown(from: trimmedURLString)
      markdown = result.markdown
      snippetCount = result.snippetCount
      suggestedFilename = result.suggestedFilename
      statusKind = .success
      statusMessage = "Markdown generated."
    } catch {
      statusKind = .failure
      statusMessage = error.localizedDescription
    }

    isGenerating = false
  }

  func clear() {
    videoURLString = ""
    markdown = ""
    isGenerating = false
    statusMessage = nil
    statusKind = .idle
    snippetCount = nil
    suggestedFilename = nil
  }

  func copyMarkdown() {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(markdown, forType: .string)
    statusKind = .success
    statusMessage = "Markdown copied."
  }

  func saveMarkdown() {
    let savePanel = NSSavePanel()
    savePanel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
    savePanel.canCreateDirectories = true
    savePanel.nameFieldStringValue = suggestedFilename ?? "WWDC-Code.md"

    guard savePanel.runModal() == .OK, let url = savePanel.url else { return }

    do {
      try markdown.write(to: url, atomically: true, encoding: .utf8)
      statusKind = .success
      statusMessage = "Saved \(url.lastPathComponent)."
    } catch {
      statusKind = .failure
      statusMessage = error.localizedDescription
    }
  }
}

enum StatusKind {
  case idle
  case success
  case failure
}
