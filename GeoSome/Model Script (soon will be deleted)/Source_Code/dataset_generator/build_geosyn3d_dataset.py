"""GeoSyn-inspired V4 dataset production with resume and integrity."""
import argparse
import hashlib
import itertools
import json
import os
from pathlib import Path

import numpy as np

from build_geosyn3d_pilot import (
    SCENARIOS,
    FAMILIES,
    make_volume,
)

VERSION = "v4-geosyn3d-multiscale-1"
COMBINATIONS = list(itertools.product(
    range(len(SCENARIOS)),
    range(len(FAMILIES)),
))
DEFAULT_COUNTS = {
    "train": 16000,
    "validation": 4000,
    "test": 4000,
}


def seed_for(*parts):
    payload = "|".join(map(str, (VERSION, *parts)))
    digest = hashlib.sha256(payload.encode()).digest()
    return int.from_bytes(digest[:4], "little")


def hash_file(path):
    digest = hashlib.sha256()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(1048576), b""):
            digest.update(block)
    return digest.hexdigest()


def atomic_json(path, data):
    tmp = path.with_suffix(path.suffix + ".tmp")
    try:
        tmp.write_text(
            json.dumps(data, indent=2, allow_nan=False)
            + "\n"
        )
        os.replace(tmp, path)
    finally:
        tmp.unlink(missing_ok=True)


def combination_for(split, index):
    block, offset = divmod(index, len(COMBINATIONS))
    rng = np.random.default_rng(
        seed_for("schedule", split, block)
    )
    order = rng.permutation(len(COMBINATIONS))
    return COMBINATIONS[int(order[offset])]


def validate_existing(npz_path, meta_path, expected):
    if not npz_path.exists() or not meta_path.exists():
        if npz_path.exists() or meta_path.exists():
            raise RuntimeError(
                f"Incomplete existing output: {npz_path}"
            )
        return False

    record = json.loads(meta_path.read_text())
    for key, value in expected.items():
        if record.get(key) != value:
            raise RuntimeError(
                f"Manifest mismatch: {npz_path}, key={key}"
            )

    if hash_file(npz_path) != record.get("sha256"):
        raise RuntimeError(
            f"SHA-256 mismatch: {npz_path}"
        )

    with np.load(npz_path, allow_pickle=False) as data:
        if data["Ic"].shape != tuple(expected["shape"]):
            raise RuntimeError(f"Shape mismatch: {npz_path}")
        if not np.isfinite(data["Ic"]).all():
            raise RuntimeError(f"Non-finite Ic: {npz_path}")
        if not data["valid_mask"].all():
            raise RuntimeError(f"Invalid mask: {npz_path}")

    return True


def run(output, counts):
    output.mkdir(parents=True, exist_ok=True)

    config_path = output / "config.json"
    config = {
        "version": VERSION,
        "counts": counts,
        "scenarios": [
            {
                "id": item[0],
                "shape": list(item[1]),
                "spacing_m": list(item[2]),
            }
            for item in SCENARIOS
        ],
        "families": list(FAMILIES),
        "source": "GeoSyn-inspired 3D pilot",
        "target": "Ic",
        "limitations": [
            "Not an exact port of GeoSyn A-F/S",
            "No qc_mpa or fs_mpa generated",
            "Not field-calibrated",
            "Five supported grid configurations",
        ],
    }

    if config_path.exists():
        if json.loads(config_path.read_text()) != config:
            raise RuntimeError(
                "Existing dataset configuration differs. "
                "Use a new --output directory."
            )
    else:
        if any(output.iterdir()):
            raise RuntimeError(
                "Output is nonempty without config.json"
            )
        atomic_json(config_path, config)

    for split, count in counts.items():
        folder = output / split
        folder.mkdir(exist_ok=True)

        records = []
        generated = 0
        resumed = 0

        for index in range(count):
            scenario_index, family_index = combination_for(
                split, index
            )

            scenario, shape, spacing = SCENARIOS[
                scenario_index
            ]
            family = FAMILIES[family_index]
            seed = seed_for("volume", split, index)

            name = f"v4_{split}_{index:05d}"
            npz_path = folder / f"{name}.npz"
            meta_path = folder / f"{name}.json"

            expected = {
                "split": split,
                "index": index,
                "scenario": scenario,
                "family": family,
                "shape": list(shape),
                "spacing_m": list(spacing),
                "seed": seed,
            }

            if validate_existing(
                npz_path, meta_path, expected
            ):
                resumed += 1
                records.append(json.loads(
                    meta_path.read_text()
                ))
                continue

            ic, unit, metadata = make_volume(
                shape, spacing, family, seed
            )

            if ic.shape != tuple(shape):
                raise RuntimeError("Unexpected volume shape")
            if not np.isfinite(ic).all():
                raise RuntimeError("Non-finite Ic")
            if np.any(np.diff(unit, axis=2) < 0):
                raise RuntimeError("Invalid layer ordering")

            metadata.update({
                "dataset_version": VERSION,
                "split": split,
                "index": index,
                "scenario": scenario,
            })

            tmp = folder / f"{name}.npz.tmp"
            try:
                with tmp.open("wb") as file:
                    np.savez_compressed(
                        file,
                        Ic=ic,
                        unit_id=unit,
                        valid_mask=np.ones(
                            shape, dtype=bool
                        ),
                        metadata_json=np.asarray(
                            json.dumps(
                                metadata,
                                allow_nan=False
                            )
                        ),
                    )

                file_hash = hash_file(tmp)
                os.replace(tmp, npz_path)
            finally:
                tmp.unlink(missing_ok=True)

            record = {
                **expected,
                "sha256": file_hash,
                "ic_mean": float(ic.mean()),
                "ic_std": float(ic.std()),
                "ic_min": float(ic.min()),
                "ic_max": float(ic.max()),
                "voxels": int(ic.size),
            }

            atomic_json(meta_path, record)
            records.append(record)
            generated += 1

            print(
                f"{split} {index+1}/{count}"
                f" | {scenario}/{family}"
                f" | mean={ic.mean():.4f}",
                flush=True,
            )

        # Manifests are written only after the split
        # is complete and all existing files verified.
        manifest = output / f"{split}_manifest.json"
        atomic_json(manifest, records)

        print(
            f"{split}: PASS "
            f"total={len(records)} "
            f"new={generated} resumed={resumed}",
            flush=True,
        )

    print("\nDATASET GENERATION COMPLETE")
    print("Output:", output)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--output", type=Path, required=True
    )
    parser.add_argument(
        "--pilot", action="store_true"
    )
    args = parser.parse_args()

    counts = (
        {"train": 30, "validation": 15, "test": 15}
        if args.pilot
        else DEFAULT_COUNTS
    )

    run(args.output, counts)


if __name__ == "__main__":
    main()
