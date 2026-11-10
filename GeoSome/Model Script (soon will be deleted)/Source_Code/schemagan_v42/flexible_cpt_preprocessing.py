
from dataclasses import dataclass

import numpy as np
import pandas as pd
import torch


@dataclass
class GridConfig:
    nx: int
    ny: int
    dx_m: float
    dy_m: float
    dz_m: float
    target_depth_m: float
    x_origin_m: float = 0.0
    y_origin_m: float = 0.0
    z_origin_m: float = 0.0


def prepare_flexible_cpt(dataframe, grid, norm):
    """
    SchemaGAN V4.2 flexible CPT adapter.

    Required columns:
        cpt_id, x_m, y_m, depth_m, Ic

    Returns:
        features       [1, 7, Z, Y, X]
        observed_mask  [X, Y, Z]
        coverage_mask  [X, Y, Z]
        metadata       dict

    Only actual aligned measurements receive mask=1.
    Missing depths are never fabricated as observations.
    """

    required = {"cpt_id", "x_m", "y_m", "depth_m", "Ic"}
    missing = required - set(dataframe.columns)

    if missing:
        raise ValueError(f"Missing columns: {sorted(missing)}")

    if dataframe.empty:
        raise ValueError("CPT dataframe is empty")

    if (
        grid.nx < 1 or grid.ny < 1
        or min(grid.dx_m, grid.dy_m, grid.dz_m) <= 0
        or not np.isfinite([
            grid.dx_m, grid.dy_m, grid.dz_m,
            grid.x_origin_m, grid.y_origin_m,
            grid.z_origin_m, grid.target_depth_m
        ]).all()
    ):
        raise ValueError("Invalid grid configuration")

    mean = float(norm["mean"])
    std = float(norm["std"])

    if not np.isfinite([mean, std]).all() or std <= 0:
        raise ValueError("Invalid normalization")

    span = (
        grid.target_depth_m - grid.z_origin_m
    ) / grid.dz_m

    if span < 0 or not np.isclose(
        span, round(span), atol=1e-6, rtol=0
    ):
        raise ValueError(
            "Target depth must align with the vertical grid"
        )

    nz = int(round(span)) + 1
    nx, ny = grid.nx, grid.ny

    z_levels = (
        grid.z_origin_m
        + np.arange(nz) * grid.dz_m
    )

    x_coords = (
        grid.x_origin_m
        + np.arange(nx) * grid.dx_m
    )
    y_coords = (
        grid.y_origin_m
        + np.arange(ny) * grid.dy_m
    )

    data = dataframe.copy()

    if data["cpt_id"].isna().any():
        raise ValueError("Missing CPT IDs")

    for column in ("x_m", "y_m", "depth_m", "Ic"):
        data[column] = pd.to_numeric(
            data[column], errors="coerce"
        )

        if not np.isfinite(
            data[column].to_numpy(dtype=float)
        ).all():
            raise ValueError(f"Invalid values: {column}")

    sparse = np.zeros((nx, ny, nz), dtype=np.float32)
    mask = np.zeros_like(sparse)
    idw = np.zeros_like(sparse)

    xx, yy = np.meshgrid(
        x_coords, y_coords, indexing="ij"
    )

    records = []
    occupied_cells = set()
    unused_rows = 0

    for cpt_id, group in data.groupby(
        "cpt_id", sort=True
    ):
        group = group.sort_values("depth_m")

        x = group["x_m"].to_numpy(float)
        y = group["y_m"].to_numpy(float)
        depths = group["depth_m"].to_numpy(float)
        ic = group["Ic"].to_numpy(float)

        if not (
            np.allclose(x, x[0], atol=1e-7, rtol=0)
            and np.allclose(y, y[0], atol=1e-7, rtol=0)
        ):
            raise ValueError(
                f"{cpt_id}: inconsistent coordinates"
            )

        if np.any(np.diff(depths) <= 1e-8):
            raise ValueError(
                f"{cpt_id}: duplicate depth measurements"
            )

        ix_f = (
            x[0] - grid.x_origin_m
        ) / grid.dx_m
        iy_f = (
            y[0] - grid.y_origin_m
        ) / grid.dy_m

        ix = int(np.rint(ix_f))
        iy = int(np.rint(iy_f))

        if (
            abs(ix_f - ix) > 1e-5
            or abs(iy_f - iy) > 1e-5
        ):
            raise ValueError(
                f"{cpt_id}: XY not aligned with grid"
            )

        if not (0 <= ix < nx and 0 <= iy < ny):
            raise ValueError(
                f"{cpt_id}: outside grid"
            )

        if (ix, iy) in occupied_cells:
            raise ValueError(
                f"{cpt_id}: grid cell collision; "
                "use finer horizontal resolution"
            )

        occupied_cells.add((ix, iy))

        indices = []
        values = []

        for depth, value in zip(depths, ic):
            if (
                depth < z_levels[0] - 1e-7
                or depth > z_levels[-1] + 1e-7
            ):
                unused_rows += 1
                continue

            iz_f = (
                depth - grid.z_origin_m
            ) / grid.dz_m
            iz = int(np.rint(iz_f))

            if abs(iz_f - iz) > 1e-5:
                raise ValueError(
                    f"{cpt_id}: depth {depth} m "
                    f"does not align with dz={grid.dz_m}"
                )

            if mask[ix, iy, iz] > 0:
                raise ValueError(
                    f"{cpt_id}: duplicate grid observation"
                )

            normalized = (value - mean) / std

            sparse[ix, iy, iz] = normalized
            mask[ix, iy, iz] = 1.0

            indices.append(iz)
            values.append(normalized)

        if not indices:
            raise ValueError(
                f"{cpt_id}: no measurements inside grid"
            )

        distance = np.sqrt(
            (xx - x[0]) ** 2
            + (yy - y[0]) ** 2
        ).astype(np.float32)

        records.append({
            "id": str(cpt_id),
            "distance": distance,
            "indices": np.asarray(indices, dtype=int),
            "values": np.asarray(values, dtype=np.float32),
            "last_depth_m": float(depths.max()),
        })

    # Use only genuinely measured CPTs at each level.
    # If no observation exists, normalized IDW remains 0,
    # corresponding to the training mean.
    coverage_z = np.zeros(nz, dtype=bool)

    for iz in range(nz):
        active_distances = []
        active_values = []

        for record in records:
            matches = np.flatnonzero(
                record["indices"] == iz
            )

            if len(matches):
                active_distances.append(record["distance"])
                active_values.append(
                    record["values"][matches[0]]
                )

        if not active_values:
            continue

        coverage_z[iz] = True

        distances = np.stack(active_distances)
        values = np.asarray(
            active_values, dtype=np.float32
        )

        weights = (
            1.0 / np.maximum(distances, 1e-5) ** 2
        )
        weights /= weights.sum(
            axis=0, keepdims=True
        )

        idw[:, :, iz] = np.einsum(
            "kxy,k->xy",
            weights,
            values,
            optimize=True
        )

    idw = np.where(mask > 0, sparse, idw)

    nearest = np.stack([
        record["distance"] for record in records
    ]).min(axis=0)

    distance_scale = max(
        nx * grid.dx_m,
        ny * grid.dy_m,
        1.0
    )

    nearest = np.broadcast_to(
        (nearest / distance_scale)[:, :, None],
        sparse.shape
    )

    # Exact 7-channel order used during V4.2 training.
    features = np.stack([
        sparse,
        mask,
        idw,
        nearest,
        np.full_like(sparse, np.log1p(grid.dx_m)),
        np.full_like(sparse, np.log1p(grid.dy_m)),
        np.full_like(sparse, np.log1p(grid.dz_m)),
    ]).astype(np.float32)

    # NumPy X,Y,Z -> PyTorch Z,Y,X.
    features = np.transpose(
        features, (0, 3, 2, 1)
    ).copy()

    coverage = np.broadcast_to(
        coverage_z[None, None, :],
        (nx, ny, nz)
    ).copy()

    return {
        "features": torch.from_numpy(features)[None],
        "observed_mask": mask.astype(bool),
        "coverage_mask": coverage,
        "metadata": {
            "cpt_count": len(records),
            "observed_voxels": int(mask.sum()),
            "unused_outside_grid_rows": unused_rows,
            "maximum_observed_depth_m": max(
                r["last_depth_m"] for r in records
            ),
            "unsupported_depth_levels": [
                float(z_levels[i])
                for i in range(nz)
                if not coverage_z[i]
            ],
            "grid": {
                "nx": nx,
                "ny": ny,
                "nz": nz,
                "dx_m": grid.dx_m,
                "dy_m": grid.dy_m,
                "dz_m": grid.dz_m,
            },
        },
    }
