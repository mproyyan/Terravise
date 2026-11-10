from pathlib import Path
import json

import joblib
import numpy as np
from scipy.ndimage import distance_transform_edt

from dqn3d.v44.runner import _entries, _case
from dqn3d.v45.adapter import FrozenV4Reconstructor

ROOT = Path("data/synthetic3d_v4_geosyn/full_24k")
OUT = Path("results/uncertainty_v2/volume_demo")
MODEL_ROOT = Path("results/uncertainty_v2")
OUT.mkdir(parents=True, exist_ok=True)

model = joblib.load(
    MODEL_ROOT / "uncertainty_v2_quantile.joblib"
)
metadata = json.loads(
    (MODEL_ROOT / "model_metadata.json").read_text()
)

FEATURES = [
    "distance_to_cpt_m",
    "depth_m",
    "predicted_ic",
    "lateral_gradient",
    "vertical_gradient",
    "nearby_cpt_fraction_25m",
    "n_cpt",
    "dx_m",
    "dy_m",
    "dz_m",
]

assert metadata["features"] == FEATURES

correction = float(
    metadata["calibration_correction"]
)

recon = FrozenV4Reconstructor(
    "model_export/SchemaGAN_V4_2/SchemaGAN_V4_2.pt",
    normalization_path=(
        "model_export/SchemaGAN_V4_2/normalization.json"
    ),
    device="cpu",
)

# New GeoSyn validation volume, demonstration only.
entries = _entries(ROOT, "validation", 189)
assert len(entries) >= 189

truth, valid, grid = _case(ROOT, entries[188])

truth = np.asarray(truth, dtype=np.float32)
valid = np.asarray(valid, dtype=bool)

nx, ny, nz = truth.shape

dx = float(grid.dx_m)
dy = float(grid.dy_m)
dz = float(grid.dz_m)

assert min(dx, dy, dz) > 0
assert min(nx, ny, nz) >= 2

sites = np.argwhere(valid.any(axis=2))

rng = np.random.default_rng(2026)
chosen_order = rng.permutation(len(sites))

xx, yy = np.meshgrid(
    np.arange(nx) * dx,
    np.arange(ny) * dy,
    indexing="ij"
)

print("===== UNCERTAINTY V2 3D MAP =====")
print("Grid:", truth.shape)
print("Resolution (m):", dx, dy, dz)

for count in [1, 3, 8]:
    assert len(sites) >= count

    chosen = sites[chosen_order[:count]]

    observed = np.zeros_like(valid, dtype=bool)
    observed[
        chosen[:, 0], chosen[:, 1], :
    ] = valid[chosen[:, 0], chosen[:, 1], :]

    sparse = np.where(
        observed, truth, 0
    ).astype(np.float32)

    prediction, _ = recon.predict(
        sparse, observed, valid, grid
    )

    prediction = np.asarray(
        prediction, dtype=np.float32
    )

    measured_xy = observed.any(axis=2)

    distance_xy = distance_transform_edt(
        ~measured_xy,
        sampling=(dx, dy),
    ).astype(np.float32)

    grad_x, grad_y, grad_z = np.gradient(
        prediction, dx, dy, dz
    )

    lateral = np.sqrt(
        grad_x ** 2 + grad_y ** 2
    )

    vertical = np.abs(grad_z)

    nearby = np.zeros(
        (nx, ny), dtype=np.float32
    )

    for x, y in chosen:
        distance_to_site = np.sqrt(
            (xx - x * dx) ** 2 +
            (yy - y * dy) ** 2
        )

        nearby += (
            distance_to_site <= 25.0
        ).astype(np.float32)

    nearby /= float(count)

    coords = np.where(valid)
    x, y, z = coords

    X = np.column_stack([
        distance_xy[x, y],
        z * dz,
        prediction[x, y, z],
        lateral[x, y, z],
        vertical[x, y, z],
        nearby[x, y],
        np.full(len(x), count),
        np.full(len(x), dx),
        np.full(len(x), dy),
        np.full(len(x), dz),
    ]).astype(np.float64)

    assert X.shape[1] == len(FEATURES)
    assert np.isfinite(X).all()

    estimated = np.maximum(
        0, model.predict(X)
    ) + correction

    error_map = np.full(
        truth.shape, np.nan, dtype=np.float32
    )

    error_map[x, y, z] = estimated

    # Observed voxels are measured, not reconstructed.
    # Mark them separately rather than claiming that
    # predictive uncertainty is zero everywhere.
    error_map[observed] = np.nan

    output = OUT / f"uncertainty_3d_cpt_{count}.npz"

    if output.exists():
        raise FileExistsError(output)

    np.savez_compressed(
        output,
        predicted_ic_3d=prediction,
        estimated_error_bound_3d=error_map,
        observed_mask=observed,
        valid_mask=valid,
        cpt_xy=chosen.astype(np.int32),
        dx_m=np.float32(dx),
        dy_m=np.float32(dy),
        dz_m=np.float32(dz),
    )

    hidden = valid & ~observed
    values = error_map[hidden]

    assert np.isfinite(values).all()
    assert (values >= 0).all()

    print(
        f"PASS | CPT={count}"
        f" | hidden_voxels={int(hidden.sum())}"
        f" | mean_bound={values.mean():.6f}"
        f" | min={values.min():.6f}"
        f" | max={values.max():.6f}"
    )

    print("Saved:", output)

print("\nSTATUS: UNCERTAINTY V2 3D MAP READY")
