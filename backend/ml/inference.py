import joblib
import numpy as np
import json
import os
import sys
from pathlib import Path

MODEL_PATH = Path(__file__).parent / "models" / "gait_model.joblib"

FEATURE_NAMES = [
    "angle_mean", "angle_std", "angle_min", "angle_max", "angle_range",
    "velocity_mean", "velocity_std", "velocity_min", "velocity_max", "velocity_range",
    "angle_change", "velocity_change", "jerk", "step_count"
]

def extract_window_features(angles: np.ndarray) -> np.ndarray:
    """Extract 14 features from a window of ankle angles."""
    if angles.size == 0:
        return np.zeros(14)
    
    feature_vec = []
    
    feature_vec.append(np.mean(angles))
    feature_vec.append(np.std(angles) if len(angles) > 1 else 0.0)
    feature_vec.append(np.min(angles))
    feature_vec.append(np.max(angles))
    feature_vec.append(np.ptp(angles))
    
    if len(angles) > 1:
        velocities = np.diff(angles)
        feature_vec.append(np.mean(velocities))
        feature_vec.append(np.std(velocities))
        feature_vec.append(np.min(velocities))
        feature_vec.append(np.max(velocities))
        feature_vec.append(np.ptp(velocities))
    else:
        feature_vec.extend([0.0] * 5)
    
    if len(angles) > 1:
        angle_change = np.mean(np.abs(np.diff(angles)))
        velocity_change = np.mean(np.abs(np.diff(velocities))) if len(velocities) > 1 else 0.0
    else:
        angle_change = 0.0
        velocity_change = 0.0
    
    feature_vec.append(angle_change)
    feature_vec.append(velocity_change)
    
    if len(angles) > 2:
        jerk = np.mean(np.abs(np.diff(velocities)))
    else:
        jerk = 0.0
    
    feature_vec.append(jerk)
    feature_vec.append(float(len(angles)))
    
    return np.array(feature_vec)


class GaitModel:
    def __init__(self, artifact_path: str = None):
        if artifact_path is None:
            artifact_path = str(MODEL_PATH)
        
        self.artifact = joblib.load(artifact_path)
        self.scaler = self.artifact["scaler"]
        self.model = self.artifact["model"]
        self.score_stats = self.artifact["score_stats"]
        self.activity_clf = self.artifact.get("activity_classifier")
        self.intention_clf = self.artifact.get("intention_classifier")
    
    def predict(self, angles: list) -> dict:
        """Run inference on a window of ankle angles."""
        angles = np.array(angles)
        
        anomaly_result = self._predict_anomaly(angles)
        activity_result = self._predict_activity(angles) if self.activity_clf else None
        
        return {
            "anomaly": anomaly_result,
            "activity": activity_result,
            "feature_names": FEATURE_NAMES,
        }
    
    def _predict_anomaly(self, angles: np.ndarray) -> dict:
        """Predict anomaly score for a single angle or window."""
        if angles.size == 1:
            X = angles.reshape(1, -1)
        else:
            angle = angles[-1]
            X = np.array([[float(angle)]])
        
        X_scaled = self.scaler.transform(X)
        pred = int(self.model.predict(X_scaled)[0])
        score = float(self.model.decision_function(X_scaled)[0])
        
        floor = self.score_stats["p01"]
        threshold = self.score_stats["p05"]
        denom = max(threshold - floor, 1e-6)
        anomaly_strength = float(np.clip((threshold - score) / denom, 0.0, 1.0))
        
        if pred == -1:
            classification = "Compensating (bad) step"
            assistance = float(np.clip(20.0 + 70.0 * anomaly_strength, 20.0, 95.0))
        else:
            classification = "Good step"
            assistance = 0.0
        
        return {
            "score": score,
            "prediction": pred,
            "anomaly_strength": anomaly_strength,
            "classification": classification,
            "assistance": assistance,
            "threshold": threshold,
            "floor": floor,
        }
    
    def _predict_activity(self, angles: np.ndarray) -> dict:
        """Predict activity and intention from a window."""
        features = extract_window_features(angles).reshape(1, -1)
        
        activity = self.activity_clf.predict(features)[0]
        intention = self.intention_clf.predict(features)[0] if self.intention_clf else None
        
        return {
            "activity": activity,
            "intention": intention,
        }


_global_model = None

def get_model() -> GaitModel:
    global _global_model
    if _global_model is None:
        _global_model = GaitModel()
    return _global_model


def handle_request(request_data: dict) -> dict:
    """Handle an inference request."""
    angles = request_data.get("angles", [])
    
    if not angles:
        return {"error": "No angles provided"}
    
    model = get_model()
    result = model.predict(angles)
    
    return result


if __name__ == "__main__":
    import sys
    
    if len(sys.argv) < 2:
        print("Usage: python inference.py <json_request>")
        sys.exit(1)
    
    request_json = sys.argv[1]
    request_data = json.loads(request_json)
    result = handle_request(request_data)
    print(json.dumps(result, indent=2))