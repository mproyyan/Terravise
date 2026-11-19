import SwiftUI

struct BoundaryCoordinateSheetView: View {
  @Binding var isTooltipVisible: Bool
  var points: [BoundaryPoint]
  var boundaryPointsText: String
  var areaPrimaryText: String
  var areaSecondaryText: String
  var onHelpTap: (() -> Void)?
  var onAddCoordinateTap: (() -> Void)?
  var onSelectPoint: ((BoundaryPoint) -> Void)?
  var onDeletePoint: ((BoundaryPoint.ID) -> Void)?

  @Environment(\.colorSchemeContrast) private var contrast
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
  @ScaledMetric(relativeTo: .caption) private var indexBadgeSize: CGFloat = 24
  @AccessibilityFocusState private var isHelpButtonFocused: Bool

  init(
    isTooltipVisible: Binding<Bool> = .constant(false),
    points: [BoundaryPoint] = [],
    boundaryPointsText: String = "0 point",
    areaPrimaryText: String = "0 m²",
    areaSecondaryText: String = "0 ha",
    onHelpTap: (() -> Void)? = nil,
    onAddCoordinateTap: (() -> Void)? = nil,
    onSelectPoint: ((BoundaryPoint) -> Void)? = nil,
    onDeletePoint: ((BoundaryPoint.ID) -> Void)? = nil
  ) {
    _isTooltipVisible = isTooltipVisible
    self.points = points
    self.boundaryPointsText = boundaryPointsText
    self.areaPrimaryText = areaPrimaryText
    self.areaSecondaryText = areaSecondaryText
    self.onHelpTap = onHelpTap
    self.onAddCoordinateTap = onAddCoordinateTap
    self.onSelectPoint = onSelectPoint
    self.onDeletePoint = onDeletePoint
  }

  private var showsSummarySection: Bool {
    points.count >= 3
  }

  private var remainingPointsNeeded: Int {
    max(0, 3 - points.count)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      if showsSummarySection {
        summarySection
          .padding(.horizontal, 20)
          .padding(.top, 20)
      }

      headerSection
        .padding(.horizontal, 20)
        .padding(.top, showsSummarySection ? 2 : 16)

      if !points.isEmpty, !showsSummarySection {
        incompleteBoundaryNotice
          .padding(.horizontal, 20)
      }

      if points.isEmpty {
        ScrollView(.vertical, showsIndicators: false) {
          VStack(spacing: 16) {
            emptyStateCard
            addCoordinateButton
          }
          .padding(.horizontal, 20)
          .padding(.bottom, 16)
        }
      } else {
        coordinateListSection
          .padding(.horizontal, 20)

        addCoordinateButton
          .padding(.horizontal, 20)
          .padding(.bottom, 16)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .onChange(of: isTooltipVisible) { wasVisible, isVisible in
      if wasVisible, !isVisible {
        Task { @MainActor in
          try? await Task.sleep(for: .milliseconds(100))
          isHelpButtonFocused = true
        }
      }
    }
  }

  @ViewBuilder
  private var summarySection: some View {
    if dynamicTypeSize.isAccessibilitySize {
      VStack(alignment: .leading, spacing: 10) {
        boundaryPointsSummaryCard
        areaSummaryCard
      }
    } else {
      HStack(spacing: 10) {
        boundaryPointsSummaryCard
        areaSummaryCard
      }
      .fixedSize(horizontal: false, vertical: true)
    }
  }

  private var boundaryPointsSummaryCard: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 4) {
        Image(systemName: "checkmark.circle.fill")
          .font(.caption.weight(.semibold))
          .foregroundStyle(contrast == .increased ? Color.primary : Color.green)
        Text("Boundary Points")
          .font(.caption.weight(.semibold))
          .foregroundStyle(contrast == .increased ? .primary : .secondary)
      }

      Text(boundaryPointsText)
        .font(.title3.weight(.bold))
        .foregroundStyle(.primary)
        .fixedSize(horizontal: false, vertical: true)

      Spacer(minLength: 0)
    }
    .padding(14)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(
      RoundedRectangle(cornerRadius: 18, style: .continuous)
        .fill(Color(.secondarySystemGroupedBackground))
    )
    .overlay(
      RoundedRectangle(cornerRadius: 18, style: .continuous)
        .stroke(
          Color.primary.opacity(contrast == .increased ? 0.35 : 0.08),
          lineWidth: contrast == .increased ? 1.5 : 1
        )
    )
    .accessibilityElement(children: .combine)
    .accessibilityLabel("Boundary Points")
    .accessibilityValue("\(boundaryPointsText), valid boundary")
  }

  private var areaSummaryCard: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text("Area")
        .font(.caption.weight(.semibold))
        .foregroundStyle(contrast == .increased ? .primary : .secondary)

      Text(areaPrimaryText)
        .font(.title3.weight(.bold))
        .foregroundStyle(.primary)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.top, 4)

      Text(areaSecondaryText)
        .font(.caption)
        .foregroundStyle(contrast == .increased ? .primary : .secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding(14)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(
      RoundedRectangle(cornerRadius: 18, style: .continuous)
        .fill(Color(.secondarySystemGroupedBackground))
    )
    .overlay(
      RoundedRectangle(cornerRadius: 18, style: .continuous)
        .stroke(
          Color.primary.opacity(contrast == .increased ? 0.35 : 0.08),
          lineWidth: contrast == .increased ? 1.5 : 1
        )
    )
    .accessibilityElement(children: .combine)
    .accessibilityLabel("Area")
    .accessibilityValue("\(areaPrimaryText), \(areaSecondaryText)")
  }

  private var incompleteBoundaryNotice: some View {
    Label(
      "Add \(remainingPointsNeeded) more \(remainingPointsNeeded == 1 ? "point" : "points") to complete boundary (minimum 3)",
      systemImage: "exclamationmark.triangle.fill"
    )
    .font(.caption.weight(.medium))
    .foregroundStyle(contrast == .increased ? .primary : .secondary)
    .fixedSize(horizontal: false, vertical: true)
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .fill(Color(.secondarySystemGroupedBackground))
    )
    .overlay(
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .stroke(
          Color.primary.opacity(contrast == .increased ? 0.35 : 0.1),
          lineWidth: 1
        )
    )
    .accessibilityElement(children: .combine)
  }

  private var headerSection: some View {
    HStack {
      Text("Boundary Coordinate")
        .font(.headline)
        .foregroundStyle(.primary)
        .accessibilityAddTraits(.isHeader)

      Spacer()

      if !showsSummarySection {
        Button(action: {
          if let onHelpTap {
            onHelpTap()
          } else {
            isTooltipVisible.toggle()
          }
        }) {
          Image(systemName: "questionmark.circle")
            .font(.title3)
            .foregroundStyle(contrast == .increased ? .primary : .secondary)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityFocused($isHelpButtonFocused)
        .accessibilityLabel("Help on boundary coordinates")
        .accessibilityHint("Shows instructions for adding boundary points")
        .accessibilityInputLabels(["Help", "Boundary Help", "Instructions"])
        .popover(isPresented: $isTooltipVisible, arrowEdge: .bottom) {
          BoundaryTooltipView()
        }
      }
    }
  }

  private var emptyStateCard: some View {
    VStack(spacing: 6) {
      Text("Add boundary points")
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.primary)

      Text("Tap the map or Add Coordinate to place points.\nYou need at least 3 to create a boundary.")
        .font(.footnote)
        .foregroundStyle(contrast == .increased ? .primary : .secondary)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 20)
    .padding(.horizontal, 16)
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
    .accessibilityElement(children: .combine)
    .accessibilityLabel("Add boundary points. Tap the map or Add Coordinate to place points. You need at least 3 to create a boundary.")
  }

  private var coordinateListSection: some View {
    let badgeDim = max(indexBadgeSize, 22)
    return List {
      ForEach(Array(points.enumerated()), id: \.element.id) { index, point in
        Button {
          onSelectPoint?(point)
        } label: {
          HStack(spacing: 12) {
            Text("\(index + 1)")
              .font(.caption.weight(.semibold))
              .foregroundStyle(.white)
              .padding(2)
              .frame(minWidth: badgeDim, minHeight: badgeDim)
              .background(Circle().fill(.blue))
              .overlay(
                Circle()
                  .stroke(.white.opacity(contrast == .increased ? 0.9 : 0), lineWidth: 1.5)
              )

            VStack(alignment: .leading, spacing: 2) {
              if differentiateWithoutColor {
                Text("CPT Point \(index + 1)")
                  .font(.caption2.weight(.semibold))
                  .foregroundStyle(contrast == .increased ? .primary : .secondary)
              }

              Text(point.formattedCoordinate)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                .fixedSize(horizontal: false, vertical: dynamicTypeSize.isAccessibilitySize)
            }

            Spacer()

            Image(systemName: "chevron.right")
              .font(.caption.weight(.semibold))
              .foregroundStyle(contrast == .increased ? .primary : .secondary)
              .accessibilityHidden(true)
          }
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(Color(.secondarySystemGroupedBackground))
        .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
        .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
        .id(point.id)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("CPT Point \(index + 1)")
        .accessibilityValue(point.formattedCoordinate)
        .accessibilityHint("Opens coordinate editor for this point")
        .accessibilityInputLabels(["Point \(index + 1)", "CPT Point \(index + 1)", "Edit Point \(index + 1)"])
        .accessibilityAction(named: "Delete Point") {
          onDeletePoint?(point.id)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
          if let onDeletePoint {
            Button(role: .destructive) {
              onDeletePoint(point.id)
            } label: {
              Label("Delete", systemImage: "trash")
            }
          }
        }
      }
    }
    .listStyle(.plain)
    .scrollContentBackground(.hidden)
    .background(
      RoundedRectangle(cornerRadius: 20, style: .continuous)
        .fill(Color(.secondarySystemGroupedBackground))
    )
    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 20, style: .continuous)
        .stroke(
          Color.primary.opacity(contrast == .increased ? 0.35 : 0.08),
          lineWidth: contrast == .increased ? 1.5 : 1
        )
    )
    .accessibilityRotor("Boundary Points") {
      ForEach(Array(points.enumerated()), id: \.element.id) { index, point in
        AccessibilityRotorEntry("CPT Point \(index + 1)", id: point.id)
      }
    }
  }

  private var addCoordinateButton: some View {
    Button(action: {
      onAddCoordinateTap?()
    }) {
      Label("Add Coordinate", systemImage: "plus")
        .font(.body.weight(.semibold))
        .frame(maxWidth: .infinity)
    }
    .buttonStyle(.bordered)
    .buttonBorderShape(.roundedRectangle(radius: 18))
    .controlSize(.large)
    .tint(.blue)
    .frame(minHeight: 44)
    .accessibilityLabel("Add Coordinate")
    .accessibilityHint("Adds a new boundary coordinate point")
    .accessibilityInputLabels(["Add Coordinate", "Add Point", "New Coordinate"])
  }
}

#Preview("Empty State") {
  @Previewable @State var selectedDetent: PresentationDetent = BoundaryCreationViewModel.defaultSheetDetent

  Text("Map Content")
    .sheet(isPresented: .constant(true)) {
      BoundaryCoordinateSheetView()
        .presentationPlacement(.leading)
        .presentationDetents(
          [
            BoundaryCreationViewModel.collapsedSheetDetent,
            BoundaryCreationViewModel.defaultSheetDetent,
            BoundaryCreationViewModel.populatedSheetDetent,
            .medium,
            .large
          ],
          selection: $selectedDetent
        )
        .presentationDragIndicator(.visible)
        .presentationBackgroundInteraction(.enabled)
        .presentationContentInteraction(.scrolls)
        .interactiveDismissDisabled()
    }
}

#Preview("3+ Coordinates") {
  @Previewable @State var selectedDetent: PresentationDetent = BoundaryCreationViewModel.populatedSheetDetent
  @Previewable @State var samplePoints = [
    BoundaryPoint(latitude: -6.215432, longitude: 106.845321),
    BoundaryPoint(latitude: -6.216543, longitude: 106.849876),
    BoundaryPoint(latitude: -6.218123, longitude: 106.842111)
  ]
  @Previewable @State var editingPoint: BoundaryPoint?
  @Previewable @State var editLatText = ""
  @Previewable @State var editLonText = ""
  @Previewable @State var isDeleteAlertPresented = false
  @Previewable @State var isDiscardAlertPresented = false
  @Previewable @State var isInvalidAlertPresented = false

  Text("Map Content")
    .sheet(isPresented: .constant(true)) {
      BoundaryCoordinateSheetView(
        points: samplePoints,
        boundaryPointsText: "\(samplePoints.count) \(samplePoints.count == 1 ? "point" : "points")",
        onSelectPoint: { point in
          editLatText = point.formattedLatitude
          editLonText = point.formattedLongitude
          editingPoint = point
        }
      )
      .presentationPlacement(.leading)
      .presentationDetents(
        [
          BoundaryCreationViewModel.collapsedSheetDetent,
          BoundaryCreationViewModel.defaultSheetDetent,
          BoundaryCreationViewModel.populatedSheetDetent,
          .medium,
          .large
        ],
        selection: $selectedDetent
      )
      .presentationDragIndicator(.visible)
      .presentationBackgroundInteraction(.enabled)
      .presentationContentInteraction(.scrolls)
      .interactiveDismissDisabled()
      .sheet(item: $editingPoint) { point in
        let index = samplePoints.firstIndex(where: { $0.id == point.id }) ?? 0
        BoundaryEditCoordinateSheetView(
          pointTitle: "CPT Point \(index + 1)",
          latitudeText: $editLatText,
          longitudeText: $editLonText,
          isDeleteConfirmationPresented: $isDeleteAlertPresented,
          isDiscardConfirmationPresented: $isDiscardAlertPresented,
          isInvalidCoordinateAlertPresented: $isInvalidAlertPresented,
          onSubmitTap: {
            if let coordinate = BoundaryCreationViewModel.parseCoordinatePair(
              latitudeText: editLatText,
              longitudeText: editLonText
            ) {
              samplePoints[index].latitude = coordinate.latitude
              samplePoints[index].longitude = coordinate.longitude
              editingPoint = nil
            } else {
              isInvalidAlertPresented = true
            }
          },
          onDeleteConfirm: {
            samplePoints.removeAll { $0.id == point.id }
            editingPoint = nil
          }
        )
        .presentationPlacement(.leading)
        .presentationDetents([BoundaryCreationViewModel.editSheetDetent, .medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackgroundInteraction(.enabled)
      }
    }
}
