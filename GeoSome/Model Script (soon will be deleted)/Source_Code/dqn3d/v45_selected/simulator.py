"""Synthetic 3D CPT reveal environment and common-mask RMSE improvement reward for DQN V4.2."""
from __future__ import annotations

import math
from typing import List, Optional, Tuple

import numpy as np

from synthetic3d.v2.core import Grid
from .features import CandidateState, build_state


class SyntheticCPTSimulator:
    """Simulates borehole investigations and rewards reconstruction error reduction."""

    def __init__(
        self,
        reconstructor,
        truth_ic: np.ndarray,
        valid_mask: np.ndarray,
        grid: Grid,
        access_mask: Optional[np.ndarray] = None,
        evaluation_mask: Optional[np.ndarray] = None,
    ):
        shape = (grid.nx, grid.ny, grid.nz)
        self._truth = np.asarray(truth_ic, dtype=np.float32).copy()
        self.valid = np.asarray(valid_mask, dtype=bool).copy()

        if (
            self._truth.shape != shape
            or self.valid.shape != shape
            or not self.valid.any()
            or not np.isfinite(self._truth[self.valid]).all()
        ):
            raise ValueError(
                f"Invalid synthetic truth, valid mask, or grid shape: truth {self._truth.shape}, grid {shape}"
            )

        self.grid = grid
        self.reconstructor = reconstructor
        self.evaluation_mask = None

        if evaluation_mask is not None:
            evaluation_mask = np.asarray(
                evaluation_mask, dtype=bool
            )
            if evaluation_mask.shape != shape:
                raise ValueError("Evaluation mask shape mismatch")

            self.evaluation_mask = evaluation_mask & self.valid

            if not self.evaluation_mask.any():
                raise ValueError("Evaluation mask must not be empty")

            # Evaluation locations must never be CPT candidates.
            accessible = (
                np.ones((grid.nx, grid.ny), dtype=bool)
                if access_mask is None
                else np.asarray(access_mask, dtype=bool).copy()
            )

            if accessible.shape != (grid.nx, grid.ny):
                raise ValueError("Access mask shape mismatch")

            reserved_xy = self.evaluation_mask.any(axis=2)
            accessible[reserved_xy] = False
            self.access_mask = accessible
        else:
            self.access_mask = access_mask
        self.observed_ic = np.zeros(shape, dtype=np.float32)
        self.observed_mask = np.zeros(shape, dtype=bool)
        self.prediction: Optional[np.ndarray] = None
        self.state: Optional[CandidateState] = None
        self.reconstruction_seconds = 0.0

    def _reveal(self, xy: Tuple[int, int]) -> None:
        x, y = int(xy[0]), int(xy[1])
        self.grid.xy_m(x, y)  # Validates spatial grid bounds
        if not self.valid[x, y].any() or self.observed_mask[x, y].any():
            raise ValueError(f"Invalid or duplicate CPT site: ({x}, {y})")

        self.observed_mask[x, y] = self.valid[x, y]
        self.observed_ic[x, y, self.valid[x, y]] = self._truth[x, y, self.valid[x, y]]

    def _reconstruct(self) -> None:
        self.prediction, self.reconstruction_seconds = self.reconstructor.predict(
            self.observed_ic, self.observed_mask, self.valid, self.grid
        )
        self.state = build_state(
            self.prediction,
            self.observed_mask,
            self.valid,
            self.grid,
            self.access_mask,
            mean=getattr(self.reconstructor, "mean", 2.790332),
            std=getattr(self.reconstructor, "std", 0.772378),
        )

    def reset(self, initial_xy: List[Tuple[int, int]] | Tuple[Tuple[int, int], ...]) -> CandidateState:
        if not initial_xy:
            raise ValueError("At least one initial CPT coordinate must be provided")

        self.observed_ic.fill(0.0)
        self.observed_mask.fill(False)
        for xy in initial_xy:
            self._reveal(xy)
        if (
            self.evaluation_mask is not None
            and np.any(self.observed_mask & self.evaluation_mask)
        ):
            raise ValueError(
                "Initial CPT overlaps evaluation locations"
            )

        self._reconstruct()
        return self.state

    def step(self, action_index: int) -> Tuple[CandidateState, float, bool, dict]:
        if self.state is None:
            raise RuntimeError("Environment must be reset before taking a step")
        if not 0 <= action_index < len(self.state.candidate_xy):
            raise ValueError(
                f"Illegal candidate action index {action_index}; total candidates: {len(self.state.candidate_xy)}"
            )

        x, y = map(int, self.state.candidate_xy[action_index])
        before_prediction = self.prediction.copy()

        self._reveal((x, y))
        self._reconstruct()

        common = (
            self.evaluation_mask
            if self.evaluation_mask is not None
            else self.valid & ~self.observed_mask
        )
        if common.any():
            before_rmse = float(np.sqrt(np.mean((before_prediction[common] - self._truth[common]) ** 2)))
            after_rmse = float(np.sqrt(np.mean((self.prediction[common] - self._truth[common]) ** 2)))
            reward = before_rmse - after_rmse
        else:
            before_rmse = after_rmse = reward = 0.0

        done = not common.any() or len(self.state.candidate_xy) == 0
        info = {
            "selected_xy": (x, y),
            "x_m": self.grid.xy_m(x, y)[0],
            "y_m": self.grid.xy_m(x, y)[1],
            "common_hidden_voxels": int(common.sum()),
            "rmse_before_common": before_rmse,
            "rmse_after_common": after_rmse,
            "rmse_improvement": reward,
            "reconstruction_seconds": self.reconstruction_seconds,
        }
        assert math.isfinite(reward), f"Non-finite reward encountered: {reward}"
        return self.state, reward, done, info
