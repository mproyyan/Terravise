import SwiftUI

struct BoundaryEditCoordinateSheetView: View {
  private enum Field: Hashable {
    case coordinate
    case latitude
    case longitude
  }

  @Environment(\.dismiss) private var dismiss
  var pointTitle: String
  @Binding var coordinateText: String
  @Binding var latitudeText: String
  @Binding var longitudeText: String
  @Binding var isDeleteConfirmationPresented: Bool
  @Binding var isDiscardConfirmationPresented: Bool
  @Binding var isInvalidCoordinateAlertPresented: Bool
  var canSubmit: Bool?
  var onCloseTap: (() -> Void)?
  var onDiscardConfirm: (() -> Void)?
  var onSubmitTap: (() -> Void)?
  var onDeleteTap: (() -> Void)?
  var onDeleteConfirm: (() -> Void)?

  @FocusState private var focusedField: Field?
  @Environment(\.colorSchemeContrast) private var contrast
  @ScaledMetric(relativeTo: .body) private var fieldMinHeight: CGFloat = 46

  init(
    pointTitle: String = "CPT Point 1",
    coordinateText: Binding<String> = .constant(""),
    latitudeText: Binding<String> = .constant("-6.216543"),
    longitudeText: Binding<String> = .constant("106.849876"),
    isDeleteConfirmationPresented: Binding<Bool> = .constant(false),
    isDiscardConfirmationPresented: Binding<Bool> = .constant(false),
    isInvalidCoordinateAlertPresented: Binding<Bool> = .constant(false),
    canSubmit: Bool? = nil,
    onCloseTap: (() -> Void)? = nil,
    onDiscardConfirm: (() -> Void)? = nil,
    onSubmitTap: (() -> Void)? = nil,
    onDeleteTap: (() -> Void)? = nil,
    onDeleteConfirm: (() -> Void)? = nil
  ) {
    self.pointTitle = pointTitle
    _coordinateText = coordinateText
    _latitudeText = latitudeText
    _longitudeText = longitudeText
    _isDeleteConfirmationPresented = isDeleteConfirmationPresented
    _isDiscardConfirmationPresented = isDiscardConfirmationPresented
    _isInvalidCoordinateAlertPresented = isInvalidCoordinateAlertPresented
    self.canSubmit = canSubmit
    self.onCloseTap = onCloseTap
    self.onDiscardConfirm = onDiscardConfirm
    self.onSubmitTap = onSubmitTap
    self.onDeleteTap = onDeleteTap
    self.onDeleteConfirm = onDeleteConfirm
  }

  private var isSubmitEnabled: Bool {
    canSubmit ?? (
      !coordinateText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
      (!latitudeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !longitudeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    )
  }

  var body: some View {
    NavigationStack {
      ScrollView(.vertical, showsIndicators: false) {
        VStack(alignment: .leading, spacing: 14) {
          VStack(alignment: .leading, spacing: 10) {
            Text(pointTitle)
              .font(.headline)
              .foregroundStyle(.primary)
              .accessibilityAddTraits(.isHeader)

            Divider()
          }

          VStack(alignment: .leading, spacing: 8) {
            Text("Coordinate")
              .font(.subheadline.weight(.semibold))
              .foregroundStyle(.primary)

            Label("Format: UTM (e.g. 48S 702634 E, 9309747 N) or lat, lon", systemImage: "info.circle")
              .font(.caption)
              .foregroundStyle(contrast == .increased ? .primary : .secondary)
              .fixedSize(horizontal: false, vertical: true)

            TextField("e.g., 48S 702634 E, 9309747 N", text: $coordinateText)
              .font(.body)
              .foregroundStyle(.primary)
              .keyboardType(.numbersAndPunctuation)
              .autocorrectionDisabled()
              .textInputAutocapitalization(.never)
              .focused($focusedField, equals: .coordinate)
              .padding(.horizontal, 16)
              .padding(.vertical, 8)
              .frame(minHeight: max(fieldMinHeight, 44))
              .background(
                Capsule(style: .continuous)
                  .fill(Color(.secondarySystemGroupedBackground))
              )
              .overlay(
                Capsule(style: .continuous)
                  .stroke(
                    Color.primary.opacity(contrast == .increased ? 0.45 : 0.14),
                    lineWidth: contrast == .increased ? 1.5 : 1
                  )
              )
              .contentShape(Capsule(style: .continuous))
              .onTapGesture {
                focusedField = .coordinate
              }
              .accessibilityLabel("Coordinate")
              .accessibilityHint("Enter UTM coordinates or latitude and longitude")
          }

          Spacer(minLength: 4)

          Button(role: .destructive) {
            focusedField = nil
            if let onDeleteTap {
              onDeleteTap()
            } else {
              isDeleteConfirmationPresented = true
            }
          } label: {
            Label("Delete Point", systemImage: "trash")
              .font(.body.weight(.medium))
              .frame(maxWidth: .infinity)
          }
          .buttonStyle(.bordered)
          .buttonBorderShape(.capsule)
          .controlSize(.large)
          .tint(.red)
          .frame(minHeight: 44)
          .accessibilityLabel("Delete Point")
          .accessibilityHint("Deletes \(pointTitle) from the boundary")
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 16)
      }
      .scrollBounceBehavior(.basedOnSize)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      .navigationTitle("Edit Coordinate")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(role: .close) {
            focusedField = nil
            if let onCloseTap {
              onCloseTap()
            } else {
              dismiss()
            }
          }
          .accessibilityLabel("Cancel")
          .accessibilityHint("Closes the edit coordinate sheet")
        }

        ToolbarItem(placement: .confirmationAction) {
          Button(role: .confirm) {
            focusedField = nil
            if let onSubmitTap {
              onSubmitTap()
            } else if !coordinateText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
              dismiss()
            } else if BoundaryCreationViewModel.parseCoordinatePair(
              latitudeText: latitudeText,
              longitudeText: longitudeText
            ) != nil {
              dismiss()
            } else {
              isInvalidCoordinateAlertPresented = true
            }
          }
          .keyboardShortcut(nil)
          .disabled(!isSubmitEnabled)
          .accessibilityLabel("Save Coordinate")
          .accessibilityHint("Saves changes to \(pointTitle)")
        }
      }
      .alert(
        "Delete Point?",
        isPresented: $isDeleteConfirmationPresented
      ) {
        Button("Delete Point", role: .destructive) {
          if let onDeleteConfirm {
            onDeleteConfirm()
          } else {
            dismiss()
          }
        }
        .keyboardShortcut(.defaultAction)

        Button("Cancel", role: .cancel) {
          isDeleteConfirmationPresented = false
        }
      } message: {
        Text("\(pointTitle) will be permanently deleted from this project.\n\nThis action can’t be undone.")
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
        Text("Please enter a valid UTM coordinate (e.g. 48S 702634 E, 9309747 N) or latitude and longitude values.")
      }
    }
  }
}

#Preview("Edit Coordinate Sheet") {
  @Previewable @State var coordinateText = "48S 702634 E, 9309747 N"
  @Previewable @State var latitudeText = "-6.216543"
  @Previewable @State var longitudeText = "106.849876"
  @Previewable @State var isDeletePresented = false
  @Previewable @State var isDiscardPresented = false
  @Previewable @State var isInvalidPresented = false

  Text("Map Content")
    .sheet(isPresented: .constant(true)) {
      BoundaryCoordinateSheetView()
        .presentationPlacement(.leading)
        .presentationDetents([BoundaryCreationViewModel.populatedSheetDetent, .medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackgroundInteraction(.enabled)
        .sheet(isPresented: .constant(true)) {
          BoundaryEditCoordinateSheetView(
            pointTitle: "CPT Point 4",
            coordinateText: $coordinateText,
            latitudeText: $latitudeText,
            longitudeText: $longitudeText,
            isDeleteConfirmationPresented: $isDeletePresented,
            isDiscardConfirmationPresented: $isDiscardPresented,
            isInvalidCoordinateAlertPresented: $isInvalidPresented
          )
          .presentationPlacement(.leading)
          .presentationDetents([BoundaryCreationViewModel.editSheetDetent, .medium, .large])
          .presentationDragIndicator(.visible)
          .presentationBackgroundInteraction(.enabled)
        }
    }
}
