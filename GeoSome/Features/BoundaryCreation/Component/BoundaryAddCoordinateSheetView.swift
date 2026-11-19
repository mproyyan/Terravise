import SwiftUI

struct BoundaryAddCoordinateSheetView: View {
  @Environment(\.dismiss) private var dismiss
  @Binding var coordinateText: String
  @Binding var isDiscardConfirmationPresented: Bool
  @Binding var isInvalidCoordinateAlertPresented: Bool
  var canSubmit: Bool?
  var onCloseTap: (() -> Void)?
  var onDiscardConfirm: (() -> Void)?
  var onSubmitTap: (() -> Void)?

  @FocusState private var isInputFocused: Bool
  @Environment(\.colorSchemeContrast) private var contrast
  @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

  init(
    coordinateText: Binding<String> = .constant(""),
    isDiscardConfirmationPresented: Binding<Bool> = .constant(false),
    isInvalidCoordinateAlertPresented: Binding<Bool> = .constant(false),
    canSubmit: Bool? = nil,
    onCloseTap: (() -> Void)? = nil,
    onDiscardConfirm: (() -> Void)? = nil,
    onSubmitTap: (() -> Void)? = nil
  ) {
    _coordinateText = coordinateText
    _isDiscardConfirmationPresented = isDiscardConfirmationPresented
    _isInvalidCoordinateAlertPresented = isInvalidCoordinateAlertPresented
    self.canSubmit = canSubmit
    self.onCloseTap = onCloseTap
    self.onDiscardConfirm = onDiscardConfirm
    self.onSubmitTap = onSubmitTap
  }

  private var isSubmitEnabled: Bool {
    canSubmit ?? !coordinateText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  var body: some View {
    NavigationStack {
      VStack(alignment: .leading, spacing: 10) {
        Text("Coordinate")
          .font(.headline)
          .foregroundStyle(.primary)
          .accessibilityAddTraits(.isHeader)

        if differentiateWithoutColor {
          Label("Format: latitude, longitude (one pair per line)", systemImage: "info.circle")
            .font(.caption)
            .foregroundStyle(contrast == .increased ? .primary : .secondary)
            .fixedSize(horizontal: false, vertical: true)
        }

        ZStack(alignment: .topLeading) {
          if coordinateText.isEmpty {
            Text("e.g., -6.215432, 106.845321")
              .font(.body)
              .foregroundStyle(contrast == .increased ? .primary : .secondary)
              .padding(.horizontal, 5)
              .padding(.vertical, 8)
              .allowsHitTesting(false)
              .accessibilityHidden(true)
          }

          TextEditor(text: $coordinateText)
            .font(.body)
            .foregroundStyle(.primary)
            .focused($isInputFocused)
            .scrollContentBackground(.hidden)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .accessibilityLabel("Coordinate input")
            .accessibilityHint("Enter latitude and longitude separated by a comma, one pair per line")
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
          RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(Color(.secondarySystemGroupedBackground))
        )
        .overlay(
          RoundedRectangle(cornerRadius: 22, style: .continuous)
            .stroke(
              Color.primary.opacity(contrast == .increased ? 0.45 : 0.14),
              lineWidth: contrast == .increased ? 1.5 : 1
            )
        )
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .onTapGesture {
          isInputFocused = true
        }
      }
      .padding(.horizontal, 20)
      .padding(.top, 8)
      .padding(.bottom, 20)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      .navigationTitle("Add Coordinate")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(role: .close) {
            if let onCloseTap {
              onCloseTap()
            } else if !coordinateText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
              isDiscardConfirmationPresented = true
            } else {
              dismiss()
            }
          }
          .accessibilityLabel("Cancel")
          .accessibilityHint("Closes the add coordinate sheet")
        }

        ToolbarItem(placement: .confirmationAction) {
          Button(role: .confirm) {
            if let onSubmitTap {
              onSubmitTap()
            } else if BoundaryCreationViewModel.isValidCoordinateInput(coordinateText) {
              coordinateText = ""
              dismiss()
            } else {
              isInvalidCoordinateAlertPresented = true
            }
          }
          .keyboardShortcut(nil)
          .disabled(!isSubmitEnabled)
          .accessibilityLabel("Add Coordinates")
          .accessibilityHint("Saves the entered boundary coordinates")
        }
      }
      .alert(
        "Discard Changes?",
        isPresented: $isDiscardConfirmationPresented
      ) {
        Button("Continue Editing") {
          isDiscardConfirmationPresented = false
        }
        .keyboardShortcut(.defaultAction)

        Button("Discard", role: .cancel) {
          if let onDiscardConfirm {
            onDiscardConfirm()
          } else {
            coordinateText = ""
            dismiss()
          }
        }
      } message: {
        Text("Your unsaved coordinate will be discarded.")
      }
      .alert(
        "Invalid Coordinate",
        isPresented: $isInvalidCoordinateAlertPresented
      ) {
        Button("OK", role: .cancel) {
          isInvalidCoordinateAlertPresented = false
        }
      } message: {
        Text("Please enter valid latitude and longitude pairs (e.g., -6.215432, 106.845321), one per line.")
      }
    }
  }
}

#Preview("Stacked Sheet") {
  @Previewable @State var isAddSheetPresented = true
  @Previewable @State var coordinateText = ""
  @Previewable @State var isDiscardPresented = false
  @Previewable @State var isInvalidAlertPresented = false

  Text("Map Content")
    .sheet(isPresented: .constant(true)) {
      BoundaryCoordinateSheetView(
        onAddCoordinateTap: {
          isAddSheetPresented = true
        }
      )
      .presentationPlacement(.leading)
      .presentationDetents([BoundaryCreationViewModel.defaultSheetDetent, .medium, .large])
      .presentationDragIndicator(.visible)
      .presentationBackgroundInteraction(.enabled)
      .sheet(isPresented: $isAddSheetPresented) {
        BoundaryAddCoordinateSheetView(
          coordinateText: $coordinateText,
          isDiscardConfirmationPresented: $isDiscardPresented,
          isInvalidCoordinateAlertPresented: $isInvalidAlertPresented
        )
        .presentationPlacement(.leading)
        .presentationDetents([BoundaryCreationViewModel.defaultSheetDetent, .medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackgroundInteraction(.enabled)
        .interactiveDismissDisabled(!coordinateText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      }
    }
}
