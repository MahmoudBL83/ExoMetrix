from flask import Flask, request, jsonify
import random
# In a real scenario, you'd load your scikit-learn model here
# import joblib
# model = joblib.load('model.pkl')

app = Flask(__name__)

@app.route('/api/predict', methods=['POST'])
def predict():
    data = request.json
    
    if not data or 'angle' not in data:
        return jsonify({'error': 'No angle data provided'}), 400
        
    angle = float(data.get('angle', 0.0))
    
    # Placeholder ML simulation:
    # If angle is within a "normal" knee bend range (e.g., 0-140 degrees), it's good.
    # We will simulate assistance prediction as well.
    classification = "Good step"
    assistance_percent = 0
    
    if angle < -10 or angle > 150:
        classification = "Compensating (bad) step"
        assistance_percent = round(random.uniform(20.0, 50.0), 1)

    return jsonify({
        'classification': classification,
        'assistance_percent': assistance_percent,
        'received_angle': angle
    })

if __name__ == '__main__':
    app.run(debug=True, port=5328)
