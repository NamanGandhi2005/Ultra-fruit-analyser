# 🍎 Fruit Analyzer Pro - Mobile App

An AI-powered mobile application designed to assess the ripeness and quality of fruits (Banana, Apple, Orange, Mango) using a ResNet-18 model exported to ONNX.

## 🚀 Key Features
- **AI Ripeness Detection:** High-accuracy classification across multiple growth stages.
- **Smart Correction V6:** Combines AI inference with Computer Vision (CV) to reduce false positives for rotten fruit.
- **TTA (Test-Time Augmentation):** Uses horizontal flipping and probability averaging for more robust predictions.
- **Nutrient Analysis:** Provides estimated sugar, fiber, and calorie data based on the fruit's stage.
- **Modern UI:** Built with Material 3, supporting both Dark and Light modes.
- **Notifications:** Integrated Telegram Bot and Email SMTP alerts for rotten fruit detection.

---

## 🛠️ Prerequisites

Before you begin, ensure you have the following installed:
- **Flutter SDK:** [Install Flutter](https://docs.flutter.dev/get-started/install) (Version 3.24.0 or higher recommended).
- **Java Development Kit (JDK):** JDK 21 is required for the latest Android Gradle Plugin.
- **Android Studio / VS Code:** Configured with Flutter and Dart plugins.
- **Android SDK:** Platform 35 and NDK `26.1.10909125`.
- **Physical Device / Emulator:** An Android device with "USB Debugging" enabled.

---

## 📦 Getting Started

### 1. Clone the Repository
```bash
git clone https://github.com/NamanGandhi2005/Ultra-fruit-analyser.git
cd Ultra-fruit-analyser/fruit_analyzer_mobile
```

### 2. Install Dependencies
Fetch all the required Flutter packages:
```bash
flutter pub get
```

### 3. Setup Assets
Ensure the following files are present in `assets/`:
- `assets/model/fruit_model.onnx` (The AI Model)
- `assets/data/nutrients.json` (The Nutrient Database)
- `assets/data/model_info.json` (Class names and metadata)

### 4. Run the App
Connect your mobile device and run:
```bash
flutter run
```

---

## ⚙️ Configuration

### Notifications
To receive alerts on your phone/email when rotten fruit is detected:
1. Open the app and go to **Settings** (⚙️ icon).
2. **Telegram:** Enter your Bot Token and Chat ID.
3. **Email:** Enter your SMTP server details and credentials.

### Fruit Selector
By default, the app uses **Auto-Detect**. If you want to force the AI to look for a specific fruit (e.g., only Apples), use the dropdown menu on the Home Screen.

---

## 🧪 Tech Stack
- **Framework:** Flutter (Dart)
- **AI Runtime:** `onnxruntime`
- **Image Processing:** `image` & `camera` packages
- **State Management:** `provider`
- **Persistence:** `shared_preferences`

---

## 📜 License
This project is for educational and research purposes.


FUTURE 

 Based on the current implementation, here are some high-impact features and technical improvements you could add to take Fruit Analyzer Pro to a professional level:


  1. AI & Model Enhancements
   * Model Quantization (Size & Speed): Your current model is ~44MB. By quantizing the ONNX model to INT8, you can reduce the size to ~11MB and significantly speed up inference on older mobile devices without losing
     noticeable accuracy.
   * Object Detection (YOLO integration): Instead of simple classification, use a lightweight YOLOv8-nano model to detect and "box" the fruit in the live camera feed. This ensures the background doesn't interfere with
     the ripeness analysis.
   * Edge Hardware Acceleration: Use NNAPI (Android) or CoreML (iOS) providers in onnxruntime to run the model on the phone's dedicated NPU (Neural Processing Unit) for near-instant results.


  2. User Experience (UX) Improvements
   * AR Overlays: Use ARCore to project the ripeness percentage and nutrient data directly onto the fruit in the 3D camera view, rather than showing a card at the bottom.
   * Scan History & Gallery: Implement a local database (SQLite or Isar) to save every scan, including the image, date, and result. This allows users to track the ripening process of a specific fruit over several days.
   * Recipe Recommendations: Integrate an API (like Spoonacular) to suggest recipes based on the fruit's stage. For example: "Your bananas are Overripe! Click here for a 5-minute Banana Bread recipe."


  3. Nutrition & Health
   * Health App Integration: Sync the calories and sugar data from a scan directly to Google Fit or Apple Health.
   * Shelf-Life Prediction: Add a "Days to Rot" timer. Based on the current stage and typical degradation curves, estimate how many days the user has left to consume the fruit.


  4. Technical Robustness
   * Offline Authentication: Move from SharedPreferences to a more secure encrypted storage (like flutter_secure_storage) for user passwords.
   * CI/CD Pipeline: Set up GitHub Actions to automatically build and sign your APK/AAB files whenever you push code to the main branch.
   * Multilingual Support (i18n): Add support for local languages, which is crucial for agricultural apps used by farmers globally.


  5. Advanced Computer Vision
   * Weight Estimation: Use the camera's distance and the fruit's relative size in the frame to estimate the weight of the fruit, providing more accurate nutrient data (e.g., "This 150g Apple contains 18g of sugar").


  Which of these directions would you like to explore first? I can help you implement any of them.

1. Advanced AI & Prediction
   * "Perfect Ripeness" Countdown: Instead of just showing the current stage, use the historical data to predict when the fruit will be at its peak (e.g., "Perfect in 2 days").
   * Multi-Fruit Detection: Allow the camera to detect and label multiple fruits in a single frame simultaneously using a bounding box UI.
   * Batch Analysis: Allow users to select 5–10 photos from the gallery at once and process them in a queue.


  2. User Engagement & Content
   * Smart Recipe Suggestions: If a fruit is "Overripe," show a button for recipes like "Banana Bread" or "Mango Smoothie" to prevent food waste.
   * Freshness Alerts: Set a reminder for a specific fruit (e.g., "Remind me to check this Avocado in 24 hours").
   * Health Ecosystem Sync: Integrate with Google Fit or Apple Health to automatically log the nutrients of the fruits the user scans.


  3. UI/UX Polish
   * Scanning HUD Animation: Replace the simple CircularProgressIndicator with a techy, "cyber-scan" overlay that moves across the fruit during the "Analyzing" phase.
   * Interactive Onboarding: A beautiful 3-page introduction (using Lottie animations) explaining how to get the best results (lighting, distance, etc.).
   * Gamification (Badges): Reward users with badges like "Fruit Master" or "Waste Warrior" for consistent scanning and tracking.


  4. Practical Utilities
   * Smart Shopping List: If the app detects "Rotten" fruit, offer to add that fruit to a built-in shopping list immediately.
   * Price Tracking: Allow users to log the price they paid for fruit to track spending versus quality over time.
   * Offline Mode Enhancements: Ensure the entire nutrient database is indexed for instant search even without a connection.