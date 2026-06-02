import SwiftUI
import PDFKit

struct StatusBarView: View {
    let document: PDFDocument?
    let pdfView: CustomPDFView
    
    @Binding var currentPage: Int
    @Binding var totalPages: Int
    @Binding var scaleFactor: Double
    @Binding var autoScales: Bool
    
    @State private var isEditingPage = false
    @State private var pageInputString = ""
    @FocusState private var isPageInputFocused: Bool
    
    @AppStorage("PageDimensionUnit") private var pageDimensionUnit: String = "mm"
    
    // Zoom percentage options for popover
    private let zoomOptions = [0.25, 0.50, 0.75, 1.00, 1.25, 1.50, 2.00, 3.00, 4.00]
    
    var body: some View {
        HStack {
            // Left Side: Page dimensions in millimeters
            HStack(spacing: 6) {
                Image(systemName: "doc.plaintext")
                    .foregroundColor(.secondary)
                Text(pageDimensionsString)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Center: Zoom Controls
            HStack(spacing: 8) {
                // Zoom Out Button
                Button(action: zoomOut) {
                    Image(systemName: "minus.magnifyingglass")
                }
                .buttonStyle(.plain)
                .help("Zoom Out")
                
                // Slider
                Slider(value: Binding(
                    get: { scaleFactor },
                    set: { newValue in
                        autoScales = false
                        scaleFactor = newValue
                    }
                ), in: 0.1...5.0)
                .frame(width: 100)
                .controlSize(.small)
                
                // Zoom In Button
                Button(action: zoomIn) {
                    Image(systemName: "plus.magnifyingglass")
                }
                .buttonStyle(.plain)
                .help("Zoom In")
                
                // Percentage Text Button with Popover
                Menu {
                    Button("Actual Size (100%)") {
                        autoScales = false
                        scaleFactor = 1.0
                    }
                    Button("Fit Page / Width") {
                        autoScales = true
                    }
                    Divider()
                    ForEach(zoomOptions, id: \.self) { val in
                        Button("\(Int(val * 100))%") {
                            autoScales = false
                            scaleFactor = val
                        }
                    }
                } label: {
                    Text("\(Int(scaleFactor * 100))%")
                        .font(.system(.caption, design: .monospaced))
                        .frame(width: 48, alignment: .trailing)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                
                if abs(scaleFactor - 1.0) < 0.01 && !autoScales {
                    Button("1:1") {
                        autoScales = false
                        scaleFactor = 1.0
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .fixedSize()
                    .help("Actual Size (1:1)")
                } else {
                    Button("1:1") {
                        autoScales = false
                        scaleFactor = 1.0
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .fixedSize()
                    .help("Actual Size (1:1)")
                }
            }
            
            Spacer()
            
            // Right Side: Jump to Page indicator
            HStack(spacing: 4) {
                if isEditingPage {
                    TextField("", text: $pageInputString)
                        .textFieldStyle(.plain)
                        .font(.system(.caption, design: .monospaced))
                        .frame(width: 35)
                        .multilineTextAlignment(.center)
                        .focused($isPageInputFocused)
                        .onSubmit {
                            submitPageJump()
                        }
                        .onChange(of: isPageInputFocused) { _, isFocused in
                            if !isFocused {
                                isEditingPage = false
                            }
                        }
                        .onExitCommand {
                            isEditingPage = false
                        }
                    
                    Text("of \(totalPages)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Button(action: startEditingPage) {
                        Text("Page \(currentPage) of \(totalPages)")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Click to jump to a page")
                }
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 28)
        .background(Color(NSColor.windowBackgroundColor))
        .overlay(
            VStack {
                Divider()
                Spacer()
            }
        )
    }
    
    // Page dimensions calculation
    private var pageDimensionsString: String {
        guard let document = document,
              currentPage >= 1 && currentPage <= document.pageCount,
              let page = document.page(at: currentPage - 1) else {
            return "-- × -- mm"
        }
        let bounds = page.bounds(for: .mediaBox)
        switch pageDimensionUnit {
        case "cm":
            let widthCm = bounds.width * 2.54 / 72.0
            let heightCm = bounds.height * 2.54 / 72.0
            return String(format: "%.2f × %.2f cm", widthCm, heightCm)
        case "inch":
            let widthInch = bounds.width / 72.0
            let heightInch = bounds.height / 72.0
            return String(format: "%.2f × %.2f in", widthInch, heightInch)
        case "points":
            return String(format: "%.0f × %.0f pt", bounds.width, bounds.height)
        default: // "mm"
            let widthMm = bounds.width * 25.4 / 72.0
            let heightMm = bounds.height * 25.4 / 72.0
            return String(format: "%.1f × %.1f mm", widthMm, heightMm)
        }
    }
    
    // Zoom operations
    private func zoomIn() {
        autoScales = false
        // Snap to next 10% interval or increase by 10%
        let nextScale = (scaleFactor + 0.1).rounded(toPlaces: 1)
        scaleFactor = min(nextScale, 5.0)
    }
    
    private func zoomOut() {
        autoScales = false
        let nextScale = (scaleFactor - 0.1).rounded(toPlaces: 1)
        scaleFactor = max(nextScale, 0.1)
    }
    
    // Jump to page operations
    private func startEditingPage() {
        guard totalPages > 0 else { return }
        pageInputString = "\(currentPage)"
        isEditingPage = true
        // Set focus in next runloop tick to ensure TextField is rendered
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            isPageInputFocused = true
        }
    }
    
    private func submitPageJump() {
        isEditingPage = false
        if let target = Int(pageInputString), target >= 1 && target <= totalPages {
            currentPage = target
        }
    }
}

// Float round helper for clean zooming
extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let divisor = pow(10.0, Double(places))
        return (self * divisor).rounded() / divisor
    }
}
