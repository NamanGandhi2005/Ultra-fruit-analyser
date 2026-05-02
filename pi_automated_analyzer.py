import os
import json
import time
import cv2
import numpy as np
import onnxruntime as ort
from PIL import Image
from datetime import datetime
import requests
import threading
from flask import Flask, Response, request, jsonify, send_file
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
    "lens_pos": 0.0,
    "automated_enabled": True,
    "hybrid_enabled": True, # For research: CNN only vs Hybrid
    "display1_mode": "result", # result, status, custom
    "display2_mode": "result", # result, status, custom
    "custom_text1_l1": "",
    "custom_text1_l2": "",
    "custom_text2_l1": "",
    "custom_text2_l2": ""
}

@app.route('/set_hybrid', methods=['POST'])
def set_hybrid():
    data = request.json
    remote_state["hybrid_enabled"] = data.get('enabled', True)
    print(f"📡 Remote command: Hybrid Logic set to {remote_state['hybrid_enabled']}")
    return jsonify({"status": "success", "enabled": remote_state["hybrid_enabled"]})

@app.route('/upload_model', methods=['POST'])
def upload_model():
    if 'model' not in request.files:
        return jsonify({"status": "error", "message": "No model (.onnx) file provided"}), 400
    
    model_file = request.files['model']
    info_file = request.files.get('info') # Optional info.json
    
    if not model_file.filename.endswith('.onnx'):
        return jsonify({"status": "error", "message": "Only .onnx files allowed"}), 400

    base_dir = os.path.dirname(os.path.abspath(__file__))
    model_path = os.path.join(base_dir, "fruit_model.onnx")
    info_path = os.path.join(base_dir, "model_info.json")
    
    try:
        model_file.save(model_path)
        if info_file:
            info_file.save(info_path)
        
        # Reload the predictor if it exists
        global analyzer
        if 'analyzer' in globals() and analyzer:
            analyzer.predictor.load_model(model_path, info_path)
        
        print(f"✅ Model replaced: {model_file.filename}")
        return jsonify({
            "status": "success", 
            "message": "Model and Info updated successfully",
            "model_name": model_file.filename
        })
    except Exception as e:
        print(f"❌ Upload failed: {e}")
        return jsonify({"status": "error", "message": str(e)}), 500

@app.route('/download_onnx')
def download_onnx():
    base_dir = os.path.dirname(os.path.abspath(__file__))
    path = os.path.join(base_dir, "fruit_model.onnx")
    if os.path.exists(path):
        return send_file(path, as_attachment=True)
    return "Not found", 404

@app.route('/download_info')
def download_info():
    base_dir = os.path.dirname(os.path.abspath(__file__))
    path = os.path.join(base_dir, "model_info.json")
    if os.path.exists(path):
        return send_file(path, as_attachment=True)
    return "Not found", 404

@app.route('/video_feed')
def video_feed():
    def generate():
        while True:
            frame = remote_state.get("current_frame")
            if frame is not None:
                yield (b'--frame\r\n'
                       b'Content-Type: image/jpeg\r\n\r\n' + frame + b'\r\n')
            time.sleep(0.05)
    return Response(generate(), mimetype='multipart/x-mixed-replace; boundary=frame')

@app.route('/latest_frame')
def latest_frame():
    frame = remote_state.get("current_frame")
    if frame is not None:
        return Response(frame, mimetype='image/jpeg')
    return "No frame", 404

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

@app.route('/set_automation', methods=['POST'])
def set_automation():
    data = request.json
    remote_state["automated_enabled"] = data.get('enabled', True)
    print(f"📡 Remote command: Automation set to {remote_state['automated_enabled']}")
    return jsonify({"status": "success", "enabled": remote_state["automated_enabled"]})

@app.route('/set_display', methods=['POST'])
def set_display():
    data = request.json
    lcd_num = data.get('lcd', 1)
    mode = data.get('mode', 'result')
    
    if lcd_num == 1:
        remote_state["display1_mode"] = mode
        if mode == "custom":
            remote_state["custom_text1_l1"] = data.get('l1', "")
            remote_state["custom_text1_l2"] = data.get('l2', "")
    else:
        remote_state["display2_mode"] = mode
        if mode == "custom":
            remote_state["custom_text2_l1"] = data.get('l1', "")
            remote_state["custom_text2_l2"] = data.get('l2', "")
            
    return jsonify({"status": "success", "lcd": lcd_num, "mode": mode})

@app.route('/status')
def get_status():
    return jsonify({
        "manual_fruit": str(remote_state["manual_fruit"]),
        "last_result": remote_state["last_result"],
        "focus_mode": remote_state["focus_mode"],
        "lens_pos": remote_state["lens_pos"],
        "automated_enabled": remote_state["automated_enabled"],
        "hybrid_enabled": remote_state["hybrid_enabled"],
        "display1_mode": remote_state["display1_mode"],
        "display2_mode": remote_state["display2_mode"]
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

# ----------------------------
# 2. MACHINE LEARNING LOGIC
# ----------------------------
class FruitPredictor:
    def __init__(self, model_path='fruit_model.onnx', info_path='model_info.json'):
        # Load Nutrient Database
        try:
            with open('nutrients.json', 'r') as f:
                self.NUTRIENT_DB = json.load(f)
        except: self.NUTRIENT_DB = {}
        
        self.session = None
        self.class_names = []
        self.load_model(model_path, info_path)

    def load_model(self, model_path, info_path):
        """Load ONNX model and info JSON"""
        try:
            if not os.path.exists(model_path):
                print(f"⚠️ Model file {model_path} not found.")
                return

            self.session = ort.InferenceSession(model_path)
            self.input_name = self.session.get_inputs()[0].name
            
            if os.path.exists(info_path):
                with open(info_path, 'r') as f:
                    info = json.load(f)
                    self.class_names = info.get('class_names', [])
            
            print(f"✅ ONNX Model loaded: {model_path} ({len(self.class_names)} classes)")
        except Exception as e:
            print(f"❌ ML Load Error: {e}")

    def is_rotten(self, image_path, brown_threshold=0.35, dark_threshold=0.50):
        """Advanced CV check for brown, dark, and mold spots using HSV and LAB"""
        try:
            img = cv2.imread(image_path)
            if img is None: return False
            
            # Convert to HSV and LAB
            hsv = cv2.cvtColor(img, cv2.COLOR_BGR2HSV)
            lab = cv2.cvtColor(img, cv2.COLOR_BGR2LAB)
            h, s, v = cv2.split(hsv)
            l, a, b = cv2.split(lab)

            # Brown spots (HSV + LAB for robustness)
            brown_mask_hsv = ((h >= 5) & (h <= 30) & (s >= 50) & (v <= 150))
            brown_mask_lab = ((a >= 130) & (a <= 165) & (b >= 130) & (b <= 165))
            brown_ratio = max(np.sum(brown_mask_hsv), np.sum(brown_mask_lab)) / (img.shape[0] * img.shape[1])
            
            # Dark/Bruised spots
            dark_mask = (v < 35)
            dark_ratio = np.sum(dark_mask) / (img.shape[0] * img.shape[1])
            
            # Mold detection (Greenish/Greyish spots)
            mold_mask = ((h >= 70) & (h <= 100) & (s >= 40) & (v >= 40))
            mold_ratio = np.sum(mold_mask) / (img.shape[0] * img.shape[1])

            is_rotten = bool((brown_ratio >= brown_threshold) or (dark_ratio >= dark_threshold) or (mold_ratio >= 0.05))
            print(f"👁️ CV Debug -> Brown: {brown_ratio:.2f}, Dark: {dark_ratio:.2f}, Mold: {mold_ratio:.2f}")
            return is_rotten
        except Exception as e:
            print(f"CV Error: {e}")
            return False

    def _preprocess(self, pil_img):
        """Preprocess image for ONNX ResNet/EfficientNet"""
        img = pil_img.resize((224, 224))
        img_data = np.array(img).transpose(2, 0, 1).astype(np.float32)
        img_data /= 255.0
        # Normalize
        mean = np.array([0.485, 0.456, 0.406]).reshape(3, 1, 1)
        std = np.array([0.229, 0.224, 0.225]).reshape(3, 1, 1)
        img_data = (img_data - mean) / std
        return img_data

    def predict(self, image_path):
        """Inference with ONNX, ROI Focus, and Hybrid Decision Logic"""
        if self.session is None:
            return None

        try:
            raw_image = Image.open(image_path).convert('RGB')
            w, h = raw_image.size
            crop_size = min(w, h, 400)
            roi_image = raw_image.crop(((w-crop_size)//2, (h-crop_size)//2, (w+crop_size)//2, (h+crop_size)//2))

            # 2-way TTA (Original + Horizontal Flip)
            img_org = self._preprocess(roi_image)
            img_flip = self._preprocess(roi_image.transpose(Image.FLIP_LEFT_RIGHT))
            
            # Combine into a batch
            input_batch = np.stack([img_org, img_flip]).astype(np.float32)

            # Run ONNX inference
            outputs = self.session.run(None, {self.input_name: input_batch})
            # Softmax
            probs = np.exp(outputs[0]) / np.sum(np.exp(outputs[0]), axis=1, keepdims=True)
            avg_probs = np.mean(probs, axis=0)
            
            # Filtering by manual fruit if selected
            target_fruit = remote_state["manual_fruit"].lower()
            if target_fruit != "auto":
                filter_prefix = target_fruit + "_"
                mask = np.array([1.0 if c.lower().startswith(filter_prefix) else 0.0 for c in self.class_names])
                
                # SAFETY: Ensure mask matches avg_probs length
                if len(mask) != len(avg_probs):
                    print(f"⚠️ Warning: Model classes ({len(avg_probs)}) != Info classes ({len(mask)})")
                    mask = mask[:len(avg_probs)] if len(mask) > len(avg_probs) else np.pad(mask, (0, len(avg_probs)-len(mask)))

                if np.sum(mask) > 0:
                    avg_probs = avg_probs * mask
                    if np.sum(avg_probs) > 0: avg_probs /= np.sum(avg_probs)

            idx = np.argmax(avg_probs)
            conf = avg_probs[idx]
            
            # SAFETY: Check if idx is within class_names range
            if idx >= len(self.class_names):
                label = f"unknown_class_{idx}"
            else:
                label = self.class_names[idx]
            
            parts = label.split('_stage_')
            fruit = parts[0] if len(parts) == 2 else label.split('_')[0]
            stage = parts[1] if len(parts) == 2 else "1"

            # Hybrid Metadata
            decision_source = "CNN Inference"
            corrections = []

            # 1. CV Analysis
            rotten_cv = self.is_rotten(image_path)
            
            # 2. Database Knowledge
            fruit_db = self.NUTRIENT_DB.get(fruit.lower(), {})
            stage_info = fruit_db.get(str(stage), {})
            rotten_db = stage_info.get('rotten', False)
            
            is_rotten = rotten_db

            # 3. Hybrid Logic Fusion (if enabled)
            if remote_state.get("hybrid_enabled", True):
                # Smart Correction: If DB says rotten but AI is unsure and CV says fresh
                if rotten_db and not rotten_cv and conf < 0.92:
                    fresh_idx, max_fresh_prob = -1, -1
                    for i, name in enumerate(self.class_names):
                        if i >= len(avg_probs): break # SAFETY: Avoid index out of range
                        
                        if name.startswith(fruit):
                            s_id = name.split('_stage_')[1] if '_stage_' in name else "1"
                            if not fruit_db.get(s_id, {}).get('rotten', False):
                                if avg_probs[i] > max_fresh_prob:
                                    max_fresh_prob = avg_probs[i]; fresh_idx = i
                    
                    if fresh_idx != -1 and max_fresh_prob > (conf * 0.65):
                        label = self.class_names[fresh_idx]
                        stage = label.split('_stage_')[1] if '_stage_' in label else "1"
                        conf = max_fresh_prob
                        stage_info = fruit_db.get(str(stage), {})
                        is_rotten = False
                        decision_source = "Hybrid Fusion"
                        corrections.append("DB-to-Fresh Override (CV Guided)")

                # CV Rotten Override: If CV detects rot, it forces Rotten regardless of CNN
                if rotten_cv and not is_rotten:
                    is_rotten = True
                    decision_source = "Hybrid Fusion"
                    corrections.append("CV Rot Detection")

            return {
                'fruit': str(fruit.capitalize()),
                'stage': str(stage),
                'name': str(stage_info.get('name', 'Unidentified')),
                'confidence': float(conf),
                'is_rotten': is_rotten,
                'nutrients': stage_info if (stage_info and not is_rotten) else {},
                'metadata': {
                    'decision_source': decision_source,
                    'corrections': corrections,
                    'cv_rot': rotten_cv,
                    'hybrid_active': remote_state.get("hybrid_enabled", True)
                }
            }
        except Exception as e:
            print(f"Predict Error: {e}")
            return None

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
                if HAS_PICAMERA and hasattr(self.camera, 'set_controls'):
                    if remote_state["focus_mode"] != last_focus_mode:
                        mode = 2 if remote_state["focus_mode"] == "auto" else 0
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

    def is_object_present(self, frame):
        """Simple check to see if an object is present in the center ROI"""
        try:
            h, w, _ = frame.shape
            crop_size = min(w, h, 400)
            y1, y2 = (h - crop_size)//2, (h + crop_size)//2
            x1, x2 = (w - crop_size)//2, (w + crop_size)//2
            roi = frame[y1:y2, x1:x2]
            
            # Convert to HSV and check for saturation/brightness variety
            hsv_roi = cv2.cvtColor(roi, cv2.COLOR_BGR2HSV)
            s_mean = np.mean(hsv_roi[:,:,1])
            v_mean = np.mean(hsv_roi[:,:,2])
            
            # If saturation is very low, it's likely a plain background
            # If brightness is very low, it's likely dark
            if s_mean < 30 or v_mean < 40:
                return False
                
            # Use edge detection to check for "interesting" features
            gray = cv2.cvtColor(roi, cv2.COLOR_BGR2GRAY)
            edges = cv2.Canny(gray, 50, 150)
            edge_density = np.sum(edges) / (crop_size * crop_size)
            
            return edge_density > 2.0 # Threshold for "something is there"
        except: return True

    def run(self):
        threading.Thread(target=run_flask, daemon=True).start()
        self.lcd_print(self.lcd1, "READY TO SCAN", "PLACE FRUIT")
        
        last_presence = False
        
        try:
            while True:
                # 1. Check if automation is enabled or scan triggered
                if not remote_state["automated_enabled"] and not remote_state["trigger_scan"]:
                    self._update_displays(None)
                    time.sleep(0.5)
                    continue

                if self.frame_buffer is None:
                    time.sleep(0.1)
                    continue

                # 2. Presence Check (Avoid analyzing empty background)
                is_present = self.is_object_present(self.frame_buffer)
                if not is_present and not remote_state["trigger_scan"]:
                    if last_presence:
                        self.lcd_print(self.lcd1, "READY TO SCAN", "PLACE FRUIT")
                    last_presence = False
                    time.sleep(0.5)
                    continue
                
                last_presence = True
                image_path = self.capture_image()
                if not image_path: continue
                
                result = self.predictor.predict(image_path)
                if result is None:
                    continue
                
                # 2. Filter by manual fruit if selected
                target_fruit = remote_state["manual_fruit"].lower()
                if target_fruit != "auto":
                    if result['fruit'].lower() != target_fruit:
                        # If triggered manually, maybe show "Wrong fruit"
                        if remote_state["trigger_scan"]:
                            self.lcd_print(self.lcd1, "WRONG FRUIT", f"Wanted: {target_fruit}")
                            remote_state["trigger_scan"] = False
                            time.sleep(2)
                        continue

                # 3. Confidence threshold
                if result['confidence'] < 0.6 and not remote_state["trigger_scan"]:
                    self.lcd_print(self.lcd1, "SEARCHING...", "PLACE FRUIT")
                    time.sleep(0.5)
                    continue

                remote_state["trigger_scan"] = False
                remote_state["last_result"] = result

                # 4. Display results
                self._update_displays(result)
                time.sleep(3)
                
        except KeyboardInterrupt: pass
        finally:
            if HAS_PICAMERA and hasattr(self.camera, 'stop'): self.camera.stop()
            if self.lcd1: self.lcd1.clear()
            if self.lcd2: self.lcd2.clear()

    def _update_displays(self, result):
        # Display 1
        mode1 = remote_state["display1_mode"]
        if mode1 == "custom":
            self.lcd_print(self.lcd1, remote_state["custom_text1_l1"], remote_state["custom_text1_l2"])
        elif mode1 == "status":
            status = "AUTO" if remote_state["automated_enabled"] else "MANUAL"
            fruit = remote_state["manual_fruit"].upper()
            self.lcd_print(self.lcd1, f"MODE: {status}", f"TARGET: {fruit}")
        elif mode1 == "result" and result:
            if result['is_rotten']:
                self.lcd_print(self.lcd1, f"{result['fruit']}: ROTTEN", f"Conf: {result['confidence']:.1%}")
            else:
                self.lcd_print(self.lcd1, f"{result['fruit']}", f"{result['name']} ({result['confidence']:.0%})")
        elif not result:
            self.lcd_print(self.lcd1, "READY TO SCAN", "PLACE FRUIT")

        # Display 2
        mode2 = remote_state["display2_mode"]
        if mode2 == "custom":
            self.lcd_print(self.lcd2, remote_state["custom_text2_l1"], remote_state["custom_text2_l2"])
        elif mode2 == "status":
            ip = "PI 5 ANALYZER"
            self.lcd_print(self.lcd2, ip, datetime.now().strftime("%H:%M:%S"))
        elif mode2 == "result" and result:
            if result['is_rotten']:
                self.lcd_print(self.lcd2, "!!! ROTTEN !!!", "DO NOT CONSUME")
            else:
                n = result['nutrients']
                if n:
                    l1 = f"Sug:{n.get('sugar_g','?')}g VitC:{n.get('vitamin_c_mg','?')}m"
                    l2 = f"Cal:{n.get('calories','?')} Fib:{n.get('fiber_g','?')}g"
                    self.lcd_print(self.lcd2, l1, l2)
                else:
                    self.lcd_print(self.lcd2, "NO NUTRIENT", "DATA FOUND")
        elif not result:
            self.lcd_print(self.lcd2, "NUTRIENT INFO", "SYSTEM READY")

if __name__ == "__main__":
    analyzer = PiFruitAnalyzer(lcd1_addr=0x27, lcd2_addr=0x22)
    analyzer.run()
