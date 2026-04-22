import os
import sys
from pathlib import Path

from flask import Flask, jsonify, request

BACKEND_ROOT = Path(__file__).resolve().parents[1]
if str(BACKEND_ROOT) not in sys.path:
    sys.path.append(str(BACKEND_ROOT))

from ml.model_runtime import GaitModelRuntime

app = Flask(__name__)

MODEL_PATH = os.getenv(
    'EXOMETRIX_MODEL_PATH',
    str(BACKEND_ROOT / 'models' / 'gait_model.joblib'),
)
runtime = GaitModelRuntime(MODEL_PATH)


@app.route('/api/model/status', methods=['GET'])
def model_status():
    return jsonify(runtime.status())

@app.route('/api/predict', methods=['POST'])
def predict():
    data = request.json
    
    if not data or 'angle' not in data:
        return jsonify({'error': 'No angle data provided'}), 400
        
    angle = float(data.get('angle', 0.0))

    angle_series = data.get('angle_series')
    if not isinstance(angle_series, list):
        angle_series = None

    result = runtime.predict(angle, angle_series=angle_series)

    return jsonify({
        'classification': result['classification'],
        'assistance_percent': result['assistance_percent'],
        'anomaly_score': result.get('anomaly_score', 0.0),
        'model_loaded': result.get('model_loaded', False),
        'received_angle': angle,
        'cadence_spm': result.get('cadence_spm', 0.0),
        'toe_clearance_mm': result.get('toe_clearance_mm', 0.0),
        'gait_phase': result.get('gait_phase', 'unknown'),
        'activity_class': result.get('activity_class', 'unknown'),
        'intention_class': result.get('intention_class', 'walking'),
        'model_confidence': result.get('model_confidence', 0.0),
    })

if __name__ == '__main__':
    host = os.getenv('EXOMETRIX_HOST', '0.0.0.0')
    port = int(os.getenv('EXOMETRIX_PORT', '5328'))
    debug = os.getenv('EXOMETRIX_DEBUG', 'false').lower() == 'true'
    app.run(host=host, port=port, debug=debug)
