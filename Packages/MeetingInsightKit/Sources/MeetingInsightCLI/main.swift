import Darwin
import Foundation
import MeetingInsightOrchestration

private let help = """
Meeting Insight

USAGE: meeting-insight <command>

COMMANDS:
  help        Show this help message

OPTIONS:
  -h, --help  Show this help message
"""

let arguments = CommandLine.arguments.dropFirst()
guard arguments.isEmpty || arguments.first == "help" || arguments.first == "--help" || arguments.first == "-h" else {
    FileHandle.standardError.write(Data("Unknown command: \(arguments.first!)\n".utf8))
    FileHandle.standardError.write(Data(help.utf8))
    exit(64)
}

print(help)
