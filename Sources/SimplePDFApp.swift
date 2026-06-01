import SwiftUI
import AppKit
import PDFKit
import UniformTypeIdentifiers

// Define the focused value key for global Cmd+F search routing
struct SearchActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

struct CloseActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

struct OpenTabActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

struct OpenWindowActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

struct JumpToPageActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

extension FocusedValues {
    var searchAction: SearchActionKey.Value? {
        get { self[SearchActionKey.self] }
        set { self[SearchActionKey.self] = newValue }
    }
    
    var closeAction: CloseActionKey.Value? {
        get { self[CloseActionKey.self] }
        set { self[CloseActionKey.self] = newValue }
    }
    
    var openTabAction: OpenTabActionKey.Value? {
        get { self[OpenTabActionKey.self] }
        set { self[OpenTabActionKey.self] = newValue }
    }
    
    var openWindowAction: OpenWindowActionKey.Value? {
        get { self[OpenWindowActionKey.self] }
        set { self[OpenWindowActionKey.self] = newValue }
    }
    
    var jumpToPageAction: JumpToPageActionKey.Value? {
        get { self[JumpToPageActionKey.self] }
        set { self[JumpToPageActionKey.self] = newValue }
    }
}

// Commands definition for global search menu item
struct SearchCommands: Commands {
    @FocusedValue(\.searchAction) var searchAction
    @AppStorage("shortcut_findText") private var findTextData: Data?
    
    var findTextShortcut: ShortcutConfig {
        ShortcutManager.getShortcut(forKey: "shortcut_findText", defaultShortcut: ShortcutManager.defaultFindText)
    }
    
    var body: some Commands {
        CommandGroup(after: .textEditing) {
            Button("Find...") {
                searchAction?()
            }
            .keyboardShortcut(findTextShortcut.swiftUIKeyEquivalent, modifiers: findTextShortcut.swiftUIModifiers)
            .disabled(searchAction == nil)
        }
    }
}

// Commands for File menu: Cmd+O (open as tab) and Cmd+N (open in new window)
struct FileOpenCommands: Commands {
    @FocusedValue(\.openTabAction) var openTabAction
    @FocusedValue(\.openWindowAction) var openWindowAction
    @AppStorage("shortcut_openTab") private var openTabShortcutData: Data?
    @AppStorage("shortcut_openWindow") private var openWindowShortcutData: Data?
    
    var openTabShortcut: ShortcutConfig {
        ShortcutManager.getShortcut(forKey: "shortcut_openTab", defaultShortcut: ShortcutManager.defaultOpenTab)
    }
    
    var openWindowShortcut: ShortcutConfig {
        ShortcutManager.getShortcut(forKey: "shortcut_openWindow", defaultShortcut: ShortcutManager.defaultOpenWindow)
    }
    
    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Open in New Tab...") {
                openTabAction?()
            }
            .keyboardShortcut(openTabShortcut.swiftUIKeyEquivalent, modifiers: openTabShortcut.swiftUIModifiers)
            
            Button("Open in New Window...") {
                openWindowAction?()
            }
            .keyboardShortcut(openWindowShortcut.swiftUIKeyEquivalent, modifiers: openWindowShortcut.swiftUIModifiers)
        }
    }
}

// Commands definition for Close (Cmd+W) routing
struct CloseCommands: Commands {
    @FocusedValue(\.closeAction) var closeAction
    @AppStorage("shortcut_closeDoc") private var closeDocData: Data?
    
    var closeDocShortcut: ShortcutConfig {
        ShortcutManager.getShortcut(forKey: "shortcut_closeDoc", defaultShortcut: ShortcutManager.defaultCloseDoc)
    }
    
    var body: some Commands {
        CommandGroup(replacing: .saveItem) {
            Button("Close Document") {
                if let action = closeAction {
                    action()
                } else {
                    NSApp.keyWindow?.performClose(nil)
                }
            }
            .keyboardShortcut(closeDocShortcut.swiftUIKeyEquivalent, modifiers: closeDocShortcut.swiftUIModifiers)
        }
    }
}

// Commands definition for Go to Page (Cmd+P) replacing Print menu item
struct FileJumpCommands: Commands {
    @FocusedValue(\.jumpToPageAction) var jumpToPageAction
    @AppStorage("shortcut_goToPage") private var goToPageData: Data?
    
    var goToPageShortcut: ShortcutConfig {
        ShortcutManager.getShortcut(forKey: "shortcut_goToPage", defaultShortcut: ShortcutManager.defaultGoToPage)
    }
    
    var body: some Commands {
        CommandGroup(replacing: .printItem) {
            Button("Go to Page...") {
                jumpToPageAction?()
            }
            .keyboardShortcut(goToPageShortcut.swiftUIKeyEquivalent, modifiers: goToPageShortcut.swiftUIModifiers)
            .disabled(jumpToPageAction == nil)
        }
    }
}

// Save the paths of all open PDF documents to restore later
func saveOpenDocuments() {
    let urls = NSApplication.shared.windows.compactMap { window -> String? in
        guard let contentView = window.contentView else { return nil }
        return findPDFView(in: contentView)?.document?.documentURL?.path
    }
    UserDefaults.standard.set(urls, forKey: "OpenPDFPaths")
}

// Helper to recursively find CustomPDFView in view hierarchy
func findPDFView(in view: NSView) -> CustomPDFView? {
    if let pdfView = view as? CustomPDFView {
        return pdfView
    }
    for subview in view.subviews {
        if let found = findPDFView(in: subview) {
            return found
        }
    }
    return nil
}

// Focus window displaying a specific PDF file and return true, or return false if not found
func focusWindow(showing url: URL, excluding currentWindow: NSWindow? = nil) -> Bool {
    let targetPath = url.standardized.path
    for window in NSApplication.shared.windows {
        guard window != currentWindow && window.isVisible && window.canBecomeKey && !window.className.contains("Panel") else { continue }
        if let contentView = window.contentView,
           let pdfView = findPDFView(in: contentView),
           let docURL = pdfView.document?.documentURL {
            if docURL.standardized.path.localizedCaseInsensitiveCompare(targetPath) == .orderedSame {
                window.makeKeyAndOrderFront(nil)
                return true
            }
        }
    }
    return false
}

// Restore previously open PDF documents (posts notifications handled by ContentView)
func restoreOpenDocuments() {
    guard let paths = UserDefaults.standard.stringArray(forKey: "OpenPDFPaths"), !paths.isEmpty else { return }
    for path in paths {
        let url = URL(fileURLWithPath: path)
        if FileManager.default.fileExists(atPath: url.path) {
            NotificationCenter.default.post(name: Notification.Name("OpenPDFAsTab"), object: url)
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    static var launchURL: URL?
    
    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        for filename in filenames {
            let url = URL(fileURLWithPath: filename)
            handleOpenURL(url)
        }
        sender.reply(toOpenOrPrint: .success)
    }
    
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            handleOpenURL(url)
        }
    }
    
    private func handleOpenURL(_ url: URL) {
        if focusWindow(showing: url) {
            return
        }
        
        let activeWindows = NSApplication.shared.windows.filter {
            $0.isVisible && !$0.className.contains("Panel") && $0.canBecomeKey
        }
        
        if activeWindows.isEmpty {
            AppDelegate.launchURL = url
        } else {
            NotificationCenter.default.post(name: Notification.Name("OpenPDFAsTab"), object: url)
        }
    }
}

@main
struct SimplePDFApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var initialURL: URL? = nil
    
    init() {
        let currentApp = NSRunningApplication.current
        let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.jonas.SimplePDF")
            .filter { $0 != currentApp }
        
        if !runningApps.isEmpty {
            // Activate the existing running instance
            runningApps.first?.activate(options: [])
            
            // Forward command line PDF arguments to the running instance
            if CommandLine.arguments.count > 1 {
                let possiblePath = CommandLine.arguments[1]
                if !possiblePath.hasPrefix("-") {
                    let url = URL(fileURLWithPath: possiblePath)
                    NSWorkspace.shared.open([url], withApplicationAt: runningApps.first!.bundleURL!, configuration: NSWorkspace.OpenConfiguration()) { _, _ in
                        exit(0)
                    }
                } else {
                    exit(0)
                }
            } else {
                exit(0)
            }
        }
        
        // Parse initial URL from argument if available
        if CommandLine.arguments.count > 1 {
            let possiblePath = CommandLine.arguments[1]
            if !possiblePath.hasPrefix("-") {
                let url = URL(fileURLWithPath: possiblePath)
                if FileManager.default.fileExists(atPath: url.path) {
                    self._initialURL = State(initialValue: url)
                }
            }
        }
    }
    
    var body: some Scene {
        // Main window (shows landing page by default, or initial URL)
        WindowGroup {
            ContentView(fileURL: AppDelegate.launchURL ?? initialURL)
                .frame(minWidth: 800, minHeight: 600)
        }
        
        // Window group for opening subsequent files as tabs
        WindowGroup(for: URL.self) { $url in
            ContentView(fileURL: url)
                .frame(minWidth: 800, minHeight: 600)
        }
        .commands {
            SidebarCommands()
            FileOpenCommands()
            SearchCommands()
            CloseCommands()
            FileJumpCommands()
        }
        
        Settings {
            SettingsView()
        }
    }
}

// Map the native macOS tab bar plus (+) button action to a custom file picker
extension NSWindow {
    @objc open override func newWindowForTab(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [UTType.pdf]
        
        if panel.runModal() == .OK, let url = panel.url {
            NotificationCenter.default.post(name: Notification.Name("OpenPDFAsTab"), object: url)
        }
    }
}
