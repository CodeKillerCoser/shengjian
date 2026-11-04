import SwiftUI

struct Editor: View {
    let title: String
    @Binding var text: String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            TextEditor(text: $text).font(.system(size: 14)).padding(6).background(.background).clipShape(
                RoundedRectangle(cornerRadius: 8)
            ).overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
        }
    }
}
