# Mobile App Specification: Ultra Fruit Analyser Pro

This document serves as the complete technical specification for developing the Flutter mobile application to interface with the Raspberry Pi 5 Fruit Analyser system.

---

## 1. Connection & Discovery
*   **Default Pi IP:** `192.168.1.65` (Should be configurable in app settings).
*   **Discovery:** Use the `multicast_dns` package to find `raspberrypi.local` or implement a simple socket-based IP scanner for the local network.
*   **Status Indicator:** A "System Link" icon in the header (Green = Connected, Red = Offline).

## 2. API Endpoints (Pi 5 Backend)
All calls are made to the Flask server running on port `5000`.

| Feature | Method | Endpoint | Payload / Details |
| :--- | :--- | :--- | :--- |
| **Live Stream** | GET | `/video_feed` | MJPEG Stream (multipart/x-mixed-replace) |
| **System Status**| GET | `/status` | Returns: `fruit`, `confidence`, `is_rotten`, `nutrients`, `focus_mode`, `lens_pos` |
| **Trigger Scan** | POST| `/trigger_scan` | `{}` - Force an immediate AI analysis |
| **Fruit Mode**   | POST| `/set_fruit` | `{"fruit": "apple"}` (Modes: auto, apple, banana, mango, orange) |
| **Focus Control**| POST| `/set_focus` | `{"mode": "manual", "pos": 5.5}` or `{"mode": "auto"}` |

---

## 3. Key Features to Implement

### A. High-Quality Live View
*   Display the stream using `Image.network` or an MJPEG plugin.
*   Overlay a "Scanning Frame" or "Crosshair" to help users align the fruit.
*   Resolution is **720p (1280x720)**; ensure the widget handles aspect ratio scaling.

### B. Manual Focus Utility
*   **Toggle Switch:** Switch between "Autofocus" and "Manual".
*   **Focus Slider:** A smooth slider (0.0 to 10.0) that sends `LensPosition` updates to the Pi in real-time (debounce the API calls to 100ms).

### C. Local History (The "Fruit Diary")
*   **Persistence:** Use `sqflite` or `hive`. 
*   **Logic:** Every time a scan returns a confidence > 80%, save the entry locally.
*   **Data Fields:** Timestamp, Fruit Name, Confidence %, Fresh/Rotten status, and full Nutrient map.
*   **UI:** A dedicated tab showing a scrollable list of past scans with a "Delete All" option.

### D. Smart Notifications
*   The app should provide an in-app popup or snackbar if `is_rotten: true` is detected.
*   Display a warning icon (⚠️) next to any fruit identified as rotten.

---

## 4. UI/UX Design Goals
*   **Theme:** Modern Dark Mode (`Color(0xFF121212)`).
*   **Primary Accent:** Electric Blue (`#2196F3`).
*   **Alert Color:** Neon Red (`#FF1744`) for Rotten fruit.
*   **Success Color:** Emerald Green (`#00E676`) for Fresh/Healthy fruit.
*   **Animations:** Use `Hero` animations when transitioning from the stream view to a detailed nutrient report.

---

## 5. Technical Requirements (Flutter)
*   **State Management:** `Provider` or `Riverpod` recommended.
*   **Network Client:** `Dio` (highly recommended for handling streams and timeouts).
*   **Local DB:** `sqflite` (for SQL) or `Isar` (for NoSQL).
*   **Icon Set:** Material Design Icons + `FontAwesome` for nutrient-specific icons (Apple, Orange, etc.).

---

*Document Generated on: April 25, 2026*
*Target Hardware: Raspberry Pi 5 + Pi Camera Module 3 / Arducam AF*
