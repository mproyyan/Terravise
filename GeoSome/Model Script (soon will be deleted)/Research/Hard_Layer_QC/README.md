# Hard Layer / QC Reconstruction Research

## Goal

Enable hard-layer indication across the reconstructed 3D area, not only at measured CPT locations.

Current SchemaGAN V4.2 reconstructs Ic only. Therefore a separate QC Reconstruction model is being investigated while keeping the frozen Ic reconstruction pipeline unchanged.

## Measured CPT input

The iOS application accepts:

- depth_m
- qc_mpa
- fs_kpa
- u2_kpa (optional)

Hard-layer indication can therefore already be evaluated directly at measured CPT locations.

## Experimental hard-layer criterion

Current PoC criterion:

- qc >= 19.613 MPa
- continuous interval >= 0.50 m

This criterion is experimental/configurable and is NOT a validated foundation-design parameter.

## Real CPT evaluation

USGS CPT dataset:

- 1,819 usable CPT profiles evaluated

Sensitivity results are stored in:

`results/criterion_sensitivity.csv`

For the current candidate:

- qc threshold: 19.613 MPa
- minimum continuous thickness: 0.50 m
- detected: 903 / 1,819 CPT
- detection rate: 49.6%
- median candidate depth: 8.50 m
- P25: 4.70 m
- P75: 12.57 m

USGS metadata does not provide hard-layer/refusal ground truth, so this is an indication criterion only.

## QC reconstruction dataset investigation

Existing V3.2 pilot:

- 1,200 volumes
- grid: 24 x 24 x 12
- resolution: 1 x 1 x 1 m
- fields include Ic, qc_mpa, fs_mpa

High-qc availability at qc >= 19.613 MPa:

- high-qc voxels: 0.3941%
- volumes containing high qc: 50.58%
- XY columns containing high qc: 3.2811%

The 1 m vertical resolution is insufficient to properly represent the current 0.50 m continuous hard-layer criterion.

## QC Reconstruction V1 pilot

A new experimental pilot was generated with:

- grid: 24 x 24 x 24
- resolution: 1 x 1 x 0.5 m
- physical domain: 24 x 24 x 12 m
- train: 80 volumes
- validation: 10 volumes
- test: 10 volumes
- total: 100 volumes
- fields: Ic, qc_mpa, fs_mpa, unit_id, valid_mask

Generated NPZ data is intentionally not stored in Git.

## Current architecture direction

Frozen existing pipeline:

Measured sparse CPT
-> SchemaGAN V4.2
-> Ic 3D

Experimental additional pipeline:

Measured sparse qc
-> QC Reconstruction V1
-> qc 3D
-> predicted vertical qc profile at arbitrary XY
-> hard-layer indication

SchemaGAN V4.2, DQN V4.6-A, Coverage V1 and Uncertainty V3 remain unchanged.

## Important limitation

Synthetic QC generation uses experimental geotechnical priors and is not field calibrated. QC Reconstruction V1 must be independently evaluated before being used for hard-layer indication across reconstructed areas.
