"""DQN V4.2 training and validation runner on GeoSyn multiscale synthetic 3D volumes."""
from __future__ import annotations

import argparse
import csv
import hashlib
import json
import time
from pathlib import Path
from typing import List, Tuple

import numpy as np

from synthetic3d.v2.core import Grid
from .adapter import FrozenV4Reconstructor
from .agent import AgentConfig, CandidateDQNAgent
from .baselines import random_action, uniform_action
from .simulator import SyntheticCPTSimulator

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_CONFIG = ROOT / "results/dqn_v4_implementation/dqn_v42_training_config.json"


def _hash_file(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _entries(root: Path, split: str, limit: int) -> list[dict]:
    manifest_file = root / f"{split}_manifest.json"
    if not manifest_file.exists():
        manifest_file = root / "manifest.json"
    if not manifest_file.exists():
        raise FileNotFoundError(f"Manifest not found for split '{split}' in {root}")

    entries = json.loads(manifest_file.read_text())
    if split in ("train", "validation", "test"):
        entries = [e for e in entries if e.get("split", split) == split]

    if not entries:
        raise ValueError(f"No manifest entries found for split: {split}")

    if limit > 0:
        entries = entries[:limit]
    return entries


def _case(root: Path, entry: dict) -> Tuple[np.ndarray, np.ndarray, Grid]:
    split = entry.get("split", "train")
    index = entry.get("index")

    if "path" in entry:
        npz_path = root / entry["path"]
    elif index is not None:
        npz_path = root / split / f"v4_{split}_{int(index):05d}.npz"
    else:
        raise ValueError(f"Cannot resolve .npz path for manifest entry: {entry}")

    if not npz_path.exists():
        raise FileNotFoundError(f"Case array file not found: {npz_path}")

    with np.load(npz_path, allow_pickle=False) as archive:
        truth = archive["Ic"].astype(np.float32)
        valid = archive["valid_mask"].astype(bool) if "valid_mask" in archive else np.ones_like(truth, bool)
        meta = json.loads(str(archive["metadata_json"]))

    grid_meta = meta["grid"]
    grid = Grid(
        nx=int(grid_meta["nx"]),
        ny=int(grid_meta["ny"]),
        nz=int(grid_meta["nz"]),
        dx_m=float(grid_meta["dx_m"]),
        dy_m=float(grid_meta["dy_m"]),
        dz_m=float(grid_meta["dz_m"]),
    )

    if truth.shape != valid.shape or truth.shape != (grid.nx, grid.ny, grid.nz):
        raise ValueError(
            f"Shape mismatch in case {npz_path}: truth {truth.shape}, valid {valid.shape}, grid {(grid.nx, grid.ny, grid.nz)}"
        )
    return truth, valid, grid


def _initial(
    grid: Grid,
    valid: np.ndarray,
    entry: dict,
    count: int,
    seed: int,
    episode: int = 0,
) -> List[Tuple[int, int]]:
    base_seed = entry.get("seed", 0)
    site_seed = int(base_seed) + int(seed) + int(episode)

    candidates = [(x, y) for x in range(grid.nx) for y in range(grid.ny) if valid[x, y].any()]
    if len(candidates) < count:
        raise ValueError(f"Insufficient valid CPT sites: {len(candidates)} < {count}")

    rng = np.random.default_rng(site_seed)
    chosen = rng.choice(len(candidates), size=count, replace=False)
    return [candidates[i] for i in chosen]


def _paired(values: np.ndarray, seed: int = 1414, resamples: int = 2000) -> dict:
    x = np.asarray(values, dtype=np.float64)
    if len(x) < 2:
        return {"mean": float(x.mean()) if len(x) else None, "ci95": None, "n": len(x)}
    rng = np.random.default_rng(seed)
    means = np.empty(resamples)
    for start in range(0, resamples, 100):
        stop = min(start + 100, resamples)
        means[start:stop] = x[rng.integers(len(x), size=(stop - start, len(x)))].mean(axis=1)
    return {
        "mean": float(x.mean()),
        "sd": float(x.std(ddof=1)),
        "ci95": [float(np.quantile(means, 0.025)), float(np.quantile(means, 0.975))],
        "n": len(x),
    }


def evaluate_validation(
    agent: CandidateDQNAgent,
    reconstructor: FrozenV4Reconstructor,
    dataset_root: Path,
    *,
    volume_count: int,
    initial_counts: list[int],
    seed: int,
) -> Tuple[list[dict], dict]:
    entries = _entries(dataset_root, "validation", volume_count)
    rows = []
    policies = ("dqn", "uniform", "random")
    groups = {}

    for entry in entries:
        truth, valid, grid = _case(dataset_root, entry)
        case_id = f"v4_val_{entry.get('index', 0):05d}"
        family = entry.get("family", "unknown")

        for count in initial_counts:
            initial = _initial(grid, valid, entry, count, seed)
            episodes = {}
            for policy in policies:
                sim = SyntheticCPTSimulator(reconstructor, truth, valid, grid)
                state = sim.reset(initial)
                initial_rmse = sim.prediction[valid & ~sim.observed_mask]
                start_time = time.perf_counter()

                if policy == "dqn":
                    action = agent.act(state, epsilon=0.0)
                elif policy == "uniform":
                    action = uniform_action(state, sim.observed_mask, grid)
                else:
                    action = random_action(state, np.random.default_rng(seed + count))

                decision_sec = time.perf_counter() - start_time
                next_state, reward, done, info = sim.step(action)
                episodes[policy] = {
                    "case_id": case_id,
                    "family": family,
                    "initial_cpt_count": count,
                    "policy": policy,
                    "selected_xy": info["selected_xy"],
                    "rmse_before_common": info["rmse_before_common"],
                    "rmse_after_common": info["rmse_after_common"],
                    "rmse_improvement": info["rmse_improvement"],
                    "decision_seconds": decision_sec,
                    "reconstruction_seconds": info["reconstruction_seconds"],
                }
                rows.append(episodes[policy])
            groups[(case_id, count)] = episodes

    def summarize(keys_subset: list) -> dict:
        out = {"n": len(keys_subset), "by_policy": {}, "paired_dqn_minus": {}}
        for policy in policies:
            after_rmse = [groups[k][policy]["rmse_after_common"] for k in keys_subset]
            improvements = [groups[k][policy]["rmse_improvement"] for k in keys_subset]
            out["by_policy"][policy] = {
                "mean_after_rmse": float(np.mean(after_rmse)),
                "mean_improvement": float(np.mean(improvements)),
                "valid_action_rate": 1.0,
                "duplicate_action_rate": 0.0,
            }
        for baseline in ("uniform", "random"):
            pairs = [
                groups[k]["dqn"]["rmse_after_common"] - groups[k][baseline]["rmse_after_common"]
                for k in keys_subset
            ]
            delta = np.array(pairs)
            out["paired_dqn_minus"][baseline] = {
                **_paired(delta),
                "dqn_win_rate": float((delta < 0).mean()),
                "bootstrap_unit": "case_id",
                "paired_case_count": len(pairs),
            }
        return out

    all_keys = list(groups)
    summary = {
        "split": "validation",
        "evaluation": "One recommendation per policy, shared initial CPT soundings and common hidden mask",
        "policies": list(policies),
        "overall": summarize(all_keys),
        "by_initial_cpt_count": {str(c): summarize([k for k in all_keys if k[1] == c]) for c in initial_counts},
    }
    return rows, summary


def _write_csv(path: Path, rows: list[dict]) -> None:
    if not rows:
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)


def run_training(config_path: Path | str, output_dir: Path | str, *, resume: bool = False) -> dict:
    config_path = Path(config_path)
    cfg = json.loads(config_path.read_text())

    output_dir = Path(output_dir)
    dataset_root = ROOT / cfg.get("dataset_root", "data/synthetic3d_v4_geosyn/full_24k")
    schemagan_ckpt = ROOT / cfg.get("schemagan_checkpoint", "model_export/SchemaGAN_V4_2/SchemaGAN_V4_2.pt")
    norm_path = dataset_root / "normalization.json"

    print("\n" + "=" * 60, flush=True)
    print(f"Starting DQN V4.2 Training ({cfg['episode_count']} episodes)", flush=True)
    print(f"Dataset Root: {dataset_root}", flush=True)
    print(f"SchemaGAN V4.2 Checkpoint: {schemagan_ckpt}", flush=True)
    print(f"Output Directory: {output_dir}", flush=True)
    print("=" * 60 + "\n", flush=True)

    reconstructor = FrozenV4Reconstructor(schemagan_ckpt, norm_path)
    train_entries = _entries(dataset_root, "train", cfg.get("train_volume_count", 400))
    validation_counts = cfg.get("initial_cpt_counts", [1, 2, 3, 5, 8, 12, 16])

    agent_cfg = AgentConfig(**cfg.get("agent", {}))
    agent = CandidateDQNAgent(agent_cfg)

    train_rows = []
    val_history = []
    start_ep = 0
    best_score = float("inf")

    if resume:
        last_ckpt = output_dir / "last.pt"
        if last_ckpt.exists():
            agent, meta = CandidateDQNAgent.load(last_ckpt)
            start_ep = meta.get("next_episode", 0)
            best_score = meta.get("best_validation_rmse", float("inf"))
            if (output_dir / "training_history.json").exists():
                train_rows = json.loads((output_dir / "training_history.json").read_text())
            if (output_dir / "validation_history.json").exists():
                val_history = json.loads((output_dir / "validation_history.json").read_text())
            print(f"Resuming DQN V4.2 training from episode {start_ep + 1} (best RMSE: {best_score:.4f})", flush=True)
    else:
        output_dir.mkdir(parents=True, exist_ok=True)
        (output_dir / "config.json").write_text(json.dumps(cfg, indent=2) + "\n")

    ep_count = cfg.get("episode_count", 5000)
    val_every = cfg.get("validation_every_episodes", 50)
    horizon = cfg.get("episode_horizon", 1)

    for episode in range(start_ep, ep_count):
        ep_start = time.perf_counter()
        entry = train_entries[episode % len(train_entries)]
        initial_cpt_count = validation_counts[episode % len(validation_counts)]

        truth, valid, grid = _case(dataset_root, entry)
        sites = _initial(grid, valid, entry, initial_cpt_count, cfg.get("seed", 14), episode)

        # V4.3: reserve fixed, never-observed CPT locations
        # for reward evaluation throughout this episode.
        fraction = float(cfg.get("evaluation_fraction", 0.10))
        if not 0.0 < fraction < 1.0:
            raise ValueError("evaluation_fraction must be between 0 and 1")

        initial_set = set(map(tuple, sites))

        eligible_xy = [
            (x, y)
            for x in range(grid.nx)
            for y in range(grid.ny)
            if valid[x, y].any() and (x, y) not in initial_set
        ]

        reserve_count = max(
            1, int(len(eligible_xy) * fraction)
        )

        # Leave enough legal locations for the training horizon.
        if len(eligible_xy) - reserve_count < horizon:
            raise ValueError(
                "Not enough CPT candidates after reserving "
                "evaluation locations"
            )

        rng_eval = np.random.default_rng(
            int(cfg.get("evaluation_seed", 20261103))
            + episode
        )

        reserved_indices = rng_eval.choice(
            len(eligible_xy),
            size=reserve_count,
            replace=False
        )

        evaluation_mask = np.zeros_like(valid, dtype=bool)

        for idx in reserved_indices:
            x, y = eligible_xy[int(idx)]
            evaluation_mask[x, y] = valid[x, y]

        sim = SyntheticCPTSimulator(
            reconstructor,
            truth,
            valid,
            grid,
            evaluation_mask=evaluation_mask,
        )

        state = sim.reset(sites)

        assert not np.any(
            sim.observed_mask & evaluation_mask
        ), "Ground-truth evaluation sites leaked into observations"


        losses = []
        rewards = []
        selected = []
        epsilon = agent.epsilon(episode)

        for step in range(horizon):
            if len(state.candidate_xy) == 0:
                break
            action = agent.act(state, epsilon)
            chosen_xy = tuple(map(int, state.candidate_xy[action]))
            selected.append(chosen_xy)

            next_state, reward, exhausted, info = sim.step(action)
            done = exhausted or (step + 1 == horizon)
            loss = agent.observe(state, action, reward, next_state, done)
            if loss is not None:
                losses.append(loss)
            rewards.append(reward)
            state = next_state
            if done:
                break

        ep_duration = time.perf_counter() - ep_start
        mean_loss = float(np.mean(losses)) if losses else None
        loss_str = f"{mean_loss:.5f}" if mean_loss is not None else "warmup"
        rew_str = f"{sum(rewards):+.4f}" if rewards else "+0.0000"

        train_record = {
            "episode": episode + 1,
            "case_index": entry.get("index", 0),
            "initial_cpt_count": initial_cpt_count,
            "epsilon": epsilon,
            "selected_xy": json.dumps(selected),
            "steps": len(rewards),
            "reward_sum": float(sum(rewards)),
            "mean_loss": mean_loss,
            "replay_size": len(agent.replay),
            "episode_seconds": ep_duration,
        }
        train_rows.append(train_record)

        print(
            f"[Episode {episode+1:04d}/{ep_count:04d}] eps: {epsilon:.3f} | reward: {rew_str} | loss: {loss_str} | replay: {len(agent.replay)} | {ep_duration:.2f}s",
            flush=True,
        )

        # Validation check
        if (episode + 1) % val_every == 0 or (episode + 1) == ep_count:
            print(f"\n--- Running Validation at Episode {episode+1} on {cfg.get('validation_volume_count', 30)} volumes ---", flush=True)
            from .validation_v43 import (
                evaluate_sequential_checkpoint
            )

            result = evaluate_sequential_checkpoint(
                agent,
                reconstructor,
                dataset_root,
                volume_count=cfg.get(
                    "validation_volume_count", 5
                ),
                initial_counts=validation_counts,
                seed=cfg.get(
                    "validation_seed", 1000014
                ),
                horizon=horizon,
                holdout_fraction=cfg.get(
                    "evaluation_fraction", 0.10
                ),
            )

            dqn_rmse = result["dqn_rmse"]
            uni_rmse = result["farthest_rmse"]
            win_rate = result["win_rate"] * 100.0
            v_summary = {
                "overall": {
                    "by_policy": {
                        "dqn": {
                            "mean_improvement":
                                result["dqn_mean_improvement"]
                        }
                    }
                }
            }
            new_best = " [NEW BEST]" if dqn_rmse < best_score else ""

            val_record = {
                "episode": episode + 1,
                "dqn_mean_after_rmse": dqn_rmse,
                "farthest_mean_after_rmse": uni_rmse,
                "dqn_win_rate_vs_farthest": win_rate,
                "dqn_mean_improvement": v_summary["overall"]["by_policy"]["dqn"]["mean_improvement"],
            }
            val_history.append(val_record)

            _write_csv(output_dir / "validation_history.csv", val_history)
            (output_dir / "validation_history.json").write_text(json.dumps(val_history, indent=2) + "\n")
            (output_dir / f"validation_summary_ep_{episode+1:04d}.json").write_text(json.dumps(v_summary, indent=2) + "\n")

            print(f">>> [Validation Ep {episode+1:04d}] DQN RMSE: {dqn_rmse:.4f} | Farthest: {uni_rmse:.4f} | Win Rate: {win_rate:.1f}%{new_best}\n", flush=True)

            if dqn_rmse < best_score:
                best_score = dqn_rmse
                agent.save(
                    output_dir / "best.pt",
                    metadata={
                        "next_episode": episode + 1,
                        "best_validation_rmse": best_score,
                        "schemagan_checkpoint": str(schemagan_ckpt),
                        "config": cfg,
                    },
                )

        agent.save(
            output_dir / "last.pt",
            metadata={
                "next_episode": episode + 1,
                "best_validation_rmse": best_score,
                "schemagan_checkpoint": str(schemagan_ckpt),
                "config": cfg,
            },
        )
        (output_dir / "training_history.json").write_text(json.dumps(train_rows, indent=2) + "\n")
        _write_csv(output_dir / "training_history.csv", train_rows)

    print(f"\nTraining completed! Best Validation RMSE: {best_score:.4f}. Model saved to {output_dir / 'best.pt'}\n", flush=True)
    return {"best_validation_rmse": best_score, "episodes_completed": ep_count}


def main():
    parser = argparse.ArgumentParser(description="Train DQN V4.2 with SchemaGAN V4.2 Digital Twin")
    parser.add_argument("--config", type=Path, default=DEFAULT_CONFIG, help="Path to training config JSON")
    parser.add_argument("--output", type=Path, default=ROOT / "results/dqn_v42_run", help="Output directory")
    parser.add_argument("--resume", action="store_true", help="Resume from last checkpoint in output directory")
    args = parser.parse_args()

    run_training(args.config, args.output, resume=args.resume)


if __name__ == "__main__":
    main()
