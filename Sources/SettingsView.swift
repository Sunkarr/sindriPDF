import SwiftUI
import AppKit
import ServiceManagement
import UniformTypeIdentifiers

// Model for saving custom shortcut settings
struct ShortcutConfig: Codable, Equatable {
    var key: String // e.g. "o"
    var modifiers: Int // bitmask of NSEvent.ModifierFlags raw values
    
    var displayString: String {
        var str = ""
        let flags = NSEvent.ModifierFlags(rawValue: UInt(modifiers))
        if flags.contains(.control) { str += "⌃" }
        if flags.contains(.option) { str += "⌥" }
        if flags.contains(.shift) { str += "⇧" }
        if flags.contains(.command) { str += "⌘" }
        str += key.uppercased()
        return str
    }
    
    var swiftUIKeyEquivalent: KeyEquivalent {
        if key.isEmpty { return KeyEquivalent(" ") }
        return KeyEquivalent(Character(key.lowercased()))
    }
    
    var swiftUIModifiers: EventModifiers {
        var mods: EventModifiers = []
        let flags = NSEvent.ModifierFlags(rawValue: UInt(modifiers))
        if flags.contains(.command) { mods.insert(.command) }
        if flags.contains(.option) { mods.insert(.option) }
        if flags.contains(.control) { mods.insert(.control) }
        if flags.contains(.shift) { mods.insert(.shift) }
        return mods
    }
}

// Manager to handle default shortcut bindings
struct ShortcutManager {
    static let defaultOpenTab = ShortcutConfig(key: "o", modifiers: Int(NSEvent.ModifierFlags.command.rawValue))
    static let defaultOpenWindow = ShortcutConfig(key: "n", modifiers: Int(NSEvent.ModifierFlags.command.rawValue))
    static let defaultCloseDoc = ShortcutConfig(key: "w", modifiers: Int(NSEvent.ModifierFlags.command.rawValue))
    static let defaultFindText = ShortcutConfig(key: "f", modifiers: Int(NSEvent.ModifierFlags.command.rawValue))
    static let defaultGoToPage = ShortcutConfig(key: "p", modifiers: Int(NSEvent.ModifierFlags.command.rawValue))
    static let defaultZoomFit = ShortcutConfig(key: "0", modifiers: Int(NSEvent.ModifierFlags.command.rawValue))
    static let defaultInspector = ShortcutConfig(key: "i", modifiers: Int(NSEvent.ModifierFlags.command.rawValue))
    static let defaultPresentation = ShortcutConfig(key: "p", modifiers: Int(NSEvent.ModifierFlags.command.rawValue | NSEvent.ModifierFlags.option.rawValue))
    
    static func getShortcut(forKey key: String, defaultShortcut: ShortcutConfig) -> ShortcutConfig {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode(ShortcutConfig.self, from: data) {
            return decoded
        }
        return defaultShortcut
    }
}

// Manager to register/unregister the app in system login items
struct LoginItemManager {
    static func setLaunchAtLogin(enabled: Bool) {
        let service = SMAppService.mainApp
        do {
            if enabled {
                if service.status != .enabled {
                    try service.register()
                }
            } else {
                if service.status == .enabled {
                    try service.unregister()
                }
            }
        } catch {
            print("SimplePDF: Failed to change login item status: \(error.localizedDescription)")
        }
    }
    
    static var isLaunchAtLoginEnabled: Bool {
        return SMAppService.mainApp.status == .enabled
    }
}

// Interactive button to record a custom shortcut
struct ShortcutRecorder: View {
    let label: String
    let key: String
    let defaultShortcut: ShortcutConfig
    
    @State private var currentShortcut: ShortcutConfig
    @State private var isRecording = false
    @State private var eventMonitor: Any? = nil
    
    init(label: String, key: String, defaultShortcut: ShortcutConfig) {
        self.label = label
        self.key = key
        self.defaultShortcut = defaultShortcut
        
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode(ShortcutConfig.self, from: data) {
            self._currentShortcut = State(initialValue: decoded)
        } else {
            self._currentShortcut = State(initialValue: defaultShortcut)
        }
    }
    
    var body: some View {
        HStack {
            Text(label)
                .font(.body)
            Spacer()
            
            Button(action: {
                if isRecording {
                    stopRecording()
                } else {
                    startRecording()
                }
            }) {
                Text(isRecording ? "Press keys..." : currentShortcut.displayString)
                    .font(.system(.body, design: .monospaced))
                    .fontWeight(.semibold)
                    .foregroundColor(isRecording ? .accentColor : .primary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(isRecording ? Color.accentColor.opacity(0.12) : Color(NSColor.controlBackgroundColor))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(isRecording ? Color.accentColor : Color.gray.opacity(0.2), lineWidth: 1)
                            )
                    )
            }
            .buttonStyle(.plain)
            
            if !isRecording && currentShortcut != defaultShortcut {
                Button(action: resetToDefault) {
                    Image(systemName: "arrow.counterclockwise")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Reset to default")
            }
        }
        .padding(.vertical, 2)
        .onDisappear {
            stopRecording()
        }
    }
    
    private func startRecording() {
        isRecording = true
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Intercept Escape key to cancel
            if event.keyCode == 53 {
                self.stopRecording()
                return nil
            }
            
            let characters = event.charactersIgnoringModifiers ?? ""
            guard let char = characters.first else { return event }
            
            // Require at least one helper modifier to prevent general keyboard conflicts
            let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
            if modifiers.isEmpty {
                return nil
            }
            
            let newShortcut = ShortcutConfig(key: String(char), modifiers: Int(event.modifierFlags.rawValue))
            self.currentShortcut = newShortcut
            
            if let encoded = try? JSONEncoder().encode(newShortcut) {
                UserDefaults.standard.set(encoded, forKey: key)
                // Post notification to trigger updates across commands and views
                NotificationCenter.default.post(name: Notification.Name("ShortcutChanged"), object: key)
            }
            
            self.stopRecording()
            return nil
        }
    }
    
    private func stopRecording() {
        isRecording = false
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }
    
    private func resetToDefault() {
        currentShortcut = defaultShortcut
        UserDefaults.standard.removeObject(forKey: key)
        NotificationCenter.default.post(name: Notification.Name("ShortcutChanged"), object: key)
    }
}

// Main settings preferences panel view
struct SettingsView: View {
    @AppStorage("PageDimensionUnit") private var pageDimensionUnit: String = "mm"
    @AppStorage("RestoreSessionOnLaunch") private var restoreSession: Bool = true
    @State private var launchAtLogin = LoginItemManager.isLaunchAtLoginEnabled
    @State private var isDefaultApp: Bool = false
    
    @AppStorage("presentationShowProgressBar") private var showProgressBar: Bool = true
    @AppStorage("presentationProgressBarPosition") private var progressBarPosition: String = "bottom"
    @AppStorage("presentationProgressBarThickness") private var progressBarThickness: Double = 2.0
    @AppStorage("presentationProgressBarColor") private var progressBarHexColor: String = "#FF0000"
    
    @AppStorage("enableDebugLogging") private var enableDebugLogging: Bool = false
    
    @State private var selectedTab: String = "credits"
    
    private let labelWidth: CGFloat = 110
    
    var body: some View {
        TabView(selection: $selectedTab) {
            // Tab 1: Author Credits & Support info
            VStack(spacing: 20) {
                // Squircle App Icon View
                BrandLogoView(size: 80)
                
                VStack(spacing: 6) {
                    Text("SimplePDF")
                        .font(.title)
                        .fontWeight(.bold)
                    Text("Version 1.0")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Text("A sleek, lightweight PDF viewer for macOS.\nNo bloatware, no popups, and no subscription... ever.")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 30)
                
                Divider().frame(width: 200)
                
                VStack(spacing: 8) {
                    Link(destination: URL(string: "https://github.com/Sunkarr/simple-pdf")!) {
                        HStack {
                            Image(systemName: "link")
                            Text("GitHub Repository")
                        }
                        .fontWeight(.semibold)
                        .foregroundColor(.accentColor)
                    }
                    
                    Link(destination: URL(string: "https://buymeacoffee.com/placeholder")!) {
                        HStack {
                            Image(systemName: "cup.and.saucer.fill")
                            Text("Buy Me a Coffee (Support)")
                        }
                        .fontWeight(.semibold)
                        .foregroundColor(.orange)
                    }
                }
                
                Spacer()
                
                Text("Created with ❤️ by Jonas")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(30)
            .tabItem {
                Label("Credits", systemImage: "info.circle")
            }
            .tag("credits")
            
            // Tab 2: General Preferences
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Section 1: Page Dimensions
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Page Dimensions Display")
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        HStack(spacing: 8) {
                            Text("Display Unit:")
                                .foregroundColor(.secondary)
                                .frame(width: labelWidth, alignment: .trailing)
                            Picker("", selection: $pageDimensionUnit) {
                                Text("Millimeters (mm)").tag("mm")
                                Text("Centimeters (cm)").tag("cm")
                                Text("Inches (in)").tag("inch")
                                Text("Points (pt)").tag("points")
                            }
                            .pickerStyle(.menu)
                            .frame(width: 180)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.4))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.gray.opacity(0.15), lineWidth: 1)
                    )
                    
                    // Section 2: Startup Behavior
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Startup Behavior")
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                Spacer()
                                    .frame(width: labelWidth)
                                Toggle("Open SimplePDF at login", isOn: $launchAtLogin)
                                    .onChange(of: launchAtLogin) { _, newValue in
                                        LoginItemManager.setLaunchAtLogin(enabled: newValue)
                                    }
                            }
                            
                            HStack(spacing: 8) {
                                Spacer()
                                    .frame(width: labelWidth)
                                Toggle("Restore last session on launch", isOn: $restoreSession)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.4))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.gray.opacity(0.15), lineWidth: 1)
                    )
                    
                    // Section 3: System Integration
                    VStack(alignment: .leading, spacing: 12) {
                        Text("System Integration")
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Default PDF Reader")
                                    .foregroundColor(.primary)
                                if isDefaultApp {
                                    Text("SimplePDF is already standard app for PDF")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                } else {
                                    Text("Make SimplePDF your default application for viewing PDFs")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            
                            Spacer()
                            
                            Button("Make Default") {
                                setDefaultApp()
                            }
                            .disabled(isDefaultApp)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.4))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.gray.opacity(0.15), lineWidth: 1)
                    )
                    
                    // Section 4: Presentation Mode
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Presentation Mode")
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 8) {
                                Spacer()
                                    .frame(width: labelWidth)
                                Toggle("Show page progress bar", isOn: $showProgressBar)
                            }
                            
                            if showProgressBar {
                                HStack(spacing: 8) {
                                    Text("Position:")
                                        .foregroundColor(.secondary)
                                        .frame(width: labelWidth, alignment: .trailing)
                                    Picker("", selection: $progressBarPosition) {
                                        Text("Top").tag("top")
                                        Text("Bottom").tag("bottom")
                                    }
                                    .pickerStyle(.menu)
                                    .frame(width: 120)
                                }
                                
                                HStack(spacing: 8) {
                                    Text("Thickness:")
                                        .foregroundColor(.secondary)
                                        .frame(width: labelWidth, alignment: .trailing)
                                    Slider(value: $progressBarThickness, in: 1...10, step: 1)
                                        .labelsHidden()
                                    Text("\(Int(progressBarThickness)) px")
                                        .font(.system(.body, design: .monospaced))
                                        .frame(width: 40, alignment: .trailing)
                                }
                                
                                HStack(spacing: 8) {
                                    Text("Bar Color:")
                                        .foregroundColor(.secondary)
                                        .frame(width: labelWidth, alignment: .trailing)
                                    ColorPicker("", selection: Binding(
                                        get: { Color(hex: progressBarHexColor) },
                                        set: { progressBarHexColor = $0.toHex() }
                                    ))
                                    .labelsHidden()
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.4))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.gray.opacity(0.15), lineWidth: 1)
                    )
                    // Section 5: Debugging
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Debugging")
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 8) {
                                Spacer()
                                    .frame(width: labelWidth)
                                Toggle("Enable Debug Logging", isOn: $enableDebugLogging)
                            }
                            
                            HStack(spacing: 8) {
                                Spacer()
                                    .frame(width: labelWidth)
                                Button("Open Log Folder") {
                                    AppLogger.shared.openLogFolder()
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.4))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.gray.opacity(0.15), lineWidth: 1)
                    )
                }
                .padding(20)
            }
            .tabItem {
                Label("General", systemImage: "gearshape")
            }
            .tag("general")
            
            // Tab 3: Keyboard Shortcuts Config
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Section 1: File & Tabs
                    VStack(alignment: .leading, spacing: 10) {
                        Text("File & Tabs")
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        ShortcutRecorder(label: "Open in New Tab", key: "shortcut_openTab", defaultShortcut: ShortcutManager.defaultOpenTab)
                        Divider()
                        ShortcutRecorder(label: "Open in New Window", key: "shortcut_openWindow", defaultShortcut: ShortcutManager.defaultOpenWindow)
                        Divider()
                        ShortcutRecorder(label: "Close Document", key: "shortcut_closeDoc", defaultShortcut: ShortcutManager.defaultCloseDoc)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.4))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.gray.opacity(0.15), lineWidth: 1)
                    )
                    
                    // Section 2: Navigation & Tools
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Navigation & Tools")
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        ShortcutRecorder(label: "Find in Document", key: "shortcut_findText", defaultShortcut: ShortcutManager.defaultFindText)
                        Divider()
                        ShortcutRecorder(label: "Go to Page", key: "shortcut_goToPage", defaultShortcut: ShortcutManager.defaultGoToPage)
                        Divider()
                        ShortcutRecorder(label: "Zoom to Fit", key: "shortcut_zoomFit", defaultShortcut: ShortcutManager.defaultZoomFit)
                        Divider()
                        ShortcutRecorder(label: "Toggle Metadata Inspector", key: "shortcut_inspector", defaultShortcut: ShortcutManager.defaultInspector)
                        Divider()
                        ShortcutRecorder(label: "Toggle Presentation Mode", key: "shortcut_presentation", defaultShortcut: ShortcutManager.defaultPresentation)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.4))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.gray.opacity(0.15), lineWidth: 1)
                    )
                }
                .padding(20)
            }
            .tabItem {
                Label("Shortcuts", systemImage: "keyboard")
            }
            .tag("shortcuts")
        }
        .onAppear {
            selectedTab = "credits"
            checkDefaultApp()
        }
        .frame(width: 440, height: 420)
    }
    
    private func checkDefaultApp() {
        if let defaultURL = NSWorkspace.shared.urlForApplication(toOpen: .pdf) {
            if let defaultBundleId = Bundle(url: defaultURL)?.bundleIdentifier {
                isDefaultApp = defaultBundleId == Bundle.main.bundleIdentifier
            }
        }
    }
    
    private func setDefaultApp() {
        Task {
            do {
                try await NSWorkspace.shared.setDefaultApplication(at: Bundle.main.bundleURL, toOpen: .pdf)
                await MainActor.run {
                    checkDefaultApp()
                }
            } catch {
                print("SimplePDF: Failed to set default application: \(error)")
            }
        }
    }
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }

    func toHex() -> String {
        guard let components = NSColor(self).usingColorSpace(.deviceRGB) else { return "#FF0000" }
        let r = Int(components.redComponent * 255)
        let g = Int(components.greenComponent * 255)
        let b = Int(components.blueComponent * 255)
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
