import Foundation
import SwiftUI

class AppLogger {
    static let shared = AppLogger()
    
    var isEnabled: Bool {
        return UserDefaults.standard.bool(forKey: "enableDebugLogging")
    }
    
    private var logFileURL: URL?
    private let queue = DispatchQueue(label: "com.simplepdf.logger")
    
    init() {
        // Log file is created lazily when first needed
    }
    
    private func setupLogFile() {
        guard isEnabled else { return }
        
        let fileManager = FileManager.default
        if let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let logDir = appSupport.appendingPathComponent("SindriPDF/Logs")
            do {
                try fileManager.createDirectory(at: logDir, withIntermediateDirectories: true)
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
                let fileName = "debug_\(dateFormatter.string(from: Date())).log"
                logFileURL = logDir.appendingPathComponent(fileName)
                
                // Create file if it doesn't exist
                if let url = logFileURL, !fileManager.fileExists(atPath: url.path) {
                    fileManager.createFile(atPath: url.path, contents: nil)
                }
            } catch {
                print("Failed to create log directory: \(error)")
            }
        }
    }
    
    func log(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        guard isEnabled else { return }
        
        if logFileURL == nil {
            setupLogFile()
        }
        
        let fileName = (file as NSString).lastPathComponent
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let logMessage = "[\(timestamp)] [\(fileName):\(line) \(function)] \(message)\n"
        
        print(logMessage, terminator: "")
        
        queue.async { [weak self] in
            guard let self = self, let logURL = self.logFileURL else { return }
            do {
                let handle = try FileHandle(forWritingTo: logURL)
                handle.seekToEndOfFile()
                if let data = logMessage.data(using: .utf8) {
                    handle.write(data)
                }
                handle.closeFile()
            } catch {
                print("Failed to write to log file: \(error)")
            }
        }
    }
    
    func openLogFolder() {
        let fileManager = FileManager.default
        if let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let logDir = appSupport.appendingPathComponent("SindriPDF/Logs")
            NSWorkspace.shared.open(logDir)
        }
    }
}

public func DLog(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
    AppLogger.shared.log(message, file: file, function: function, line: line)
}
