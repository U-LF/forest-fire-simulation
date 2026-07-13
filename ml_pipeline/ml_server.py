import os
import json
import joblib
import pandas as pd
from http.server import BaseHTTPRequestHandler, HTTPServer

# Load the model globally when the server starts
MODEL_PATH = os.path.join(os.path.dirname(__file__), 'random_forest_model.joblib')
print(f"Loading ML Model from {MODEL_PATH}...")
try:
    model = joblib.load(MODEL_PATH)
    print("Model loaded successfully!")
except Exception as e:
    print(f"Failed to load model: {e}")
    exit(1)

# Ensure feature order matches the training script precisely
FEATURE_NAMES = [
    'fire_north', 'fire_south', 'fire_east', 'fire_west', 'total_burning_neighbors',
    'elevation', 'pdsi', 'NDVI', 'pr', 'sph', 'th', 'tmmn', 'tmmx', 'vs', 'erc', 'population'
]

class PredictHandler(BaseHTTPRequestHandler):
    def _set_headers(self, content_length=0):
        self.send_response(200)
        self.send_header('Content-type', 'application/json')
        if content_length > 0:
            self.send_header('Content-Length', str(content_length))
        self.end_headers()

    def do_POST(self):
        if self.path == '/predict':
            content_length = int(self.headers['Content-Length'])
            post_data = self.rfile.read(content_length)
            
            try:
                # Expecting a JSON dict with a list of 'cells'
                req_data = json.loads(post_data.decode('utf-8'))
                cells = req_data.get('cells', [])
                
                if not cells:
                    self.send_response(400)
                    self.end_headers()
                    self.wfile.write(b'{"error": "No cells provided"}')
                    return
                
                # Convert to DataFrame
                df = pd.DataFrame(cells)
                
                # If Godot doesn't send certain features (like population), fill with defaults
                for col in FEATURE_NAMES:
                    if col not in df.columns:
                        df[col] = 0.0
                
                # Reorder columns to exactly match training data
                X = df[FEATURE_NAMES]
                
                # Run Inference with a custom threshold!
                probs = model.predict_proba(X)
                
                # Check if the probability of catching fire (index 1) is greater than 15%
                if probs.shape[1] > 1:
                    predictions = (probs[:, 1] > 0.15).astype(int)
                    # Debug logging!
                    with open("debug_log.txt", "w") as f:
                        f.write(f"Max Prob: {probs[:, 1].max()}\n")
                        f.write(f"Sample Data:\n{df.iloc[0].to_dict()}\n")
                else:
                    predictions = probs[:, 0] * 0 # Fallback
                
                # Return list of 0s and 1s
                response = {"predictions": predictions.tolist()}
                body = json.dumps(response).encode('utf-8')
                self._set_headers(len(body))
                self.wfile.write(body)
                
            except Exception as e:
                self.send_response(500)
                self.end_headers()
                self.wfile.write(json.dumps({"error": str(e)}).encode('utf-8'))
        else:
            self.send_response(404)
            self.end_headers()

    def log_message(self, format, *args):
        # Mute standard HTTP logging to keep console clean
        pass

def run(server_class=HTTPServer, handler_class=PredictHandler, port=5000):
    server_address = ('', port)
    httpd = server_class(server_address, handler_class)
    print(f"ML Inference Server running on port {port}...")
    print("Waiting for Godot to send simulation data...")
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        pass
    httpd.server_close()
    print("Server stopped.")

if __name__ == '__main__':
    run()
