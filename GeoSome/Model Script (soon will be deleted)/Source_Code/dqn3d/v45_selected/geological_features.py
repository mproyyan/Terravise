"""Experimental lateral Ic gradient features."""
import numpy as np


def lateral_ic_gradient(reconstruction, valid_mask, grid):
    ic = np.asarray(reconstruction, dtype=np.float64)
    valid = np.asarray(valid_mask, dtype=bool)

    if ic.shape != valid.shape:
        raise ValueError("Ic and valid mask shape mismatch")

    if ic.shape != (grid.nx, grid.ny, grid.nz):
        raise ValueError("Grid shape mismatch")

    if grid.nx < 2 or grid.ny < 2:
        raise ValueError("Need at least two cells per XY axis")

    if grid.dx_m <= 0 or grid.dy_m <= 0:
        raise ValueError("Invalid horizontal resolution")

    if not np.isfinite(ic[valid]).all():
        raise ValueError("Non-finite valid Ic values")

    count = valid.sum(axis=2)
    sum_ic = np.where(valid, ic, 0.0).sum(axis=2)
    mean_ic = np.divide(
        sum_ic, count,
        out=np.zeros_like(sum_ic),
        where=count > 0
    )

    # Use only pairs where both XY profiles are valid.
    valid_xy = count > 0
    gx = np.zeros_like(mean_ic)
    gy = np.zeros_like(mean_ic)
    weight_x = np.zeros_like(mean_ic)
    weight_y = np.zeros_like(mean_ic)

    pair_x = valid_xy[:-1] & valid_xy[1:]
    diff_x = (mean_ic[1:] - mean_ic[:-1]) / grid.dx_m
    abs_x = np.where(pair_x, np.abs(diff_x), 0.0)
    gx[:-1] += abs_x
    gx[1:] += abs_x
    weight_x[:-1] += pair_x
    weight_x[1:] += pair_x

    pair_y = valid_xy[:, :-1] & valid_xy[:, 1:]
    diff_y = (mean_ic[:, 1:] - mean_ic[:, :-1]) / grid.dy_m
    abs_y = np.where(pair_y, np.abs(diff_y), 0.0)
    gy[:, :-1] += abs_y
    gy[:, 1:] += abs_y
    weight_y[:, :-1] += pair_y
    weight_y[:, 1:] += pair_y

    gx = np.divide(
        gx, weight_x,
        out=np.zeros_like(gx),
        where=weight_x > 0
    )
    gy = np.divide(
        gy, weight_y,
        out=np.zeros_like(gy),
        where=weight_y > 0
    )

    gradient = np.hypot(gx, gy)
    gradient[~valid_xy] = 0.0
    return gradient.astype(np.float32)
