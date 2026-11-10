"""Frozen SchemaGAN V4.2 reconstruction adapter from observed CPT profiles only."""
from __future__ import annotations

import hashlib
import json
import sys
import time
from pathlib import Path
from typing import Tuple

import numpy as np
import torch
import torch.nn as nn
import torch.nn.functional as F

from synthetic3d.v2.core import Grid

EXPECTED_V4_2_SHA = "f130358b9044821912f53d9085c12084aeed8b506e8096704d75b6f3d7b4ed85"
DEFAULT_MEAN = 2.7903323310879604
DEFAULT_STD = 0.7723778445702414


class Block(nn.Module):
    """Dilated residual 3D convolution block for SchemaGAN V4.2."""

    def __init__(self, channels: int = 16, dilation: int = 1):
        super().__init__()
        self.net = nn.Sequential(
            nn.Conv3d(channels, channels, 3, padding=dilation, dilation=dilation),
            nn.LeakyReLU(0.1),
            nn.Conv3d(channels, channels, 3, padding=1),
        )

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        return F.leaky_relu(x + self.net(x), 0.1)


class Generator(nn.Module):
    """SchemaGAN V4.2 conditional residual generator accepting 7 feature channels."""

    def __init__(self, channels: int = 16):
        super().__init__()
        self.net = nn.Sequential(
            nn.Conv3d(7, channels, 3, padding=1),
            nn.LeakyReLU(0.1),
            Block(channels, 1),
            Block(channels, 2),
            Block(channels, 4),
            nn.Conv3d(channels, 1, 3, padding=1),
        )
        nn.init.zeros_(self.net[-1].weight)
        nn.init.zeros_(self.net[-1].bias)

    def forward(self, features: torch.Tensor) -> torch.Tensor:
        sparse = features[:, 0:1]
        mask = features[:, 1:2]
        idw = features[:, 2:3]

        prediction = idw + self.net(features)
        return torch.where(mask > 0, sparse, prediction)


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


class FrozenV4Reconstructor:
    """Inference-only adapter for trained SchemaGAN V4.2 models.
    
    Accepts arbitrary 3D grid dimensions (e.g. 24x24x12, 40x40x24),
    constructs the required 7 input channels, runs forward evaluation,
    and guarantees hard data consistency on observed voxels.
    """

    def __init__(
        self,
        checkpoint: Path | str,
        normalization_path: Path | str | None = None,
        *,
        device: str | None = None,
        verify_sha: bool = False,
    ):
        self.checkpoint = Path(checkpoint)
        if not self.checkpoint.exists():
            raise FileNotFoundError(f"SchemaGAN V4.2 checkpoint not found at: {self.checkpoint}")

        self.checkpoint_sha256 = _sha256(self.checkpoint)
        if verify_sha and self.checkpoint_sha256 != EXPECTED_V4_2_SHA:
            raise ValueError(
                f"SchemaGAN V4.2 checkpoint SHA-256 mismatch: {self.checkpoint_sha256} != {EXPECTED_V4_2_SHA}"
            )

        if not hasattr(np, "_core"):
            sys.modules.setdefault("numpy._core", np.core)
            sys.modules.setdefault("numpy._core.multiarray", np.core.multiarray)
            sys.modules.setdefault("numpy._core.numeric", np.core.numeric)

        # Select target device
        if device is not None:
            self.device = torch.device(device)
        elif torch.cuda.is_available():
            self.device = torch.device("cuda")
        elif torch.backends.mps.is_available():
            self.device = torch.device("mps")
        else:
            self.device = torch.device("cpu")

        # Load checkpoint
        saved = torch.load(self.checkpoint, map_location="cpu", weights_only=False)
        self.metadata = {k: saved[k] for k in saved if k not in ("generator_state", "discriminator_state")}

        # Determine normalization statistics
        if normalization_path is not None and Path(normalization_path).exists():
            norm_json = json.loads(Path(normalization_path).read_text())
            self.mean = float(norm_json.get("mean", DEFAULT_MEAN))
            self.std = float(norm_json.get("std", DEFAULT_STD))
        elif "normalization" in saved:
            norm_dict = saved["normalization"]
            self.mean = float(norm_dict.get("mean", DEFAULT_MEAN))
            self.std = float(norm_dict.get("std", DEFAULT_STD))
        else:
            self.mean = DEFAULT_MEAN
            self.std = DEFAULT_STD

        if self.std <= 0:
            raise ValueError("Normalization std must be positive.")

        # Build and freeze Generator model
        channels = saved.get("generator_channels", 16)
        self.model = Generator(channels=channels).to(self.device).eval()
        if "generator_state" in saved:
            self.model.load_state_dict(saved["generator_state"], strict=True)
        else:
            self.model.load_state_dict(saved, strict=False)

        for param in self.model.parameters():
            param.requires_grad_(False)

    def normalize(self, val: np.ndarray | float) -> np.ndarray | float:
        return (val - self.mean) / self.std

    def denormalize(self, val: np.ndarray | float) -> np.ndarray | float:
        return val * self.std + self.mean

    def predict(
        self,
        observed_ic: np.ndarray,
        observed_mask: np.ndarray,
        valid_mask: np.ndarray,
        grid: Grid,
    ) -> Tuple[np.ndarray, float]:
        """Produce 3D physical Ic reconstruction from observed CPT soundings.
        
        Args:
            observed_ic: Shape [nx, ny, nz] physical Ic values (0.0 at unobserved).
            observed_mask: Shape [nx, ny, nz] boolean array.
            valid_mask: Shape [nx, ny, nz] domain validity mask.
            grid: Grid specification containing dimensions and physical spacing.
            
        Returns:
            Tuple of (physical_ic_prediction [nx, ny, nz], elapsed_seconds).
        """
        shape = (grid.nx, grid.ny, grid.nz)
        obs = np.asarray(observed_ic, dtype=np.float32)
        mask = np.asarray(observed_mask, dtype=bool)
        valid = np.asarray(valid_mask, dtype=bool)

        if obs.shape != shape or mask.shape != shape or valid.shape != shape:
            raise ValueError(
                f"Shape mismatch: obs {obs.shape}, mask {mask.shape}, valid {valid.shape}, grid {shape}"
            )
        if not mask.any() or np.any(mask & ~valid) or not np.isfinite(obs[mask]).all():
            raise ValueError("Invalid observed CPT values or mask")

        sites_xy = mask.any(axis=2)
        px, py = np.where(sites_xy)
        if len(px) == 0:
            raise ValueError("At least one observed CPT sounding is required")

        nx, ny, nz = shape
        dx = float(grid.dx_m)
        dy = float(grid.dy_m)
        dz = float(grid.dz_m)

        # 1. Normalized sparse observations and binary mask
        norm_target = (obs - self.mean) / self.std
        sparse = np.where(mask, norm_target, 0.0).astype(np.float32)

        # 2. 2D Euclidean distance from all grid cells to observed CPT sites
        xx, yy = np.meshgrid(
            np.arange(nx, dtype=np.float32) * dx,
            np.arange(ny, dtype=np.float32) * dy,
            indexing="ij",
        )
        dist = np.sqrt(
            (xx[None] - px[:, None, None] * dx) ** 2
            + (yy[None] - py[:, None, None] * dy) ** 2
        )

        # 3. Depth-aware Inverse Distance Weighting (handles varying termination depths)
        inv_d2 = 1.0 / np.maximum(dist, 1e-5) ** 2
        obs_k_z = mask[px, py, :].astype(np.float32)

        num = np.einsum("kxy,kz->xyz", inv_d2, sparse[px, py, :], optimize=True)
        den = np.einsum("kxy,kz->xyz", inv_d2, obs_k_z, optimize=True)

        has_data = den > 0
        idw = np.zeros(shape, dtype=np.float32)
        idw[has_data] = num[has_data] / den[has_data]

        # If any depth slices have no active CPTs, propagate from nearest depth slice with observations
        if not has_data.all():
            valid_z = np.where(has_data.any(axis=(0, 1)))[0]
            if len(valid_z) > 0:
                for z in range(nz):
                    if not has_data[:, :, z].any():
                        nearest_z = valid_z[np.argmin(np.abs(valid_z - z))]
                        idw[:, :, z] = idw[:, :, nearest_z]

        idw = np.where(mask, sparse, idw)

        # 4. Normalized distance field
        distance_scale = max(nx * dx, ny * dy, 1.0)
        distance = np.broadcast_to(
            dist.min(axis=0)[:, :, None] / distance_scale,
            shape,
        ).astype(np.float32)

        # 5. Physical log spacing channels
        log_dx = np.full(shape, np.log1p(dx), dtype=np.float32)
        log_dy = np.full(shape, np.log1p(dy), dtype=np.float32)
        log_dz = np.full(shape, np.log1p(dz), dtype=np.float32)

        # 6. Stack into 7-channel volume
        features = np.stack([
            sparse,
            mask.astype(np.float32),
            idw,
            distance,
            log_dx,
            log_dy,
            log_dz,
        ]).astype(np.float32)

        # NumPy layout [C, X, Y, Z] -> PyTorch layout [C, Z, Y, X]
        features = np.transpose(features, (0, 3, 2, 1)).copy()
        features_t = torch.from_numpy(features)[None].to(self.device)

        # 7. Model forward pass
        started = time.perf_counter()
        with torch.inference_mode():
            pred_t = self.model(features_t)
            if self.device.type == "mps":
                torch.mps.synchronize()
        elapsed = time.perf_counter() - started

        # PyTorch layout [1, 1, Z, Y, X] -> NumPy layout [X, Y, Z]
        pred_normalized = pred_t[0, 0].cpu().numpy().transpose(2, 1, 0).copy()

        # 8. Denormalize to physical Robertson Ic
        physical = (pred_normalized * self.std + self.mean).astype(np.float32)

        # 9. Hard data consistency: preserve measured sounding exactly
        physical[mask] = obs[mask]

        return physical, elapsed
