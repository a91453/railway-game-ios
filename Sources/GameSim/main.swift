import Foundation
import GamePresentation

// Decision 260: the game with no screen, from the command line. Everything
// it does is GamePresentation's `HeadlessCommandLine`; this only reaches
// the disk and the terminal. `swift run GameSim --help` lists what it does.

let arguments = Array(CommandLine.arguments.dropFirst())
if arguments.isEmpty || arguments == ["--help"] || arguments == ["help"] {
    print(HeadlessCommandLine.usage)
    exit(arguments.isEmpty ? 2 : 0)
}
let commandLine: HeadlessCommandLine
do {
    commandLine = try HeadlessCommandLine(arguments: arguments)
} catch {
    FileHandle.standardError.write(Data("\(error)\n".utf8))
    exit(2)
}
let ran = commandLine.run(
    print: { print($0) },
    read: { try Data(contentsOf: URL(fileURLWithPath: $0)) },
    write: { try $1.write(to: URL(fileURLWithPath: $0)) }
)
exit(ran ? 0 : 1)
