# ExoMetrix

ExoMetrix is a real-time gait analysis and assistance recommendation system for rehabilitation workflows.

It combines:

- A Flutter mobile app for patients and clinicians.
- A Flask backend for prediction APIs.
- A machine learning model trained on AB06 biomechanics data.

## What The System Does

1. Collects knee-angle signals from BLE hardware, simulation input, or mock stream.
2. Sends angles to a backend model.
3. Classifies each step as:
   - Good step
   - Compensating (bad) step
4. Estimates assistance percentage for exoskeleton control guidance.
5. Displays real-time metrics, trends, and exportable session stats.

## Project Structure

- `app/`: Flutter mobile application.
- `backend/`: Flask API + ML training/runtime.
- `AB06/`: biomechanics dataset used for training.

## Mobile Application

### Patient View

- Real-time angle visualization with feedback status.
- Gamified score that changes based on step quality.
- Session timer and analyzed step count.
- Simulation mode to test model behavior using custom angle sequences.

Main files:

- `app/lib/screens/patient_dashboard.dart`
- `app/lib/services/bluetooth_service.dart`

### Clinician View

- Live knee-angle chart.
- Stability and compensation KPIs.
- Backend/model status panel.
- API endpoint configuration panel.
- Navigation to detailed session analytics.

Main files:

- `app/lib/screens/clinician_dashboard.dart`
- `app/lib/screens/session_stats_screen.dart`
- `app/lib/services/bluetooth_service.dart`

### Session Analytics

- Time windows: last 30 seconds, last 2 minutes, full session.
- Angle metrics: average, min, max, range.
- Session summary and latest classification.
- CSV export to clipboard and temp file.

## Backend API

Main file:

- `backend/api/index.py`

### Endpoints

#### `GET /api/model/status`

Returns model loading status and metadata.

Example response fields:

- `loaded`
- `model_type`
- `sample_count`
- `source`
- `error` or `fallback` when model is unavailable

#### `POST /api/predict`

Input:

```json
{
  "angle": 45.0
}
```

Output:

```json
{
  "classification": "Good step",
  "assistance_percent": 0.0,
  "anomaly_score": 0.0,
  "model_loaded": true,
  "received_angle": 45.0
}
```

## ML Model Details

Training script:

- `backend/ml/train_gait_model.py`

Runtime inference:

- `backend/ml/model_runtime.py`

### Data Pipeline

1. Reads AB06 MAT files, focusing on gait sensor sources (`gon/*.mat`).
2. Attempts recursive numeric extraction from MATLAB structures.
3. Uses fallback decoder for opaque MATLAB table/MCOS files via `__function_workspace__` bytes.
4. Selects the most plausible angle-like signal.
5. Calibrates extracted values to app range and clips to 0-180 degrees.

### Model Architecture

- Feature: single angle value per sample.
- Preprocessing: `RobustScaler`.
- Detector: `IsolationForest`.

Training hyperparameters:

- `n_estimators=300`
- `contamination=0.08`
- `random_state=42`
- `n_jobs=-1`

### Trained Metadata (Current)

From `backend/models/gait_model_meta.json`:

- `model_type`: `IsolationForest`
- `sample_count`: `286000`
- `data_decoder`: `function_workspace_f64_fallback`

### Runtime Decision Logic

- Predicts inlier/outlier using trained IsolationForest.
- Converts model decision score into normalized anomaly strength using stored score percentiles.
- Maps anomaly strength to assistance percentage.
- If model is unavailable, falls back to a deterministic heuristic so the app remains operational.

## Setup And Run

## 1) Backend Setup

From `backend/`:

```bash
pip install -r requirements.txt
python ml/train_gait_model.py --dataset-root ../AB06
python api/index.py
```

Optional environment variables:

- `EXOMETRIX_MODEL_PATH`
- `EXOMETRIX_HOST` (default `0.0.0.0`)
- `EXOMETRIX_PORT` (default `5328`)
- `EXOMETRIX_DEBUG`

## 2) Mobile Setup

From `app/`:

```bash
flutter pub get
flutter run --dart-define=EXOMETRIX_API_BASE_URL=http://127.0.0.1:5328
```

For Android emulator, use:

- `http://10.0.2.2:5328`

For physical phone on same Wi-Fi as laptop, use:

- `http://<laptop_lan_ip>:5328`

Example:

- `http://192.168.1.4:5328`

## 3) Release APK With Backend URL

```bash
flutter build apk --release --dart-define=EXOMETRIX_API_BASE_URL=http://192.168.1.4:5328
```

## Notes On Large Files

- Trained model binaries are intentionally ignored by Git due to size.
- Keep `backend/models/gait_model_meta.json` tracked for reproducibility metadata.
- Retrain locally when needed using the training script.
