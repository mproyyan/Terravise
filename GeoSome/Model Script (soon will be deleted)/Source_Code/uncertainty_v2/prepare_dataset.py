from pathlib import Path

import numpy as np
import pandas as pd
from scipy.ndimage import distance_transform_edt

from dqn3d.v44.runner import _entries, _case
from dqn3d.v45.adapter import FrozenV4Reconstructor

ROOT = Path("data/synthetic3d_v4_geosyn/full_24k")
OUT = Path("results/uncertainty_v2")
OUT.mkdir(parents=True, exist_ok=True)

SPLITS = {
    "train": range(164, 176),
    "calibration": range(176, 182),
    "evaluation": range(182, 188),
}

CPT_COUNTS = [1, 3, 8]
SAMPLES_PER_SCENARIO = 1024

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

recon = FrozenV4Reconstructor(
    "model_export/SchemaGAN_V4_2/SchemaGAN_V4_2.pt",
    normalization_path=(
        "model_export/SchemaGAN_V4_2/normalization.json"
    ),
    device="cpu",
)

entries = _entries(ROOT, "validation", 188)
assert len(entries) >= 188

print("===== UNCERTAINTY V2 DATASET GENERATION =====")
print("Features:", len(FEATURES), flush=True)

for split, indices in SPLITS.items():
    records = []

    for volume_index in indices:
        truth, valid, grid = _case(
            ROOT, entries[volume_index]
        )

        truth = np.asarray(truth, dtype=np.float32)
        valid = np.asarray(valid, dtype=bool)

        assert truth.shape == valid.shape
        assert np.isfinite(truth[valid]).all()

        dx = float(grid.dx_m)
        dy = float(grid.dy_m)
        dz = float(grid.dz_m)

        assert min(dx, dy, dz) > 0

        nx, ny, nz = truth.shape
        assert min(nx, ny, nz) >= 2

        sites = np.argwhere(valid.any(axis=2))
        assert len(sites) >= max(CPT_COUNTS)

        rng = np.random.default_rng(
            2026 + volume_index
        )

        site_order = rng.permutation(len(sites))

        for n_cpt in CPT_COUNTS:
            chosen = sites[site_order[:n_cpt]]

            observed = np.zeros_like(valid, dtype=bool)
            observed[
                chosen[:, 0], chosen[:, 1], :
            ] = valid[
                chosen[:, 0], chosen[:, 1], :
            ]

            sparse = np.where(
                observed, truth, 0
            ).astype(np.float32)

            prediction, _ = recon.predict(
                sparse, observed, valid, grid
            )

            prediction = np.asarray(
                prediction, dtype=np.float32
            )

            assert prediction.shape == truth.shape
            assert np.isfinite(prediction[valid]).all()

            measured_xy = observed.any(axis=2)

            distance_xy = distance_transform_edt(
                ~measured_xy,
                sampling=(dx, dy),
            )

            grad_x, grad_y, grad_z = np.gradient(
                prediction, dx, dy, dz
            )

            lateral_gradient = np.sqrt(
                grad_x ** 2 + grad_y ** 2
            )

            vertical_gradient = np.abs(grad_z)

            x_m = np.arange(nx) * dx
            y_m = np.arange(ny) * dy

            xx, yy = np.meshgrid(
                x_m, y_m, indexing="ij"
            )

            nearby_count = np.zeros(
                (nx, ny), dtype=np.float32
            )

            for x, y in chosen:
                distance_to_site = np.sqrt(
                    (xx - x * dx) ** 2 +
                    (yy - y * dy) ** 2
                )

                nearby_count += (
                    distance_to_site <= 25.0
                ).astype(np.float32)

            nearby_fraction = (
                nearby_count / float(n_cpt)
            )

            hidden_coords = np.argwhere(
                valid & ~observed
            )

            assert len(hidden_coords) > 0

            sample_indices = rng.choice(
                len(hidden_coords),
                size=min(
                    SAMPLES_PER_SCENARIO,
                    len(hidden_coords)
                ),
                replace=False,
            )

            selected = hidden_coords[sample_indices]

            x = selected[:, 0]
            y = selected[:, 1]
            z = selected[:, 2]

            error = np.abs(
                prediction[x, y, z] -
                truth[x, y, z]
            )

            frame = pd.DataFrame({
                "volume_index": volume_index,
                "n_cpt": n_cpt,
                "distance_to_cpt_m": distance_xy[x, y],
                "depth_m": z * dz,
                "predicted_ic": prediction[x, y, z],
                "lateral_gradient": lateral_gradient[x, y, z],
                "vertical_gradient": vertical_gradient[x, y, z],
                "nearby_cpt_fraction_25m": nearby_fraction[x, y],
                "dx_m": dx,
                "dy_m": dy,
                "dz_m": dz,
                "abs_error_ic": error,
            })

            assert np.isfinite(
                frame[FEATURES + ["abs_error_ic"]]
                .to_numpy(dtype=np.float64)
            ).all()

            records.append(frame)

        print(
            f"PASS | {split}"
            f" | volume={volume_index}"
            f" | CPT={CPT_COUNTS}",
            flush=True,
        )

    result = pd.concat(
        records, ignore_index=True
    )

    path = OUT / f"{split}.csv"

    if path.exists():
        raise FileExistsError(
            f"Refusing to overwrite: {path}"
        )

    result.to_csv(path, index=False)

    print(
        f"SAVED | {split}"
        f" | rows={len(result)}"
        f" | volumes={result.volume_index.nunique()}",
        flush=True,
    )

print("\n===== DATASET SUMMARY =====")

for split in SPLITS:
    data = pd.read_csv(
        OUT / f"{split}.csv"
    )

    print(
        split,
        "rows=", len(data),
        "volumes=", data.volume_index.nunique(),
        "mean_abs_error=",
        round(data.abs_error_ic.mean(), 6),
    )

print("STATUS: UNCERTAINTY V2 DATASET READY")
