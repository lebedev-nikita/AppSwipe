import AppKit
import Observation
import SwiftUI

/// The strip in Settings for trying the Step length: swipes over it move a row of dots instead of
/// opening a Switcher.
@MainActor
@Observable
final class StepTrial {
    static let dots = 9

    /// The dot the Selection is on, or nil while no swipe is in progress.
    var selection: Int?

    @ObservationIgnored weak var area: NSView?

    /// Whether a swipe starting now should go to the strip: the pointer is over it, in the key window.
    var isUnderPointer: Bool {
        guard let area, let window = area.window, window.isKeyWindow else { return false }
        let frame = window.convertToScreen(area.convert(area.bounds, to: nil))
        return frame.contains(NSEvent.mouseLocation)
    }
}

struct StepTrialStrip: View {
    let trial: StepTrial

    var body: some View {
        HStack(spacing: 10) {
            ForEach(0..<StepTrial.dots, id: \.self) { dot in
                Circle()
                    .fill(dot == trial.selection ? Color.accentColor : Color.secondary.opacity(0.3))
                    .frame(width: 12, height: 12)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 56)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .background(AreaReader(trial: trial))
        .overlay(alignment: .bottom) {
            Text(trial.selection == nil ? LocalizedStringKey("Swipe here with three or four fingers") : "")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.bottom, 4)
        }
    }
}

/// Hands the strip's view to the trial, so it can tell where the strip is on screen.
private struct AreaReader: NSViewRepresentable {
    let trial: StepTrial

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        trial.area = view
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        trial.area = view
    }
}
