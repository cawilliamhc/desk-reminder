import DeskCore
import Foundation

/// The desk and computer logs, kept across restarts.
///
/// They were in memory only, so every relaunch started the day's shape from
/// nothing - and the app gets relaunched whenever it's rebuilt.
struct LogStore: Sendable {
    struct Saved: Codable, Sendable {
        var heights = HeightLog()
        var computer = ComputerLog()
    }

    let url: URL

    func load() -> Saved {
        guard let data = try? Data(contentsOf: url),
              let saved = try? JSONDecoder.deskDecoder.decode(Saved.self, from: data)
        else { return Saved() }
        return saved
    }

    func save(heights: HeightLog, computer: ComputerLog) {
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try? JSONEncoder.deskEncoder
            .encode(Saved(heights: heights, computer: computer))
            .write(to: url, options: .atomic)
    }
}
