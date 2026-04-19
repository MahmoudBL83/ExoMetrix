from pathlib import Path

import joblib
import numpy as np


class GaitModelRuntime:
    def __init__(self, model_path: str):
        self.model_path = Path(model_path)
        self.loaded = False
        self.artifact = None
        self.error = None

        try:
            self.artifact = joblib.load(self.model_path)
            self.loaded = True
        except Exception as exc:  # pragma: no cover
            self.error = str(exc)

    def status(self) -> dict:
        if self.loaded:
            meta = self.artifact.get("meta", {})
            return {
                "loaded": True,
                "model_path": str(self.model_path),
                "model_type": meta.get("model_type", "unknown"),
                "sample_count": meta.get("sample_count", 0),
                "source": meta.get("source", "unknown"),
            }

        return {
            "loaded": False,
            "model_path": str(self.model_path),
            "error": self.error or "Model not loaded",
            "fallback": "heuristic",
        }

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

    def predict(self, angle: float) -> dict:
        if not self.loaded or self.artifact is None:
            result = self._heuristic_predict(angle)
            result["model_loaded"] = False
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
        }
