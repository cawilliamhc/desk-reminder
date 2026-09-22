import Foundation

/// What the coach says. Every line exists in three tones; playful is the
/// default. Lines rotate so the same nudge doesn't wear out its welcome.
public enum CoachMessage: Equatable, Sendable {
    case noteWindow                      // a session just ended
    case stillSitting                    // 5 minutes later, still down
    case goalReached(percent: Int)
    case newStreak(days: Int, best: Int)
    case endOfDay(percent: Int, notesStanding: Int, notesTotal: Int)
    /// After the last session: tomorrow, in a sentence, with an offer to shape it.
    case planTomorrow(sessions: Int, virtual: Int)
    /// A planned intermission's time has come.
    case intermissionDue(name: String, minutes: Int, shortened: Bool)
}

public struct CoachCopy: Sendable {
    public var tone: Tone
    /// Rotates the variants. Injected so tests are deterministic.
    private var pick: @Sendable ([String]) -> String

    public init(tone: Tone, pick: (@Sendable ([String]) -> String)? = nil) {
        self.tone = tone
        self.pick = pick ?? { $0.randomElement() ?? "" }
    }

    public func text(for message: CoachMessage) -> String {
        switch message {
        case .noteWindow:
            return switch tone {
            case .dry: "Session ended. Raise the desk for the note."
            case .warm: "Session's over — raise the desk to write your note."
            case .playful: pick([
                "Session's over. The note is a standing ovation kind of note.",
                "Up you get — this note reads better from four feet.",
                "Desk's been down a while. Give the note the standing treatment.",
                "One session down. Raise the desk and write it on your feet.",
            ])
            }
        case .stillSitting:
            return switch tone {
            case .dry: "Still seated. The note window closes soon."
            case .warm: "Still sitting — raise the desk before you start the note?"
            case .playful: pick([
                "Still down there. The desk is right here, waiting, gathering dust.",
                "Five minutes on. Your chair is winning.",
                "The note isn't going to write itself, and neither is the desk going up.",
            ])
            }
        case .goalReached(let percent):
            return switch tone {
            case .dry: "Standing goal met: \(percent)% of desk time."
            case .warm: "\(percent)% standing — that's the goal for today."
            case .playful: pick([
                "\(percent)% and the goal's done. Anything from here is showing off.",
                "Goal cleared at \(percent)%. The rest of the day is victory laps.",
                "\(percent)%. You may now sit smugly.",
            ])
            }
        case .newStreak(let days, let best):
            let tail = days >= best ? "That's a new best." : "Your best is \(best)."
            return switch tone {
            case .dry: "\(days) days over goal. \(tail)"
            case .warm: "\(days) days over the line in a row. \(tail)"
            case .playful: "\(days) days over the line. \(tail) Tomorrow decides it."
            }
        case .intermissionDue(let name, let minutes, let shortened):
            let lower = name.lowercased()
            if shortened {
                return switch tone {
                case .dry: "\(name): \(minutes) min, shorter than usual. The day is full."
                case .warm: "Only \(minutes) minutes for \(lower) today — take them."
                case .playful: pick([
                    "\(minutes) minutes of \(lower) is what today can spare. Better than none.",
                    "A short \(lower): \(minutes) minutes. The day drove a hard bargain.",
                ])
                }
            }
            return switch tone {
            case .dry: "\(name): \(minutes) min, starting now."
            case .warm: "\(name) now — \(minutes) minutes to yourself."
            case .playful: pick([
                "\(name), \(minutes) minutes, starting now. The desk will hold.",
                "That's \(lower) o'clock. \(minutes) minutes, and the screen can wait.",
            ])
            }
        case .planTomorrow(let sessions, let virtual):
            let count = switch sessions {
            case 0: "Nothing booked tomorrow"
            case 1: "One session tomorrow"
            default: "\(sessions) sessions tomorrow"
            }
            let seated = virtual > 0 ? ", \(virtual) of them seated" : ""
            return switch tone {
            case .dry: "\(count)\(seated). Plan it?"
            case .warm: "\(count)\(seated). Want to shape tomorrow before you go?"
            case .playful: pick([
                "\(count)\(seated). Shall we find the gaps before they find you?",
                "That's today done. \(count)\(seated) — worth two minutes now?",
                "\(count)\(seated). Tomorrow goes better when it's been thought about once.",
            ])
            }
        case .endOfDay(let percent, let standing, let total):
            return switch tone {
            case .dry: "Day done: \(percent)% standing, \(standing)/\(total) notes standing."
            case .warm: "Up \(percent)% of desk time, \(standing) of \(total) notes standing. Nice day."
            case .playful: pick([
                "Up \(percent)% of desk time, \(standing) of \(total) notes on your feet. Desk rests now.",
                "That's the day: \(percent)% up, \(standing) of \(total) notes standing. Chair wins the night.",
            ])
            }
        }
    }
}
