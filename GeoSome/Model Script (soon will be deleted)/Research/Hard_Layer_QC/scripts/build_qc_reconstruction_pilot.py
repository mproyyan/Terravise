from pathlib import Path
import json
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))

from synthetic3d.v2.core import Grid
from scripts.synthetic_v4 import build_multiscale_pilot as base


OUT = ROOT / "data/synthetic3d_qc_v1/pilot_100"
VERSION = "synthetic-qc-v1-pilot-1"

GRID = Grid(
    24, 24, 24,
    1.0, 1.0, 0.5
)

SPLITS = {
    "train": 80,
    "validation": 10,
    "test": 10,
}


def main():
    if OUT.exists() and any(OUT.iterdir()):
        raise FileExistsError(
            f"Output already contains files: {OUT}"
        )

    OUT.mkdir(parents=True, exist_ok=True)

    # generate_one() reads VERSION from its own module.
    base.VERSION = VERSION

    config = {
        "version": VERSION,
        "grid": {
            "nx": GRID.nx,
            "ny": GRID.ny,
            "nz": GRID.nz,
            "dx_m": GRID.dx_m,
            "dy_m": GRID.dy_m,
            "dz_m": GRID.dz_m,
        },
        "physical_size_m": [
            GRID.nx * GRID.dx_m,
            GRID.ny * GRID.dy_m,
            GRID.nz * GRID.dz_m,
        ],
        "splits": SPLITS,
        "purpose": (
            "QC reconstruction pilot with "
            "0.5 m vertical resolution"
        ),
        "outputs": [
            "Ic",
            "qc_mpa",
            "fs_mpa",
            "unit_id",
            "valid_mask",
        ],
        "limitations": [
            "Synthetic experimental geotechnical priors",
            "Not field calibrated",
            "No model training performed",
        ],
    }

    (OUT / "config.json").write_text(
        json.dumps(
            config,
            indent=2,
            allow_nan=False,
        ) + "\n"
    )

    total = sum(SPLITS.values())
    done = 0

    for split, count in SPLITS.items():
        folder = OUT / split
        folder.mkdir(exist_ok=True)

        for index in range(count):
            volume, info = base.generate_one(
                split,
                index,
                GRID,
            )

            filename = (
                f"qc_v1_{split}_{index:05d}.npz"
            )

            base.save_volume(
                folder / filename,
                volume,
            )

            done += 1

            qc = volume["qc_mpa"]

            print(
                f"{done}/{total}"
                f" | {split}"
                f" | shape={qc.shape}"
                f" | qc_max={qc.max():.3f} MPa",
                flush=True,
            )

    print()
    print("QC PILOT COMPLETE")
    print("Output:", OUT)


if __name__ == "__main__":
    main()
