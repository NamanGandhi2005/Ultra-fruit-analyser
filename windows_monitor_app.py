import tkinter as tk
from tkinter import ttk
import cv2
import PIL.Image, PIL.ImageTk
import threading
import requests
import time
import json
import numpy as np

try:
    import customtkinter as ctk
    ctk.set_appearance_mode("Dark")
    ctk.set_default_color_theme("blue")
    BASE_CLASS = ctk.CTk
    FRAME_CLASS = ctk.CTkFrame
    BUTTON_CLASS = ctk.CTkButton
    LABEL_CLASS = ctk.CTkLabel
    SLIDER_CLASS = ctk.CTkSlider
except ImportError:
    BASE_CLASS = tk.Tk
    FRAME_CLASS = tk.Frame
    BUTTON_CLASS = tk.Button
    LABEL_CLASS = tk.Label
    SLIDER_CLASS = tk.Scale

PI_IP = "192.168.1.65"
PI_URL = f"http://{PI_IP}:5000"

class CameraStreamThread(threading.Thread):
    def __init__(self, url, label_widget):
        super().__init__()
        self.url = f"{url}/video_feed"
        self.label_widget = label_widget
        self.running = True
        self.daemon = True

    def run(self):
        while self.running:
            try:
                stream = requests.get(self.url, stream=True, timeout=5)
                bytes_data = bytes()
                for chunk in stream.iter_content(chunk_size=4096):
                    if not self.running: break
                    bytes_data += chunk
                    a = bytes_data.find(b'\xff\xd8')
                    b = bytes_data.find(b'\xff\xd9')
                    if a != -1 and b != -1:
                        jpg = bytes_data[a:b+2]
                        bytes_data = bytes_data[b+2:]
                        frame = cv2.imdecode(np.frombuffer(jpg, dtype=np.uint8), cv2.IMREAD_COLOR)
                        if frame is not None:
                            frame = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
                            # Adaptive resizing for high-quality display
                            h, w = frame.shape[:2]
                            target_h = 540
                            target_w = int(w * (target_h / h))
                            frame = cv2.resize(frame, (target_w, target_h), interpolation=cv2.INTER_AREA)
                            img = PIL.Image.fromarray(frame)
                            imgtk = PIL.ImageTk.PhotoImage(image=img)
                            self.label_widget.configure(image=imgtk, text="")
                            self.label_widget.image = imgtk
            except:
                time.sleep(2)

class FruitMonitorApp(BASE_CLASS):
    def __init__(self):
        super().__init__()
        self.title("Ultra Fruit Analyser Pro - Desktop Control")
        self.geometry("1280x800")

        self.grid_columnconfigure(1, weight=1)
        self.grid_rowconfigure(0, weight=1)

        # --- Sidebar ---
        self.sidebar = FRAME_CLASS(self, width=250, corner_radius=0)
        self.sidebar.grid(row=0, column=0, sticky="nsew", padx=10, pady=10)
        
        LABEL_CLASS(self.sidebar, text="FRUIT ANALYSER", font=("Roboto", 22, "bold")).pack(pady=20)

        # Control Group
        self.btn_scan = BUTTON_CLASS(self.sidebar, text="🚀 TRIGGER SCAN", command=self.trigger_scan, height=40)
        self.btn_scan.pack(pady=10, padx=20, fill="x")

        LABEL_CLASS(self.sidebar, text="Target Fruit Mode", font=("Roboto", 12)).pack(pady=(20, 0))
        self.fruit_var = tk.StringVar(value="auto")
        ctk.CTkOptionMenu(self.sidebar, values=["auto", "apple", "banana", "mango", "orange"], 
                         command=self.set_fruit_mode, variable=self.fruit_var).pack(pady=10, padx=20, fill="x")

        # Focus Control Group
        LABEL_CLASS(self.sidebar, text="Camera Focus", font=("Roboto", 14, "bold")).pack(pady=(30, 0))
        
        self.focus_mode_var = tk.StringVar(value="auto")
        self.focus_toggle = ctk.CTkSegmentedButton(self.sidebar, values=["auto", "manual"], 
                                                 command=self.set_focus_mode, variable=self.focus_mode_var)
        self.focus_toggle.pack(pady=10, padx=20, fill="x")

        LABEL_CLASS(self.sidebar, text="Manual Focus Distance", font=("Roboto", 11)).pack()
        self.focus_slider = SLIDER_CLASS(self.sidebar, from_=0, to=10, number_of_steps=100, command=self.on_focus_slide)
        self.focus_slider.pack(pady=10, padx=20, fill="x")
        self.focus_slider.set(0)

        # --- Main Content ---
        self.main_frame = FRAME_CLASS(self)
        self.main_frame.grid(row=0, column=1, sticky="nsew", padx=10, pady=10)

        self.video_label = LABEL_CLASS(self.main_frame, text="Waiting for Stream...", font=("Roboto", 16))
        self.video_label.pack(expand=True, fill="both", padx=10, pady=10)

        # Results Dashboard
        self.dash_frame = FRAME_CLASS(self.main_frame, height=200)
        self.dash_frame.pack(fill="x", side="bottom", padx=10, pady=10)
        
        self.status_label = LABEL_CLASS(self.dash_frame, text="System: Connected", font=("Roboto", 18, "bold"), text_color="green")
        self.status_label.pack(pady=10)

        self.nut_label = LABEL_CLASS(self.dash_frame, text="Place a fruit to begin analysis", justify="center", font=("Roboto", 13))
        self.nut_label.pack(pady=5)

        self.stream_thread = CameraStreamThread(PI_URL, self.video_label)
        self.stream_thread.start()
        self.update_loop()

    def set_focus_mode(self, mode):
        requests.post(f"{PI_URL}/set_focus", json={"mode": mode, "pos": self.focus_slider.get()})

    def on_focus_slide(self, val):
        if self.focus_mode_var.get() == "manual":
            requests.post(f"{PI_URL}/set_focus", json={"mode": "manual", "pos": float(val)})

    def trigger_scan(self):
        requests.post(f"{PI_URL}/trigger_scan")
        self.status_label.configure(text="Processing...", text_color="orange")

    def set_fruit_mode(self, val):
        requests.post(f"{PI_URL}/set_fruit", json={"fruit": val})

    def update_loop(self):
        try:
            r = requests.get(f"{PI_URL}/status", timeout=1)
            if r.status_code == 200:
                data = r.json()
                res = data.get("last_result")
                if res:
                    txt = f"{res['fruit']} Identified ({res['confidence']:.1%})"
                    color = "red" if res['is_rotten'] else "green"
                    if res['is_rotten']: txt += " - ROTTEN"
                    self.status_label.configure(text=txt, text_color=color)
                    
                    n = res.get('nutrients')
                    if n:
                        nut_txt = f"Variety: {res['name']} | Calories: {n.get('calories')} | Sugar: {n.get('sugar_g')}g | Vit C: {n.get('vitamin_c_mg')}mg"
                        self.nut_label.configure(text=nut_txt)
        except: pass
        self.after(2000, self.update_loop)

if __name__ == "__main__":
    app = FruitMonitorApp()
    app.mainloop()
