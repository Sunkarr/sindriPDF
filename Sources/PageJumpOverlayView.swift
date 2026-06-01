import SwiftUI
import PDFKit

struct PageJumpOverlayView: View {
    let pdfView: CustomPDFView
    @Binding var isPresented: Bool
    @Binding var currentPage: Int
    let totalPages: Int
    
    @State private var pageInput = ""
    @State private var showError = false
    @FocusState private var isFieldFocused: Bool
    
    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                // Book/Page Icon
                Image(systemName: "doc.text.fill")
                    .foregroundColor(.accentColor)
                    .font(.title3)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Go to Page")
                        .font(.headline)
                    Text("Enter page between 1 and \(totalPages)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                
                // Close button
                Button(action: closeOverlay) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            
            HStack(spacing: 8) {
                // Text Field for input
                TextField("Page #", text: $pageInput)
                    .textFieldStyle(.plain)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .padding(8)
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                    .cornerRadius(6)
                    .focused($isFieldFocused)
                    .onSubmit {
                        submitPage()
                    }
                    .onChange(of: pageInput) { _, newValue in
                        // Only allow numeric input
                        let filtered = newValue.filter { "0123456789".contains($0) }
                        if filtered != newValue {
                            pageInput = filtered
                        }
                        if showError {
                            showError = false
                        }
                    }
                
                // Jump Action Button
                Button(action: submitPage) {
                    Text("Go")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.accentColor)
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }
            
            if showError {
                Text("Please enter a valid page number")
                    .font(.caption)
                    .foregroundColor(.red)
                    .transition(.opacity)
            }
        }
        .padding(16)
        .frame(width: 280)
        .background(VisualEffectView(material: .hudWindow, blendingMode: .withinWindow).cornerRadius(12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.3), radius: 12, y: 6)
        .onExitCommand {
            closeOverlay()
        }
        .onAppear {
            pageInput = "\(currentPage)"
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isFieldFocused = true
            }
        }
    }
    
    private func submitPage() {
        guard let pageNum = Int(pageInput), pageNum >= 1 && pageNum <= totalPages else {
            withAnimation(.default) {
                showError = true
            }
            return
        }
        currentPage = pageNum
        closeOverlay()
    }
    
    private func closeOverlay() {
        isPresented = false
    }
}
