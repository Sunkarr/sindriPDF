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

// Payload for swapping a document URL into a specific window during tab sorting
class SwapDocumentPayload: NSObject {
    let assignments: [NSWindow: URL]  // window → new URL mapping for batch swap
    let activeURL: URL?  // URL that was active before sorting — the window receiving this should become key
    init(assignments: [NSWindow: URL], activeURL: URL?) {
        self.assignments = assignments
        self.activeURL = activeURL
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

enum ViewModeSelection: String, CaseIterable, Identifiable {
    case single
    case twoUp
    case presentation
    
    var id: String { self.rawValue }
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
    
    @AppStorage("sidebarWidth") private var sidebarWidth: Double = 250.0
    @AppStorage("shortcut_zoomFit") private var zoomFitShortcutData: Data?
    
    // Presentation Mode states
    @State private var isPresentationMode = false
    @State private var savedDisplayMode: PDFDisplayMode = .singlePageContinuous
    @State private var savedAutoScales = true
    @State private var savedScaleFactor: Double = 1.0
    @State private var savedColumnVisibility: NavigationSplitViewVisibility = .all
    
    @State private var currentPageRect: CGRect = .zero
    
    // Presentation AppStorage customization keys
    @AppStorage("presentationShowProgressBar") private var showProgressBar: Bool = true
    @AppStorage("presentationProgressBarPosition") private var progressBarPosition: String = "bottom"
    @AppStorage("presentationProgressBarThickness") private var progressBarThickness: Double = 2.0
    @AppStorage("presentationProgressBarColor") private var progressBarHexColor: String = "#FF0000"
    
    private var zoomFitShortcut: ShortcutConfig {
        ShortcutManager.getShortcut(forKey: "shortcut_zoomFit", defaultShortcut: ShortcutManager.defaultZoomFit)
    }
    
    private var viewModeSelection: Binding<ViewModeSelection> {
        Binding<ViewModeSelection>(
            get: {
                if isPresentationMode {
                    return .presentation
                } else if displayMode == .twoUpContinuous || displayMode == .twoUp {
                    return .twoUp
                } else {
                    return .single
                }
            },
            set: { newValue in
                switch newValue {
                case .single:
                    if isPresentationMode {
                        exitPresentationMode()
                    }
                    displayMode = .singlePageContinuous
                case .twoUp:
                    if isPresentationMode {
                        exitPresentationMode()
                    }
                    displayMode = .twoUpContinuous
                case .presentation:
                    if !isPresentationMode {
                        enterPresentationMode()
                    }
                }
            }
        )
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
                    .background(
                        GeometryReader { geometry in
                            Color.clear
                                .onChange(of: geometry.size.width) { _, newWidth in
                                    if newWidth >= 150 && abs(sidebarWidth - newWidth) > 0.5 {
                                        sidebarWidth = newWidth
                                    }
                                }
                        }
                    )
                    .navigationSplitViewColumnWidth(min: 150, ideal: sidebarWidth, max: 400)
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
                                displayMode: $displayMode,
                                isPresentationMode: $isPresentationMode,
                                currentPageRect: $currentPageRect
                            )
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color(NSColor.underPageBackgroundColor))
                            
                            // Bottom Status Bar
                            if !isPresentationMode {
                                StatusBarView(
                                    document: doc,
                                    pdfView: sharedPDFView,
                                    currentPage: $currentPage,
                                    totalPages: $totalPages,
                                    scaleFactor: $scaleFactor,
                                    autoScales: $autoScales
                                )
                            }
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
                        
                        // Presentation Progress Bar
                        if isPresentationMode && showProgressBar && currentPageRect != .zero {
                            GeometryReader { geo in
                                let progress = totalPages > 0 ? CGFloat(currentPage) / CGFloat(totalPages) : 0
                                let width = currentPageRect.size.width * progress
                                let xOffset = currentPageRect.origin.x
                                let yOffset = progressBarPosition == "top" ?
                                    (geo.size.height - currentPageRect.maxY) :
                                    (geo.size.height - currentPageRect.minY - CGFloat(progressBarThickness))
                                
                                Rectangle()
                                    .fill(Color(hex: progressBarHexColor))
                                    .frame(width: width, height: CGFloat(progressBarThickness))
                                    .offset(x: xOffset, y: yOffset)
                            }
                            .ignoresSafeArea()
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ignoresSafeArea(isPresentationMode ? .all : [])
                }
                .toolbar(isPresentationMode ? .hidden : .visible, for: .windowToolbar)
                .toolbar {
                    ToolbarItemGroup(placement: .primaryAction) {
                        // View Mode Picker (Single Page, Two Pages, Presentation Mode)
                        Picker("View Mode", selection: viewModeSelection) {
                            Label("Single Page", systemImage: "doc").tag(ViewModeSelection.single)
                            Label("Two Pages", systemImage: "book").tag(ViewModeSelection.twoUp)
                            Label("Presentation Mode", systemImage: "play.rectangle.on.rectangle").tag(ViewModeSelection.presentation)
                        }
                        .pickerStyle(.segmented)
                        .help("Switch between Portrait, Spread, or Presentation mode")
                        
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
        // Handle Sort Tabs request from the AppKit button next to plus
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("SortTabsAlphabetically"))) { _ in
            // Only the key window should handle the sort to prevent triple-execution
            guard currentWindow?.isKeyWindow == true || currentWindow == NSApp.keyWindow else {
                DLog("SortTabsAlphabetically: skipping, not the key window")
                return
            }
            DLog("SortTabsAlphabetically notification received (key window), currentWindow=\(String(describing: currentWindow))")
            sortTabsAlphabetically()
        }
        // Handle per-window URL swap during tab sorting (batch notification)
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("SwapDocumentURL"))) { notification in
            guard let payload = notification.object as? SwapDocumentPayload,
                  let window = currentWindow,
                  let newURL = payload.assignments[window] else { return }
            
            DLog("SwapDocumentURL: swapping to \(newURL.lastPathComponent) in window \(String(describing: currentWindow))")
            
            // Directly load the new document (registry is pre-cleared by the sender)
            self.fileURL = newURL
            if let doc = PDFDocument(url: newURL) {
                doc.delegate = sharedPDFView
                self.pdfDocument = doc
                self.totalPages = doc.pageCount
                self.currentPage = 1
                self.scaleFactor = 1.0
                self.autoScales = true
                self.updateRegistry()
                DLog("SwapDocumentURL: successfully loaded \(newURL.lastPathComponent)")
            } else {
                DLog("SwapDocumentURL: FAILED to create PDFDocument from \(newURL.path)")
            }
            
            // If this window now holds the previously-active URL, make it the selected tab
            if let activeURL = payload.activeURL,
               newURL.standardized.path == activeURL.standardized.path {
                DLog("SwapDocumentURL: restoring active tab for \(newURL.lastPathComponent)")
                window.makeKey()
            }
            
            saveOpenDocuments()
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
        // Expose presentation trigger (Cmd+Option+P)
        .focusedSceneValue(\.presentationAction, {
            if pdfDocument != nil {
                if isPresentationMode {
                    exitPresentationMode()
                } else {
                    enterPresentationMode()
                }
            }
        })
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ExitPresentationMode"))) { _ in
            if isPresentationMode {
                exitPresentationMode()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) { notification in
            guard let window = notification.object as? NSWindow, window == currentWindow else { return }
            if isPresentationMode {
                exitPresentationMode()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEnterFullScreenNotification)) { notification in
            guard let window = notification.object as? NSWindow, window == currentWindow else { return }
            if isPresentationMode {
                sharedPDFView.autoScales = false
                DispatchQueue.main.async {
                    sharedPDFView.autoScales = true
                }
            }
        }
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
                
                // Suppress toolbar right-click context menu
                if let toolbar = window.toolbar {
                    toolbar.allowsUserCustomization = false
                    if #available(macOS 15.0, *) {
                        toolbar.allowsDisplayModeCustomization = false
                    }
                }
                if let superview = window.contentView?.superview {
                    superview.menu = nil
                }
                
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
    
    private func enterPresentationMode() {
        guard let window = currentWindow else { return }
        
        savedDisplayMode = displayMode
        savedAutoScales = autoScales
        savedScaleFactor = scaleFactor
        savedColumnVisibility = columnVisibility
        
        displayMode = .singlePage
        autoScales = true
        columnVisibility = .detailOnly
        isPresentationMode = true
        
        if !window.styleMask.contains(.fullScreen) {
            window.toggleFullScreen(nil)
        }
    }
    
    private func exitPresentationMode() {
        guard isPresentationMode else { return }
        isPresentationMode = false
        
        displayMode = savedDisplayMode
        autoScales = savedAutoScales
        scaleFactor = savedScaleFactor
        columnVisibility = savedColumnVisibility
        
        if let window = currentWindow, window.styleMask.contains(.fullScreen) {
            window.toggleFullScreen(nil)
        }
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
    private func sortTabsAlphabetically() {
        DLog("sortTabsAlphabetically() called")
        
        guard let window = currentWindow ?? NSApp.keyWindow else {
            DLog("sortTabsAlphabetically: no currentWindow or keyWindow")
            return
        }
        guard let tabGroup = window.tabGroup else {
            DLog("sortTabsAlphabetically: window has no tabGroup")
            return
        }
        
        let tabbedWindows = tabGroup.windows  // ordered left-to-right
        DLog("sortTabsAlphabetically: tabGroup has \(tabbedWindows.count) windows")
        
        // Build mapping: window → current fileURL (via OpenDocumentsRegistry)
        let registry = OpenDocumentsRegistry.shared
        var windowURLPairs: [(NSWindow, URL)] = []
        for (i, w) in tabbedWindows.enumerated() {
            if let url = registry.url(for: w) {
                DLog("sortTabsAlphabetically: window[\(i)] → \(url.lastPathComponent)")
                windowURLPairs.append((w, url))
            } else {
                DLog("sortTabsAlphabetically: window[\(i)] → NO URL in registry (window=\(w))")
            }
        }
        
        DLog("sortTabsAlphabetically: found \(windowURLPairs.count) windows with URLs out of \(tabbedWindows.count) total")
        
        guard windowURLPairs.count == tabbedWindows.count else {
            DLog("sortTabsAlphabetically: not all windows have URLs, aborting")
            return
        }
        
        // Sort URLs alphabetically by filename using natural/numeric comparison
        // so "Lesson 3" sorts before "Lesson 10"
        let sortedURLs = windowURLPairs
            .map { $0.1 }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        
        // Check if already sorted
        let currentURLs = windowURLPairs.map { $0.1 }
        let currentPaths = currentURLs.map({ $0.standardized.path })
        let sortedPaths = sortedURLs.map({ $0.standardized.path })
        DLog("sortTabsAlphabetically: current order = \(currentURLs.map { $0.lastPathComponent })")
        DLog("sortTabsAlphabetically: sorted order  = \(sortedURLs.map { $0.lastPathComponent })")
        
        guard sortedPaths != currentPaths else {
            DLog("sortTabsAlphabetically: already sorted, nothing to do")
            return
        }
        
        // Remember which URL is currently active so we can re-select it after the swap
        let activeURL = self.fileURL
        DLog("sortTabsAlphabetically: active URL = \(activeURL?.lastPathComponent ?? "nil")")
        
        // Build the batch assignment map: window → new URL
        var assignments: [NSWindow: URL] = [:]
        for (index, w) in tabbedWindows.enumerated() {
            guard index < sortedURLs.count else { break }
            assignments[w] = sortedURLs[index]
            DLog("sortTabsAlphabetically: window[\(index)] ← \(sortedURLs[index].lastPathComponent)")
        }
        
        // Clear all URLs from the registry first to prevent conflicts during swap
        for (_, url) in windowURLPairs {
            registry.unregister(url: url)
        }
        DLog("sortTabsAlphabetically: cleared registry")
        
        // Animate: fade out → swap → fade in
        let contentViews = tabbedWindows.compactMap { $0.contentView }
        
        // Phase 1: Fade out
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            for view in contentViews {
                view.animator().alphaValue = 0.0
            }
        }, completionHandler: {
            // Phase 2: Perform the swap
            DLog("sortTabsAlphabetically: fade-out complete, dispatching batch SwapDocumentURL")
            NotificationCenter.default.post(
                name: Notification.Name("SwapDocumentURL"),
                object: SwapDocumentPayload(assignments: assignments, activeURL: activeURL)
            )
            
            // Phase 3: Fade back in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                NSAnimationContext.runAnimationGroup({ context in
                    context.duration = 0.2
                    context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    for view in contentViews {
                        view.animator().alphaValue = 1.0
                    }
                })
            }
            DLog("sortTabsAlphabetically: done")
        })
    }
    
    // Dynamically inject the sort button next to the native plus button on the AppKit tab bar
    private func setupTabBarButtons() {
        guard let window = currentWindow ?? NSApp.keyWindow else { return }
        
        // Suppress toolbar right-click context menu
        if let toolbar = window.toolbar {
            if toolbar.allowsUserCustomization {
                toolbar.allowsUserCustomization = false
            }
            if #available(macOS 15.0, *) {
                if toolbar.allowsDisplayModeCustomization {
                    toolbar.allowsDisplayModeCustomization = false
                }
            }
        }
        if let superview = window.contentView?.superview, superview.menu != nil {
            superview.menu = nil
        }
        
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
            doc.delegate = sharedPDFView
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
