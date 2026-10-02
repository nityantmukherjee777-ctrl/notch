import SwiftUI

extension View {
    /// Preserve initial delivery on Ventura while using the current API on Sonoma.
    @ViewBuilder func onNotchChange<Value: Equatable>(of value: Value, initial: Bool = false,
                                                     _ action: @escaping () -> Void) -> some View {
        if #available(macOS 14, *) {
            onChange(of: value, initial: initial, action)
        } else {
            onChange(of: value) { _ in action() }
                .onAppear { if initial { action() } }
        }
    }
}
