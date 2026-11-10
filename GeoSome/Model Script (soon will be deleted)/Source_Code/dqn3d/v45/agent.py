"""Candidate Q-network, replay buffer, and masked Bellman learning for DQN V4.2."""
from __future__ import annotations

import os
from collections import deque
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Optional, Tuple

import numpy as np
import torch
from torch import nn

from .features import CANDIDATE_NAMES, GLOBAL_NAMES, CandidateState


@dataclass(frozen=True)
class AgentConfig:
    learning_rate: float = 1e-4
    gamma: float = 0.99
    replay_capacity: int = 2000
    batch_size: int = 16
    target_update_steps: int = 100
    epsilon_start: float = 1.0
    epsilon_end: float = 0.05
    epsilon_decay_episodes: int = 350
    seed: int = 14
    hidden_width: int = 64

    def __post_init__(self) -> None:
        if (
            self.learning_rate <= 0
            or not 0 <= self.gamma <= 1
            or self.replay_capacity < 1
            or self.batch_size < 1
            or self.target_update_steps < 1
            or self.hidden_width < 1
        ):
            raise ValueError("Invalid DQN agent configuration parameters")


class SharedCandidateQ(nn.Module):
    """Feedforward network scoring individual candidate sites conditioned on global site context."""

    def __init__(self, width: int = 64):
        super().__init__()
        input_dim = len(CANDIDATE_NAMES) + len(GLOBAL_NAMES)
        self.net = nn.Sequential(
            nn.Linear(input_dim, width),
            nn.ReLU(),
            nn.Linear(width, width),
            nn.ReLU(),
            nn.Linear(width, 1),
        )

    def forward(self, features: torch.Tensor, context: torch.Tensor) -> torch.Tensor:
        """Score candidate sites.
        
        Args:
            features: Shape [N, 17] candidate local features.
            context: Shape [11] global context.
        Returns:
            Shape [N] vector of predicted Q-values.
        """
        if features.ndim != 2 or features.shape[1] != len(CANDIDATE_NAMES) or context.shape != (len(GLOBAL_NAMES),):
            raise ValueError(
                f"Candidate Q tensor shape mismatch: features {features.shape}, context {context.shape}"
            )
        if len(features) == 0:
            return features.new_empty((0,))
        combined = torch.cat((features, context[None].expand(len(features), -1)), dim=1)
        return self.net(combined).squeeze(1)


@dataclass(frozen=True)
class Transition:
    state: CandidateState
    action_index: int
    action_xy: Tuple[int, int]
    reward: float
    next_state: CandidateState
    done: bool


def _copy_state(state: CandidateState) -> CandidateState:
    return CandidateState(
        state.candidate_xy.copy(),
        state.features.copy(),
        state.global_context.copy(),
    )


class CandidateDQNAgent:
    """Masked deep Q-learning agent for variable-candidate spatial action spaces."""

    def __init__(self, config: AgentConfig = AgentConfig(), device: str = "cpu"):
        self.config = config
        self.device = torch.device(device)
        self.rng = np.random.default_rng(config.seed)
        torch.manual_seed(config.seed)

        self.online = SharedCandidateQ(config.hidden_width).to(self.device)
        self.target = SharedCandidateQ(config.hidden_width).to(self.device)
        self.target.load_state_dict(self.online.state_dict())
        for param in self.target.parameters():
            param.requires_grad_(False)

        self.optimizer = torch.optim.Adam(self.online.parameters(), lr=config.learning_rate)
        self.loss_fn = nn.MSELoss()
        self.replay: deque[Transition] = deque(maxlen=config.replay_capacity)
        self.learn_steps = 0

    def epsilon(self, episode: int) -> float:
        if self.config.epsilon_decay_episodes <= 0:
            return self.config.epsilon_end
        frac = min(max(float(episode) / float(self.config.epsilon_decay_episodes), 0.0), 1.0)
        return float(self.config.epsilon_start + frac * (self.config.epsilon_end - self.config.epsilon_start))

    @torch.no_grad()
    def scores(self, state: CandidateState) -> np.ndarray:
        if len(state.candidate_xy) == 0:
            return np.empty((0,), dtype=np.float32)
        feat_t = torch.from_numpy(state.features).to(self.device)
        ctx_t = torch.from_numpy(state.global_context).to(self.device)
        return self.online(feat_t, ctx_t).cpu().numpy()

    def act(self, state: CandidateState, epsilon: float = 0.0) -> int:
        n = len(state.candidate_xy)
        if n == 0:
            raise ValueError("Cannot act: no legal candidate locations available")
        if epsilon > 0.0 and self.rng.random() < epsilon:
            return int(self.rng.integers(n))
        scores = self.scores(state)
        best_indices = np.flatnonzero(scores == scores.max())
        return int(self.rng.choice(best_indices))

    def observe(
        self,
        state: CandidateState,
        action_index: int,
        reward: float,
        next_state: CandidateState,
        done: bool,
    ) -> Optional[float]:
        action_xy = tuple(map(int, state.candidate_xy[action_index]))
        trans = Transition(
            _copy_state(state),
            action_index,
            action_xy,
            float(reward),
            _copy_state(next_state),
            done,
        )
        self.replay.append(trans)
        return self._learn_step()

    def _learn_step(self) -> Optional[float]:
        if len(self.replay) < self.config.batch_size:
            return None

        indices = self.rng.choice(len(self.replay), size=self.config.batch_size, replace=False)
        batch = [self.replay[i] for i in indices]

        losses = []
        for trans in batch:
            # Current Q-value
            feat_t = torch.from_numpy(trans.state.features).to(self.device)
            ctx_t = torch.from_numpy(trans.state.global_context).to(self.device)
            current_q = self.online(feat_t, ctx_t)[trans.action_index]

            if trans.done or len(trans.next_state.candidate_xy) == 0:
                target_q = torch.tensor(trans.reward, dtype=torch.float32, device=self.device)
            else:
                with torch.no_grad():
                    next_feat_t = torch.from_numpy(trans.next_state.features).to(self.device)
                    next_ctx_t = torch.from_numpy(trans.next_state.global_context).to(self.device)
                    # Double DQN: action selected by online net, evaluated by target net
                    next_online_scores = self.online(next_feat_t, next_ctx_t)
                    best_next_action = torch.argmax(next_online_scores)
                    next_target_scores = self.target(next_feat_t, next_ctx_t)
                    max_next_q = next_target_scores[best_next_action]
                    target_q = torch.tensor(trans.reward, dtype=torch.float32, device=self.device) + self.config.gamma * max_next_q

            losses.append(self.loss_fn(current_q, target_q))

        batch_loss = torch.stack(losses).mean()
        self.optimizer.zero_grad()
        batch_loss.backward()
        torch.nn.utils.clip_grad_norm_(self.online.parameters(), max_norm=1.0)
        self.optimizer.step()

        self.learn_steps += 1
        if self.learn_steps % self.config.target_update_steps == 0:
            self.target.load_state_dict(self.online.state_dict())

        return float(batch_loss.item())

    def save(self, path: Path | str, metadata: dict | None = None) -> None:
        path = Path(path)
        path.parent.mkdir(parents=True, exist_ok=True)
        payload = {
            "version": "dqn-v4.2",
            "config": asdict(self.config),
            "online_state": self.online.state_dict(),
            "target_state": self.target.state_dict(),
            "optimizer_state": self.optimizer.state_dict(),
            "learn_steps": self.learn_steps,
            "metadata": metadata or {},
        }
        tmp_path = path.with_suffix(path.suffix + ".tmp")
        torch.save(payload, tmp_path)
        os.replace(tmp_path, path)

    @classmethod
    def load(cls, path: Path | str, map_location: str = "cpu") -> Tuple[CandidateDQNAgent, dict]:
        path = Path(path)
        if not path.exists():
            raise FileNotFoundError(f"Checkpoint not found at: {path}")
        payload = torch.load(path, map_location=map_location, weights_only=False)
        cfg = AgentConfig(**payload["config"])
        agent = cls(cfg, device=map_location)
        agent.online.load_state_dict(payload["online_state"])
        agent.target.load_state_dict(payload["target_state"])
        if "optimizer_state" in payload:
            agent.optimizer.load_state_dict(payload["optimizer_state"])
        agent.learn_steps = payload.get("learn_steps", 0)
        return agent, payload.get("metadata", {})
