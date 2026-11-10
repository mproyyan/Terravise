"""Fixed-mask sequential checkpoint validation for DQN V4.3."""
from pathlib import Path
import numpy as np

from .runner import _entries, _case, _initial
from .simulator import SyntheticCPTSimulator


def evaluate_sequential_checkpoint(
    agent, reconstructor, dataset_root,
    volume_count=5, initial_counts=(1, 2, 3),
    seed=1000014, horizon=3, holdout_fraction=0.10,
):
    root = Path(dataset_root)
    results = {"dqn": [], "farthest": []}
    gains = {"dqn": [], "farthest": []}
    paired_wins = []

    for case_i, entry in enumerate(
        _entries(root, "validation", volume_count)
    ):
        truth, valid, grid = _case(root, entry)
        coords = np.argwhere(valid.any(axis=2))

        rng = np.random.default_rng(seed + case_i)
        coords = coords[rng.permutation(len(coords))]

        n_holdout = max(
            1, int(len(coords) * holdout_fraction)
        )
        reserved = coords[:n_holdout]
        eligible = coords[n_holdout:]

        mask = np.zeros_like(valid, dtype=bool)
        for x, y in reserved:
            mask[x, y] = valid[x, y]

        if not mask.any():
            raise ValueError("Empty evaluation mask")

        for n_initial in initial_counts:
            if len(eligible) < n_initial + horizon:
                raise ValueError("Not enough legal CPT sites")

            # Identical initial CPTs for both policies.
            initial = [
                tuple(map(int, xy))
                for xy in eligible[:n_initial]
            ]

            scenario = {}
            for policy in ("dqn", "farthest"):
                sim = SyntheticCPTSimulator(
                    reconstructor, truth, valid, grid,
                    evaluation_mask=mask
                )
                state = sim.reset(initial)

                def rmse():
                    delta = sim.prediction[mask] - truth[mask]
                    return float(
                        np.sqrt(np.mean(delta ** 2))
                    )

                start_rmse = rmse()

                for step in range(horizon):
                    if len(state.candidate_xy) == 0:
                        break

                    if policy == "dqn":
                        action = agent.act(
                            state, epsilon=0.0
                        )
                    else:
                        observed = np.argwhere(
                            sim.observed_mask.any(axis=2)
                        )
                        sites_m = np.array([
                            grid.xy_m(int(x), int(y))
                            for x, y in observed
                        ])
                        candidate_m = np.array([
                            grid.xy_m(int(x), int(y))
                            for x, y in state.candidate_xy
                        ])
                        distances = np.linalg.norm(
                            candidate_m[:, None, :]
                            - sites_m[None, :, :],
                            axis=2
                        )
                        action = int(np.argmax(
                            distances.min(axis=1)
                        ))

                    state, reward, done, _ = sim.step(action)
                    if done:
                        break

                final_rmse = rmse()
                results[policy].append(final_rmse)
                gains[policy].append(
                    start_rmse - final_rmse
                )
                scenario[policy] = final_rmse

            paired_wins.append(
                scenario["dqn"] < scenario["farthest"]
            )

    return {
        "dqn_rmse": float(np.mean(results["dqn"])),
        "farthest_rmse": float(np.mean(results["farthest"])),
        "dqn_mean_improvement": float(
            np.mean(gains["dqn"])
        ),
        "win_rate": float(np.mean(paired_wins)),
        "scenarios": len(paired_wins),
    }
