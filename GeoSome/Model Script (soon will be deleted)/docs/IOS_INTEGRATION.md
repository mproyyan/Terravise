# CPT3D-67 — iOS Integration Guide

## 1. Purpose

Integrate CPT3D-67 research models into a SwiftUI proof-of-concept application such as Demnas3DMap.

Preserve frozen model parameters and verify output parity with Python.

## 2. Required Model Assets

| Component | Location |
|---|---|
| SchemaGAN V4.2 | `SchemaGAN_V4_2/` |
| DQN V4.6-A | `model_export/DQN_V4_6_A_iOS/` |
| Uncertainty V3.1 | `model_export/Uncertainty_V3_1_iOS/` |
| Sufficiency Gate V2.1 | `model_export/SufficiencyGate_V2_1/` |

Inspect each model manifest and input/output contract before integration.

## 3. Integration Workflow

### Step A — Input CPT

1. Receive CPT measurements and XY coordinates.
2. Prepare grid, physical resolution, and observation masks.
3. Convert measured profiles into SchemaGAN input.
4. Support input starting from 1 CPT.

### Step B — SchemaGAN V4.2

1. Load the frozen Core ML reconstruction model.
2. Apply the exported normalization.
3. Reconstruct the 3D Ic volume.
4. Validate spatial orientation, tensor dimensions, and CPT preservation.

### Step C — Uncertainty

1. Obtain the Ic reconstruction.
2. Compute uncertainty input features.
3. Run the compatible uncertainty model.
4. Produce predicted coverage and estimated error bounds.

**Important:** Gate V2.1 was evaluated with Uncertainty V3 quantile features. The existing V3.1 iOS export must be verified for compatibility before integration.

### Step D — Sufficiency Gate V2.1

Use these six features in the exact order:

1. `predicted_coverage`
2. `n_cpt`
3. `estimated_mean_bound`
4. `estimated_p90_bound`
5. `delta_predicted`
6. `delta_p90`

Delta features are calculated relative to the previous CPT state. Set both deltas to zero for the first CPT.

Load numerical parameters from:

`model_export/SufficiencyGate_V2_1/gate_v21_swift_parameters.json`

Probability calculation:

    scaled = (features - scaler.mean) / scaler.scale
    z = dot(scaled, classifier.coef) + classifier.intercept
    p_raw = sigmoid(z)
    p_clipped = clip(p_raw, 1e-6, 1 - 1e-6)
    platt_input = logit(p_clipped)
    p_sufficient = sigmoid(platt.coef * platt_input + platt.intercept)

Experimental gate condition:

    n_cpt >= 5 AND p_sufficient >= 0.995

This is a reconstruction sufficiency indicator, not permission to stop actual site investigation.

If input features are invalid or incompatible, report insufficient information instead of generating a probability.

### Step E — DQN V4.6-A

1. Load the Core ML model using its deployment contract.
2. Build the DQN state using reconstruction and measured CPT data.
3. Obtain the next recommended CPT coordinate.
4. Verify the recommendation is within the project boundary.
5. Avoid duplicate CPT coordinates and apply the configured minimum separation policy.
6. Repeat reconstruction and evaluation after new observations.

## 4. Recommended UI States

- `Belum cukup data untuk evaluasi`
- `Investigasi tambahan direkomendasikan`
- `Kriteria rekonstruksi terpenuhi (eksperimental)`

Do not display `Fondasi aman`, `Sudah memenuhi SNI`, or `Investigasi selesai` based solely on model output.

## 5. Required Integration Tests

1. Verify model assets load in iOS.
2. Test CPT counts 1, 4, 5, and 16.
3. Verify SchemaGAN reconstruction orientation.
4. Check CPT preservation.
5. Verify all six gate features and units.
6. Verify the initial delta values are zero.
7. Compare Swift probability with Python reference.
8. Compare STOP decisions around threshold 0.995.
9. Test invalid inputs and unsupported grids.
10. Verify DQN recommendations remain within the project area.

Python/JSON parity passed on 3,200 synthetic states with maximum probability difference 2.22e-16.

Swift parity is not yet verified.

## 6. Current Status

| Component | Status |
|---|---|
| SchemaGAN V4.2 | Frozen |
| DQN V4.6-A | iOS export available |
| Uncertainty V3.1 | Export available; Gate compatibility unverified |
| Sufficiency Gate V2.1 | Experimental frozen |
| Python/JSON parity | Passed |
| Swift runtime parity | Pending |
| Automatic field STOP | Not approved |

## 7. Engineering Limitations

The sufficiency gate evaluates reconstruction objectives using synthetic GeoSyn data.

It does not determine required CPT spacing under SNI 8460:2017, bearing capacity, or foundation safety.

Engineering review and field validation remain necessary.
