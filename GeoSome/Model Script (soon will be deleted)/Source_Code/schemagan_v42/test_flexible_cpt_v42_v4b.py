
from pathlib import Path
import argparse
import json
import sys

import numpy as np
import pandas as pd
import torch

# Project paths: run from cpt_super_learn root.
ROOT = Path.cwd()

sys.path.insert(
    0, str(ROOT / "scripts" / "real_world_testing")
)
sys.path.insert(
    0, str(ROOT / "scripts" / "synthetic_v4")
)

from flexible_cpt_preprocessing import (
    GridConfig,
    prepare_flexible_cpt,
)
from train_sgan_v42 import Generator


DATA = ROOT / "data/synthetic3d_v4_geosyn/full_24k/test"
MODEL_PATH = ROOT / (
    "model_export/SchemaGAN_V4_2/SchemaGAN_V4_2.pt"
)
NORM_PATH = ROOT / (
    "model_export/SchemaGAN_V4_2/normalization.json"
)
OUTPUT = ROOT / "results/synthetic_v4/flexible_cpt_v4b"

INTERVALS_M = (0.2, 0.5, 1.0)


def parse_counts(value):
    counts = tuple(
        dict.fromkeys(
            int(part.strip())
            for part in value.split(",")
        )
    )
    if not counts or min(counts) < 1:
        raise ValueError("CPT counts must be positive")
    return counts


def load_test_files(scenarios, limit):
    selected = {name: [] for name in scenarios}

    for path in sorted(DATA.glob("*.npz")):
        with np.load(path, allow_pickle=False) as data:
            meta = json.loads(str(data["metadata_json"]))

        scenario = str(meta.get("scenario", ""))

        if (
            scenario in selected
            and len(selected[scenario]) < limit
        ):
            selected[scenario].append(path)

        if all(
            len(files) >= limit
            for files in selected.values()
        ):
            break

    for scenario, files in selected.items():
        if len(files) < limit:
            raise RuntimeError(
                f"Scenario {scenario}: found {len(files)}, "
                f"expected {limit}"
            )

    return selected


def interpolate_truth(native, native_dz, output_z):
    """
    Interpolate synthetic native ground truth vertically.

    Finer resolution is a numerical proxy, not new
    independent geological ground truth.
    """
    nx, ny, nz = native.shape

    native_z = (
        np.arange(nz, dtype=np.float64) * native_dz
    )

    if output_z[-1] > native_z[-1] + 1e-6:
        raise ValueError("Output exceeds native depth")

    flat = native.reshape(-1, nz)

    result = np.stack([
        np.interp(output_z, native_z, profile)
        for profile in flat
    ])

    return result.reshape(
        nx, ny, len(output_z)
    ).astype(np.float32)


def make_cpt_data(native, dx, dy, native_dz,
                  n_cpt, seed):
    """
    Simulate distinct stopping depths.

    Stopping depth varies by CPT, using random fractions
    of native depth. This is NOT a physically validated
    refusal model.
    """
    rng = np.random.default_rng(seed)

    nx, ny, nz = native.shape
    maximum_depth = (nz - 1) * native_dz

    if n_cpt > nx * ny:
        raise ValueError("Too many CPTs for grid")

    indices = rng.choice(
        nx * ny,
        size=n_cpt,
        replace=False,
    )

    rows = []
    summaries = []

    native_z = np.arange(nz) * native_dz

    for index, flat_index in enumerate(indices):
        ix, iy = np.unravel_index(
            int(flat_index), (nx, ny)
        )

        # Mix 20 cm, 50 cm and 1 m in one project.
        interval = INTERVALS_M[index % len(INTERVALS_M)]

        # Example bounded penetration:
        # between 35% and 90% of native available depth.
        stop_fraction = rng.uniform(0.35, 0.90)
        stop_target = maximum_depth * stop_fraction

        measured_z = np.arange(
            0.0,
            stop_target + 1e-8,
            interval,
            dtype=np.float64,
        )

        if len(measured_z) < 2:
            raise RuntimeError("Insufficient CPT depths")

        # All measurements are simulated from synthetic
        # ground truth; no real submeter measurements exist.
        values = np.interp(
            measured_z,
            native_z,
            native[ix, iy, :],
        )

        cpt_id = f"CPT-{index + 1:02d}"

        for depth, ic in zip(measured_z, values):
            rows.append({
                "cpt_id": cpt_id,
                "x_m": float(ix * dx),
                "y_m": float(iy * dy),
                "depth_m": round(float(depth), 6),
                "Ic": float(ic),
            })

        summaries.append({
            "cpt_id": cpt_id,
            "interval_m": interval,
            "last_depth_m": float(measured_z[-1]),
            "stop_reason": "simulated_limited_penetration",
        })

    return pd.DataFrame(rows), pd.DataFrame(summaries)


def vertical_idw(data, grid, mean):
    """
    IDW with interpolation along each measured CPT.

    Values between actual measurements are allowed for
    baseline estimation but are NOT marked as observed.
    No extrapolation beyond the deepest measurement
    in an individual CPT.

    Beyond all CPT depths: fallback to training mean.
    """
    nx, ny = grid.nx, grid.ny

    z_levels = np.arange(
        round(
            (grid.target_depth_m - grid.z_origin_m)
            / grid.dz_m
        ) + 1
    ) * grid.dz_m + grid.z_origin_m

    x_levels = (
        grid.x_origin_m
        + np.arange(nx) * grid.dx_m
    )
    y_levels = (
        grid.y_origin_m
        + np.arange(ny) * grid.dy_m
    )

    xx, yy = np.meshgrid(
        x_levels, y_levels, indexing="ij"
    )

    result = np.full(
        (nx, ny, len(z_levels)),
        mean,
        dtype=np.float32,
    )

    grouped = list(data.groupby("cpt_id"))

    for iz, z in enumerate(z_levels):
        source_dist = []
        source_value = []

        for _, group in grouped:
            group = group.sort_values("depth_m")
            depths = group["depth_m"].to_numpy(float)
            values = group["Ic"].to_numpy(float)

            if (
                z < depths[0] - 1e-7
                or z > depths[-1] + 1e-7
            ):
                continue

            x = float(group["x_m"].iloc[0])
            y = float(group["y_m"].iloc[0])

            dist = np.sqrt(
                (xx - x) ** 2 + (yy - y) ** 2
            )

            source_dist.append(dist)
            source_value.append(
                np.interp(z, depths, values)
            )

        if not source_value:
            continue

        dist = np.stack(source_dist)
        values = np.asarray(source_value)

        weights = 1.0 / np.maximum(dist, 1e-5) ** 2
        weights /= weights.sum(axis=0, keepdims=True)

        result[:, :, iz] = np.einsum(
            "kxy,k->xy",
            weights,
            values,
            optimize=True,
        )

    return result


def calculate_metrics(predictions, truth, mask):
    if not mask.any():
        return None

    result = {"voxels": int(mask.sum())}

    for name, pred in predictions.items():
        error = pred[mask] - truth[mask]

        result[f"{name}_sse"] = float(
            np.sum(error.astype(np.float64) ** 2)
        )
        result[f"{name}_sae"] = float(
            np.sum(np.abs(error.astype(np.float64)))
        )

    return result


def main():
    parser = argparse.ArgumentParser()

    parser.add_argument(
        "--volumes-per-scenario",
        type=int,
        default=1,
    )
    parser.add_argument(
        "--scenarios",
        type=str,
        default="A,B,C,D,E",
    )
    parser.add_argument(
        "--cpts",
        type=str,
        default="3,5",
    )
    parser.add_argument(
        "--output-dz",
        type=float,
        default=0.1,
    )

    args = parser.parse_args()

    scenarios = tuple(
        s.strip().upper()
        for s in args.scenarios.split(",")
    )
    counts = parse_counts(args.cpts)

    if args.volumes_per_scenario < 1:
        raise ValueError("Invalid volume count")

    # 0.1 m aligns 0.2, 0.5 and 1.0 m readings.
    if args.output_dz <= 0:
        raise ValueError("Invalid output resolution")

    for interval in INTERVALS_M:
        ratio = interval / args.output_dz

        if not np.isclose(
            ratio, round(ratio),
            atol=1e-6,
            rtol=0,
        ):
            raise ValueError(
                "Output dz must align with all CPT intervals"
            )

    norm = json.loads(NORM_PATH.read_text())
    mean = float(norm["mean"])
    std = float(norm["std"])

    checkpoint = torch.load(
        MODEL_PATH,
        map_location="cpu",
        weights_only=True,
    )

    model = Generator()
    model.load_state_dict(
        checkpoint["generator_state"],
        strict=True,
    )
    model.eval()

    selected = load_test_files(
        scenarios,
        args.volumes_per_scenario,
    )

    rows = []
    stop_rows = []

    print("===== FLEXIBLE CPT V4 START =====")
    print("Scenarios:", scenarios)
    print("CPT counts:", counts)
    print("Intervals:", INTERVALS_M)
    print("Output dz:", args.output_dz)
    print("Checkpoint:", MODEL_PATH)

    with torch.inference_mode():
        for scenario in scenarios:
            files = selected[scenario]

            for volume_index, path in enumerate(files):
                with np.load(
                    path,
                    allow_pickle=False,
                ) as dataset:
                    native = dataset["Ic"].astype(
                        np.float32
                    )
                    meta = json.loads(
                        str(dataset["metadata_json"])
                    )

                grid_meta = meta["grid"]
                dx = float(grid_meta["dx_m"])
                dy = float(grid_meta["dy_m"])
                native_dz = float(grid_meta["dz_m"])

                nx, ny, native_nz = native.shape

                full_depth = (
                    (native_nz - 1) * native_dz
                )

                for n_cpt in counts:
                    seed = (
                        42
                        + volume_index * 1009
                        + n_cpt * 97
                        + ord(scenario) * 100003
                    )

                    cpt_data, cpt_summary = make_cpt_data(
                        native,
                        dx,
                        dy,
                        native_dz,
                        n_cpt,
                        seed,
                    )

                    for record in cpt_summary.to_dict(
                        orient="records"
                    ):
                        stop_rows.append({
                            "scenario": scenario,
                            "volume": path.stem,
                            "n_cpt": n_cpt,
                            **record,
                        })

                    max_stop = float(
                        cpt_summary["last_depth_m"].max()
                    )

                    for mode in ("crop", "full"):
                        target_depth = (
                            max_stop
                            if mode == "crop"
                            else full_depth
                        )

                        # Align output to the chosen grid.
                        nz_output = (
                            int(np.ceil(
                                target_depth / args.output_dz
                                - 1e-8
                            )) + 1
                        )

                        aligned_target = (
                            (nz_output - 1)
                            * args.output_dz
                        )

                        if aligned_target > full_depth + 1e-6:
                            raise RuntimeError(
                                "Target exceeds native ground truth"
                            )

                        grid = GridConfig(
                            nx=nx,
                            ny=ny,
                            dx_m=dx,
                            dy_m=dy,
                            dz_m=args.output_dz,
                            target_depth_m=round(
                                aligned_target, 8
                            ),
                        )

                        prepared = prepare_flexible_cpt(
                            cpt_data,
                            grid,
                            norm,
                        )

                        output_z = (
                            np.arange(nz_output)
                            * args.output_dz
                        )

                        truth = interpolate_truth(
                            native,
                            native_dz,
                            output_z,
                        )

                        # Interpolate vertically using ONLY input
                        # CPT measurements. Do not modify observation mask.
                        vertical_baseline = vertical_idw(
                            cpt_data,
                            grid,
                            mean,
                        )

                        features = prepared["features"].clone()

                        # Channel 2 is normalized IDW.
                        idw_normalized = (
                            (vertical_baseline - mean) / std
                        ).astype(np.float32)

                        features[0, 2] = torch.from_numpy(
                            idw_normalized.transpose(
                                2, 1, 0
                            ).copy()
                        )

                        output = model(
                            features
                        )[0, 0].cpu().numpy()

                        model_pred = (
                            output.transpose(2, 1, 0)
                            * std + mean
                        )

                        idw_direct = (
                            prepared["features"][
                                0, 2
                            ].numpy().transpose(2, 1, 0)
                            * std + mean
                        )

                        idw_vertical = vertical_idw(
                            cpt_data,
                            grid,
                            mean,
                        )

                        predictions = {
                            "model": model_pred,
                            "idw_direct": idw_direct,
                            "idw_vertical": idw_vertical,
                        }

                        observed = prepared["observed_mask"]
                        hidden = ~observed

                        max_measured = (
                            prepared["metadata"][
                                "maximum_observed_depth_m"
                            ]
                        )

                        within_z = (
                            output_z <= max_measured + 1e-7
                        )

                        within = np.broadcast_to(
                            within_z[None, None, :],
                            truth.shape,
                        )

                        regions = {
                            "all_hidden": hidden,
                            "within_penetration": hidden & within,
                            "below_penetration": hidden & ~within,
                        }

                        preservation_error = float(
                            np.max(
                                np.abs(
                                    (model_pred - truth)[observed]
                                )
                            )
                        )

                        if preservation_error > 1e-5:
                            raise RuntimeError(
                                "Observed values were changed"
                            )

                        for region_name, region in regions.items():
                            result = calculate_metrics(
                                predictions, truth, region
                            )

                            if result is None:
                                continue

                            rows.append({
                                "scenario": scenario,
                                "volume": path.stem,
                                "n_cpt": n_cpt,
                                "mode": mode,
                                "region": region_name,
                                "dx_m": dx,
                                "dy_m": dy,
                                "native_dz_m": native_dz,
                                "output_dz_m": args.output_dz,
                                "target_depth_m": float(
                                    aligned_target
                                ),
                                "max_penetration_m": max_measured,
                                "observed_voxels": int(
                                    observed.sum()
                                ),
                                "preservation_error": preservation_error,
                                **result,
                            })

                print(
                    f"[{scenario}] "
                    f"{volume_index + 1}/{len(files)} DONE",
                    flush=True,
                )

    OUTPUT.mkdir(parents=True, exist_ok=True)

    details = pd.DataFrame(rows)
    details.to_csv(
        OUTPUT / "details.csv",
        index=False,
    )

    pd.DataFrame(stop_rows).to_csv(
        OUTPUT / "cpt_penetration.csv",
        index=False,
    )

    group_columns = [
        "scenario",
        "n_cpt",
        "mode",
        "region",
    ]

    aggregation = {
        "voxels": ("voxels", "sum"),
        "volumes": ("volume", "nunique"),
    }

    methods = (
        "model",
        "idw_direct",
        "idw_vertical",
    )

    for method in methods:
        aggregation[f"{method}_sse"] = (
            f"{method}_sse", "sum"
        )
        aggregation[f"{method}_sae"] = (
            f"{method}_sae", "sum"
        )

    summary = details.groupby(
        group_columns,
        as_index=False,
    ).agg(**aggregation)

    for method in methods:
        summary[f"{method}_rmse"] = np.sqrt(
            summary[f"{method}_sse"]
            / summary["voxels"]
        )
        summary[f"{method}_mae"] = (
            summary[f"{method}_sae"]
            / summary["voxels"]
        )

    summary["improvement_vs_vertical_pct"] = (
        100
        * (
            summary["idw_vertical_rmse"]
            - summary["model_rmse"]
        )
        / summary["idw_vertical_rmse"]
    )

    visible_columns = [
        "scenario",
        "n_cpt",
        "mode",
        "region",
        "volumes",
        "voxels",
        "model_rmse",
        "idw_direct_rmse",
        "idw_vertical_rmse",
        "improvement_vs_vertical_pct",
    ]

    summary = summary[visible_columns]

    summary.to_csv(
        OUTPUT / "summary.csv",
        index=False,
    )

    print("\n===== FLEXIBLE CPT V4 RESULTS =====")
    print(
        summary.round(5).to_string(index=False)
    )

    print(
        "\nMaximum preservation error:",
        details["preservation_error"].max(),
    )
    print("Output:", OUTPUT)
    print("FLEXIBLE CPT V4 COMPLETE")


if __name__ == "__main__":
    main()
