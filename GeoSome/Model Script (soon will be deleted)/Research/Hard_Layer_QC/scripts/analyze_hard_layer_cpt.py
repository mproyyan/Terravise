from __future__ import annotations

import argparse
from pathlib import Path

import numpy as np
import pandas as pd


# 200 kg/cm² ≈ 19.613 MPa
DEFAULT_QC_THRESHOLD_MPA = 19.613

# PoC continuity requirement, configurable.
DEFAULT_MIN_THICKNESS_M = 0.50


def load_cpt(path: Path) -> pd.DataFrame:
    df = pd.read_csv(path)

    cols = {
        str(c).strip().lower(): c
        for c in df.columns
    }

    # USGS format:
    # z = depth (m)
    # tip = qc (MPa)
    # sleeve = fs (kPa)
    if "z" in cols and "tip" in cols:
        out = pd.DataFrame({
            "depth_m": pd.to_numeric(
                df[cols["z"]],
                errors="coerce",
            ),
            "qc_mpa": pd.to_numeric(
                df[cols["tip"]],
                errors="coerce",
            ),
        })

        if "sleeve" in cols:
            out["fs_kpa"] = pd.to_numeric(
                df[cols["sleeve"]],
                errors="coerce",
            )

        print("Detected format : USGS z,tip,sleeve")

    # App format
    elif "depth_m" in cols and "qc_mpa" in cols:
        out = pd.DataFrame({
            "depth_m": pd.to_numeric(
                df[cols["depth_m"]],
                errors="coerce",
            ),
            "qc_mpa": pd.to_numeric(
                df[cols["qc_mpa"]],
                errors="coerce",
            ),
        })

        if "fs_kpa" in cols:
            out["fs_kpa"] = pd.to_numeric(
                df[cols["fs_kpa"]],
                errors="coerce",
            )

        print("Detected format : Demnas3DMap CPT")

    else:
        raise RuntimeError(
            "Unsupported CSV format. "
            "Expected z,tip,sleeve or "
            "depth_m,qc_mpa,fs_kpa."
        )

    out = out.dropna(
        subset=["depth_m", "qc_mpa"]
    ).copy()

    out = out[
        (out["depth_m"] > 0)
        & (out["qc_mpa"] > 0)
    ]

    out = out.sort_values(
        "depth_m"
    ).reset_index(drop=True)

    if len(out) < 2:
        raise RuntimeError(
            "Too few valid CPT measurements."
        )

    if not np.all(
        np.diff(out["depth_m"]) > 0
    ):
        raise RuntimeError(
            "Depth must increase monotonically."
        )

    return out


def detect_hard_layer(
    df: pd.DataFrame,
    threshold: float,
    min_thickness: float,
):
    above = (
        df["qc_mpa"].to_numpy()
        >= threshold
    )

    depths = df["depth_m"].to_numpy()

    start = None

    for i, is_above in enumerate(above):
        if is_above:
            if start is None:
                start = i

            thickness = (
                depths[i] - depths[start]
            )

            if thickness >= min_thickness:
                return start, i

        else:
            start = None

    return None


def main():
    parser = argparse.ArgumentParser()

    parser.add_argument(
        "csv",
        type=Path,
    )

    parser.add_argument(
        "--qc-threshold-mpa",
        type=float,
        default=DEFAULT_QC_THRESHOLD_MPA,
    )

    parser.add_argument(
        "--min-thickness-m",
        type=float,
        default=DEFAULT_MIN_THICKNESS_M,
    )

    args = parser.parse_args()

    df = load_cpt(args.csv)

    result = detect_hard_layer(
        df,
        args.qc_threshold_mpa,
        args.min_thickness_m,
    )

    print()
    print("====================================")
    print("CPT HARD-LAYER CANDIDATE ANALYSIS")
    print("====================================")

    print(f"File              : {args.csv.name}")
    print(f"Measurements      : {len(df)}")
    print(
        f"Depth range       : "
        f"{df.depth_m.min():.2f}–"
        f"{df.depth_m.max():.2f} m"
    )
    print(
        f"Maximum qc        : "
        f"{df.qc_mpa.max():.2f} MPa"
    )
    print(
        f"qc criterion      : "
        f"{args.qc_threshold_mpa:.3f} MPa"
    )
    print(
        f"Min continuity    : "
        f"{args.min_thickness_m:.2f} m"
    )

    if result is None:
        print()
        print("RESULT")
        print(
            "Candidate hard layer: "
            "NOT DETECTED"
        )

    else:
        start, end = result

        print()
        print("RESULT")
        print(
            "Candidate hard layer: DETECTED"
        )
        print(
            f"Candidate depth   : "
            f"{df.iloc[start].depth_m:.2f} m"
        )
        print(
            f"Confirmed until   : "
            f"{df.iloc[end].depth_m:.2f} m"
        )
        print(
            f"qc start          : "
            f"{df.iloc[start].qc_mpa:.2f} MPa"
        )
        print(
            f"Mean qc interval  : "
            f"{df.iloc[start:end+1].qc_mpa.mean():.2f} MPa"
        )

    print()
    print(
        "Status: PoC interpretation only; "
        "criterion must be validated before "
        "engineering/design use."
    )


if __name__ == "__main__":
    main()
