import Foundation
import GlobalPetAgentBridgeCore

let stdinData = FileHandle.standardInput.readDataToEndOfFile()
let exitCode = GlobalPetAgentBridge.run(
    arguments: Array(CommandLine.arguments.dropFirst()),
    stdinData: stdinData
)
exit(exitCode)
