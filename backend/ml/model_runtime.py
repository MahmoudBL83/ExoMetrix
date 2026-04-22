from pathlib import Path
from collections import deque

import joblib
import numpy as np


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

    peaks = _count_peaks(values)
    peak_density = float(peaks / max(values.size, 1))

    return np.array(
        [
            float(np.mean(values)),
            float(np.std(values)),
            float(np.min(values)),
            float(np.max(values)),
            float(np.max(values) - np.min(values)),
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


class GaitModelRuntime:
    def __init__(self, model_path: str):
        self.model_path = Path(model_path)
        self.loaded = False
        self.artifact = None
        self.error = None
        self.angle_history: deque[float] = deque(maxlen=120)

        try:
            self.artifact = joblib.load(self.model_path)
            self.loaded = True
        except Exception as exc:  # pragma: no cover
            self.error = str(exc)

    def status(self) -> dict:
        if self.loaded:
            meta = self.artifact.get("meta", {})
            activity_classifier = self.artifact.get("activity_classifier")
            intention_classifier = self.artifact.get("intention_classifier")
            return {
                "loaded": True,
                "model_path": str(self.model_path),
                "model_type": meta.get("model_type", "unknown"),
                "sample_count": meta.get("sample_count", 0),
                "source": meta.get("source", "unknown"),
                "supports_activity_classification": activity_classifier is not None,
                "supports_intention_classification": intention_classifier is not None,
            }

        return {
            "loaded": False,
            "model_path": str(self.model_path),
            "error": self.error or "Model not loaded",
            "fallback": "heuristic",
        }

    def _prepare_window(self, angle: float, angle_series: list[float] | None = None) -> np.ndarray:
        if angle_series:
            cleaned = [
                float(np.clip(x, 0.0, 180.0))
                for x in angle_series
                if isinstance(x, (int, float)) and np.isfinite(x)
            ]
            if not cleaned:
                cleaned = [float(np.clip(angle, 0.0, 180.0))]
            if cleaned[-1] != float(angle):
                cleaned.append(float(np.clip(angle, 0.0, 180.0)))

            self.angle_history.extend(cleaned[-20:])
            return np.array(cleaned[-80:], dtype=float)

        self.angle_history.append(float(np.clip(angle, 0.0, 180.0)))
        return np.array(self.angle_history, dtype=float)

    def _estimate_cadence_spm(self, window: np.ndarray, sample_rate_hz: float = 10.0) -> float:
        if window.size < 6:
            return 0.0

        peaks = _count_peaks(window)
        duration_sec = max((window.size - 1) / sample_rate_hz, 1e-6)
        cadence = (peaks / duration_sec) * 60.0
        return float(np.clip(cadence, 0.0, 220.0))

    def _estimate_gait_phase(self, window: np.ndarray) -> str:
        if window.size < 2:
            return "unknown"

        current = float(window[-1])
        velocity = float(window[-1] - window[-2])
        high_band = float(np.percentile(window, 65))

        if velocity > 1.2:
            return "swing"
        if velocity < -1.2:
            return "loading_response"
        if current > high_band:
            return "terminal_swing"
        return "stance"

    def _estimate_toe_clearance_mm(self, angle: float, window: np.ndarray, cadence_spm: float) -> float:
        if window.size < 2:
            return 10.0

        lo = float(np.min(window))
        hi = float(np.max(window))
        span = max(hi - lo, 1e-6)
        normalized = float(np.clip((angle - lo) / span, 0.0, 1.0))

        clearance = 8.0 + 52.0 * normalized
        if cadence_spm > 145:
            clearance += 4.0

        return float(np.clip(clearance, 4.0, 70.0))

    def _heuristic_activity_intention(
        self,
        angle: float,
        cadence_spm: float,
        window: np.ndarray,
    ) -> tuple[str, str, float]:
        variability = float(np.std(window)) if window.size else 0.0

        if cadence_spm >= 150.0:
            return "running", "running", 0.62
        if angle >= 105.0 and cadence_spm >= 70.0:
            return "stair", "upstairs", 0.58
        if angle >= 90.0 and cadence_spm >= 60.0:
            return "ramp", "ramp_up", 0.55
        if 55.0 <= cadence_spm <= 130.0 and variability < 10.0 and window.size >= 20:
            return "treadmill", "walking", 0.52
        return "levelground", "walking", 0.56

    def _classifier_activity_intention(
        self,
        window: np.ndarray,
    ) -> tuple[str, str, float] | None:
        if not self.artifact:
            return None

        activity_clf = self.artifact.get("activity_classifier")
        intention_clf = self.artifact.get("intention_classifier")
        if activity_clf is None or intention_clf is None:
            return None

        try:
            features = _extract_window_features(window).reshape(1, -1)
            activity = str(activity_clf.predict(features)[0])
            intention = str(intention_clf.predict(features)[0])

            conf_a = 0.65
            conf_i = 0.65
            if hasattr(activity_clf, "predict_proba"):
                conf_a = float(np.max(activity_clf.predict_proba(features)))
            if hasattr(intention_clf, "predict_proba"):
                conf_i = float(np.max(intention_clf.predict_proba(features)))

            return activity, intention, float(np.clip((conf_a + conf_i) * 0.5, 0.0, 1.0))
        except Exception:
            return None

    def _heuristic_predict(self, angle: float) -> dict:
        if -10 <= angle <= 150:
            return {
                "classification": "Good step",
                "assistance_percent": 0.0,
                "anomaly_score": 0.0,
            }

        overflow = max(abs(angle - 70.0) - 80.0, 0.0)
        assistance = float(np.clip(20.0 + overflow * 0.6, 20.0, 90.0))
        return {
            "classification": "Compensating (bad) step",
            "assistance_percent": round(assistance, 1),
            "anomaly_score": round(min(1.0, assistance / 100.0), 4),
        }

    def predict(self, angle: float, angle_series: list[float] | None = None) -> dict:
        angle = float(np.clip(angle, 0.0, 180.0))
        window = self._prepare_window(angle, angle_series=angle_series)
        cadence_spm = self._estimate_cadence_spm(window)
        gait_phase = self._estimate_gait_phase(window)
        toe_clearance_mm = self._estimate_toe_clearance_mm(angle, window, cadence_spm)

        classifier_result = self._classifier_activity_intention(window)
        if classifier_result is None:
            activity_class, intention_class, model_confidence = self._heuristic_activity_intention(
                angle,
                cadence_spm,
                window,
            )
        else:
            activity_class, intention_class, model_confidence = classifier_result

        if not self.loaded or self.artifact is None:
            result = self._heuristic_predict(angle)
            result.update(
                {
                    "model_loaded": False,
                    "cadence_spm": round(cadence_spm, 1),
                    "toe_clearance_mm": round(toe_clearance_mm, 2),
                    "gait_phase": gait_phase,
                    "activity_class": activity_class,
                    "intention_class": intention_class,
                    "model_confidence": round(model_confidence, 3),
                }
            )
            return result

        scaler = self.artifact["scaler"]
        model = self.artifact["model"]
        score_stats = self.artifact.get("score_stats", {})

        X = np.array([[float(angle)]], dtype=float)
        X_scaled = scaler.transform(X)

        pred = int(model.predict(X_scaled)[0])
        score = float(model.decision_function(X_scaled)[0])

        floor = float(score_stats.get("p01", -0.2))
        threshold = float(score_stats.get("p05", 0.0))
        denom = max(threshold - floor, 1e-6)

        # Higher anomaly when score falls below expected inlier threshold.
        anomaly_strength = float(np.clip((threshold - score) / denom, 0.0, 1.0))

        if pred == -1:
            classification = "Compensating (bad) step"
            assistance = float(np.clip(20.0 + 70.0 * anomaly_strength, 20.0, 95.0))
        else:
            classification = "Good step"
            assistance = 0.0

        return {
            "classification": classification,
            "assistance_percent": round(float(assistance), 1),
            "anomaly_score": round(anomaly_strength, 4),
            "model_loaded": True,
            "cadence_spm": round(cadence_spm, 1),
            "toe_clearance_mm": round(toe_clearance_mm, 2),
            "gait_phase": gait_phase,
            "activity_class": activity_class,
            "intention_class": intention_class,
            "model_confidence": round(model_confidence, 3),
        }
