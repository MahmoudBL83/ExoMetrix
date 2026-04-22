import argparse
import json
from collections import Counter
from pathlib import Path
from typing import Iterable, List, Tuple

import joblib
import numpy as np
from sklearn.ensemble import IsolationForest
from sklearn.ensemble import RandomForestClassifier
from sklearn.metrics import accuracy_score
from sklearn.model_selection import train_test_split
from sklearn.preprocessing import RobustScaler

try:
    from scipy.io import loadmat
except Exception:  # pragma: no cover
    loadmat = None

try:
    import h5py
except Exception:  # pragma: no cover
    h5py = None


FEATURE_NAMES = [
    "mean_angle",
    "std_angle",
    "min_angle",
    "max_angle",
    "range_angle",
    "median_angle",
    "p10_angle",
    "p90_angle",
    "mean_abs_velocity",
    "std_velocity",
    "max_velocity",
    "min_velocity",
    "energy",
    "peak_density",
]


def _extract_from_function_workspace(mat_obj) -> np.ndarray | None:
    """Best-effort decoder for MATLAB opaque/table MAT files.

    AB06 sensor files are often stored as MATLAB MCOS tables, which scipy loads as
    `MatlabOpaque` plus a `__function_workspace__` uint8 blob. This attempts to
    reinterpret that blob as little-endian float64 streams and selects the most
    plausible angle-like sequence.
    """
    workspace = mat_obj.get("__function_workspace__")
    if workspace is None:
        return None

    raw = np.asarray(workspace, dtype=np.uint8).ravel()
    if raw.size < 8 * 100:
        return None

    best_signal = None
    best_score = float("-inf")

    for offset in range(8):
        n = (raw.size - offset) // 8
        if n < 100:
            continue

        chunk = raw[offset : offset + n * 8]
        values = np.frombuffer(chunk.tobytes(), dtype="<f8")
        values = values[np.isfinite(values)]
        if values.size < 100:
            continue

        # Keep a permissive range for joint angles and related kinematic traces.
        values = values[(values >= -220.0) & (values <= 220.0)]
        if values.size < 100:
            continue

        p1 = float(np.percentile(values, 1))
        p99 = float(np.percentile(values, 99))
        dynamic = p99 - p1
        spread = float(np.std(values))

        # Prefer sequences with good dynamic range and many valid points.
        score = values.size + dynamic * 50.0 + spread * 25.0
        if score > best_score:
            best_score = score
            best_signal = values.copy()

    return best_signal


def _calibrate_to_app_angle_range(raw_angles: np.ndarray) -> np.ndarray:
    """Map extracted angles to the app's expected range (~5..120 deg core gait)."""
    p1 = float(np.percentile(raw_angles, 1))
    p99 = float(np.percentile(raw_angles, 99))

    if abs(p99 - p1) < 1e-6:
        return np.clip(raw_angles, 0.0, 180.0)

    target_low, target_high = 5.0, 120.0
    scale = (target_high - target_low) / (p99 - p1)
    shift = target_low - scale * p1

    calibrated = raw_angles * scale + shift
    return np.clip(calibrated, 0.0, 180.0)


def _iter_mat_values(node) -> Iterable[np.ndarray]:
    if isinstance(node, np.ndarray):
        if node.dtype == object:
            for item in node.flat:
                yield from _iter_mat_values(item)
        else:
            yield node
        return

    # scipy mat_struct-like object
    if hasattr(node, "_fieldnames"):
        for name in getattr(node, "_fieldnames", []):
            yield from _iter_mat_values(getattr(node, name))
        return

    if isinstance(node, dict):
        for key, value in node.items():
            if str(key).startswith("__"):
                continue
            yield from _iter_mat_values(value)
        return

    if isinstance(node, (list, tuple)):
        for item in node:
            yield from _iter_mat_values(item)


def _load_mat_file(path: Path):
    if loadmat is not None:
        try:
            return loadmat(path, squeeze_me=True, struct_as_record=False)
        except Exception:
            pass

    if h5py is None:
        raise RuntimeError(
            f"Unable to read MAT file {path}; scipy failed and h5py is unavailable."
        )

    result = {}
    with h5py.File(path, "r") as f:
        for key in f.keys():
            result[key] = np.array(f[key])
    return result


def _choose_signal(arrays: List[np.ndarray]) -> np.ndarray | None:
    candidates = []
    for arr in arrays:
        if not np.issubdtype(arr.dtype, np.number):
            continue

        arr = np.asarray(arr, dtype=float)
        arr = arr[np.isfinite(arr)]
        if arr.size < 40:
            continue

        if arr.ndim == 1:
            series = arr
        else:
            flattened = arr.reshape(arr.shape[0], -1) if arr.shape[0] > 1 else arr.reshape(-1, 1)
            stds = np.nanstd(flattened, axis=0)
            idx = int(np.argmax(stds))
            series = flattened[:, idx]

        if series.size < 40:
            continue

        variance = float(np.nanvar(series))
        dynamic = float(np.nanmax(series) - np.nanmin(series))
        within_angle_like = np.mean((series >= -200) & (series <= 220))

        score = variance + dynamic * 0.1 + within_angle_like * 10
        candidates.append((score, series))

    if not candidates:
        return None

    candidates.sort(key=lambda x: x[0], reverse=True)
    return candidates[0][1]


def _extract_best_signal(mat_obj, max_per_file: int | None = None) -> np.ndarray | None:
    arrays = list(_iter_mat_values(mat_obj))
    signal = _choose_signal(arrays)
    if signal is None:
        signal = _extract_from_function_workspace(mat_obj)
    if signal is None:
        return None

    signal = np.asarray(signal, dtype=float)
    signal = signal[np.isfinite(signal)]
    signal = signal[(signal >= -220.0) & (signal <= 220.0)]
    if signal.size < 40:
        return None

    if max_per_file is not None and signal.size > max_per_file:
        step = max(1, signal.size // max_per_file)
        signal = signal[::step][:max_per_file]

    return signal.astype(float)


def _count_peaks(values: np.ndarray) -> int:
    if values.size < 3:
        return 0

    threshold = float(np.mean(values) + 0.25 * np.std(values))
    peaks = 0
    for i in range(1, values.size - 1):
        if values[i] > values[i - 1] and values[i] >= values[i + 1] and values[i] > threshold:
            peaks += 1
    return peaks


def _extract_window_features(values: np.ndarray) -> np.ndarray:
    values = np.asarray(values, dtype=float)
    values = values[np.isfinite(values)]
    if values.size < 6:
        pad = np.full(6 - values.size, values[-1] if values.size else 0.0)
        values = np.concatenate([values, pad], axis=0)

    velocity = np.diff(values)
    if velocity.size == 0:
        velocity = np.array([0.0], dtype=float)

    angle_range = float(np.max(values) - np.min(values))
    peaks = _count_peaks(values)
    peak_density = float(peaks / max(values.size, 1))

    feature_vector = np.array(
        [
            float(np.mean(values)),
            float(np.std(values)),
            float(np.min(values)),
            float(np.max(values)),
            angle_range,
            float(np.median(values)),
            float(np.percentile(values, 10)),
            float(np.percentile(values, 90)),
            float(np.mean(np.abs(velocity))),
            float(np.std(velocity)),
            float(np.max(velocity)),
            float(np.min(velocity)),
            float(np.mean(np.square(values - np.mean(values)))),
            peak_density,
        ],
        dtype=float,
    )

    return feature_vector


def _derive_labels_from_path(mat_path: Path) -> Tuple[str, str]:
    activity = mat_path.parents[1].name.lower()
    stem = mat_path.stem.lower()

    if activity == "levelground":
        activity_class = "levelground"
        intention_class = "running" if "_fast_" in stem else "walking"
    elif activity == "stair":
        activity_class = "stair"
        intention_class = "upstairs"
    elif activity == "ramp":
        activity_class = "ramp"
        intention_class = "ramp_up"
    elif activity == "treadmill":
        activity_class = "treadmill"
        intention_class = "walking"
    else:
        activity_class = "unknown"
        intention_class = "walking"

    return activity_class, intention_class


def _collect_labeled_feature_rows(
    subject_root: Path,
    max_per_file: int = 2000,
) -> tuple[list[np.ndarray], list[str], list[str]]:
    files = sorted(subject_root.rglob("gon/*.mat"))
    feature_rows: list[np.ndarray] = []
    activity_labels: list[str] = []
    intention_labels: list[str] = []

    for mat_path in files:
        try:
            mat_obj = _load_mat_file(mat_path)
            signal = _extract_best_signal(mat_obj, max_per_file=max_per_file)
            if signal is None:
                continue

            calibrated = _calibrate_to_app_angle_range(signal)
            feature_rows.append(_extract_window_features(calibrated))
            activity_class, intention_class = _derive_labels_from_path(mat_path)
            activity_labels.append(activity_class)
            intention_labels.append(intention_class)
        except Exception as exc:
            print(f"[WARN] Skipping labeled row from {mat_path.name}: {exc}")

    return feature_rows, activity_labels, intention_labels


def _train_classifier(
    X: np.ndarray,
    y: list[str],
) -> tuple[RandomForestClassifier | None, dict]:
    if X.size == 0 or len(y) == 0:
        return None, {"classes": [], "val_accuracy": None}

    class_counts = Counter(y)
    if len(class_counts) < 2:
        # Not enough label diversity for supervised classification.
        return None, {
            "classes": sorted(class_counts.keys()),
            "val_accuracy": None,
            "note": "insufficient_label_diversity",
        }

    clf = RandomForestClassifier(
        n_estimators=350,
        random_state=42,
        class_weight="balanced_subsample",
        n_jobs=-1,
    )

    metrics: dict = {
        "classes": sorted(class_counts.keys()),
        "val_accuracy": None,
    }

    min_count = min(class_counts.values())
    if X.shape[0] >= 30 and min_count >= 2:
        X_train, X_val, y_train, y_val = train_test_split(
            X,
            y,
            test_size=0.2,
            random_state=42,
            stratify=y,
        )
        clf.fit(X_train, y_train)
        y_pred = clf.predict(X_val)
        metrics["val_accuracy"] = float(accuracy_score(y_val, y_pred))
    else:
        clf.fit(X, y)

    return clf, metrics


def _collect_angles(gon_dir: Path, max_per_file: int = 2000) -> np.ndarray:
    angles = []
    if gon_dir.name.lower() == "gon":
        files = sorted(gon_dir.glob("*.mat"))
    else:
        files = sorted(gon_dir.rglob("gon/*.mat"))

    if not files:
        # Fallback in case user passes a custom prefiltered folder.
        files = sorted(gon_dir.rglob("*.mat"))

    if not files:
        raise FileNotFoundError(f"No .mat files found under {gon_dir}")

    for mat_path in files:
        try:
            mat_obj = _load_mat_file(mat_path)
            signal = _extract_best_signal(mat_obj, max_per_file=max_per_file)
            if signal is None:
                continue

            angles.append(signal.astype(float))
        except Exception as exc:
            print(f"[WARN] Skipping {mat_path.name}: {exc}")

    if not angles:
        raise RuntimeError("No valid angle-like signals were extracted from the dataset.")

    merged = np.concatenate(angles, axis=0)
    merged = merged[np.isfinite(merged)]
    if merged.size < 100:
        raise RuntimeError("Insufficient data extracted for model training.")

    return merged


def _resolve_subject_roots(dataset_root: Path, subject_glob: str) -> List[Path]:
    if not dataset_root.exists():
        raise FileNotFoundError(f"Dataset root does not exist: {dataset_root}")

    # If the user already passed a single subject folder (AB06/AB07/AB08), use it directly.
    if (dataset_root / "osimxml").exists():
        return [dataset_root]

    # Otherwise, try to discover AB subject folders from a parent root.
    discovered = sorted(
        path
        for path in dataset_root.glob(subject_glob)
        if path.is_dir() and (path / "osimxml").exists()
    )
    if discovered:
        return discovered

    # Fallback: treat the provided path as a single data root.
    return [dataset_root]


def train_model(
    dataset_root: Path,
    output_model: Path,
    output_meta: Path,
    subject_glob: str = "AB*",
):
    subject_roots = _resolve_subject_roots(dataset_root, subject_glob)

    raw_chunks = []
    feature_rows: list[np.ndarray] = []
    activity_labels: list[str] = []
    intention_labels: list[str] = []
    source_subjects = []
    samples_per_subject = {}
    feature_rows_per_subject = {}

    for subject_root in subject_roots:
        subject_name = subject_root.name
        raw = _collect_angles(subject_root)
        raw_chunks.append(raw)

        subject_features, subject_activity, subject_intention = _collect_labeled_feature_rows(
            subject_root
        )
        feature_rows.extend(subject_features)
        activity_labels.extend(subject_activity)
        intention_labels.extend(subject_intention)

        source_subjects.append(subject_name)
        samples_per_subject[subject_name] = int(raw.size)
        feature_rows_per_subject[subject_name] = int(len(subject_features))
        print(f"[INFO] {subject_name}: collected {raw.size} samples")
        print(
            f"[INFO] {subject_name}: labeled feature windows {len(subject_features)}"
        )

    raw_angles = np.concatenate(raw_chunks, axis=0)
    calibrated_angles = _calibrate_to_app_angle_range(raw_angles)

    X = calibrated_angles.reshape(-1, 1)
    scaler = RobustScaler()
    X_scaled = scaler.fit_transform(X)

    model = IsolationForest(
        n_estimators=300,
        contamination=0.08,
        random_state=42,
        n_jobs=-1,
    )
    model.fit(X_scaled)

    scores = model.decision_function(X_scaled)

    if feature_rows:
        X_features = np.vstack(feature_rows).astype(float)
    else:
        X_features = np.zeros((0, len(FEATURE_NAMES)), dtype=float)

    activity_classifier, activity_metrics = _train_classifier(
        X_features,
        activity_labels,
    )
    intention_classifier, intention_metrics = _train_classifier(
        X_features,
        intention_labels,
    )

    activity_label_counts = dict(sorted(Counter(activity_labels).items()))
    intention_label_counts = dict(sorted(Counter(intention_labels).items()))

    artifact = {
        "model": model,
        "scaler": scaler,
        "activity_classifier": activity_classifier,
        "intention_classifier": intention_classifier,
        "feature_names": FEATURE_NAMES,
        "angle_stats": {
            "mean": float(np.mean(calibrated_angles)),
            "std": float(np.std(calibrated_angles)),
            "median": float(np.median(calibrated_angles)),
            "p01": float(np.percentile(calibrated_angles, 1)),
            "p99": float(np.percentile(calibrated_angles, 99)),
        },
        "score_stats": {
            "p01": float(np.percentile(scores, 1)),
            "p05": float(np.percentile(scores, 5)),
            "p50": float(np.percentile(scores, 50)),
        },
        "meta": {
            "source": str(dataset_root),
            "source_subjects": source_subjects,
            "subject_count": len(source_subjects),
            "samples_per_subject": samples_per_subject,
            "feature_rows_per_subject": feature_rows_per_subject,
            "sample_count": int(calibrated_angles.size),
            "model_type": "IsolationForest",
            "data_decoder": "function_workspace_f64_fallback",
            "supports_activity_classification": activity_classifier is not None,
            "supports_intention_classification": intention_classifier is not None,
            "activity_label_counts": activity_label_counts,
            "intention_label_counts": intention_label_counts,
            "activity_classifier_metrics": activity_metrics,
            "intention_classifier_metrics": intention_metrics,
            "intention_mapping_policy": {
                "levelground_fast": "running",
                "levelground_normal_or_slow": "walking",
                "stair": "upstairs",
                "ramp": "ramp_up",
                "treadmill": "walking",
            },
        },
    }

    output_model.parent.mkdir(parents=True, exist_ok=True)
    joblib.dump(artifact, output_model)

    output_meta.parent.mkdir(parents=True, exist_ok=True)
    with output_meta.open("w", encoding="utf-8") as f:
        json.dump(artifact["meta"] | artifact["angle_stats"] | artifact["score_stats"], f, indent=2)

    print(f"Model saved to: {output_model}")
    print(f"Metadata saved to: {output_meta}")
    print(f"Samples used: {calibrated_angles.size}")
    print(
        "Activity labels: "
        + (str(activity_label_counts) if activity_label_counts else "none")
    )
    print(
        "Intention labels: "
        + (str(intention_label_counts) if intention_label_counts else "none")
    )


def main():
    parser = argparse.ArgumentParser(
        description="Train ExoMetrix gait anomaly model from one or more AB subject datasets."
    )
    parser.add_argument(
        "--dataset-root",
        default=str(Path(__file__).resolve().parents[2]),
        help=(
            "Path to dataset root. Can be a single subject folder (e.g., AB06) "
            "or a parent folder that contains multiple subjects (AB06, AB07, AB08)."
        ),
    )
    parser.add_argument(
        "--subject-glob",
        default="AB*",
        help="Glob pattern used to discover subject folders inside --dataset-root",
    )
    parser.add_argument(
        "--output-model",
        default=str(Path(__file__).resolve().parents[1] / "models" / "gait_model.joblib"),
        help="Path to save trained joblib model",
    )
    parser.add_argument(
        "--output-meta",
        default=str(Path(__file__).resolve().parents[1] / "models" / "gait_model_meta.json"),
        help="Path to save JSON metadata",
    )

    args = parser.parse_args()

    train_model(
        dataset_root=Path(args.dataset_root),
        output_model=Path(args.output_model),
        output_meta=Path(args.output_meta),
        subject_glob=args.subject_glob,
    )


if __name__ == "__main__":
    main()
