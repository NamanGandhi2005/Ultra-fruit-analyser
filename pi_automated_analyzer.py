import os
import json
import time
import cv2
import numpy as np
import torch
import torch.nn as nn
from torchvision import models, transforms
from PIL import Image
from datetime import datetime
import requests
import threading
from flask import Flask, Response, request, jsonify
from flask_cors import CORS

# --- Flask Server for Remote Monitoring ---
app = Flask(__name__)
CORS(app)

# Global state for remote access
remote_state = {
    "current_frame": None,
    "manual_fruit": "auto",
    "trigger_scan": False,
    "last_result": None,
    "focus_mode": "auto", # auto or manual
    "lens_pos": 0.0
}

@app.route('/video_feed')
def video_feed():
    print("📡 Remote command: Video feed requested")
    def generate():
        while True:
            if remote_state["current_frame"] is not None:
                yield (b'--frame\r\n'
                       b'Content-Type: image/jpeg\r\n\r\n' + remote_state["current_frame"] + b'\r\n')
            time.sleep(0.05) # ~20 FPS limit for bandwidth efficiency
    return Response(generate(), mimetype='multipart/x-mixed-replace; boundary=frame')

@app.route('/set_fruit', methods=['POST'])
def set_fruit():
    data = request.json
    remote_state["manual_fruit"] = data.get('fruit', 'auto')
    print(f"📡 Remote command: Fruit set to {remote_state['manual_fruit']}")
    return jsonify({"status": "success", "fruit": remote_state["manual_fruit"]})

@app.route('/set_focus', methods=['POST'])
def set_focus():
    data = request.json
    mode = data.get('mode', 'auto')
    pos = data.get('pos', 0.0)
    remote_state["focus_mode"] = mode
    remote_state["lens_pos"] = float(pos)
    return jsonify({"status": "success", "mode": mode, "pos": pos})

@app.route('/trigger_scan', methods=['POST'])
def trigger_scan():
    remote_state["trigger_scan"] = True
    return jsonify({"status": "success", "message": "Scan triggered"})

@app.route('/status')
def get_status():
    # Ensure last_result is JSON serializable
    return jsonify({
        "manual_fruit": str(remote_state["manual_fruit"]),
        "last_result": remote_state["last_result"],
        "focus_mode": remote_state["focus_mode"],
        "lens_pos": remote_state["lens_pos"]
    })

def run_flask():
    app.run(host='0.0.0.0', port=5000, threaded=True)

# --- Raspberry Pi Specific Libraries ---
try:
    from picamera2 import Picamera2
    HAS_PICAMERA = True
except ImportError:
    HAS_PICAMERA = False

try:
    from RPLCD.i2c import CharLCD
    import smbus2
    HAS_LCD = True
except ImportError:
    HAS_LCD = False

# ----------------------------
# 1. NOTIFICATION MANAGER
# ----------------------------
class NotificationManager:
    def __init__(self):
        self.telegram_config = self.load_config('telegram_config.json', {'bot_token': '', 'chat_id': '', 'enabled': False})

    def load_config(self, filename, default):
        try:
            if os.path.exists(filename):
                with open(filename, 'r') as f: return json.load(f)
        except: pass
        return default

    def send_telegram_alert(self, message, image_path=None):
        if not self.telegram_config.get('enabled'): return False
        try:
            bot_token = self.telegram_config['bot_token']
            chat_id = self.telegram_config['chat_id']
            if image_path and os.path.exists(image_path):
                url = f"https://api.telegram.org/bot{bot_token}/sendPhoto"
                with open(image_path, 'rb') as f:
                    requests.post(url, files={'photo': f}, data={'chat_id': chat_id, 'caption': message})
            else:
                url = f"https://api.telegram.org/bot{bot_token}/sendMessage"
                requests.post(url, data={'chat_id': chat_id, 'text': message})
            return True
        except: return False

# ----------------------------
# 2. FRUIT PREDICTOR
# ----------------------------
class FruitPredictor:
    def __init__(self, model_path='fruit_resnet_model.pth'):
        self.device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
        self.model = None
        self.class_names = []
        self.load_model(model_path)
        self.load_nutrients()

    def load_model(self, model_path):
        checkpoint = torch.load(model_path, map_location=self.device)
        self.class_names = checkpoint['class_names']
        num_classes = checkpoint['num_classes']
        self.model = models.resnet18(weights=None)
        self.model.fc = nn.Linear(self.model.fc.in_features, num_classes)
        self.model.load_state_dict(checkpoint['model_state_dict'])
        self.model.to(self.device).eval()

    def load_nutrients(self):
        try:
            with open('nutrients.json', 'r') as f: self.NUTRIENT_DB = json.load(f)
        except: self.NUTRIENT_DB = {}

    def is_rotten(self, image_path):
        try:
            img = cv2.imread(image_path)
            if img is None: return False
            img_hsv = cv2.cvtColor(img, cv2.COLOR_BGR2HSV)
            h, s, v = cv2.split(img_hsv)
            brown_mask = ((h >= 5) & (h <= 35) & (s >= 50) & (v <= 180))
            brown_ratio = np.sum(brown_mask) / (img.shape[0] * img.shape[1])
            dark_mask = (v < 35)
            dark_ratio = np.sum(dark_mask) / (img.shape[0] * img.shape[1])
            # Cast to standard bool for JSON
            return bool((brown_ratio >= 0.35) or (dark_ratio >= 0.50))
        except: return False

    def predict(self, image_path):
        transform = transforms.Compose([
            transforms.Resize((224, 224)),
            transforms.ToTensor(),
            transforms.Normalize([0.485, 0.456, 0.406], [0.229, 0.224, 0.225])
        ])
        raw_image = Image.open(image_path).convert('RGB')
        img_tensor = transform(raw_image).unsqueeze(0).to(self.device)

        with torch.no_grad():
            outputs = self.model(img_tensor)
            probs = torch.nn.functional.softmax(outputs, dim=1)
            conf, idx = torch.max(probs, 1)
            
        label = self.class_names[idx.item()]
        parts = label.split('_stage_')
        fruit = parts[0] if len(parts) == 2 else label.split('_')[0]
        stage = parts[1] if len(parts) == 2 else "1"

        rotten_cv = self.is_rotten(image_path)
        fruit_db = self.NUTRIENT_DB.get(fruit.lower(), {})
        stage_info = fruit_db.get(str(stage), {})
        rotten_db = stage_info.get('rotten', False)
        
        is_rotten = bool(rotten_db or rotten_cv)

        return {
            'fruit': str(fruit.capitalize()),
            'stage': str(stage),
            'name': str(stage_info.get('name', 'Unidentified')),
            'confidence': float(conf.item()),
            'is_rotten': is_rotten,
            'nutrients': stage_info if not is_rotten else None
        }

# ----------------------------
# 3. MAIN PI CONTROLLER
# ----------------------------
class PiFruitAnalyzer:
    def __init__(self, lcd1_addr=0x27, lcd2_addr=0x22, port1=1, port2=0):
        self.predictor = FruitPredictor()
        self.notifier = NotificationManager()
        self.lcd1_addr = lcd1_addr
        self.lcd2_addr = lcd2_addr
        self.port1 = port1
        self.port2 = port2
        self.setup_lcd()
        self.setup_camera()

    def setup_lcd(self):
        self.lcd1, self.lcd2 = None, None
        if HAS_LCD:
            try:
                self.lcd1 = CharLCD('PCF8574', self.lcd1_addr, port=self.port1, cols=16, rows=2)
                self.lcd_print(self.lcd1, "FRUIT ANALYZER", "INITIALIZING...")
            except: pass
            try:
                self.lcd2 = CharLCD('PCF8574', self.lcd2_addr, port=self.port2, cols=16, rows=2)
                self.lcd_print(self.lcd2, "NUTRIENT INFO", "SYSTEM READY")
            except: pass

    def setup_camera(self):
        self.frame_buffer = None
        self.running = True
        if HAS_PICAMERA:
            try:
                self.camera = Picamera2()
                # High quality config
                config = self.camera.create_preview_configuration(main={"size": (1280, 720), "format": "XBGR8888"})
                self.camera.configure(config)
                self.camera.start()
                print("✅ Picamera2 started (720p).")
            except: self.camera = cv2.VideoCapture(0)
        else: self.camera = cv2.VideoCapture(0)
        
        self.capture_thread = threading.Thread(target=self._capture_loop, daemon=True)
        self.capture_thread.start()

    def lcd_print(self, lcd, line1, line2):
        if lcd:
            try:
                lcd.clear()
                lcd.write_string(line1[:16])
                lcd.cursor_pos = (1, 0)
                lcd.write_string(line2[:16])
            except: pass
        print(f"LCD: {line1:16} | {line2:16}")

    def _capture_loop(self):
        last_focus_mode = ""
        last_lens_pos = -1.0
        
        while self.running:
            try:
                # Handle Dynamic Focus Control
                if HAS_PICAMERA and hasattr(self.camera, 'set_controls'):
                    if remote_state["focus_mode"] != last_focus_mode:
                        mode = 2 if remote_state["focus_mode"] == "auto" else 0 # 2=Continuous, 0=Manual
                        self.camera.set_controls({"AfMode": mode})
                        last_focus_mode = remote_state["focus_mode"]
                    
                    if remote_state["focus_mode"] == "manual" and remote_state["lens_pos"] != last_lens_pos:
                        self.camera.set_controls({"LensPosition": remote_state["lens_pos"]})
                        last_lens_pos = remote_state["lens_pos"]

                if HAS_PICAMERA and hasattr(self.camera, 'capture_array'):
                    frame = self.camera.capture_array()
                    frame = cv2.cvtColor(frame, cv2.COLOR_RGB2BGR)
                else:
                    ret, frame = self.camera.read()
                    if not ret: continue

                self.frame_buffer = frame
                # Resize for MJPEG stream to save bandwidth and improve compatibility
                stream_frame = cv2.resize(frame, (640, 480))
                ret, buffer = cv2.imencode('.jpg', stream_frame, [int(cv2.IMWRITE_JPEG_QUALITY), 70])
                if ret: remote_state["current_frame"] = buffer.tobytes()
                time.sleep(0.01)
            except: time.sleep(1)

    def capture_image(self, path='pi_capture.jpg'):
        if self.frame_buffer is not None:
            cv2.imwrite(path, self.frame_buffer)
            return path
        return None

    def run(self):
        threading.Thread(target=run_flask, daemon=True).start()
        self.lcd_print(self.lcd1, "READY TO SCAN", "PLACE FRUIT")
        
        try:
            while True:
                image_path = self.capture_image()
                if not image_path:
                    time.sleep(0.1)
                    continue
                
                result = self.predictor.predict(image_path)
                
                if result['confidence'] < 0.6 and not remote_state["trigger_scan"]:
                    self.lcd_print(self.lcd1, "SEARCHING...", "PLACE FRUIT")
                    time.sleep(1)
                    continue

                remote_state["trigger_scan"] = False
                remote_state["last_result"] = result

                if result['is_rotten']:
                    self.lcd_print(self.lcd1, f"{result['fruit']}: ROTTEN", f"Conf: {result['confidence']:.1%}")
                    self.lcd_print(self.lcd2, "!!! ROTTEN !!!", "DO NOT CONSUME")
                else:
                    self.lcd_print(self.lcd1, f"{result['fruit']}", f"{result['name']} ({result['confidence']:.0%})")
                    n = result['nutrients']
                    if n:
                        l1 = f"Sug:{n.get('sugar_g','?')}g VitC:{n.get('vitamin_c_mg','?')}m"
                        l2 = f"Cal:{n.get('calories','?')} Fib:{n.get('fiber_g','?')}g"
                        self.lcd_print(self.lcd2, l1, l2)

                time.sleep(3)
        except KeyboardInterrupt: pass
        finally:
            if HAS_PICAMERA and hasattr(self.camera, 'stop'): self.camera.stop()
            if self.lcd1: self.lcd1.clear()

if __name__ == "__main__":
    analyzer = PiFruitAnalyzer(lcd1_addr=0x27, lcd2_addr=0x22)
    analyzer.run()
