import SwiftUI

/// PDF 页面卡片：写上页码取出来存成新的 PDF，或者每页存成一个 PDF。
@MainActor
final class PDFPagesModel: ObservableObject {
    let pdf: URL
    let pageCount: Int
    @Published var input = ""

    init(pdf: URL, pageCount: Int) {
        self.pdf = pdf
        self.pageCount = pageCount
    }

    var pages: [Int]? {
        PDFTools.pageIndices(input, pageCount: pageCount)
    }

    var isInvalid: Bool {
        !input.trimmingCharacters(in: .whitespaces).isEmpty && pages == nil
    }

    var summary: String {
        if input.trimmingCharacters(in: .whitespaces).isEmpty {
            return String(localized: "一共 \(pageCount) 页。写上要取出的页码，比如 1-3, 5, 8-（8- 是第 8 页到最后）")
        }
        guard let pages else { return String(localized: "页码写得不对，或者不在 1–\(pageCount) 之间") }
        return String(localized: "\(PDFTools.describe(pages))，一共 \(pages.count) 页")
    }
}

struct PDFPagesView: View {
    @ObservedObject var model: PDFPagesModel
    var onExtract: ([Int]) -> Void
    var onSplit: () -> Void
    var onClose: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        CardContainer(title: String(localized: "PDF 页面"), subtitle: model.pdf.lastPathComponent, width: 420, onClose: onClose) {
            TextField("页码，比如 1-3, 5, 8-", text: $model.input)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .onSubmit {
                    if let pages = model.pages {
                        onExtract(pages)
                    }
                }
            Text(model.summary)
                .font(.caption)
                .foregroundStyle(model.isInvalid ? Color.red : Color.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Spacer()
                Button("每页存成一个 PDF", action: onSplit)
                Button("取出这几页") {
                    if let pages = model.pages {
                        onExtract(pages)
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(model.pages == nil)
            }
            .controlSize(.small)
        }
        .task {
            focused = true
        }
    }
}
