from pathlib import Path
import numpy as np
import pandas as pd

from dqn3d.v44.runner import _entries, _case
from dqn3d.v44.adapter import FrozenV4Reconstructor
from dqn3d.v44.agent import CandidateDQNAgent
from dqn3d.v45.agent import (
    CandidateDQNAgent as V45Agent
)
from dqn3d.v44.simulator import SyntheticCPTSimulator

DATA = Path("data/synthetic3d_v4_geosyn/full_24k")
OUT = Path("results/dqn_v45_experimental/final_test_100")
OUT.mkdir(parents=True, exist_ok=True)

CHECKPOINTS = {
    "DQN_V45_5000":
        "results/dqn_v45_experimental/training_5000/best.pt",
    "DQN_V42":
        "model_export/DQN/best_v42.pt",
}

print("===== LOADING MODELS =====", flush=True)

recon = FrozenV4Reconstructor(
    "model_export/SchemaGAN_V4_2/SchemaGAN_V4_2.pt",
    DATA / "normalization.json",
    device="cpu"
)

agents = {}
for name, path in CHECKPOINTS.items():
    if not Path(path).is_file():
        raise FileNotFoundError(path)
    loader = (
        V45Agent
        if name in ("DQN_V45_300", "DQN_V45_5000")
        else CandidateDQNAgent
    )
    agents[name], _ = loader.load(
        path, map_location="cpu"
    )
    print(name, "LOADED")

policies = list(agents) + [
    "FARTHEST", "RANDOM_0", "RANDOM_1", "RANDOM_2"
]
# Use a different validation subset from the first 10 volumes
# used during training checkpoint selection.
entries = _entries(DATA, "test", 100)[:100]
assert len(entries) == 100, "Expected 20 validation volumes"
rows = []

def rmse(sim, truth, mask):
    error = sim.prediction[mask] - truth[mask]
    return float(np.sqrt(np.mean(error ** 2)))

from dqn3d.v4.features import build_state as features_v42
from dqn3d.v43.features import build_state as features_v43
from dqn3d.v44.features import build_state as features_v44
from dqn3d.v45.features import build_state as features_v45

NATIVE_FEATURES = {
    "DQN_V42": features_v42,
    "DQN_MULTISTEP": features_v42,
    "DQN_V43_300": features_v43,
    "DQN_V43_SMOKE": features_v43,
    "DQN_V44_300": features_v44,
    "DQN_V45_300": features_v45,
    "DQN_V45_5000": features_v45,
}

def choose_action(policy, state, sim, grid, rng):
    if policy in agents:
        # Use the feature representation that each
        # checkpoint was originally trained with.
        feature_builder = NATIVE_FEATURES[policy]

        native_state = feature_builder(
            sim.prediction,
            sim.observed_mask,
            sim.valid,
            grid,
            sim.access_mask,
            mean=getattr(
                sim.reconstructor, "mean", 2.790332
            ),
            std=getattr(
                sim.reconstructor, "std", 0.772378
            ),
        )

        if not np.array_equal(
            native_state.candidate_xy,
            state.candidate_xy
        ):
            raise RuntimeError(
                "Candidate indices differ between "
                "native and evaluation states"
            )

        return agents[policy].act(
            native_state, epsilon=0.0
        )

    if policy.startswith("RANDOM_"):
        return int(rng.integers(len(state.candidate_xy)))

    observed = np.argwhere(sim.observed_mask.any(axis=2))
    candidates = np.asarray(state.candidate_xy)

    observed_m = np.asarray([
        grid.xy_m(int(x), int(y)) for x, y in observed
    ], dtype=float)

    candidate_m = np.asarray([
        grid.xy_m(int(x), int(y)) for x, y in candidates
    ], dtype=float)

    distances = np.linalg.norm(
        candidate_m[:, None, :] - observed_m[None, :, :],
        axis=2
    ).min(axis=1)

    return int(np.argmax(distances))

print("\n===== SEQUENTIAL VALIDATION =====", flush=True)

for case_id, entry in enumerate(entries):
    truth, valid, grid = _case(DATA, entry)
    xy = np.argwhere(valid.any(axis=2))

    rng_split = np.random.default_rng(10000 + case_id)
    xy = xy[rng_split.permutation(len(xy))]

    n_holdout = max(1, int(len(xy) * 0.10))
    reserved = xy[:n_holdout]
    available = xy[n_holdout:]

    evaluation_mask = np.zeros_like(valid, dtype=bool)
    for x, y in reserved:
        evaluation_mask[x, y] = valid[x, y]

    for n_initial in [1, 2, 3, 5, 8, 12, 16]:
        initial = [
            tuple(map(int, point))
            for point in available[:n_initial]
        ]

        for policy in policies:
            sim = SyntheticCPTSimulator(
                recon, truth, valid, grid,
                evaluation_mask=evaluation_mask
            )

            state = sim.reset(initial)
            start_rmse = rmse(sim, truth, evaluation_mask)

            random_seed_id = (
                int(policy.split("_")[-1])
                if policy.startswith("RANDOM_")
                else 0
            )
            rng_policy = np.random.default_rng(
                20261103
                + case_id * 1000
                + n_initial * 10
                + random_seed_id
            )

            for step in range(1, 4):
                if len(state.candidate_xy) == 0:
                    break

                action = choose_action(
                    policy, state, sim, grid, rng_policy
                )

                x, y = map(int, state.candidate_xy[action])

                observed = np.argwhere(
                    sim.observed_mask.any(axis=2)
                )
                site_m = np.asarray(grid.xy_m(x, y))
                nearest_m = min(
                    np.linalg.norm(
                        site_m - np.asarray(
                            grid.xy_m(int(ox), int(oy))
                        )
                    )
                    for ox, oy in observed
                )

                before = rmse(sim, truth, evaluation_mask)
                state, reward, done, info = sim.step(action)
                after = rmse(sim, truth, evaluation_mask)

                assert np.isclose(
                    reward, before - after, atol=1e-6
                )

                rows.append({
                    "case": case_id,
                    "initial_count": n_initial,
                    "policy": policy,
                    "step": step,
                    "x": x,
                    "y": y,
                    "nearest_distance_m": nearest_m,
                    "start_rmse": start_rmse,
                    "rmse_before": before,
                    "rmse_after": after,
                    "step_gain": before - after,
                    "cumulative_gain": start_rmse - after,
                })

                if done:
                    break

        print(
            f"Case {case_id + 1}/{len(entries)} | "
            f"initial CPT {n_initial} | PASS",
            flush=True
        )

df = pd.DataFrame(rows)

summary = (
    df.groupby(["policy", "step"], as_index=False)
    .agg(
        scenarios=("rmse_after", "size"),
        mean_rmse=("rmse_after", "mean"),
        mean_cumulative_gain=("cumulative_gain", "mean"),
        mean_nearest_distance_m=(
            "nearest_distance_m", "mean"
        ),
        improvement_rate=(
            "step_gain", lambda s: float((s > 0).mean())
        ),
    )
)

print("\n===== RMSE BY STEP =====")
print(summary.round(6).to_string(index=False))

print("\n===== FINAL STEP COMPARISON =====")
final = summary[summary.step == 3].sort_values("mean_rmse")
print(final.round(6).to_string(index=False))

df.to_csv(OUT / "details.csv", index=False)
summary.to_csv(OUT / "summary.csv", index=False)

print("\nSaved:", OUT)
print("STATUS: FINAL TEST EVALUATION COMPLETE")
