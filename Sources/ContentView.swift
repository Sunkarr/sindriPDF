import SwiftUI
import PDFKit
import UniformTypeIdentifiers

// Global target class to redirect AppKit button actions to NotificationCenter
@objc class TabBarButtonTarget: NSObject {
    static let shared = TabBarButtonTarget()
    static var isSorting = false
    @objc func sortTabs() {
        NotificationCenter.default.post(name: Notification.Name("SortTabsAlphabetically"), object: nil)
    }
}

struct WindowAccessor: NSViewRepresentable {
    var shouldClose: Bool
    var onWindowFound: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                onWindowFound(window)
                if shouldClose {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        window.close()
                    }
                }
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            if let window = nsView.window {
                onWindowFound(window)
                if shouldClose {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        window.close()
                    }
                }
            }
        }
    }
}

// Brand logo view displaying "simple" on top and "PDF" on bottom
struct BrandLogoView: View {
    let size: CGFloat
    
    var body: some View {
        ZStack {
            // Squircle background with a beautiful red gradient
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.95, green: 0.15, blue: 0.15), Color(red: 0.78, green: 0.05, blue: 0.05)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: size, height: size)
                .shadow(color: Color.black.opacity(0.18), radius: size * 0.04, y: size * 0.02)
            
            // Centered stacked lettering matching the redesigned App Icon
            VStack(spacing: size * 0.015) {
                Text("simple")
                    .font(.system(size: size * 0.115, weight: .medium, design: .default))
                    .foregroundColor(.white.opacity(0.9))
                Text("PDF")
                    .font(.system(size: size * 0.22, weight: .black, design: .default))
                    .foregroundColor(.white)
            }
        }
        .frame(width: size, height: size)
    }
}

struct ContentView: View {
    @State var fileURL: URL?
    @State private var currentWindow: NSWindow? = nil
    @State private var registeredURL: URL? = nil
    @State private var shouldCloseWindow = false
    
    // Timer to track tab bar button positions
    @State private var tabCheckTimer: Timer? = nil
    
    // Environment action to programmatically open new windows (tabs)
    @Environment(\.openWindow) private var openWindow
    
    // Sidebar visibility state
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    
    // Search overlay state
    @State private var isSearchPresented = false
    
    // Jump to page overlay state
    @State private var isJumpToPagePresented = false
    
    // Metadata Inspector state
    @State private var isInspectorPresented = false
    
    // Active loaded PDFDocument
    @State private var pdfDocument: PDFDocument? = nil
    
    // Drag-and-drop state
    @State private var isDraggingOver = false
    
    // Document and PDF View states
    @State private var currentPage: Int = 1
    @State private var totalPages: Int = 0
    @State private var scaleFactor: Double = 1.0
    @State private var autoScales: Bool = true
    @State private var displayMode: PDFDisplayMode = .singlePageContinuous
    
    @AppStorage("shortcut_zoomFit") private var zoomFitShortcutData: Data?
    
    private var zoomFitShortcut: ShortcutConfig {
        ShortcutManager.getShortcut(forKey: "shortcut_zoomFit", defaultShortcut: ShortcutManager.defaultZoomFit)
    }
    
    // Shared CustomPDFView for this document window
    @State private var sharedPDFView = CustomPDFView()
    
    var body: some View {
        Group {
            if let doc = pdfDocument {
                NavigationSplitView(columnVisibility: $columnVisibility) {
                    SidebarView(
                        document: doc,
                        pdfView: sharedPDFView,
                        currentPage: $currentPage
                    )
                } detail: {
                    ZStack {
                        VStack(spacing: 0) {
                            // PDF Kit View
                            PDFViewRepresentable(
                                document: doc,
                                pdfView: sharedPDFView,
                                currentPage: $currentPage,
                                totalPages: $totalPages,
                                scaleFactor: $scaleFactor,
                                autoScales: $autoScales,
                                displayMode: $displayMode
                            )
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color(NSColor.underPageBackgroundColor))
                            
                            // Bottom Status Bar
                            StatusBarView(
                                document: doc,
                                pdfView: sharedPDFView,
                                currentPage: $currentPage,
                                totalPages: $totalPages,
                                scaleFactor: $scaleFactor,
                                autoScales: $autoScales
                            )
                        }
                        
                        // Search HUD overlay
                        if isSearchPresented {
                            VStack {
                                HStack {
                                    Spacer()
                                    SearchOverlayView(
                                        pdfView: sharedPDFView,
                                        isPresented: $isSearchPresented
                                    )
                                    .padding()
                                }
                                Spacer()
                            }
                        }
                        
                        // Jump to Page HUD overlay
                        if isJumpToPagePresented {
                            VStack {
                                Spacer()
                                PageJumpOverlayView(
                                    pdfView: sharedPDFView,
                                    isPresented: $isJumpToPagePresented,
                                    currentPage: $currentPage,
                                    totalPages: totalPages
                                )
                                .padding()
                                Spacer()
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .toolbar {
                    ToolbarItemGroup(placement: .primaryAction) {
                        // Portrait vs Spread display modes
                        Picker("Page Layout", selection: $displayMode) {
                            Label("Single Page", systemImage: "doc").tag(PDFDisplayMode.singlePageContinuous)
                            Label("Two Pages", systemImage: "book").tag(PDFDisplayMode.twoUpContinuous)
                        }
                        .pickerStyle(.segmented)
                        .help("Switch between Portrait layout and Side-by-side spread")
                        
                        // Toggle Search
                        Button(action: { isSearchPresented.toggle() }) {
                            Image(systemName: "magnifyingglass")
                        }
                        .help("Find Text (Cmd + F)")
                        
                        // Show metadata details
                        Button(action: { isInspectorPresented.toggle() }) {
                            Image(systemName: "info.circle")
                        }
                        .keyboardShortcut("i", modifiers: .command)
                        .help("Document Metadata Inspector (Cmd + I)")
                    }
                }
                .sheet(isPresented: $isInspectorPresented) {
                    InspectorView(
                        document: doc,
                        fileURL: fileURL,
                        isPresented: $isInspectorPresented
                    )
                }
            } else {
                landingPageView
            }
        }
        .navigationTitle(fileURL?.lastPathComponent ?? "SimplePDF")
        .onAppear {
            loadPDF()
            restoreSavedSessionIfFirstWindow()
            
            // Set up a periodic timer to find the new tab button and place the sort button next to it
            tabCheckTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
                setupTabBarButtons()
            }
            
            // Register Apple Event handler for subsequent document opens
            if !AppleEventsHandler.hasRegistered {
                AppleEventsHandler.hasRegistered = true
                NSAppleEventManager.shared().setEventHandler(
                    AppleEventsHandler.shared,
                    andSelector: #selector(AppleEventsHandler.handleOpenDocsEvent(_:withReplyEvent:)),
                    forEventClass: AEEventClass(kCoreEventClass),
                    andEventID: AEEventID(kAEOpenDocuments)
                )
            }
        }
        .onDisappear {
            tabCheckTimer?.invalidate()
            tabCheckTimer = nil
            if let url = registeredURL {
                OpenDocumentsRegistry.shared.unregister(url: url)
            }
        }
        .onChange(of: fileURL) { _, _ in
            loadPDF()
        }
        .onOpenURL { url in
            if focusWindow(showing: url) {
                if let window = currentWindow {
                    window.close()
                } else {
                    self.shouldCloseWindow = true
                }
                return
            }
            if fileURL == nil {
                fileURL = url
                loadPDF()
            } else {
                openWindow(value: url)
            }
        }
        // Handle PDF opening requests from the native tab bar '+' button
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("OpenPDFAsTab"))) { notification in
            guard currentWindow?.isKeyWindow == true else { return }
            if let url = notification.object as? URL {
                if focusWindow(showing: url) {
                    return
                }
                if fileURL == nil {
                    self.fileURL = url
                    self.loadPDF()
                } else {
                    openWindow(value: url)
                }
            }
        }
        // Handle middle-click close on the last tab → return to landing page
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ReturnToLandingPage"))) { notification in
            guard let closingWindow = notification.object as? NSWindow,
                  closingWindow == currentWindow else { return }
            self.pdfDocument = nil
            self.fileURL = nil
            self.currentPage = 1
            self.totalPages = 0
            self.scaleFactor = 1.0
            self.autoScales = true
            self.isSearchPresented = false
            saveOpenDocuments()
        }
        // Handle Sort Tabs request from the AppKit button next to plus (not yet implemented)
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("SortTabsAlphabetically"))) { _ in
            // TODO: Implement tab sorting
        }
        // Expose search trigger to global command menu
        .focusedSceneValue(\.searchAction, {
            isSearchPresented.toggle()
        })
        // Expose jump to page trigger to global command menu (Cmd+P)
        .focusedSceneValue(\.jumpToPageAction, {
            if pdfDocument != nil {
                isJumpToPagePresented.toggle()
            }
        })
        // Expose custom close trigger to global command menu (Cmd+W)
        .focusedSceneValue(\.closeAction, {
            closeCurrentDocument()
        })
        // Expose open-as-tab trigger (Cmd+O)
        .focusedSceneValue(\.openTabAction, {
            openNewPDF()
        })
        // Expose open-in-new-window trigger (Cmd+N)
        .focusedSceneValue(\.openWindowAction, {
            openNewPDFInNewWindow()
        })
        .background(
            Button("") {
                autoScales.toggle()
            }
            .keyboardShortcut(zoomFitShortcut.swiftUIKeyEquivalent, modifiers: zoomFitShortcut.swiftUIModifiers)
            .opacity(0)
            .allowsHitTesting(false)
        )
        .background(
            WindowAccessor(shouldClose: shouldCloseWindow) { window in
                self.currentWindow = window
                self.updateRegistry()
                if let url = fileURL {
                    if let existingWindow = OpenDocumentsRegistry.shared.window(showing: url), existingWindow != window {
                        existingWindow.makeKeyAndOrderFront(nil)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            window.close()
                        }
                    }
                }
            }
        )
    }
    
    // Close the current tab, or return to the landing page if it is the last tab
    private func closeCurrentDocument() {
        guard pdfDocument != nil else { return } // Already on landing page
        
        let currentWindow = self.currentWindow ?? NSApp.keyWindow
        
        // Check how many tabs are in the current tab group
        let tabbedWindowCount = currentWindow?.tabGroup?.windows.count ?? 1
        
        if tabbedWindowCount > 1 {
            // Multiple tabs: close this tab's window entirely
            currentWindow?.close()
        } else {
            // Last tab (or only window): return to the landing page
            self.pdfDocument = nil
            self.fileURL = nil
            self.currentPage = 1
            self.totalPages = 0
            self.scaleFactor = 1.0
            self.autoScales = true
            self.isSearchPresented = false
            saveOpenDocuments()
        }
    }
    
    // Sort tabs alphabetically by swapping PDF content between windows.
    // This avoids moving windows between tab positions entirely, which triggers
    // AppKit lifecycle events that cause splits, freezes, and ghost tabs.
    // Instead, every window stays exactly where it is — only the loaded document
    // is changed so that reading left-to-right produces alphabetical order.
    // TODO: Implement tab sorting
    private func sortTabsAlphabetically() {
        // Not yet implemented
    }
    
    // Dynamically inject the sort button next to the native plus button on the AppKit tab bar
    private func setupTabBarButtons() {
        guard let window = currentWindow ?? NSApp.keyWindow else { return }
        
        func findNewTabButton(in view: NSView) -> NSView? {
            let className = String(describing: type(of: view))
            if className.contains("NewTabButton") || className.contains("TabBarNewTabButton") {
                return view
            }
            for subview in view.subviews {
                if let found = findNewTabButton(in: subview) {
                    return found
                }
            }
            return nil
        }
        
        guard let frameView = window.contentView?.superview,
              let newTabButton = findNewTabButton(in: frameView),
              let container = newTabButton.superview else { return }
              
        // Find or create the sort button
        let sortBtn: NSButton
        if let existing = container.subviews.first(where: { $0.identifier?.rawValue == "SimplePDFSortButton" }) as? NSButton {
            sortBtn = existing
        } else {
            sortBtn = NSButton(image: NSImage(systemSymbolName: "arrow.up.arrow.down", accessibilityDescription: "Sort Tabs")!, target: TabBarButtonTarget.shared, action: #selector(TabBarButtonTarget.sortTabs))
            sortBtn.identifier = NSUserInterfaceItemIdentifier("SimplePDFSortButton")
            
            // Match the native look of the newTabButton (bezelStyle rawValue 16 is .inline)
            let asBtn = newTabButton as? NSButton
            sortBtn.bezelStyle = asBtn?.bezelStyle ?? NSButton.BezelStyle(rawValue: 16) ?? .inline
            sortBtn.isBordered = asBtn?.isBordered ?? true
            if let asBtn = asBtn {
                sortBtn.controlSize = asBtn.controlSize
            }
            
            sortBtn.translatesAutoresizingMaskIntoConstraints = false
            if let img = sortBtn.image {
                img.isTemplate = true
            }
            container.addSubview(sortBtn)
        }
        
        // Check if newTabButton has active trailing constraints to container
        let hasTrailingConstraints = container.constraints.contains { c in
            let isFirst = c.firstItem === newTabButton && (c.firstAttribute == .trailing || c.firstAttribute == .right)
            let isSecond = c.secondItem === newTabButton && (c.secondAttribute == .trailing || c.secondAttribute == .right)
            return isFirst || isSecond
        }
        
        // If sortBtn already exists and newTabButton's trailing constraint is already deactivated,
        // we only need to update isHidden and return early.
        if container.subviews.contains(sortBtn) && !hasTrailingConstraints {
            sortBtn.isHidden = newTabButton.isHidden
            return
        }
        
        sortBtn.isHidden = newTabButton.isHidden
        
        // Find and deactivate any trailing constraints on newTabButton so we can place sortBtn to its right
        var trailingConstraints: [NSLayoutConstraint] = []
        for c in container.constraints {
            let isFirst = c.firstItem === newTabButton && (c.firstAttribute == .trailing || c.firstAttribute == .right)
            let isSecond = c.secondItem === newTabButton && (c.secondAttribute == .trailing || c.secondAttribute == .right)
            if isFirst || isSecond {
                trailingConstraints.append(c)
            }
        }
        
        // Remove existing sort button constraints to prevent duplicate/conflicting constraints
        let existingSortConstraints = container.constraints.filter {
            $0.firstItem === sortBtn || $0.secondItem === sortBtn
        }
        
        if !existingSortConstraints.isEmpty {
            container.removeConstraints(existingSortConstraints)
        }
        
        if !trailingConstraints.isEmpty {
            NSLayoutConstraint.deactivate(trailingConstraints)
        }
        
        // Activate new constraints: sortBtn to the right of newTabButton, matching its size, and sortBtn pinned to the trailing edge
        NSLayoutConstraint.activate([
            sortBtn.leadingAnchor.constraint(equalTo: newTabButton.trailingAnchor, constant: 6),
            sortBtn.centerYAnchor.constraint(equalTo: newTabButton.centerYAnchor),
            sortBtn.widthAnchor.constraint(equalTo: newTabButton.widthAnchor),
            sortBtn.heightAnchor.constraint(equalTo: newTabButton.heightAnchor),
            sortBtn.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12)
        ])
    }
    
    // Landing page view
    private var landingPageView: some View {
        VStack(spacing: 25) {
            // App Branding Logo
            BrandLogoView(size: 120)
                .padding(.bottom, 10)
            
            VStack(spacing: 8) {
                Text("Simple PDF")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                
                Text("Crisp, Fast, & Distraction-Free")
                    .font(.title3)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                
                Text("Drag and drop a PDF file here or select one to begin")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Button("Choose PDF...") {
                selectPDFFile()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(
                    isDraggingOver ? Color.accentColor : Color.secondary.opacity(0.2),
                    style: StrokeStyle(lineWidth: 2, dash: [8])
                )
                .background(isDraggingOver ? Color.accentColor.opacity(0.03) : Color.clear)
                .padding(30)
        )
        // Drag and drop registration
        .onDrop(of: [UTType.fileURL], isTargeted: $isDraggingOver) { providers in
            guard let provider = providers.first else { return false }
            
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                
                if url.pathExtension.lowercased() == "pdf" {
                    DispatchQueue.main.async {
                        self.fileURL = url
                        self.loadPDF()
                    }
                }
            }
            return true
        }
    }
    
    // Load PDFDocument from fileURL state
    private func loadPDF() {
        guard let url = fileURL else {
            pdfDocument = nil
            updateRegistry()
            return
        }
        
        if let window = currentWindow {
            if focusWindow(showing: url, excluding: window) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    window.close()
                }
                return
            }
        } else {
            if OpenDocumentsRegistry.shared.window(showing: url) != nil {
                self.shouldCloseWindow = true
                return
            }
        }
        
        if let doc = PDFDocument(url: url) {
            self.pdfDocument = doc
            self.totalPages = doc.pageCount
            self.currentPage = 1
            self.updateRegistry()
        }
    }
    
    // Choose file dialog
    private func selectPDFFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.pdf]
        
        if panel.runModal() == .OK {
            if let url = panel.url {
                if focusWindow(showing: url) {
                    return
                }
                self.fileURL = url
                self.loadPDF()
            }
        }
    }
    
    // Open new PDF as tab (Cmd+O) — loads in current window if empty, else new tab
    private func openNewPDF() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.pdf]
        
        if panel.runModal() == .OK {
            if let url = panel.url {
                if focusWindow(showing: url) {
                    return
                }
                if fileURL == nil {
                    self.fileURL = url
                    self.loadPDF()
                } else {
                    openWindow(value: url)
                }
            }
        }
    }
    
    // Open new PDF in a completely separate window (Cmd+N)
    private func openNewPDFInNewWindow() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.pdf]
        
        if panel.runModal() == .OK {
            if let url = panel.url {
                if focusWindow(showing: url) {
                    return
                }
                // Always open in a new window by temporarily disabling tab merging
                openWindow(value: url)
                // After the window appears, detach it from the tab group
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    if let newWindow = NSApplication.shared.windows.last(where: { $0.isVisible && $0.canBecomeKey }) {
                        newWindow.tabbingMode = .disallowed
                        newWindow.moveTabToNewWindow(nil)
                        newWindow.tabbingMode = .preferred
                        // Ensure tab bar stays visible on the new window
                        if let tabGroup = newWindow.tabGroup, !tabGroup.isTabBarVisible {
                            newWindow.toggleTabBar(nil)
                        }
                    }
                }
            }
        }
    }
    
    // Restore session of PDF documents
    private func restoreSavedSessionIfFirstWindow() {
        guard fileURL == nil else { return }
        
        let shouldRestore = UserDefaults.standard.object(forKey: "RestoreSessionOnLaunch") as? Bool ?? true
        guard shouldRestore else { return }
        
        // Find visible application windows to determine if we are the first window
        let otherWindows = NSApplication.shared.windows.filter {
            $0.isVisible &&
            !$0.className.contains("NSColorPanel") &&
            !$0.className.contains("NSFontPanel") &&
            $0.canBecomeKey
        }
        guard otherWindows.count <= 1 else { return }
        
        if let paths = UserDefaults.standard.stringArray(forKey: "OpenPDFPaths"), !paths.isEmpty {
            // Load the first saved document in the current window
            let firstPath = paths[0]
            let firstURL = URL(fileURLWithPath: firstPath)
            if FileManager.default.fileExists(atPath: firstURL.path) {
                self.fileURL = firstURL
                self.loadPDF()
            }
            
            // Open the remaining documents in new tab windows
            if paths.count > 1 {
                for i in 1..<paths.count {
                    let path = paths[i]
                    let url = URL(fileURLWithPath: path)
                    if FileManager.default.fileExists(atPath: url.path) {
                        openWindow(value: url)
                    }
                }
            }
        }
    }
    
    private func updateRegistry() {
        guard let window = currentWindow else { return }
        
        // Unregister old URL if it changed
        if let oldURL = registeredURL, oldURL != fileURL {
            OpenDocumentsRegistry.shared.unregister(url: oldURL)
            registeredURL = nil
        }
        
        // Register new URL
        if let newURL = fileURL {
            OpenDocumentsRegistry.shared.register(window: window, for: newURL)
            registeredURL = newURL
        }
    }
}
