import SwiftUI
import PDFKit
import Combine

// Proxy delegate that intercepts middle-click close on the last tab
// and redirects to landing page instead of closing the window.
class WindowCloseProxy: NSObject, NSWindowDelegate {
    var originalDelegate: NSWindowDelegate?
    
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        let tabCount = sender.tabGroup?.windows.count ?? 1
        if tabCount <= 1 {
            // Last tab — post notification to return to landing page
            NotificationCenter.default.post(name: Notification.Name("ReturnToLandingPage"), object: sender)
            return false
        }
        return originalDelegate?.windowShouldClose?(sender) ?? true
    }
    
    // Forward all other delegate methods to the original SwiftUI delegate
    override func responds(to aSelector: Selector!) -> Bool {
        if aSelector == #selector(NSWindowDelegate.windowShouldClose(_:)) {
            return true
        }
        return originalDelegate?.responds(to: aSelector) ?? super.responds(to: aSelector)
    }
    
    override func forwardingTarget(for aSelector: Selector!) -> Any? {
        if aSelector == #selector(NSWindowDelegate.windowShouldClose(_:)) {
            return nil // Handle ourselves
        }
        return originalDelegate
    }
}

class CustomPDFView: PDFView, PDFDocumentDelegate {
    private var scrollMonitor: Any?
    private var closeProxy: WindowCloseProxy?
    private var hasMergedIntoTabGroup = false
    
    private var activeHighlightedPage: HighlightablePDFPage?
    private var activeHighlightedRect: CGRect?
    
    override var document: PDFDocument? {
        didSet {
            document?.delegate = self
        }
    }
    
    var isPresentationMode = false {
        didSet {
            self.backgroundColor = isPresentationMode ? NSColor.black : NSColor.windowBackgroundColor
        }
    }
    
    private var isMiddleDragging = false
    private var initialScrollPoint: NSPoint?
    private var initialMousePoint: NSPoint?
    
    private func findScrollView() -> NSScrollView? {
        func find(in view: NSView) -> NSScrollView? {
            if let sv = view as? NSScrollView {
                return sv
            }
            for subview in view.subviews {
                if let sv = find(in: subview) {
                    return sv
                }
            }
            return nil
        }
        return find(in: self)
    }
    
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        if newWindow == nil && isMiddleDragging {
            isMiddleDragging = false
            NSCursor.pop()
        }
    }
    
    override func otherMouseDown(with event: NSEvent) {
        if event.buttonNumber == 2 {
            if let scrollView = findScrollView() {
                self.initialScrollPoint = scrollView.contentView.bounds.origin
                self.initialMousePoint = self.convert(event.locationInWindow, from: nil)
                self.isMiddleDragging = true
                NSCursor.closedHand.push()
            }
        } else {
            super.otherMouseDown(with: event)
        }
    }
    
    override func otherMouseDragged(with event: NSEvent) {
        if event.buttonNumber == 2 && isMiddleDragging,
           let initialScroll = self.initialScrollPoint,
           let initialMouse = self.initialMousePoint,
           let scrollView = findScrollView() {
            
            let currentMouse = self.convert(event.locationInWindow, from: nil)
            let dx = currentMouse.x - initialMouse.x
            let dy = currentMouse.y - initialMouse.y
            
            // Convert displacement from PDFView space to contentView space to respect magnification/zoom
            let p0 = self.convert(NSPoint.zero, to: scrollView.contentView)
            let p1 = self.convert(NSPoint(x: dx, y: dy), to: scrollView.contentView)
            let deltaX = p1.x - p0.x
            let deltaY = p1.y - p0.y
            
            let newScrollPoint = NSPoint(x: initialScroll.x - deltaX, y: initialScroll.y - deltaY)
            scrollView.contentView.scroll(to: newScrollPoint)
            scrollView.reflectScrolledClipView(scrollView.contentView)
        } else {
            super.otherMouseDragged(with: event)
        }
    }
    
    override func otherMouseUp(with event: NSEvent) {
        if event.buttonNumber == 2 && isMiddleDragging {
            self.initialScrollPoint = nil
            self.initialMousePoint = nil
            self.isMiddleDragging = false
            NSCursor.pop()
        } else {
            super.otherMouseUp(with: event)
        }
    }
    
    override func keyDown(with event: NSEvent) {
        if isPresentationMode && event.keyCode == 53 { // Escape
            NotificationCenter.default.post(name: Notification.Name("ExitPresentationMode"), object: nil)
            return
        }
        
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        if modifiers.isEmpty {
            if event.keyCode == 123 { // Left Arrow
                if self.canGoToPreviousPage {
                    self.goToPreviousPage(nil)
                    return
                }
            } else if event.keyCode == 124 { // Right Arrow
                if self.canGoToNextPage {
                    self.goToNextPage(nil)
                    return
                }
            }
        }
        super.keyDown(with: event)
    }
    
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        
        if let window = self.window {
            // Install the close proxy to intercept last-tab close
            if closeProxy == nil {
                let proxy = WindowCloseProxy()
                proxy.originalDelegate = window.delegate
                window.delegate = proxy
                closeProxy = proxy
            }
            // Force window tabbing mode to preferred so new documents open as tabs
            window.tabbingMode = .preferred
            
            // Merge this window into any existing window's tab group to ensure tabs are used
            // Only run once per window to prevent resize flashes from repeated viewDidMoveToWindow calls
            if !TabBarButtonTarget.isSorting && !hasMergedIntoTabGroup {
                let otherWindows = NSApplication.shared.windows.filter {
                    $0 != window &&
                    $0.isVisible &&
                    !$0.className.contains("NSColorPanel") &&
                    !$0.className.contains("NSFontPanel") &&
                    $0.canBecomeKey
                }
                if let hostWindow = otherWindows.first {
                    hasMergedIntoTabGroup = true
                    
                    // Match the frame synchronously so the window is the right size instantly and doesn't flash
                    NSAnimationContext.beginGrouping()
                    NSAnimationContext.current.duration = 0
                    window.setFrame(hostWindow.frame, display: false, animate: false)
                    NSAnimationContext.endGrouping()
                    
                    // Defer the tab group manipulation to avoid layout-time AppKit exceptions
                    DispatchQueue.main.async {
                        NSAnimationContext.beginGrouping()
                        NSAnimationContext.current.duration = 0
                        
                        let lastTab = hostWindow.tabGroup?.windows.last ?? hostWindow
                        lastTab.makeKey()
                        lastTab.addTabbedWindow(window, ordered: .above)
                        // Select this new tab so it becomes active
                        window.makeKey()
                        NSAnimationContext.endGrouping()
                    }
                }
            }
            

            // Show the Apple tab bar by default if it is currently hidden
            if let tabGroup = window.tabGroup, !tabGroup.isTabBarVisible {
                window.toggleTabBar(nil)
            }
            
            // Save open documents state on new window creation
            DispatchQueue.main.async {
                saveOpenDocuments()
            }
            
            // Observe window closing to update the saved session state
            NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification,
                object: window,
                queue: .main
            ) { _ in
                DispatchQueue.main.async {
                    saveOpenDocuments()
                    
                    // Ensure the remaining windows keep their tab bars visible (e.g. if only one tab is left)
                    for w in NSApplication.shared.windows {
                        if w.isVisible && w.canBecomeKey && !w.className.contains("Panel") {
                            if let tabGroup = w.tabGroup, !tabGroup.isTabBarVisible {
                                w.toggleTabBar(nil)
                            }
                        }
                    }
                }
            }
            
            if scrollMonitor == nil {
                scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                    guard let self = self, self.window == event.window else { return event }
                    
                    if event.modifierFlags.contains(.command) {
                        let mouseLoc = event.locationInWindow
                        let localPoint = self.convert(mouseLoc, from: nil)
                        if self.bounds.contains(localPoint) {
                            self.handleScrollZoom(with: event)
                            return nil // Consume event
                        }
                    }
                    return event
                }
            }
        } else {
            if let monitor = scrollMonitor {
                NSEvent.removeMonitor(monitor)
                scrollMonitor = nil
            }
        }
    }
    
    var onUserZooming: (() -> Void)?
    
    private func handleScrollZoom(with event: NSEvent) {
        let dy = event.scrollingDeltaY
        if dy != 0 {
            if self.autoScales {
                self.autoScales = false
                self.onUserZooming?()
            }
            let factor = 1.0 + (dy > 0 ? 0.05 : -0.05)
            self.scaleFactor = min(max(self.scaleFactor * CGFloat(factor), 0.1), 5.0)
        }
    }
    
    override func magnify(with event: NSEvent) {
        if event.magnification != 0 {
            if self.autoScales {
                DLog("CustomPDFView: magnify starting, setting autoScales = false. Magnification: \(event.magnification)")
                self.autoScales = false
                self.onUserZooming?()
            }
        }
        super.magnify(with: event)
    }
    
    private func clearImageHighlight() {
        if let page = activeHighlightedPage {
            page.highlightedImageRect = nil
            activeHighlightedPage = nil
            activeHighlightedRect = nil
            self.needsDisplay = true
        }
    }
    
    @objc private func copySelectedImage() {
        guard let page = activeHighlightedPage,
              let rect = activeHighlightedRect else { return }
        
        let scale: CGFloat = 3.0
        let pageBounds = page.bounds(for: .cropBox)
        
        let targetSize = NSSize(width: pageBounds.width * scale, height: pageBounds.height * scale)
        let thumbnail = page.thumbnail(of: targetSize, for: .cropBox)
        
        let rotatedRect = cropRectFor(rect: rect, pageBounds: pageBounds, rotation: page.rotation)
        
        let rotatedHeight = (page.rotation == 90 || page.rotation == 270) ? pageBounds.width : pageBounds.height
        
        let cgCropRect = CGRect(
            x: rotatedRect.origin.x * scale,
            y: (rotatedHeight - rotatedRect.origin.y - rotatedRect.height) * scale,
            width: rotatedRect.width * scale,
            height: rotatedRect.height * scale
        )
        
        guard let cgImage = thumbnail.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        guard let croppedCGImage = cgImage.cropping(to: cgCropRect) else { return }
        
        let croppedNSImage = NSImage(cgImage: croppedCGImage, size: NSSize(width: rect.width * scale, height: rect.height * scale))
        
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([croppedNSImage])
    }
    
    private func cropRectFor(rect: CGRect, pageBounds: CGRect, rotation: Int) -> CGRect {
        let x = rect.origin.x - pageBounds.origin.x
        let y = rect.origin.y - pageBounds.origin.y
        let w = rect.width
        let h = rect.height
        
        let width = pageBounds.width
        let height = pageBounds.height
        
        switch rotation {
        case 90:
            return CGRect(x: y, y: width - x - w, width: h, height: w)
        case 180:
            return CGRect(x: width - x - w, y: height - y - h, width: w, height: h)
        case 270:
            return CGRect(x: height - y - h, y: x, width: h, height: w)
        default:
            return CGRect(x: x, y: y, width: w, height: h)
        }
    }
    
    override func menuDidClose(_ menu: NSMenu) {
        DispatchQueue.main.async { [weak self] in
            self?.clearImageHighlight()
        }
    }
    
    func classForPage() -> AnyClass {
        return HighlightablePDFPage.self
    }
    
    override func menu(for event: NSEvent) -> NSMenu? {
        clearImageHighlight()
        
        let viewPoint = self.convert(event.locationInWindow, from: nil)
        var isImageMenu = false
        
        if let page = self.page(for: viewPoint, nearest: false),
           let cgPage = page.pageRef {
            let pagePoint = self.convert(viewPoint, to: page)
            
            let scanner = PDFImageScanner(page: cgPage)
            let imageRects = scanner.scan()
            
            if let clickedRect = imageRects.first(where: { $0.contains(pagePoint) }) {
                if let highlightablePage = page as? HighlightablePDFPage {
                    highlightablePage.highlightedImageRect = clickedRect
                    self.activeHighlightedPage = highlightablePage
                    self.activeHighlightedRect = clickedRect
                    self.needsDisplay = true
                    isImageMenu = true
                    self.currentSelection = nil // Clear text selection to prevent double selection
                }
            }
        }
        
        guard let menu = super.menu(for: event) else { return nil }
        
        menu.delegate = self
        
        if isImageMenu {
            let copyItem = NSMenuItem(title: "Copy Image", action: #selector(copySelectedImage), keyEquivalent: "")
            copyItem.target = self
            menu.insertItem(copyItem, at: 0)
            menu.insertItem(NSMenuItem.separator(), at: 1)
        }
        
        let actionsToSuppress: Set<String> = [
            "_setSinglePage:",
            "_setSinglePageScrolling:",
            "_setDoublePage:",
            "_setDoublePageScrolling:"
        ]
        
        // Remove items with matching actions
        for item in menu.items.reversed() {
            if let action = item.action {
                let actionName = String(describing: action)
                if actionsToSuppress.contains(actionName) {
                    menu.removeItem(item)
                }
            }
        }
        
        // Clean up separators in the modified menu
        var lastWasSeparator = false
        var itemsToRemove: [NSMenuItem] = []
        
        // Remove leading separator if any
        if menu.items.first?.isSeparatorItem == true {
            itemsToRemove.append(menu.items.first!)
        }
        
        for item in menu.items {
            if item.isSeparatorItem {
                if lastWasSeparator {
                    itemsToRemove.append(item)
                }
                lastWasSeparator = true
            } else {
                lastWasSeparator = false
            }
        }
        
        // Remove trailing separator if any
        if menu.items.last?.isSeparatorItem == true {
            itemsToRemove.append(menu.items.last!)
        }
        
        for item in itemsToRemove {
            if menu.items.contains(item) {
                menu.removeItem(item)
            }
        }
        
        return menu
    }
    
    deinit {
        if let monitor = scrollMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if isMiddleDragging {
            NSCursor.pop()
        }
    }
}

struct PDFViewRepresentable: NSViewRepresentable {
    let document: PDFDocument?
    let pdfView: CustomPDFView
    
    @Binding var currentPage: Int
    @Binding var totalPages: Int
    @Binding var scaleFactor: Double
    @Binding var autoScales: Bool
    @Binding var displayMode: PDFDisplayMode
    @Binding var isPresentationMode: Bool
    @Binding var currentPageRect: CGRect
    
    func makeNSView(context: Context) -> CustomPDFView {
        pdfView.document = document
        pdfView.autoScales = autoScales
        pdfView.displayMode = displayMode
        pdfView.isPresentationMode = isPresentationMode
        pdfView.backgroundColor = isPresentationMode ? NSColor.black : NSColor.windowBackgroundColor
        pdfView.displaysPageBreaks = !isPresentationMode
        pdfView.postsFrameChangedNotifications = true
        
        pdfView.onUserZooming = {
            context.coordinator.userDidStartZooming()
        }
        
        context.coordinator.updateCurrentPage()
        context.coordinator.updateScaleFactor()
        
        return pdfView
    }
    
    func updateNSView(_ nsView: CustomPDFView, context: Context) {
        context.coordinator.parent = self
        
        // Update Document
        if nsView.document != document {
            nsView.document = document
        }
        
        // Sync totalPages if it differs
        if let doc = document {
            if totalPages != doc.pageCount {
                DispatchQueue.main.async {
                    self.totalPages = doc.pageCount
                }
            }
        }
        
        // Update presentation mode
        if nsView.isPresentationMode != isPresentationMode {
            nsView.isPresentationMode = isPresentationMode
            DispatchQueue.main.async {
                context.coordinator.updatePageRect()
            }
        }
        
        let targetPageBreaks = !isPresentationMode
        if nsView.displaysPageBreaks != targetPageBreaks {
            nsView.displaysPageBreaks = targetPageBreaks
        }
        
        // Update Auto Scales first (order matters to resolve scale sync races)
        if nsView.autoScales != autoScales {
            if autoScales == true && !nsView.autoScales && abs(Double(nsView.scaleFactor) - scaleFactor) > 0.01 {
                // User zoomed internally; do not force autoScales=true. Let state sync later.
                DLog("updateNSView: User zoomed internally, syncing autoScales to false instead of forcing true")
                DispatchQueue.main.async {
                    self.autoScales = false
                }
            } else {
                DLog("updateNSView: Changing nsView.autoScales from \(nsView.autoScales) to \(autoScales)")
                nsView.autoScales = autoScales
                if autoScales {
                    // If autoScales is turned on, sync the scale factor back to state
                    DLog("updateNSView: AutoScales is true, syncing scaleFactor state to \(nsView.scaleFactor)")
                    DispatchQueue.main.async {
                        self.scaleFactor = Double(nsView.scaleFactor)
                    }
                }
            }
        }
        
        // Then Update Scale
        if !autoScales && abs(Double(nsView.scaleFactor) - scaleFactor) > 0.01 {
            if let index = context.coordinator.scalesSentToSwiftUI.firstIndex(where: { abs($0 - scaleFactor) < 0.001 }) {
                // This state update originated from PDFView (e.g. trackpad), ignore it to prevent jumpiness
                context.coordinator.scalesSentToSwiftUI.removeSubrange(0...index)
            } else {
                // This state update originated from SwiftUI (e.g. slider), push to PDFView
                nsView.scaleFactor = CGFloat(scaleFactor)
                context.coordinator.scalesSentToSwiftUI.removeAll()
            }
        }
        
        // Update Display Mode
        if nsView.displayMode != displayMode {
            nsView.displayMode = displayMode
            DispatchQueue.main.async {
                context.coordinator.updatePageRect()
            }
        }
        
        // Jump to page if programmatically changed
        if let doc = nsView.document,
           currentPage >= 1 && currentPage <= doc.pageCount {
            if let currentPageObj = nsView.currentPage {
                let currentIndex = doc.index(for: currentPageObj) + 1
                if currentIndex != currentPage {
                    if let targetPage = doc.page(at: currentPage - 1) {
                        nsView.go(to: targetPage)
                    }
                }
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject {
        var parent: PDFViewRepresentable
        private var cancellables = Set<AnyCancellable>()
        var scalesSentToSwiftUI: [Double] = []
        
        init(_ parent: PDFViewRepresentable) {
            self.parent = parent
            super.init()
            
            // Observe page changes
            NotificationCenter.default.publisher(for: .PDFViewPageChanged)
                .sink { [weak self] notification in
                    guard let self = self,
                          let notificationView = notification.object as? CustomPDFView,
                          notificationView == self.parent.pdfView else { return }
                    self.updateCurrentPage()
                }
                .store(in: &cancellables)
            
            // Observe scale changes
            NotificationCenter.default.publisher(for: .PDFViewScaleChanged)
                .sink { [weak self] notification in
                    guard let self = self,
                           let notificationView = notification.object as? CustomPDFView,
                           notificationView == self.parent.pdfView else { return }
                     self.updateScaleFactor()
                }
                .store(in: &cancellables)
            
            // Observe frame changes (window/view resize)
            NotificationCenter.default.publisher(for: NSView.frameDidChangeNotification, object: parent.pdfView)
                .sink { [weak self] _ in
                    guard let self = self else { return }
                    self.updatePageRect()
                }
                .store(in: &cancellables)
                
            // Observe live magnification (trackpad pinch)
            NotificationCenter.default.publisher(for: NSScrollView.willStartLiveMagnifyNotification)
                .sink { [weak self] notification in
                    guard let self = self,
                          let scrollView = notification.object as? NSScrollView,
                          scrollView.isDescendant(of: self.parent.pdfView) else { return }
                    
                    DLog("Coordinator: NSScrollView started live magnify! Setting autoScales = false")
                    if self.parent.autoScales {
                        DispatchQueue.main.async {
                            self.parent.autoScales = false
                        }
                        self.parent.pdfView.autoScales = false
                    }
                }
                .store(in: &cancellables)
                
            NotificationCenter.default.publisher(for: NSScrollView.didEndLiveMagnifyNotification)
                .sink { [weak self] notification in
                    guard let self = self,
                          let scrollView = notification.object as? NSScrollView,
                          scrollView.isDescendant(of: self.parent.pdfView) else { return }
                    
                    DLog("Coordinator: NSScrollView ended live magnify! Updating scale factor.")
                    self.updateScaleFactor()
                }
                .store(in: &cancellables)
        }
        
        func updateCurrentPage() {
            guard let document = parent.pdfView.document,
                  let currentPageObj = parent.pdfView.currentPage else { return }
            let index = document.index(for: currentPageObj) + 1
            if parent.currentPage != index {
                DispatchQueue.main.async {
                    self.parent.currentPage = index
                }
            }
            updatePageRect()
        }
        
        func userDidStartZooming() {
            DLog("Coordinator: userDidStartZooming called, current autoScales: \(parent.autoScales)")
            if parent.autoScales {
                self.parent.autoScales = false
            }
        }
        
        func updateScaleFactor() {
            let scale = Double(parent.pdfView.scaleFactor)
            if abs(parent.scaleFactor - scale) > 0.01 {
                scalesSentToSwiftUI.append(scale)
                DispatchQueue.main.async {
                    self.parent.scaleFactor = scale
                    if !self.parent.pdfView.autoScales && self.parent.autoScales {
                        self.parent.autoScales = false
                    }
                }
            }
            updatePageRect()
        }
        
        func updatePageRect() {
            guard let page = parent.pdfView.currentPage else { return }
            let rect = parent.pdfView.convert(page.bounds(for: parent.pdfView.displayBox), from: page)
            if parent.currentPageRect != rect {
                DispatchQueue.main.async {
                    self.parent.currentPageRect = rect
                }
            }
        }
    }
}

struct PDFThumbnailViewRepresentable: NSViewRepresentable {
    let pdfView: PDFView
    @Binding var selectionCount: Int
    
    func makeNSView(context: Context) -> PDFThumbnailView {
        let thumbnailView = PDFThumbnailView()
        thumbnailView.pdfView = pdfView
        thumbnailView.thumbnailSize = NSSize(width: 80, height: 110)
        return thumbnailView
    }
    
    func updateNSView(_ nsView: PDFThumbnailView, context: Context) {
        nsView.pdfView = pdfView
    }
}

class HighlightablePDFPage: PDFPage {
    var highlightedImageRect: CGRect?
    
    override func draw(with box: PDFDisplayBox, to context: CGContext) {
        super.draw(with: box, to: context)
        
        if let rect = highlightedImageRect {
            context.saveGState()
            context.setFillColor(NSColor.systemBlue.withAlphaComponent(0.25).cgColor)
            context.setStrokeColor(NSColor.systemBlue.cgColor)
            context.setLineWidth(2.0)
            context.fill(rect)
            context.stroke(rect)
            context.restoreGState()
        }
    }
}

class PDFImageScanner {
    var currentCTM = CGAffineTransform.identity
    var ctmStack: [CGAffineTransform] = []
    var imageRects: [CGRect] = []
    let page: CGPDFPage
    var operationCount = 0
    let maxOperations = 100_000 // Defensive limit
    
    init(page: CGPDFPage) {
        self.page = page
    }
    
    func scan() -> [CGRect] {
        let contentStream = CGPDFContentStreamCreateWithPage(page)
        guard let table = CGPDFOperatorTableCreate() else { return [] }
        
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        
        CGPDFOperatorTableSetCallback(table, "q") { (_, info) in
            guard let info = info else { return }
            let scannerState = Unmanaged<PDFImageScanner>.fromOpaque(info).takeUnretainedValue()
            scannerState.operationCount += 1
            if scannerState.operationCount > scannerState.maxOperations { return }
            
            if scannerState.ctmStack.count < 500 {
                scannerState.ctmStack.append(scannerState.currentCTM)
            }
        }
        
        CGPDFOperatorTableSetCallback(table, "Q") { (_, info) in
            guard let info = info else { return }
            let scannerState = Unmanaged<PDFImageScanner>.fromOpaque(info).takeUnretainedValue()
            scannerState.operationCount += 1
            if scannerState.operationCount > scannerState.maxOperations { return }
            
            if !scannerState.ctmStack.isEmpty {
                scannerState.currentCTM = scannerState.ctmStack.removeLast()
            }
        }
        
        CGPDFOperatorTableSetCallback(table, "cm") { (scanner, info) in
            guard let info = info else { return }
            let scannerState = Unmanaged<PDFImageScanner>.fromOpaque(info).takeUnretainedValue()
            scannerState.operationCount += 1
            if scannerState.operationCount > scannerState.maxOperations { return }
            
            var ty: CGPDFReal = 0
            var tx: CGPDFReal = 0
            var d: CGPDFReal = 0
            var c: CGPDFReal = 0
            var b: CGPDFReal = 0
            var a: CGPDFReal = 0
            
            if CGPDFScannerPopNumber(scanner, &ty),
               CGPDFScannerPopNumber(scanner, &tx),
               CGPDFScannerPopNumber(scanner, &d),
               CGPDFScannerPopNumber(scanner, &c),
               CGPDFScannerPopNumber(scanner, &b),
               CGPDFScannerPopNumber(scanner, &a) {
                let transform = CGAffineTransform(a: a, b: b, c: c, d: d, tx: tx, ty: ty)
                scannerState.currentCTM = transform.concatenating(scannerState.currentCTM)
            }
        }
        
        CGPDFOperatorTableSetCallback(table, "Do") { (scanner, info) in
            guard let info = info else { return }
            let scannerState = Unmanaged<PDFImageScanner>.fromOpaque(info).takeUnretainedValue()
            scannerState.operationCount += 1
            if scannerState.operationCount > scannerState.maxOperations { return }
            
            var name: UnsafePointer<Int8>? = nil
            if CGPDFScannerPopName(scanner, &name), let name = name {
                let objectName = String(cString: name)
                if scannerState.isImage(objectName) {
                    let unitRect = CGRect(x: 0, y: 0, width: 1, height: 1)
                    let rect = unitRect.applying(scannerState.currentCTM)
                    scannerState.imageRects.append(rect)
                }
            }
        }
        
        let pdfScanner = CGPDFScannerCreate(contentStream, table, selfPtr)
        CGPDFScannerScan(pdfScanner)
        
        return imageRects
    }
    
    private func isImage(_ name: String) -> Bool {
        guard let pageDict = page.dictionary else { return false }
        var resources: CGPDFDictionaryRef? = nil
        if CGPDFDictionaryGetDictionary(pageDict, "Resources", &resources), let res = resources {
            var xObjects: CGPDFDictionaryRef? = nil
            if CGPDFDictionaryGetDictionary(res, "XObject", &xObjects), let xObjs = xObjects {
                var stream: CGPDFStreamRef? = nil
                if CGPDFDictionaryGetStream(xObjs, name, &stream), let str = stream {
                    if let streamDict = CGPDFStreamGetDictionary(str) {
                        var subtype: UnsafePointer<Int8>? = nil
                        if CGPDFDictionaryGetName(streamDict, "Subtype", &subtype), let sub = subtype {
                            return String(cString: sub) == "Image"
                        }
                    }
                }
            }
        }
        return false
    }
}
