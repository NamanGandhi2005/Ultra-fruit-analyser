# Research Documentation: Ultra Fruit Ripeness Analyzer

This document provides a detailed technical overview of the implementation, inference logic, and system architecture of the Ultra Fruit Ripeness Analyzer, focusing on the Raspberry Pi 5 integration and the mobile ecosystem.

---

## 1. System Architecture
The system follows a **Distributed Edge-AI** architecture consisting of two primary nodes:
- **Edge Node (Raspberry Pi 5):** Handles real-time video capture, advanced image processing, and high-speed ONNX inference.
- **Controller Node (Flutter Mobile App):** Provides a remote interface for monitoring, system configuration, and dynamic model deployment over both Local Network (LAN) and Internet (via Tunnels).

### Communication Protocol
Communication is handled via a **RESTful Flask API** running on the Pi 5 (Port 5000). 
- **State Synchronization:** A global `remote_state` object on the Pi tracks automation status, display modes, and manual overrides.
- **Data Streaming:** A multipart JPEG stream (`/video_feed`) provides low-latency visual feedback to the mobile client.

---

## 2. Inference Engine & ML Logic
The system transitioned from PyTorch to **ONNX Runtime (ort)** to optimize for the ARM64 architecture of the Pi 5.

### Inference Pipeline:
1.  **ROI Focus (Region of Interest):** To reduce background noise and improve accuracy, the system crops a central square (min 400px) from the 720p/1080p frame.
2.  **Test-Time Augmentation (TTA):** Each frame is passed through the model twice (Original + Horizontal Flip). The resulting probability distributions are averaged to mitigate angle sensitivity.
3.  **Pre-processing:**
    - Resize: $224 \times 224$ pixels.
    - Normalization: Image tensors are normalized using ImageNet means ($\mu=[0.485, 0.456, 0.406]$) and standard deviations ($\sigma=[0.229, 0.224, 0.225]$).
4.  **Softmax Aggregation:** Raw logits are converted to probabilities using a Softmax function, allowing for confidence-based filtering.

### Conflict Resolution (Smart Correction):
The system employs a "Double-Check" mechanism between the Neural Network (AI) and traditional Computer Vision (CV):
- If the AI predicts a **Rotten** stage but the CV checks find the fruit **Clean**, the system dynamically lowers the "Freshness" threshold. It searches for the highest-scoring non-rotten stage of the same fruit. If found with sufficient confidence ($>60\%$ of the rotten score), the system corrects the result to "Fresh."

---

## 3. Advanced Computer Vision (CV) Checks
Beyond deep learning, the system uses pixel-level analysis in multiple color spaces to ensure safety.

### Multi-Space Detection:
- **HSV Space (Hue, Saturation, Value):**
    - **Brown Spots:** Detected in the Hue range $5^\circ$ to $30^\circ$ with high saturation.
    - **Dark/Bruised areas:** Detected via low Value ($V < 35$).
    - **Mold Detection:** Specifically targets greenish/greyish growth in the Hue range $70^\circ$ to $100^\circ$ with moderate saturation.
- **LAB Space (Luminosity, A, B):**
    - Used specifically for brown spot robustness, targeting the $a^*$ (green-red) and $b^*$ (blue-yellow) ranges that represent organic decay.

### Presence Detection:
To prevent the AI from analyzing empty backgrounds, the `is_object_present` module checks for:
- **Saturation Variance:** Plain backgrounds have low saturation.
- **Edge Density (Canny):** Objects (fruits) have high edge density compared to a table or wall.

---

## 4. Raspberry Pi 5 Features
### Hardware Integration:
- **Dual LCD Control:** Supports two I2C-based 16x2 LCDs via the `RPLCD` library.
- **Lens Control (V3 Camera):** Integrated Autofocus (AF) and manual lens position control ($0.0$ to $10.0$ focus units) accessible remotely via the app.

### Display Modes:
1.  **Result Mode:** Shows Fruit Name, Stage, and Nutrient data.
2.  **Status Mode:** Shows system IP, time, and current automation state.
3.  **Custom Mode:** Allows the researcher/user to send arbitrary text strings from the mobile app to the Pi's hardware displays.

---

## 5. Mobile Integration & Model Management
### Remote Model Deployment:
The app features a **Unified Uploader** for `.onnx` and `model_info.json` files. 
- **Atomic Updates:** Both files are uploaded to the Pi simultaneously. Upon successful upload, the Pi reloads its inference session in real-time without a script restart.
- **Local Synchronization:** The app also updates its own internal inference engine with the uploaded files, ensuring parity between mobile and Pi results.

### Internet Connectivity:
By supporting standard URLs in addition to IP addresses, the system can be exposed via tunnels like **Ngrok** or **Cloudflare**. This allows for remote research monitoring across different geographical locations.

---

## 6. Research Use-Case Parameters
Researchers can tune the system by modifying the following thresholds in `pi_automated_analyzer.py`:
- `brown_threshold`: Default `0.35` (ratio of brown pixels).
- `dark_threshold`: Default `0.50` (ratio of dark pixels).
- `confidence_filter`: Default `0.60` (minimum AI probability to trigger a scan).
