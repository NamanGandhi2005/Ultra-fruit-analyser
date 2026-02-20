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
