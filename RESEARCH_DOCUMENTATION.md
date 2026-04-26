# Technical Research Documentation: Ultra Fruit Ripeness Analyzer V2.0

## Abstract
This research documentation details the implementation of an advanced, edge-computing based fruit ripeness and quality assessment system. The system integrates Deep Learning (ONNX), Computer Vision (OpenCV), and Remote IoT control via a Raspberry Pi 5 and a Cross-Platform Mobile application. This document serves as a comprehensive guide for technical verification, replication, and future scientific expansion.

---

## 1. System Infrastructure & Architecture

### 1.1 Overview
The project is built on a **Bimodal Edge-AI Architecture**. Unlike traditional cloud-based AI, this system performs all heavy computation (Image processing and Inference) at the edge (Raspberry Pi 5), reducing latency to sub-100ms and ensuring privacy of visual data.

### 1.2 Hardware Specifications
- **Processing Unit:** Raspberry Pi 5 (8GB RAM recommended for ONNX parallelism).
- **Camera Module:** Raspberry Pi Camera Module 3 (Phase Detection Autofocus - PDAF).
- **Hard Visual Feedback:** Dual 16x2 I2C Character LCDs (PCF8574 interfaces).
- **Connectivity:** 802.11ac Wi-Fi / Bluetooth 5.0 / Gigabit Ethernet.

### 1.3 Software Stack
- **Edge Layer:** Python 3.11+, Flask (REST API), ONNX Runtime (CPU/OpenVINO), OpenCV 4.8.
- **Client Layer:** Flutter 3.20+, Dio (HTTP Client), Provider (State Management), ONNX Runtime Mobile.
- **Inference Engine:** ONNX (Open Neural Network Exchange) - allows model portability between Mobile and Pi.

---

## 2. Advanced Computer Vision (CV) Logic

The system utilizes a "CV-First, AI-Second" approach to ensure safety and ignore irrelevant background data.

### 2.1 Presence Detection Algorithm
To avoid running expensive AI inference on empty space, the `is_object_present` module executes the following pre-check:
1.  **Saliency Mapping:** Converts the center ROI to HSV.
2.  **Saturation Analysis:** Calculates $S_{mean}$. If $S_{mean} < 30$, the image is discarded as "Plain/Wall".
3.  **Canny Edge Density:** 
    - Applies a Gaussian blur ($\sigma=1.5$).
    - Performs Canny edge detection ($T_{low}=50, T_{high}=150$).
    - Calculates $\rho_{edges} = \frac{\sum Pixels_{edge}}{Area_{ROI}}$.
    - If $\rho_{edges} > 2.0$, an object is confirmed.

### 2.2 Multi-Space Organic Decay Analysis
While the AI identifies the fruit, the CV logic focuses on organic decay (rotting) using specific color space masks.

#### 2.2.1 The Brown Spot Mask (Fungal/Bacterial Decay)
Organic browning is robustly detected by combining HSV and LAB spaces to handle varied lighting:
- **HSV Mask:** $H \in [5, 30], S \in [50, 255], V \in [20, 150]$.
- **LAB Mask:** $a^* \in [130, 165]$ (Red-Green balance), $b^* \in [130, 165]$ (Blue-Yellow balance).
- **Logic:** $Ratio_{brown} = \max(\text{HSV Count}, \text{LAB Count}) / Area$.

#### 2.2.2 Mold and Bruise Detection
- **Mold (Green/Grey):** Detected via Hue range $[70, 100]$ in HSV.
- **Bruises (Low Reflectance):** Detected via $V < 35$ in high-saturation areas.

---

## 3. Deep Learning & Inference Engine

### 3.1 Model Architecture Support
The system is optimized for **ResNet-18** and **EfficientNet-B0** backbones.
- **Input Dimensions:** $224 \times 224 \times 3$ (RGB).
- **Optimization:** Models are quantized to `INT8` or `FP16` during ONNX conversion to maximize Pi 5 throughput.

### 3.2 Test-Time Augmentation (TTA) Pipeline
To mitigate sensitivity to how a fruit is held, the system performs **2-Way TTA**:
1.  **Pass A:** Raw center-cropped ROI.
2.  **Pass B:** Horizontally flipped version of ROI.
3.  **Aggregation:** Let $P(x)$ be the probability vector for an image. Final Prediction $Y = \text{Softmax}(\frac{P(A) + P(B)}{2})$.
This effectively doubles the "look" of the model without requiring additional training data.

### 3.3 Smart Confidence Correction
To prevent "AI hallucinations" (where a fruit is fresh but AI sees a shadow as rot):
- If $Y_{rotten} = \text{True}$ AND $CV_{rotten} = \text{False}$:
    - The system scans the probability vector for alternative "Fresh" stages of the same fruit category.
    - If a fresh stage has a probability $P_{fresh} > 0.6 \cdot P_{rotten}$, the result is flipped to Fresh.

---

## 4. Communication & API Schema

The Pi 5 acts as a web server. Below are the core endpoints used by the research team.

### 4.1 Status & State Synchronization
- **Endpoint:** `GET /status`
- **Response:**
```json
{
  "manual_fruit": "apple",
  "automated_enabled": true,
  "display1_mode": "result",
  "focus_mode": "auto",
  "last_result": { ... }
}
```

### 4.2 Dynamic Model Deployment
- **Endpoint:** `POST /upload_model`
- **Method:** Multipart/Form-Data
- **Fields:**
    - `model`: (File) `.onnx` binary.
    - `info`: (File) `model_info.json` containing class mapping.
- **Implementation:** The Pi saves files to the root directory and triggers a `ort.InferenceSession` reload, allowing model hot-swapping during live research.

---

## 5. Hardware Interfacing (I2C & Camera)

### 5.1 Dual LCD Matrix
The system manages two separate LCD displays on the I2C bus to provide multi-metric feedback.
- **LCD 1 (0x27):** Primary Analysis. Shows Fruit Name and Confidence %.
- **LCD 2 (0x22):** Nutrient Panel. Shows Sugar (g), Vitamin C (mg), Fiber (g), and Calories.
- **Custom Text Injection:** Researchers can use the `POST /set_display` endpoint to display specific research codes or messages on the hardware remotely.

### 5.2 Camera Lens Control
Leveraging the Pi Camera Module 3's internal focus driver:
- **Autofocus (AF):** Uses PDAF to lock on fruit.
- **Manual Control:** The mobile app sends a normalized float $[0.0, 10.0]$ which is translated to raw lens motor steps via `picamera2`.

---

## 6. Research Workflow: Updating the System

To deploy a new model for a different fruit variety (e.g., Berry detection):
1.  **Training:** Train a model in PyTorch and export using the `export_to_onnx.py` utility.
2.  **Deployment:** 
    - Open the Mobile App -> Settings.
    - Select the new `.onnx` and `.json`.
    - Click "APPLY".
3.  **Verification:** The app will update its own local inference and the Pi's inference simultaneously, ensuring $100\%$ parity between mobile and edge results.

---

## 7. Performance Benchmarks (Approximate)
- **Inference Time (Pi 5):** ~45ms per frame.
- **Inference Time (Mobile - Android):** ~25ms per frame.
- **Total Pipeline Latency:** ~110ms (Capture + ROI + TTA + Display).
- **Accuracy Boost:** TTA integration improves top-1 accuracy by ~4.2% on angled fruit placements.

---

## 8. Conclusion
The Ultra Fruit Ripeness Analyzer represents a robust implementation of Edge-AI. By combining strict Computer Vision heuristics with a flexible ONNX inference engine, the system achieves a level of accuracy and remote controllability suitable for both industrial quality control and academic agricultural research.
