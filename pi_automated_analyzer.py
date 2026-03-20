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
import smtplib
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart
from email.mime.image import MIMEImage
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
    "last_result": None
}

@app.route('/video_feed')
def video_feed():
    def generate():
        while True:
            if remote_state["current_frame"] is not None:
                yield (b'--frame\r\n'
                       b'Content-Type: image/jpeg\r\n\r\n' + remote_state["current_frame"] + b'\r\n')
            time.sleep(0.1)
    return Response(generate(), mimetype='multipart/x-mixed-replace; boundary=frame')

@app.route('/set_fruit', methods=['POST'])
def set_fruit():
    data = request.json
    remote_state["manual_fruit"] = data.get('fruit', 'auto')
    print(f"📡 Remote command: Fruit set to {remote_state['manual_fruit']}")
    return jsonify({"status": "success", "fruit": remote_state["manual_fruit"]})

@app.route('/trigger_scan', methods=['POST'])
def trigger_scan():
    remote_state["trigger_scan"] = True
    return jsonify({"status": "success", "message": "Scan triggered"})

@app.route('/status')
def get_status():
    return jsonify({
        "manual_fruit": remote_state["manual_fruit"],
        "last_result": remote_state["last_result"]
    })

def run_flask():
    app.run(host='0.0.0.0', port=5000, threaded=True)

# --- Raspberry Pi Specific Libraries ---
try:
    from picamera2 import Picamera2
    HAS_PICAMERA = True
except ImportError:
    print("⚠️ Picamera2 not found. Falling back to OpenCV for camera.")
    HAS_PICAMERA = False

try:
    from RPLCD.i2c import CharLCD
    import smbus2
    HAS_LCD = True
except ImportError:
    print("⚠️ RPLCD or smbus2 not found. LCD display will be simulated in console.")
    HAS_LCD = False

# ----------------------------
# 1. NOTIFICATION MANAGER
# ----------------------------
class NotificationManager:
    def __init__(self):
        self.telegram_config = self.load_config('telegram_config.json', {'bot_token': '', 'chat_id': '', 'enabled': False})
        self.email_config = self.load_config('email_config.json', {'smtp_server': '', 'smtp_port': 587, 'email': '', 'password': '', 'enabled': False})

    def load_config(self, filename, default):
        try:
            if os.path.exists(filename):
                with open(filename, 'r') as f:
                    return json.load(f)
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
                    files = {'photo': f}
                    data = {'chat_id': chat_id, 'caption': message}
                    response = requests.post(url, files=files, data=data)
            else:
                url = f"https://api.telegram.org/bot{bot_token}/sendMessage"
                data = {'chat_id': chat_id, 'text': message}
                response = requests.post(url, data=data)
            return response.status_code == 200
        except: return False

# ----------------------------
# 2. FRUIT PREDICTOR
# ----------------------------
class FruitPredictor:
    def __init__(self, model_path='fruit_resnet_model.pth'):
        self.device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
        print(f"🚀 AI Engine utilizing: {self.device}")
        self.model = None
        self.class_names = []
        self.load_model(model_path)
        self.load_nutrients()

    def load_model(self, model_path):
        if not os.path.exists(model_path):
            raise FileNotFoundError(f"Model file {model_path} not found.")
        
        checkpoint = torch.load(model_path, map_location=self.device)
        self.class_names = checkpoint['class_names']
        num_classes = checkpoint['num_classes']
        
        self.model = models.resnet18(weights=None)
        self.model.fc = nn.Linear(self.model.fc.in_features, num_classes)
        self.model.load_state_dict(checkpoint['model_state_dict'])
        self.model.to(self.device)
        self.model.eval()
        print(f"✅ Model loaded. Classes: {len(self.class_names)}")

    def load_nutrients(self):
        try:
            with open('nutrients.json', 'r') as f:
                self.NUTRIENT_DB = json.load(f)
        except Exception as e:
            print(f"⚠️ Failed to load nutrients.json: {e}")
            self.NUTRIENT_DB = {}

    def is_rotten(self, image_path):
        try:
            img = cv2.imread(image_path)
            if img is None: return False
            img_hsv = cv2.cvtColor(img, cv2.COLOR_BGR2HSV)
            h, s, v = cv2.split(img_hsv)
            # Brown/Rotten spots heuristic
            brown_mask = ((h >= 5) & (h <= 35) & (s >= 50) & (v <= 180))
            brown_ratio = np.sum(brown_mask) / (img.shape[0] * img.shape[1])
            dark_mask = (v < 35)
            dark_ratio = np.sum(dark_mask) / (img.shape[0] * img.shape[1])
            return (brown_ratio >= 0.35) or (dark_ratio >= 0.50)
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
        # label format usually: fruit_stage_X
        parts = label.split('_stage_')
        fruit = parts[0] if len(parts) == 2 else label.split('_')[0]
        stage = parts[1] if len(parts) == 2 else "1"

        is_rotten_cv = self.is_rotten(image_path)
        
        fruit_db = self.NUTRIENT_DB.get(fruit.lower(), {})
        stage_info = fruit_db.get(str(stage), {})
        is_rotten_db = stage_info.get('rotten', False)
        
        is_rotten = is_rotten_db or is_rotten_cv

        return {
            'fruit': fruit.capitalize(),
            'stage': stage,
            'name': stage_info.get('name', 'Unidentified'),
            'confidence': conf.item(),
            'is_rotten': is_rotten,
            'nutrients': stage_info if not is_rotten else None
        }

# ----------------------------
# 3. MAIN PI CONTROLLER
# ----------------------------
class PiFruitAnalyzer:
    def __init__(self, lcd1_addr=0x27, lcd2_addr=0x27, port1=1, port2=0):
        self.predictor = FruitPredictor()
        self.notifier = NotificationManager()
        self.lcd1_addr = lcd1_addr
        self.lcd2_addr = lcd2_addr
        self.port1 = port1
        self.port2 = port2
        self.setup_lcd()
        self.setup_camera()

    def setup_lcd(self):
        self.lcd1 = None
        self.lcd2 = None
        if HAS_LCD:
            try:
                # LCD 1: Primary Info (Bus 1 by default)
                self.lcd1 = CharLCD('PCF8574', self.lcd1_addr, port=self.port1, cols=16, rows=2)
                self.lcd1.clear()
                self.lcd_print(self.lcd1, "FRUIT ANALYZER", "INITIALIZING...")
                print(f"✅ LCD 1 initialized at {hex(self.lcd1_addr)} on Port {self.port1}")
            except Exception as e:
                print(f"⚠️ LCD 1 (Port {self.port1}) failed: {e}")

            try:
                # LCD 2: Nutrient Info (Bus 0 as requested)
                self.lcd2 = CharLCD('PCF8574', self.lcd2_addr, port=self.port2, cols=16, rows=2)
                self.lcd2.clear()
                self.lcd_print(self.lcd2, "NUTRIENT INFO", "SYSTEM READY")
                print(f"✅ LCD 2 initialized at {hex(self.lcd2_addr)} on Port {self.port2}")
            except Exception as e:
                print(f"⚠️ LCD 2 (Port {self.port2}) failed: {e}")
        else:
            print("💡 No LCD hardware detected. Check smbus2 and RPLCD.")

    def setup_camera(self):
        if HAS_PICAMERA:
            try:
                self.camera = Picamera2()
                config = self.camera.create_preview_configuration(main={"size": (640, 480)})
                self.camera.configure(config)
                self.camera.start()
                print("✅ Picamera2 started.")
            except Exception as e:
                print(f"❌ Picamera2 failed: {e}. Falling back to OpenCV.")
                self.camera = cv2.VideoCapture(0)
        else:
            self.camera = cv2.VideoCapture(0)
            print("✅ OpenCV Camera started.")

    def lcd_print(self, lcd, line1, line2):
        if lcd:
            try:
                lcd.clear()
                lcd.write_string(line1[:16])
                lcd.cursor_pos = (1, 0)
                lcd.write_string(line2[:16])
            except:
                pass
        print(f"LCD [{'1' if lcd == self.lcd1 else '2'}]: {line1:16} | {line2:16}")

    def capture_image(self, path='pi_capture.jpg'):
        frame_to_save = None
        if HAS_PICAMERA and hasattr(self.camera, 'capture_file'):
            self.camera.capture_file(path)
            # For streaming, we still need a frame buffer
            # We can read the file back or capture to stream (file is safer for existing logic)
            img = cv2.imread(path)
            if img is not None:
                frame_to_save = img
        else:
            ret, frame = self.camera.read()
            if ret:
                cv2.imwrite(path, frame)
                frame_to_save = frame
            else:
                print("❌ Camera capture failed!")
        
        # Update global buffer for Flask streaming
        if frame_to_save is not None:
            ret, buffer = cv2.imencode('.jpg', frame_to_save)
            if ret:
                remote_state["current_frame"] = buffer.tobytes()
                
        return path

    def run(self):
        print("🚀 Starting automated analysis loop...")
        # Start Flask server in background
        flask_thread = threading.Thread(target=run_flask, daemon=True)
        flask_thread.start()
        print("🌐 Remote server running at http://0.0.0.0:5000")

        self.lcd_print(self.lcd1, "READY TO SCAN", "PLACE FRUIT")
        self.lcd_print(self.lcd2, "NUTRIENT DATA", "WILL APPEAR HERE")
        
        try:
            while True:
                image_path = self.capture_image()
                
                # Check if we should process
                # Triggered by timer OR remote manual trigger
                if not remote_state["trigger_scan"]:
                    # In normal auto-mode, we check for confidence first (implicit in logic below)
                    pass

                result = self.predictor.predict(image_path)
                
                # If manual fruit is selected, we could override or filter, 
                # but for now we just log it and store it in status
                if remote_state["manual_fruit"] != "auto":
                    print(f"🔍 Manual Override: Targeting {remote_state['manual_fruit']}")

                if result['confidence'] < 0.6 and not remote_state["trigger_scan"]:
                    self.lcd_print(self.lcd1, "SEARCHING...", "PLACE FRUIT")
                    time.sleep(1)
                    continue

                # Reset trigger
                remote_state["trigger_scan"] = False
                remote_state["last_result"] = result

                # LCD 1: Results
                if result['is_rotten']:
                    self.lcd_print(self.lcd1, f"{result['fruit']}: ROTTEN", f"Conf: {result['confidence']:.1%}")
                    self.lcd_print(self.lcd2, "!!! ROTTEN !!!", "DO NOT CONSUME")
                    
                    # Notify
                    msg = f"🚨 ROTTEN {result['fruit']} detected ({result['confidence']:.1%})."
                    self.notifier.send_telegram_alert(msg, image_path)
                else:
                    self.lcd_print(self.lcd1, f"{result['fruit']}", f"{result['name']} ({result['confidence']:.0%})")
                    
                    # LCD 2: Nutrients
                    n = result['nutrients']
                    if n:
                        # Format line 1: Sugar & Vit C
                        l1 = f"Sug:{n.get('sugar_g','?')}g VitC:{n.get('vitamin_c_mg','?')}m"
                        # Format line 2: Calories & Fiber
                        l2 = f"Cal:{n.get('calories','?')} Fib:{n.get('fiber_g','?')}g"
                        self.lcd_print(self.lcd2, l1, l2)
                    else:
                        self.lcd_print(self.lcd2, "NO DATA FOR", result['fruit'])

                time.sleep(3) # Wait between scans
        except KeyboardInterrupt:
            print("\n🛑 Stopping system...")
        finally:
            if HAS_PICAMERA and hasattr(self.camera, 'stop'): self.camera.stop()
            elif hasattr(self.camera, 'release'): self.camera.release()
            if self.lcd1: self.lcd1.clear()
            if self.lcd2: self.lcd2.clear()

if __name__ == "__main__":
    # LCD 1 is at 0x27 on Port 1, LCD 2 is at 0x22 on Port 0
    analyzer = PiFruitAnalyzer(lcd1_addr=0x27, lcd2_addr=0x22)
    analyzer.run()
