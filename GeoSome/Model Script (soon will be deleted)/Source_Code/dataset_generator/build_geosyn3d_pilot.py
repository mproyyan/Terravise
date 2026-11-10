"""Experimental 3D adaptation of GeoSyn's layered Ic random fields."""
import json
import hashlib
from pathlib import Path

import numpy as np
import gstools as gs

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "data/synthetic3d_v4_geosyn/pilot_15"

# Reference Ic ranges from GeoSyn soil_types.py.
MATERIALS = {
    "clay": (2.95, 3.60),
    "siltmix": (2.60, 2.95),
    "sandmix": (2.05, 2.60),
    "sand": (1.31, 2.05),
    "organic": (3.60, 4.20),
}

SCENARIOS = [
    ("A", (24, 24, 12), (1., 1., 1.)),
    ("B", (24, 24, 12), (5., 5., 1.)),
    ("C", (32, 32, 16), (5., 5., 2.)),
    ("D", (48, 32, 20), (10., 10., 2.)),
    ("E", (40, 40, 24), (25., 25., 2.)),
]

FAMILIES = ("horizontal", "inclined", "undulating")


def make_volume(shape, spacing, family, seed):
    rng = np.random.default_rng(seed)
    nx, ny, nz = shape
    dx, dy, dz = spacing
    extent = np.array(shape) * np.array(spacing)

    x = (np.arange(nx) + .5) * dx
    y = (np.arange(ny) + .5) * dy
    z = (np.arange(nz) + .5) * dz

    xx, yy = np.meshgrid(x, y, indexing="ij")
    width, height, depth = extent

    # GeoSyn-inspired sinusoidal boundaries extended
    # to two horizontal dimensions.
    boundaries = []
    parameters = []

    for k in range(3):
        center = depth * (k + 1) / 4
        phase = float(rng.uniform(0, 2 * np.pi))
        amplitude = float(rng.uniform(.01, .04) * depth)
        period_x = float(rng.uniform(.6, 1.8) * width)
        period_y = float(rng.uniform(.6, 1.8) * height)

        surface = np.full((nx, ny), center)

        if family == "inclined":
            sx = rng.uniform(-.06, .06) * depth
            sy = rng.uniform(-.06, .06) * depth
            surface += sx * (xx / width - .5)
            surface += sy * (yy / height - .5)

        elif family == "undulating":
            surface += amplitude * np.sin(
                2 * np.pi * xx / period_x + phase
            ) * np.cos(
                2 * np.pi * yy / period_y + phase
            )

        parameters.append({
            "center_depth_m": float(center),
            "amplitude_m": amplitude,
            "period_x_m": period_x,
            "period_y_m": period_y,
            "phase_rad": phase,
        })

        boundaries.append(surface)

    # Maintain ordered layers and minimum thickness
    # at each horizontal location.
    boundaries = np.sort(np.stack(boundaries), axis=0)
    min_gap = min(depth / 20, dz / 2)

    for k in range(1, len(boundaries)):
        boundaries[k] = np.maximum(
            boundaries[k], boundaries[k-1] + min_gap
        )

    if np.any(boundaries[-1] >= depth):
        raise ValueError("Boundary exceeds domain")

    zz = z[None, None, :]
    unit = np.zeros(shape, dtype=np.int16)

    for boundary in boundaries:
        unit += (zz >= boundary[:, :, None])

    ic = np.empty(shape, dtype=np.float32)
    layer_meta = []

    choices = list(MATERIALS)

    for k in range(4):
        material = choices[int(rng.integers(len(choices)))]
        lo, hi = MATERIALS[material]

        mean = (lo + hi) / 2
        sd = (hi - lo) / 6

        # Experimental physically dimensioned covariance.
        lx = float(rng.uniform(3, 80))
        ly = float(rng.uniform(3, 80))
        lz = float(rng.uniform(.2, 3))

        covariance = gs.Gaussian(
            dim=3,
            var=sd**2,
            len_scale=[lx, ly, lz],
        )

        rf_seed = int(rng.integers(0, 2**32 - 1))
        field = gs.SRF(
            covariance, mean=mean, seed=rf_seed
        ).structured([x, y, z])

        mask = unit == k
        ic[mask] = np.asarray(field)[mask]

        layer_meta.append({
            "unit": k,
            "material": material,
            "mean_ic": mean,
            "std_ic": sd,
            "length_scale_m": [lx, ly, lz],
            "rf_seed": rf_seed,
        })

    if not np.isfinite(ic).all():
        raise ValueError("Invalid Ic values")

    metadata = {
        "generator": "GeoSyn-inspired 3D experimental adaptation",
        "reference_commit": (
            "253b9bcad7b7dcddcb9099e2fb1860f8d0026e5c"
        ),
        "gstools_version": gs.__version__,
        "grid": {
            "nx": nx, "ny": ny, "nz": nz,
            "dx_m": dx, "dy_m": dy, "dz_m": dz,
        },
        "family": family,
        "seed": seed,
        "boundaries": parameters,
        "layers": layer_meta,
        "target": "Ic",
        "limitations": [
            "Not identical to original 2D GeoSyn",
            "Synthetic experimental parameters",
            "No qc/fs generation or CPT formula inversion",
            "Not field calibrated",
        ],
    }

    return ic, unit, metadata


def main():
    if OUT.exists() and any(OUT.iterdir()):
        raise FileExistsError(OUT)

    OUT.mkdir(parents=True, exist_ok=True)
    manifest = []

    for scenario, (shape, spacing) in [
        (s[0], (s[1], s[2])) for s in SCENARIOS
    ]:
        for family in FAMILIES:
            key = f"{scenario}|{family}"
            seed = int.from_bytes(
                hashlib.sha256(key.encode()).digest()[:4],
                "little"
            )

            ic, unit, metadata = make_volume(
                shape, spacing, family, seed
            )

            name = f"geosyn3d_{scenario}_{family}.npz"
            path = OUT / name

            np.savez_compressed(
                path,
                Ic=ic,
                unit_id=unit,
                valid_mask=np.ones(shape, dtype=bool),
                metadata_json=np.asarray(
                    json.dumps(metadata)
                ),
            )

            manifest.append({
                "file": name,
                "scenario": scenario,
                "family": family,
                "shape": shape,
                "spacing_m": spacing,
                "mean_ic": float(ic.mean()),
                "std_ic": float(ic.std()),
            })

            print(
                scenario, family, shape,
                f"mean={ic.mean():.4f}",
                flush=True
            )

    (OUT / "manifest.json").write_text(
        json.dumps(manifest, indent=2)
    )
    print("\nGEOSYN 3D PILOT:", len(manifest), "volumes")


if __name__ == "__main__":
    main()
