"""Fixed 28-feature candidate schema for spatial borehole placement in DQN V4.2."""
from __future__ import annotations

import math
from dataclasses import dataclass
from typing import Tuple

import numpy as np

from synthetic3d.v2.core import Grid
from .adapter import DEFAULT_MEAN, DEFAULT_STD
from .geological_features import lateral_ic_gradient

CANDIDATE_NAMES: Tuple[str, ...] = (
    "x_local_fraction",
    "y_local_fraction",
    "nearest_cpt_distance_fraction",
    "local_observed_density_4m",
    "valid_depth_fraction",
    "reconstructed_ic_mean_z",
    "reconstructed_ic_std_z",
    "depth_bin_0_ic_mean_z",
    "depth_bin_1_ic_mean_z",
    "depth_bin_2_ic_mean_z",
    "depth_bin_3_ic_mean_z",
    "depth_bin_0_empty",
    "depth_bin_1_empty",
    "depth_bin_2_empty",
    "depth_bin_3_empty",
    "local_4m_reconstructed_ic_mean_z",
    "local_4m_valid_fraction",
    "lateral_ic_gradient",
)

GLOBAL_NAMES: Tuple[str, ...] = (
    "log_observed_cpt_fraction",
    "extent_x_over_32m",
    "extent_y_over_32m",
    "extent_z_over_16m",
    "dx_over_2m",
    "dy_over_2m",
    "dz_over_2m",
    "global_reconstructed_ic_mean_z",
    "global_reconstructed_ic_std_z",
    "valid_voxel_fraction",
    "observed_valid_voxel_fraction",
)


@dataclass(frozen=True)
class CandidateState:
    """State representation containing candidate site features and global site context."""

    candidate_xy: np.ndarray  # [N, 2], int16 (x, y) coordinates
    features: np.ndarray  # [N, 17], float32 local candidate features
    global_context: np.ndarray  # [11], float32 site context

    def __post_init__(self) -> None:
        if (
            self.candidate_xy.ndim != 2
            or self.candidate_xy.shape[1] != 2
            or self.features.shape != (len(self.candidate_xy), len(CANDIDATE_NAMES))
            or self.global_context.shape != (len(GLOBAL_NAMES),)
        ):
            raise ValueError(
                f"Candidate state shape mismatch: xy {self.candidate_xy.shape}, "
                f"features {self.features.shape}, context {self.global_context.shape}"
            )
        if not np.isfinite(self.features).all() or not np.isfinite(self.global_context).all():
            raise ValueError("Non-finite values encountered in candidate state features")
        if len({tuple(row) for row in self.candidate_xy}) != len(self.candidate_xy):
            raise ValueError("Duplicate candidate coordinate in candidate list")


def build_state(
    reconstruction: np.ndarray,
    observed_mask: np.ndarray,
    valid_mask: np.ndarray,
    grid: Grid,
    access_mask: np.ndarray | None = None,
    mean: float = DEFAULT_MEAN,
    std: float = DEFAULT_STD,
) -> CandidateState:
    """Extract spatial candidate features and global context from 3D reconstruction.
    
    Args:
        reconstruction: Predicted 3D Ic volume [nx, ny, nz].
        observed_mask: Boolean mask [nx, ny, nz] of measured locations.
        valid_mask: Boolean domain mask [nx, ny, nz].
        grid: Geometry specification (nx, ny, nz, dx_m, dy_m, dz_m).
        access_mask: Optional 2D boolean mask [nx, ny] defining accessible drilling terrain.
        mean: Normalization mean for standardizing features.
        std: Normalization std for standardizing features.
    """
    shape = (grid.nx, grid.ny, grid.nz)
    rec = np.asarray(reconstruction, dtype=np.float32)
    observed = np.asarray(observed_mask, dtype=bool)
    valid = np.asarray(valid_mask, dtype=bool)

    if rec.shape != shape or observed.shape != shape or valid.shape != shape:
        raise ValueError(
            f"State grid shape mismatch: rec {rec.shape}, observed {observed.shape}, valid {valid.shape}, grid {shape}"
        )
    if np.any(observed & ~valid) or not valid.any() or not np.isfinite(rec[valid]).all():
        raise ValueError("Invalid masks or non-finite reconstruction values in valid domain")

    observed_xy = observed.any(axis=2)
    if not observed_xy.any():
        raise ValueError("At least one observed CPT sounding is required to build state")

    if access_mask is None:
        accessible = np.ones((grid.nx, grid.ny), dtype=bool)
    else:
        accessible = np.asarray(access_mask, dtype=bool)
        if accessible.shape != (grid.nx, grid.ny):
            raise ValueError(f"Access mask shape mismatch: {accessible.shape} != {(grid.nx, grid.ny)}")

    legal = valid.any(axis=2) & ~observed_xy & accessible
    candidates = np.argwhere(legal).astype(np.int16)
    sites = np.argwhere(observed_xy)

    coords = np.array(
        [grid.xy_m(x, y) for x in range(grid.nx) for y in range(grid.ny)],
        dtype=np.float64,
    ).reshape(grid.nx, grid.ny, 2)
    site_coords = coords[observed_xy]
    diagonal = math.hypot(grid.nx * grid.dx_m, grid.ny * grid.dy_m)
    # V4.6: adaptive neighborhood for multiscale grids.
    local_radius = max(
        4.0,
        2.0 * max(float(grid.dx_m), float(grid.dy_m)),
    )

    features = np.empty((len(candidates), len(CANDIDATE_NAMES)), dtype=np.float32)
    zrec = (rec - mean) / std
    gradient_map = lateral_ic_gradient(
        rec, valid, grid
    )

    for k, (x, y) in enumerate(candidates):
        xy = coords[x, y]
        distance_to_sites = np.linalg.norm(site_coords - xy, axis=1)
        distances_all = np.linalg.norm(coords - xy, axis=2)
        neighborhood = distances_all <= (local_radius + 1e-9)

        # V4.6: compare candidate against its true surroundings.
        # Do not mix the candidate itself into the neighborhood mean.
        surrounding = neighborhood.copy()
        surrounding[x, y] = False

        if surrounding.any() and valid[surrounding].any():
            local_valid = valid[surrounding]
            local_rec = zrec[surrounding]
        else:
            local_valid = valid[neighborhood]
            local_rec = zrec[neighborhood]

        profile_valid = valid[x, y]
        profile = zrec[x, y, profile_valid]

        bins = np.array_split(np.arange(grid.nz), 4)
        bin_means = []
        bin_empty = []
        for indices in bins:
            keep = profile_valid[indices]
            bin_empty.append(float(not keep.any()))
            bin_means.append(float(zrec[x, y, indices][keep].mean()) if keep.any() else 0.0)

        features[k] = (
            x / max(grid.nx - 1, 1),
            y / max(grid.ny - 1, 1),
            min(float(distance_to_sites.min() / max(diagonal, 1e-6)), 1.0),
            float(observed_xy[neighborhood].sum() / max(int(neighborhood.sum()), 1)),
            float(profile_valid.mean()),
            float(profile.mean()) if len(profile) > 0 else 0.0,
            float(profile.std()) if len(profile) > 0 else 0.0,
            *bin_means,
            *bin_empty,
            float(local_rec[local_valid].mean()) if local_valid.any() else 0.0,
            float(local_valid.mean()),
            float(
                gradient_map[x, y]
                / max(float(std), 1e-6)
            ),
        )

    global_z = zrec[valid]
    n_sites = int(observed_xy.sum())
    possible_sites = int(valid.any(axis=2).sum())

    context = np.array(
        (
            math.log1p(n_sites) / max(math.log1p(possible_sites), 1e-6),
            math.log1p((grid.nx * grid.dx_m) / 32.0),
            math.log1p((grid.ny * grid.dy_m) / 32.0),
            math.log1p((grid.nz * grid.dz_m) / 16.0),
            math.log1p(grid.dx_m / 2.0),
            math.log1p(grid.dy_m / 2.0),
            math.log1p(grid.dz_m / 2.0),
            float(global_z.mean()) if len(global_z) > 0 else 0.0,
            float(global_z.std()) if len(global_z) > 0 else 0.0,
            float(valid.mean()),
            float(observed[valid].mean()),
        ),
        dtype=np.float32,
    )

    return CandidateState(candidates, features, context)
