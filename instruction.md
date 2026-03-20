# Instructions: Adding Remote Screen to Fruit Analyzer Pro

This guide outlines how to implement a "Remote Screen" feature to monitor the Raspberry Pi 5 camera feed and control analysis from the mobile app.

## Phase 1: Raspberry Pi Setup (Streaming Server)

To allow the mobile app to see what the Pi sees, we need a lightweight web server.

### 1. Install Dependencies
```bash
pip install flask flask-cors
```

### 2. Integration into `pi_automated_analyzer.py`
Add a Flask server that runs in a separate thread. This server will provide:
- `/video_feed`: MJPEG stream of the camera.
- `/set_fruit`: API to manually select the fruit type.
- `/trigger_scan`: API to force a manual scan.

**Proposed Python Changes:**
```python
from flask import Flask, Response, request, jsonify
from flask_cors import CORS
import threading

app = Flask(__name__)
CORS(app)

current_frame = None
manual_fruit = 'auto'

@app.route('/video_feed')
def video_feed():
    def generate():
        global current_frame
        while True:
            if current_frame is not None:
                yield (b'--frame\r\n'
                       b'Content-Type: image/jpeg\r\n\r\n' + current_frame + b'\r\n')
            time.sleep(0.1)
    return Response(generate(), mimetype='multipart/x-mixed-replace; boundary=frame')

@app.route('/set_fruit', methods=['POST'])
def set_fruit():
    global manual_fruit
    data = request.json
    manual_fruit = data.get('fruit', 'auto')
    return jsonify({"status": "success", "fruit": manual_fruit})

def run_server():
    app.run(host='0.0.0.0', port=5000, threaded=True)

# In your main loop, update current_frame after every capture
# thread = threading.Thread(target=run_server)
# thread.daemon = True
# thread.start()
```

---

## Phase 2: Mobile App Changes (Flutter)

### 1. Update `pubspec.yaml`
Add the following dependency to handle the MJPEG stream:
```yaml
dependencies:
  flutter_mjpeg: ^0.3.0
```

### 2. Create `lib/screens/remote_screen.dart`
This new screen will connect to the Pi's IP address.

**Key Features to Implement:**
- **URL Input:** A field to enter the Pi's IP (e.g., `http://192.168.1.100:5000/video_feed`).
- **Live Feed:** Use `Mjpeg(isLive: true, stream: url)` to display the camera.
- **Fruit Selector:** A `DropdownButton` that sends a POST request to `/set_fruit` on the Pi.
- **Trigger Button:** A floating action button to call `/trigger_scan`.

### 3. Navigation Update
- Add a "Remote Monitor" tile to the `Drawer` or a button on the `HomeScreen`.
- Ensure it passes the user configuration (IP address) which should be stored in `SharedPreferences`.

---

## Phase 3: Customizations & Features

### 1. Remote Fruit Selector
When a user selects "Mango" on the mobile app:
- The app sends `{"fruit": "mango"}` to the Pi.
- The Pi's `FruitPredictor.predict()` logic should prioritize this selection over the "Auto" detection.

### 2. Status Overlay
The Pi should also expose a `/status` endpoint that returns the latest prediction results (fruit, ripeness, nutrients). The mobile app can poll this or use a WebSocket to show the data as an overlay on the live feed.

### 3. Recording/Snapshots
Add a button on the `RemoteScreen` to save the current frame from the MJPEG stream to the phone's local gallery.

---

## Summary for Gemini Implementation
1. **Modify `pi_automated_analyzer.py`**: Add Flask threading logic and update `current_frame` buffer.
2. **Modify `lib/screens/remote_screen.dart`**: Implement the UI with `flutter_mjpeg` and `http` calls.
3. **Connect the two**: Ensure the Pi and Mobile are on the same WiFi network.
