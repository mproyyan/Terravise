"""V4 multi-scale GSTools pilot. No model training."""
import hashlib
import json
import os
import sys
from dataclasses import asdict
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))

from synthetic3d.v2.core import Grid
from scripts.synthetic_v33 import build_pilot as v33

OUT = ROOT / "data/synthetic3d_v4_gstools/pilot_30"
VERSION = "synthetic-v4-multiscale-pilot-1"

SCENARIOS = [
    ("A", Grid(24, 24, 12, 1, 1, 1)),
    ("B", Grid(24, 24, 12, 5, 5, 1)),
    ("C", Grid(32, 32, 16, 5, 5, 2)),
    ("D", Grid(48, 32, 20, 10, 10, 2)),
    ("E", Grid(40, 40, 24, 25, 25, 2)),
]

SPLITS = {
    "train": 20,
    "validation": 5,
    "test": 5,
}


def write_json(path, obj):
    path.write_text(
        json.dumps(obj, indent=2, allow_nan=False) + "\n"
    )


def sha256(path):
    h = hashlib.sha256()
    with path.open("rb") as f:
        for block in iter(
            lambda: f.read(1024 * 1024), b""
        ):
            h.update(block)
    return h.hexdigest()


def generate_one(split, index, grid):
    # v33.create_volume reads v33.GRID in its
    # generation and validation functions.
    # This adapter is single-threaded.
    old_grid = v33.GRID
    had_shape = hasattr(v33, "SHAPE")
    old_shape = getattr(v33, "SHAPE", None)

    try:
        v33.GRID = grid
        v33.SHAPE = (grid.nx, grid.ny, grid.nz)
        volume, info = v33.create_volume(split, index)
    finally:
        v33.GRID = old_grid

        if had_shape:
            v33.SHAPE = old_shape
        elif hasattr(v33, "SHAPE"):
            delattr(v33, "SHAPE")

    shape = (grid.nx, grid.ny, grid.nz)

    for key in (
        "Ic", "qc_mpa", "fs_mpa",
        "unit_id", "valid_mask"
    ):
        assert volume[key].shape == shape, key

    for key in ("Ic", "qc_mpa", "fs_mpa"):
        assert np.isfinite(volume[key]).all(), key

    metadata = volume["metadata"]
    metadata["dataset_version"] = VERSION
    metadata["multiscale_scenario"] = {
        "grid": asdict(grid),
        "physical_extent_m": [
            grid.nx * grid.dx_m,
            grid.ny * grid.dy_m,
            grid.nz * grid.dz_m,
        ],
        "spacing_is_model_input": False,
        "field_length_scales": (
            "Experimental, inherited from V3.3"
        ),
    }

    return volume, info


def save_volume(path, volume):
    tmp = path.with_suffix(".npz.tmp")
    try:
        with tmp.open("wb") as f:
            np.savez_compressed(
                f,
                Ic=volume["Ic"],
                qc_mpa=volume["qc_mpa"],
                fs_mpa=volume["fs_mpa"],
                unit_id=volume["unit_id"],
                valid_mask=volume["valid_mask"],
                metadata_json=np.asarray(
                    json.dumps(
                        volume["metadata"],
                        allow_nan=False
                    )
                ),
            )
        os.replace(tmp, path)
    finally:
        tmp.unlink(missing_ok=True)


def main():
    if OUT.exists() and any(OUT.iterdir()):
        raise FileExistsError(
            f"Output already contains files: {OUT}"
        )

    OUT.mkdir(parents=True, exist_ok=True)

    write_json(OUT / "config.json", {
        "version": VERSION,
        "splits": SPLITS,
        "scenarios": [
            {
                "id": name,
                "grid": asdict(grid),
            }
            for name, grid in SCENARIOS
        ],
        "generator": (
            "V3.3 GSTools with variable Grid"
        ),
        "limitations": [
            "Experimental geotechnical priors",
            "Not field-calibrated",
            "No model training performed",
            "Not yet validated for large-area ML",
        ],
    })

    train_sum = 0.0
    train_sumsq = 0.0
    train_count = 0
    summary = {"version": VERSION, "splits": {}}

    for split, count in SPLITS.items():
        folder = OUT / split
        folder.mkdir(exist_ok=True)
        manifest = []

        for index in range(count):
            name, grid = SCENARIOS[
                index % len(SCENARIOS)
            ]

            volume, info = generate_one(
                split, index, grid
            )

            filename = (
                f"v4_{split}_{index:05d}.npz"
            )
            path = folder / filename
            save_volume(path, volume)

            ic = volume["Ic"].astype(np.float64)

            if split == "train":
                train_sum += float(ic.sum())
                train_sumsq += float(
                    np.square(ic).sum()
                )
                train_count += ic.size

            manifest.append({
                "path": f"{split}/{filename}",
                "scenario": name,
                "grid": asdict(grid),
                "seed": info["seed"],
                "config": info["config"],
                "family": info["family"],
                "n_layers": info["n_layers"],
                "attempt": info["attempt"],
                "ic_mean": float(ic.mean()),
                "ic_std": float(ic.std()),
                "sha256": sha256(path),
            })

            print(
                f"{split} {index + 1}/{count}"
                f" | scenario={name}"
                f" | shape={ic.shape}"
                f" | mean={ic.mean():.5f}",
                flush=True,
            )

        manifest_file = OUT / (
            f"{split}_manifest.json"
        )
        write_json(manifest_file, manifest)

        summary["splits"][split] = {
            "volumes": len(manifest),
            "manifest_sha256": sha256(manifest_file),
        }

    mean = train_sum / train_count
    std = float(np.sqrt(max(
        train_sumsq / train_count - mean**2,
        0.0,
    )))

    if not np.isfinite(std) or std <= 1e-9:
        raise ValueError("Invalid normalization")

    norm = {
        "mean": float(mean),
        "std": std,
        "count": int(train_count),
        "source_split": "train",
        "field": "Ic",
        "method": "pooled training voxels",
    }

    write_json(OUT / "normalization.json", norm)
    summary["normalization"] = norm
    write_json(OUT / "summary.json", summary)

    print("\n===== V4 MULTISCALE PILOT =====")
    print("Total volumes:", sum(SPLITS.values()))
    print("Normalization:", norm)
    print("Output:", OUT)
    print("Training: NOT RUN")


if __name__ == "__main__":
    main()
