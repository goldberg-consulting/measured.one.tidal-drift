import Foundation

struct ShellExecutor {
    
    @discardableResult
    static func execute(_ command: String, arguments: [String] = []) -> (output: String, exitCode: Int32) {
        let task = Process()
        let pipe = Pipe()
        
        task.standardOutput = pipe
        task.standardError = pipe
        task.executableURL = URL(fileURLWithPath: "/bin/zsh")
        task.arguments = ["-c", command]
        
        if !arguments.isEmpty {
            let fullCommand = ([command] + arguments).joined(separator: " ")
            task.arguments = ["-c", fullCommand]
        }
        
        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            return (output: "Failed to execute: \(error.localizedDescription)", exitCode: -1)
        }
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        
        return (output: output.trimmingCharacters(in: .whitespacesAndNewlines), exitCode: task.terminationStatus)
    }
    
    static func executeAsync(_ command: String, completion: @escaping (String, Int32) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let result = execute(command)
            DispatchQueue.main.async {
                completion(result.output, result.exitCode)
            }
        }
    }
    
    static func executeWithSudo(_ command: String, password: String) -> (output: String, exitCode: Int32) {
        let escapedPassword = password.replacingOccurrences(of: "'", with: "'\\''")
        let sudoCommand = "echo '\(escapedPassword)' | sudo -S \(command)"
        return execute(sudoCommand)
    }
    
    static func checkCommandExists(_ command: String) -> Bool {
        let result = execute("which \(command)")
        return result.exitCode == 0 && !result.output.isEmpty
    }
    
    static func getSystemVersion() -> String {
        let result = execute("sw_vers -productVersion")
        return result.output
    }
    
    static func getHostname() -> String {
        let result = execute("hostname")
        return result.output
    }
    
    static func ping(_ host: String, count: Int = 1, timeout: Int = 2) -> Bool {
        let result = execute("ping -c \(count) -t \(timeout) \(host)")
        return result.exitCode == 0
    }
    
    static func openSystemPreference(_ pane: String) {
        execute("open 'x-apple.systempreferences:\(pane)'")
    }
}
