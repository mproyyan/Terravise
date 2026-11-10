from pathlib import Path
import json
import math

import joblib
import numpy as np
import pandas as pd
from sklearn.ensemble import HistGradientBoostingRegressor

ROOT = Path("results/uncertainty_v2")
ALPHA = 0.10

FEATURES = [
    "distance_to_cpt_m",
    "depth_m",
    "predicted_ic",
    "lateral_gradient",
    "vertical_gradient",
    "nearby_cpt_fraction_25m",
    "n_cpt",
    "dx_m",
    "dy_m",
    "dz_m",
]

train = pd.read_csv(ROOT / "train.csv")
cal = pd.read_csv(ROOT / "calibration.csv")
test = pd.read_csv(ROOT / "evaluation.csv")

splits = [train, cal, test]

for frame in splits:
    required = set(FEATURES + [
        "volume_index", "abs_error_ic"
    ])
    assert required.issubset(frame.columns)
    assert np.isfinite(
        frame[FEATURES + ["abs_error_ic"]].to_numpy()
    ).all()
    assert (frame.abs_error_ic >= 0).all()

ids = [set(df.volume_index.unique()) for df in splits]
assert not (ids[0] & ids[1])
assert not (ids[0] & ids[2])
assert not (ids[1] & ids[2])

X_train = train[FEATURES].to_numpy()
y_train = train.abs_error_ic.to_numpy()

X_cal = cal[FEATURES].to_numpy()
y_cal = cal.abs_error_ic.to_numpy()

X_test = test[FEATURES].to_numpy()
y_test = test.abs_error_ic.to_numpy()

print("===== TRAIN UNCERTAINTY V2 =====")
print("Train samples:", len(train))
print("Calibration samples:", len(cal))
print("Evaluation samples:", len(test))

model = HistGradientBoostingRegressor(
    loss="quantile",
    quantile=0.90,
    max_iter=180,
    max_leaf_nodes=15,
    min_samples_leaf=60,
    learning_rate=0.06,
    l2_regularization=1.0,
    random_state=42,
)

model.fit(X_train, y_train)

def upper_quantile(values, coverage):
    n = len(values)
    level = min(
        1.0,
        math.ceil((n + 1) * coverage) / n
    )
    return float(
        np.quantile(values, level, method="higher")
    )

# V2 predicts a nonnegative upper error bound.
raw_cal = np.maximum(
    0, model.predict(X_cal)
)
raw_test = np.maximum(
    0, model.predict(X_test)
)

# Additive split-conformal calibration.
# Voxel-level calibration is exploratory because
# voxels from one volume are spatially dependent.
residuals = y_cal - raw_cal

correction = max(
    0.0,
    upper_quantile(residuals, 1 - ALPHA)
)

v2_bound = raw_test + correction

# Constant quantile baseline, calibrated on
# the same calibration split.
constant_raw = upper_quantile(
    y_train, 1 - ALPHA
)
constant_correction = max(
    0.0,
    upper_quantile(
        y_cal - constant_raw,
        1 - ALPHA
    )
)
constant_bound = (
    constant_raw + constant_correction
)

def report(name, bounds):
    if np.isscalar(bounds):
        bounds = np.full_like(y_test, bounds)

    coverage = float(np.mean(
        y_test <= bounds
    ))

    width = float(np.mean(bounds))

    print(
        f"{name}: "
        f"coverage={coverage:.4f}, "
        f"mean_bound={width:.6f}"
    )

    by_volume = []

    for volume in sorted(test.volume_index.unique()):
        mask = (
            test.volume_index.to_numpy() == volume
        )

        by_volume.append({
            "volume": int(volume),
            "coverage": float(np.mean(
                y_test[mask] <= bounds[mask]
            )),
            "mean_bound": float(np.mean(
                bounds[mask]
            )),
            "mean_abs_error": float(np.mean(
                y_test[mask]
            )),
        })

    return by_volume

print("\n===== CALIBRATION =====")
print("Target coverage:", 1 - ALPHA)
print("V2 correction:", round(correction, 6))
print(
    "Constant baseline bound:",
    round(constant_bound, 6)
)

print("\n===== HELD-OUT EVALUATION =====")

v2_rows = report("V2 Quantile", v2_bound)
baseline_rows = report(
    "Constant baseline", constant_bound
)

comparison = pd.DataFrame([
    {
        **row,
        "method": "V2 Quantile",
    }
    for row in v2_rows
] + [
    {
        **row,
        "method": "Constant baseline",
    }
    for row in baseline_rows
])

print("\n===== COVERAGE BY VOLUME =====")
print(
    comparison[
        ["method", "volume", "coverage",
         "mean_bound", "mean_abs_error"]
    ].round(6).to_string(index=False)
)

joblib.dump(
    model, ROOT / "uncertainty_v2_quantile.joblib"
)

metadata = {
    "features": FEATURES,
    "quantile": 0.90,
    "calibration_correction": correction,
    "constant_baseline_bound": constant_bound,
    "source": "GeoSyn V4 validation",
    "train_volume_indices": sorted(ids[0]),
    "calibration_volume_indices": sorted(ids[1]),
    "evaluation_volume_indices": sorted(ids[2]),
    "warning": (
        "Voxel-level error-bound experiment. "
        "Spatial dependence and domain shift prevent "
        "a general 90% coverage guarantee."
    ),
}

(ROOT / "model_metadata.json").write_text(
    json.dumps(metadata, indent=2) + "\n"
)

comparison.to_csv(
    ROOT / "evaluation_by_volume.csv",
    index=False
)

print("\nSaved: uncertainty_v2_quantile.joblib")
print("Saved: model_metadata.json")
print("Saved: evaluation_by_volume.csv")
print("STATUS: UNCERTAINTY V2 TRAINING COMPLETE")
