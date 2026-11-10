"""Benchmark baseline policies for DQN V4.2 comparison."""
from __future__ import annotations

import numpy as np

from synthetic3d.v2.core import Grid
from .features import CandidateState


def random_action(state: CandidateState, rng: np.random.Generator) -> int:
    """Select a random legal candidate index uniformly at random."""
    if len(state.candidate_xy) == 0:
        raise ValueError("Cannot select action: candidate list is empty")
    return int(rng.integers(len(state.candidate_xy)))


def uniform_action(state: CandidateState, observed_mask: np.ndarray, grid: Grid) -> int:
    """Select the candidate site that maximizes physical distance to existing observed soundings."""
    if len(state.candidate_xy) == 0:
        raise ValueError("Cannot select action: candidate list is empty")
    sites = np.argwhere(np.asarray(observed_mask, dtype=bool).any(axis=2))
    if len(sites) == 0:
        raise ValueError("No existing observed CPT sounding found")

    site_m = np.array([grid.xy_m(int(x), int(y)) for x, y in sites])
    candidate_m = np.array([grid.xy_m(int(x), int(y)) for x, y in state.candidate_xy])

    # Euclidean distance from each candidate to all existing sites
    nearest = np.linalg.norm(candidate_m[:, None, :] - site_m[None, :, :], axis=2).min(axis=1)
    # Pick the candidate with maximum distance to existing sites
    return int(np.argmax(nearest))
