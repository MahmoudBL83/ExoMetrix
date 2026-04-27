#!/usr/bin/env python3
"""
ExoMetrix Inference API Server
Run this separately to serve model predictions via HTTP.
"""

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
import joblib
import numpy as np
from pathlib import Path

app = FastAPI(title="ExoMetrix Gait Inference API")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

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
        
        if len(velocities) > 1:
            angle_change = np.mean(np.abs(np.diff(angles)))
            velocity_change = np.mean(np.abs(np.diff(velocities)))
        else:
            angle_change = 0.0
            velocity_change = 0.0
    else:
        feature_vec.extend([0.0] * 5)
        angle_change = 0.0
        velocity_change = 0.0
    
    feature_vec.append(angle_change)
    feature_vec.append(velocity_change)
    
    if len(angles) > 2:
        jerk = np.mean(np.abs(np.diff(np.diff(angles))))
    else:
        jerk = 0.0
    
    feature_vec.append(jerk)
    feature_vec.append(float(len(angles)))
    
    return np.array(feature_vec)


class InferenceRequest(BaseModel):
    angles: list[float]


@app.on_event("startup")
def load_model():
    global artifact, scaler, model, score_stats, activity_clf, intention_clf
    
    print(f"Loading model from {MODEL_PATH}...")
    artifact = joblib.load(MODEL_PATH)
    scaler = artifact["scaler"]
    model = artifact["model"]
    score_stats = artifact["score_stats"]
    activity_clf = artifact.get("activity_classifier")
    intention_clf = artifact.get("intention_classifier")
    print("Model loaded successfully!")


@app.get("/")
def root():
    return {"message": "ExoMetrix Gait Inference API", "version": "1.0.0"}


@app.get("/health")
def health():
    return {"status": "healthy", "model_loaded": artifact is not None}


@app.post("/infer")
def infer(request: InferenceRequest):
    if not request.angles:
        raise HTTPException(status_code=400, detail="No angles provided")
    
    angles = np.array(request.angles)
    
    if angles.size == 1:
        X = angles.reshape(1, -1)
    else:
        X = np.array([[float(angles[-1])]])
    
    X_scaled = scaler.transform(X)
    pred = int(model.predict(X_scaled)[0])
    score = float(model.decision_function(X_scaled)[0])
    
    floor = score_stats["p01"]
    threshold = score_stats["p05"]
    denom = max(threshold - floor, 1e-6)
    anomaly_strength = float(np.clip((threshold - score) / denom, 0.0, 1.0))
    
    if pred == -1:
        classification = "Compensating (bad) step"
        assistance = float(np.clip(20.0 + 70.0 * anomaly_strength, 20.0, 95.0))
    else:
        classification = "Good step"
        assistance = 0.0
    
    result = {
        "anomaly": {
            "score": score,
            "prediction": pred,
            "anomaly_strength": anomaly_strength,
            "classification": classification,
            "assistance": assistance,
            "threshold": threshold,
            "floor": floor,
        },
        "feature_names": FEATURE_NAMES,
    }
    
    if activity_clf:
        features = extract_window_features(angles).reshape(1, -1)
        activity = str(activity_clf.predict(features)[0])
        intention = str(intention_clf.predict(features)[0]) if intention_clf else None
        
        result["activity"] = {
            "activity": activity,
            "intention": intention,
        }
    
    return result


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)