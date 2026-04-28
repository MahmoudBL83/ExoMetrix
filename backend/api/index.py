import os
import sys
from pathlib import Path
from functools import wraps

from flask import Flask, jsonify, request, g
from flask_cors import CORS

BACKEND_ROOT = Path(__file__).resolve().parents[1]
if str(BACKEND_ROOT) not in sys.path:
    sys.path.append(str(BACKEND_ROOT))

from ml.model_runtime import GaitModelRuntime
from api.database import (
    init_db,
    register_user,
    login_user,
    create_session,
    get_user_sessions,
    get_session,
    end_session,
    delete_session,
    save_prediction,
)

app = Flask(__name__)
CORS(app)

# Initialize database
init_db()

MODEL_PATH = os.getenv(
    'EXOMETRIX_MODEL_PATH',
    str(BACKEND_ROOT / 'models' / 'gait_model.joblib'),
)
runtime = GaitModelRuntime(MODEL_PATH)


# Simple token-based auth (store in memory for now)
# In production, use proper JWT or session tokens
_active_tokens = {}


def token_required(f):
    @wraps(f)
    def decorated(*args, **kwargs):
        token = request.headers.get('Authorization', '').replace('Bearer ', '')
        user_id = _active_tokens.get(token)
        
        if not user_id:
            return jsonify({'error': 'Unauthorized'}), 401
        
        g.user_id = user_id
        return f(*args, **kwargs)
    
    return decorated


@app.route('/api/register', methods=['POST'])
def register():
    data = request.json
    username = data.get('username', '').strip()
    password = data.get('password', '')
    email = data.get('email', '')
    
    if not username or not password:
        return jsonify({'error': 'Username and password required'}), 400
    
    result = register_user(username, password, email)
    
    if result['success']:
        token = result.pop('token')
        _active_tokens[token] = result['user_id']
        return jsonify({**result, 'token': token})
    
    return jsonify(result), 400


@app.route('/api/login', methods=['POST'])
def login():
    data = request.json
    username = data.get('username', '').strip()
    password = data.get('password', '')
    
    if not username or not password:
        return jsonify({'error': 'Username and password required'}), 400
    
    result = login_user(username, password)
    
    if result['success']:
        token = result.pop('token')
        _active_tokens[token] = result['user_id']
        return jsonify({**result, 'token': token})
    
    return jsonify(result), 401


@app.route('/api/logout', methods=['POST'])
def logout():
    token = request.headers.get('Authorization', '').replace('Bearer ', '')
    _active_tokens.pop(token, None)
    return jsonify({'success': True})


@app.route('/api/model/status', methods=['GET'])
def model_status():
    return jsonify(runtime.status())


@app.route('/api/sessions', methods=['GET'])
@token_required
def list_sessions():
    sessions = get_user_sessions(g.user_id)
    return jsonify({'sessions': sessions})


@app.route('/api/sessions', methods=['POST'])
@token_required
def new_session():
    data = request.json or {}
    name = data.get('name')
    result = create_session(g.user_id, name)
    return jsonify(result)


@app.route('/api/sessions/<int:session_id>', methods=['GET'])
@token_required
def get_session_details(session_id):
    session = get_session(session_id, g.user_id)
    if session:
        return jsonify(session)
    return jsonify({'error': 'Session not found'}), 404


@app.route('/api/sessions/<int:session_id>', methods=['DELETE'])
@token_required
def delete_session_endpoint(session_id):
    result = delete_session(session_id, g.user_id)
    if result['success']:
        return jsonify(result)
    return jsonify(result), 404


@app.route('/api/sessions/<int:session_id>/end', methods=['POST'])
@token_required
def end_session_endpoint(session_id):
    data = request.json or {}
    stats = {
        'good_steps': data.get('good_steps', 0),
        'bad_steps': data.get('bad_steps', 0),
        'total_samples': data.get('total_samples', 0),
        'avg_angle': data.get('avg_angle', 0.0),
    }
    result = end_session(session_id, g.user_id, stats)
    return jsonify(result)


@app.route('/api/predict', methods=['POST'])
@token_required
def predict():
    data = request.json
    
    if not data or 'angle' not in data:
        return jsonify({'error': 'No angle data provided'}), 400
        
    angle = float(data.get('angle', 0.0))
    angle_series = data.get('angle_series')
    session_id = data.get('session_id')
    
    if not isinstance(angle_series, list):
        angle_series = None
    
    result = runtime.predict(angle, angle_series=angle_series)
    
    # Save prediction to session if provided
    if session_id:
        save_prediction(session_id, {
            'angle': angle,
            'model_score': result.get('model_score', 0.0),
            'anomaly_strength': result.get('anomaly_strength', 0.0),
            'classification': result.get('classification', 'unknown'),
            'assistance_percent': result.get('assistance_percent', 0.0),
            'activity_class': result.get('activity_class', 'unknown'),
            'intention_class': result.get('intention_class', 'walking'),
        })
    
    return jsonify({
        'classification': result['classification'],
        'assistance_percent': result['assistance_percent'],
        'model_score': result.get('model_score', 0.0),
        'anomaly_strength': result.get('anomaly_strength', 0.0),
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