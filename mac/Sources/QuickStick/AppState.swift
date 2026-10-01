import Foundation
import SwiftUI

enum SaveStatus { case idle, saving, saved, error }

@MainActor
final class AppState: ObservableObject {
    /// Always 12 cells. Showing 6 hides the last 6, it never drops them.
    @Published var stickies: [Sticky] = Palette.blank() {
        didSet { persist() }
    }
    @Published var count: Int = 9 { didSet { persist() } }
    @Published var status: SaveStatus = .idle
    @Published var message = ""
    @Published var settingsOpen = false

    private let api = APIClient()
    private var loaded = false
    private var saveTask: Task<Void, Never>?
    private var listenTask: Task<Void, Never>?
    private var syncing = false
    /// Edits not yet written to the table.
    private var dirty = false
    /// Set while the table's copy is being applied, so it is not written back.
    private var applyingRemote = false

    /// Content sitting in cells that are currently out of view.
    var hidden: Int {
        stickies.dropFirst(count).filter { !$0.isEmpty }.count
    }

    // MARK: - Draft on disk

    private let draftURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("QuickStick", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("draft.json")
    }()

    private struct Draft: Codable { var count: Int; var stickies: [Sticky] }

    /// Written on every keystroke. A debounce here only buys a window in which
    /// a crash loses what was typed.
    private func persist() {
        guard loaded else { return }
        let draft = Draft(count: count, stickies: stickies)
        guard let data = try? JSONEncoder().encode(draft) else { return }
        try? data.write(to: draftURL, options: .atomic)
        scheduleSync()
    }

    /// Opens on the last draft, then takes whatever the web app wrote since.
    func load() {
        if let data = try? Data(contentsOf: draftURL),
           let draft = try? JSONDecoder().decode(Draft.self, from: data),
           !draft.stickies.isEmpty {
            count = draft.count
            stickies = pad(draft.stickies).map { var s = $0; s.content = CellTextView.normalizeDone(s.content); return s }
        }
        loaded = true
        Task { await pull() }
        listen()
    }

    /// Stays on the web app's event stream for the life of the app, so a
    /// note typed anywhere else is on this board the moment it is written.
    private func listen() {
        listenTask?.cancel()
        listenTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                try? await self.api.events { event in
                    await self.apply(event)
                }
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private func apply(_ event: BoardEvent) {
        guard event.client != api.client else { return }
        apply(event.cells)
    }

    /// Older drafts were stored trimmed to the visible count. Pad back to 12.
    private func pad(_ saved: [Sticky]) -> [Sticky] {
        Palette.blank().enumerated().map { i, blank in
            i < saved.count ? saved[i] : blank
        }
    }

    // MARK: - Autosave

    /// Settle for a beat before writing, so a burst of typing is one request.
    private func scheduleSync() {
        guard !applyingRemote else { return }
        dirty = true
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            await self?.sync()
        }
    }

    /// Nothing to press. A board that stops changing is written to the web
    /// app's table, all 12 slots at once, the same way the web page saves.
    func sync() async {
        guard dirty, !syncing else { return }
        syncing = true
        status = .saving
        defer { syncing = false }

        // A keystroke that lands while a write is in flight is picked up by
        // the next turn of the loop, so nothing typed waits for another one.
        while dirty {
            let cells = stickies.enumerated().map {
                BoardCell(slot: $0.offset, title: $0.element.title, content: $0.element.content, color: $0.element.color)
            }
            dirty = false
            do {
                try await api.put(cells)
                status = .saved
                message = ""
            } catch {
                dirty = true
                status = .error
                message = error.localizedDescription
                return
            }
        }
    }

    // MARK: - Pulling from the web app

    /// Brings the board in line with the table. Anything typed here and not
    /// yet written wins: the pull is skipped until that write has landed.
    func pull() async {
        guard !dirty, !syncing else { return }
        do {
            let cells = try await api.board()
            // A bare table takes what is here rather than the other way round,
            // so the first launch against it never wipes the board.
            if cells.allSatisfy({ $0.title.trimmed.isEmpty && $0.content.trimmed.isEmpty }) {
                if !stickies.allSatisfy(\.isEmpty) { dirty = true; await sync() }
                return
            }
            apply(cells)
            if status == .error { status = .idle; message = "" }
        } catch {
            status = .error
            message = error.localizedDescription
        }
    }

    /// Takes the table's board, unless something typed here is still unwritten.
    private func apply(_ cells: [BoardCell]) {
        guard !dirty, !syncing else { return }
        var next = Palette.blank()
        for c in cells where next.indices.contains(c.slot) {
            next[c.slot] = Sticky(title: c.title, content: CellTextView.normalizeDone(c.content), color: c.color)
        }
        guard next.map(\.title) != stickies.map(\.title) || next.map(\.content) != stickies.map(\.content) else { return }
        applyingRemote = true
        stickies = next
        applyingRemote = false
    }

    // MARK: - Moving a sticky

    /// Swaps what is written. Each slot keeps its own colour, so moving a note
    /// moves the writing and nothing else.
    func move(from: Int, to: Int) {
        guard from != to, stickies.indices.contains(from), stickies.indices.contains(to) else { return }
        let a = stickies[from], b = stickies[to]
        stickies[from].title = b.title
        stickies[from].content = b.content
        stickies[to].title = a.title
        stickies[to].content = a.content
    }
}
