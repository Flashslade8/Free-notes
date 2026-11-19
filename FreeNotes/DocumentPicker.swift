import SwiftUI
import UniformTypeIdentifiers

/// Apple's own file chooser. It hands back a copy of the file that the app can always read,
/// which avoids the problems SwiftUI's built-in file importer has.
struct DocumentPicker: UIViewControllerRepresentable {
    let types: [UTType]
    let onFinish: (URL?) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish) }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onFinish: (URL?) -> Void
        init(_ onFinish: @escaping (URL?) -> Void) { self.onFinish = onFinish }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            onFinish(urls.first)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onFinish(nil)
        }
    }
}

extension View {
    /// Shows the file chooser, then calls `onPick` once it has closed.
    func documentPicker(isPresented: Binding<Bool>, types: [UTType],
                        onPick: @escaping (URL) -> Void) -> some View {
        sheet(isPresented: isPresented) {
            DocumentPicker(types: types) { url in
                isPresented.wrappedValue = false
                guard let url else { return }
                // Wait for the chooser to finish closing before doing anything with the file.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { onPick(url) }
            }
            .ignoresSafeArea()
        }
    }
}
