from pathlib import Path
import json

import joblib
import numpy as np
import pandas as pd

ROOT = Path("results/uncertainty_v2")
OUT = Path("model_export/Uncertainty_V2")
OUT.mkdir(parents=True, exist_ok=True)

model = joblib.load(
    ROOT / "uncertainty_v2_quantile.joblib"
)

metadata = json.loads(
    (ROOT / "model_metadata.json").read_text()
)

features = metadata["features"]
assert len(features) == model.n_features_in_ == 10

baseline = float(
    np.asarray(model._baseline_prediction).item()
)

trees = []

for iteration in model._predictors:
    for predictor in iteration:
        nodes = []

        for n in predictor.nodes:
            if bool(n["is_categorical"]):
                raise ValueError(
                    "Categorical splits not supported"
                )

            nodes.append({
                "value": float(n["value"]),
                "feature": int(n["feature_idx"]),
                "threshold": float(n["num_threshold"]),
                "missing_left": bool(
                    n["missing_go_to_left"]
                ),
                "left": int(n["left"]),
                "right": int(n["right"]),
                "leaf": bool(n["is_leaf"]),
            })

        trees.append(nodes)

payload = {
    "model": "Uncertainty_V2_Quantile",
    "format_version": 1,
    "features": features,
    "baseline": baseline,
    "trees": trees,
    "calibration_correction": float(
        metadata["calibration_correction"]
    ),
    "output": "estimated_absolute_Ic_error_bound",
    "warning": (
        "Experimental error bound. "
        "Not calibrated confidence."
    ),
}

path = OUT / "uncertainty_v2_trees.json"

path.write_text(
    json.dumps(
        payload,
        indent=2,
        allow_nan=False
    ) + "\n"
)

print("===== UNCERTAINTY V2 JSON EXPORT =====")
print("Features:", len(features))
print("Trees:", len(trees))
print("JSON size:", path.stat().st_size, "bytes")

# Independent interpreter for the exported
# tree structure.
def predict_json(X, exported):
    predictions = np.full(
        len(X),
        exported["baseline"],
        dtype=np.float64
    )

    for tree in exported["trees"]:
        for i, row in enumerate(X):
            idx = 0

            while True:
                node = tree[idx]

                if node["leaf"]:
                    predictions[i] += node["value"]
                    break

                feature = row[node["feature"]]

                if np.isnan(feature):
                    go_left = node["missing_left"]
                else:
                    go_left = (
                        feature <= node["threshold"]
                    )

                idx = (
                    node["left"]
                    if go_left
                    else node["right"]
                )

    return np.maximum(
        0.0, predictions
    ) + exported["calibration_correction"]

exported = json.loads(path.read_text())

results = []
rng = np.random.default_rng(42)

for split in ["train", "calibration", "evaluation"]:
    frame = pd.read_csv(
        ROOT / f"{split}.csv"
    )

    indices = rng.choice(
        len(frame),
        size=min(512, len(frame)),
        replace=False
    )

    X = frame.iloc[indices][
        features
    ].to_numpy(dtype=np.float64)

    original = np.maximum(
        0.0,
        model.predict(X)
    ) + float(
        metadata["calibration_correction"]
    )

    reconstructed = predict_json(
        X, exported
    )

    diff = np.abs(
        original - reconstructed
    )

    max_diff = float(diff.max())
    mean_diff = float(diff.mean())

    results.append({
        "split": split,
        "samples": len(X),
        "max_abs_diff": max_diff,
        "mean_abs_diff": mean_diff,
    })

    print(
        f"PARITY | {split}"
        f" | samples={len(X)}"
        f" | max_diff={max_diff:.12g}"
        f" | mean_diff={mean_diff:.12g}"
    )

    assert max_diff < 1e-5, (
        f"JSON parity failed on {split}"
    )

report = {
    "format_version": 1,
    "trees": len(trees),
    "features": features,
    "tolerance": 1e-5,
    "results": results,
    "status": "PASS",
    "note": (
        "Python JSON interpreter parity only. "
        "Swift parity not yet tested."
    ),
}

(OUT / "parity_report.json").write_text(
    json.dumps(report, indent=2) + "\n"
)

print("\nSaved:", path)
print("Saved:", OUT / "parity_report.json")
print("STATUS: UNCERTAINTY V2 JSON PARITY PASS")
