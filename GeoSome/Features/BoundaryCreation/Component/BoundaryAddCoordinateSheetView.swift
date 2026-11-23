import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct BoundaryAddCoordinateSheetView: View {
  @Environment(\.dismiss) private var dismiss
  @Binding var zoneText: String
  @Binding var eastingText: String
  @Binding var northingText: String
  @Binding var isDiscardConfirmationPresented: Bool
  @Binding var isInvalidCoordinateAlertPresented: Bool
  var canSubmit: Bool?
  var onCloseTap: (() -> Void)?
  var onDiscardConfirm: (() -> Void)?
  var onSubmitTap: (() -> Void)?

  @Environment(\.colorSchemeContrast) private var contrast
  @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

  init(
    zoneText: Binding<String> = .constant("48S"),
    eastingText: Binding<String> = .constant(""),
    northingText: Binding<String> = .constant(""),
    isDiscardConfirmationPresented: Binding<Bool> = .constant(false),
    isInvalidCoordinateAlertPresented: Binding<Bool> = .constant(false),
    canSubmit: Bool? = nil,
    onCloseTap: (() -> Void)? = nil,
    onDiscardConfirm: (() -> Void)? = nil,
    onSubmitTap: (() -> Void)? = nil
  ) {
    _zoneText = zoneText
    _eastingText = eastingText
    _northingText = northingText
    _isDiscardConfirmationPresented = isDiscardConfirmationPresented
    _isInvalidCoordinateAlertPresented = isInvalidCoordinateAlertPresented
    self.canSubmit = canSubmit
    self.onCloseTap = onCloseTap
    self.onDiscardConfirm = onDiscardConfirm
    self.onSubmitTap = onSubmitTap
  }

  private var isSubmitEnabled: Bool {
    canSubmit ?? (
      !zoneText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
      !eastingText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
      !northingText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    )
  }

  private var hasInput: Bool {
    !eastingText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
    !northingText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  var body: some View {
    NavigationStack {
      VStack(alignment: .leading, spacing: 14) {
        Text("Coordinates")
          .font(.headline.weight(.bold))
          .foregroundStyle(Color.primary)
          .accessibilityAddTraits(.isHeader)

        VStack(spacing: 0) {
          coordinateRow(
            title: "Zone",
            placeholder: "48S",
            text: $zoneText,
            keyboardType: .default,
            autocapitalization: .characters
          )

          Divider().padding(.horizontal, 16)

          coordinateRow(
            title: "Easting (m)",
            placeholder: "702634",
            text: $eastingText,
            keyboardType: .decimalPad,
            autocapitalization: .never
          )

          Divider().padding(.horizontal, 16)

          coordinateRow(
            title: "Northing (m)",
            placeholder: "9309747",
            text: $northingText,
            keyboardType: .decimalPad,
            autocapitalization: .never
          )
        }
        .background(
          RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Color(.secondarySystemGroupedBackground))
        )
        .overlay(
          RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(
              Color.primary.opacity(contrast == .increased ? 0.35 : 0.08),
              lineWidth: contrast == .increased ? 1.5 : 1
            )
        )
        .accessibilityHint("Enter UTM zone, easting, and northing coordinates")

        Spacer()
      }
      .padding(.horizontal, 20)
      .padding(.top, 16)
      .padding(.bottom, 20)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      .navigationTitle("Add Coordinate")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(role: .close) {
            if let onCloseTap {
              onCloseTap()
            } else if hasInput {
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
            } else {
              dismiss()
            }
          }
          .keyboardShortcut(nil)
          .disabled(!isSubmitEnabled)
          .accessibilityLabel("Add Coordinate")
          .accessibilityHint("Saves the entered boundary coordinate")
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
            eastingText = ""
            northingText = ""
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
        Text("Please enter a valid UTM coordinate (e.g., Zone 48S, Easting 702634, Northing 9309747).")
      }
    }
  }

  private func coordinateRow(
    title: String,
    placeholder: String,
    text: Binding<String>,
    keyboardType: UIKeyboardType = .decimalPad,
    autocapitalization: TextInputAutocapitalization = .never
  ) -> some View {
    HStack(spacing: 12) {
      Text(title)
        .font(.body)
        .foregroundStyle(Color.secondary)
        .lineLimit(1)

      Spacer(minLength: 8)

      TextField(placeholder, text: text)
        #if canImport(UIKit)
        .keyboardType(keyboardType)
        #endif
        .font(.body)
        .foregroundStyle(Color.primary)
        .multilineTextAlignment(.trailing)
        .autocorrectionDisabled()
        .textInputAutocapitalization(autocapitalization)
        .frame(maxWidth: 130)
    }
    .padding(.horizontal, 16)
    .frame(height: 52)
  }
}

#Preview("Stacked Sheet") {
  @Previewable @State var isAddSheetPresented = true
  @Previewable @State var zone = "48S"
  @Previewable @State var easting = ""
  @Previewable @State var northing = ""
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
          zoneText: $zone,
          eastingText: $easting,
          northingText: $northing,
          isDiscardConfirmationPresented: $isDiscardPresented,
          isInvalidCoordinateAlertPresented: $isInvalidAlertPresented
        )
        .presentationPlacement(.leading)
        .presentationDetents([BoundaryCreationViewModel.editSheetDetent, .medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackgroundInteraction(.enabled)
        .interactiveDismissDisabled(!easting.isEmpty || !northing.isEmpty)
      }
    }
}
