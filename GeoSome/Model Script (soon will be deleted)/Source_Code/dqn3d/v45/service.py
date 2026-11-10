"""Field-facing borehole recommendation service using trained DQN V4.2 and SchemaGAN V4.2."""
from __future__ import annotations

from typing import Optional

import numpy as np

from synthetic3d.v2.core import Grid
from .agent import CandidateDQNAgent
from .features import build_state


def recommend(
    reconstructor,
    agent: CandidateDQNAgent,
    observed_ic: np.ndarray,
    observed_mask: np.ndarray,
    valid_mask: np.ndarray,
    grid: Grid,
    access_mask: Optional[np.ndarray] = None,
    *,
    top_k: int = 0,
) -> dict:
    """Recommend the next optimal CPT borehole location.
    
    Args:
        reconstructor: FrozenV4Reconstructor instance.
        agent: Trained CandidateDQNAgent.
        observed_ic: Observed Ic volume [nx, ny, nz].
        observed_mask: Boolean mask of observations [nx, ny, nz].
        valid_mask: Boolean mask of domain [nx, ny, nz].
        grid: CPTGrid geometry.
        access_mask: Optional 2D boolean mask [nx, ny] of accessible drill sites.
        top_k: If > 0, return top K ranked candidates in order of Q-score.
        
    Returns:
        Dictionary containing top recommendation coordinates, physical meters, Q-score,
        and optionally ranked candidates.
    """
    if top_k < 0:
        raise ValueError("top_k must be non-negative")

    reconstruction, seconds = reconstructor.predict(observed_ic, observed_mask, valid_mask, grid)
    state = build_state(
        reconstruction,
        observed_mask,
        valid_mask,
        grid,
        access_mask,
        mean=getattr(reconstructor, "mean", 2.790332),
        std=getattr(reconstructor, "std", 0.772378),
    )

    if len(state.candidate_xy) == 0:
        return {
            "status": "no_candidate",
            "reconstruction_seconds": seconds,
            "ranked_candidates": [],
        }

    scores = agent.scores(state)
    order = sorted(
        range(len(scores)),
        key=lambda i: (-float(scores[i]), int(state.candidate_xy[i, 0]), int(state.candidate_xy[i, 1])),
    )

    def row(index: int) -> dict:
        x, y = map(int, state.candidate_xy[index])
        xm, ym = grid.xy_m(x, y)
        return {
            "x_index": x,
            "y_index": y,
            "x_m": float(xm),
            "y_m": float(ym),
            "q_score": float(scores[index]),
            "nearest_cpt_distance_fraction": float(state.features[index, 2]),
        }

    top_choice = row(order[0])
    ranked = [row(i) for i in order[:top_k]] if top_k > 0 else []

    return {
        "status": "ok",
        **top_choice,
        "reconstruction_seconds": seconds,
        "ranked_candidates": ranked,
    }
