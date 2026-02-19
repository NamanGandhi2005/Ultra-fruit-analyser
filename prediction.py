import tkinter as tk
from tkinter import ttk, filedialog, messagebox
from PIL import Image, ImageTk
import os
import json
import smtplib
import hashlib
import requests
import threading
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart
from email.mime.image import MIMEImage
from datetime import datetime
import cv2
import numpy as np

# --- AI Libraries (PyTorch Only - TensorFlow removed) ---
import torch
import torch.nn as nn
from torchvision import models, transforms


# ----------------------------
# 1. USER AUTH SYSTEM
# ----------------------------
class UserAuth:
    def __init__(self, users_file='users.json'):
        self.users_file = users_file
        self.current_user = None
        self.load_users()

    def load_users(self):
        """Load users from JSON file"""
        try:
            if os.path.exists(self.users_file):
                with open(self.users_file, 'r') as f:
                    self.users = json.load(f)
            else:
                self.users = {}
                self.save_users()
        except Exception as e:
            print(f"Error loading users: {e}")
            self.users = {}

    def save_users(self):
        """Save users to JSON file"""
        try:
            with open(self.users_file, 'w') as f:
                json.dump(self.users, f, indent=4)
        except Exception as e:
            print(f"Error saving users: {e}")

    def hash_password(self, password):
        """Hash password using SHA-256"""
        return hashlib.sha256(password.encode()).hexdigest()

    def signup(self, username, password, email=""):
        """Register a new user"""
        if username in self.users:
            return False, "Username already exists"

        if len(username) < 3:
            return False, "Username must be at least 3 characters"

        if len(password) < 6:
            return False, "Password must be at least 6 characters"

        self.users[username] = {
            'password': self.hash_password(password),
            'email': email,
            'created_at': datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
            'analysis_count': 0
        }
        self.save_users()
        return True, "Signup successful!"

    def login(self, username, password):
        """Authenticate user"""
        if username not in self.users:
            return False, "Username not found"

        if self.users[username]['password'] != self.hash_password(password):
            return False, "Incorrect password"

        self.current_user = username
        return True, "Login successful!"

    def logout(self):
        """Logout current user"""
        self.current_user = None

    def get_user_stats(self):
        """Get current user statistics"""
        if self.current_user and self.current_user in self.users:
            return self.users[self.current_user]
        return None

    def increment_analysis_count(self):
        """Increment analysis count for current user"""
        if self.current_user and self.current_user in self.users:
            self.users[self.current_user]['analysis_count'] += 1
            self.save_users()


# ----------------------------
# 2. NOTIFICATION MANAGER
# ----------------------------
class NotificationManager:
    def __init__(self):
        self.telegram_config = self.load_telegram_config()
        self.email_config = self.load_email_config()

    def load_telegram_config(self):
        """Load Telegram configuration"""
        try:
            if os.path.exists('telegram_config.json'):
                with open('telegram_config.json', 'r') as f:
                    return json.load(f)
        except:
            pass
        return {'bot_token': '', 'chat_id': '', 'enabled': False}

    def load_email_config(self):
        """Load Email configuration"""
        try:
            if os.path.exists('email_config.json'):
                with open('email_config.json', 'r') as f:
                    return json.load(f)
        except:
            pass
        return {'smtp_server': '', 'smtp_port': 587, 'email': '', 'password': '', 'enabled': False}

    def save_telegram_config(self, bot_token, chat_id, enabled):
        """Save Telegram configuration"""
        self.telegram_config = {
            'bot_token': bot_token,
            'chat_id': chat_id,
            'enabled': enabled
        }
        with open('telegram_config.json', 'w') as f:
            json.dump(self.telegram_config, f, indent=4)

    def save_email_config(self, smtp_server, smtp_port, email, password, enabled):
        """Save Email configuration"""
        self.email_config = {
            'smtp_server': smtp_server,
            'smtp_port': smtp_port,
            'email': email,
            'password': password,
            'enabled': enabled
        }
        with open('email_config.json', 'w') as f:
            json.dump(self.email_config, f, indent=4)

    def send_telegram_alert(self, message, image_path=None):
        """Send Telegram notification"""
        if not self.telegram_config.get('enabled') or not self.telegram_config.get(
                'bot_token') or not self.telegram_config.get('chat_id'):
            return False, "Telegram not configured"

        try:
            bot_token = self.telegram_config['bot_token']
            chat_id = self.telegram_config['chat_id']

            if image_path and os.path.exists(image_path):
                # Send photo with caption
                url = f"https://api.telegram.org/bot{bot_token}/sendPhoto"
                with open(image_path, 'rb') as f:
                    files = {'photo': f}
                    data = {'chat_id': chat_id, 'caption': message}
                    response = requests.post(url, files=files, data=data)
            else:
                # Send text message
                url = f"https://api.telegram.org/bot{bot_token}/sendMessage"
                data = {'chat_id': chat_id, 'text': message}
                response = requests.post(url, data=data)

            if response.status_code == 200:
                return True, "Telegram alert sent successfully"
            else:
                return False, f"Telegram error: {response.text}"

        except Exception as e:
            return False, f"Telegram error: {str(e)}"

    def send_email_alert(self, subject, message, image_path=None):
        """Send Email notification"""
        if not self.email_config.get('enabled') or not self.email_config.get('email'):
            return False, "Email not configured"

        try:
            smtp_server = self.email_config['smtp_server']
            smtp_port = self.email_config['smtp_port']
            email = self.email_config['email']
            password = self.email_config['password']

            # Create message
            msg = MIMEMultipart()
            msg['From'] = email
            msg['To'] = email
            msg['Subject'] = subject

            # Add text message
            msg.attach(MIMEText(message, 'plain'))

            # Add image if provided
            if image_path and os.path.exists(image_path):
                with open(image_path, 'rb') as f:
                    img_data = f.read()
                image = MIMEImage(img_data, name=os.path.basename(image_path))
                msg.attach(image)

            # Send email
            server = smtplib.SMTP(smtp_server, smtp_port)
            server.starttls()
            server.login(email, password)
            server.send_message(msg)
            server.quit()

            return True, "Email alert sent successfully"

        except Exception as e:
            return False, f"Email error: {str(e)}"


# ----------------------------
# 3. FRUIT PREDICTOR (Smart Logic V6 - TTA Boost + Safety)
# ----------------------------
class FruitPredictor:
    def __init__(self, model_path='fruit_resnet_model.pth'):
        self.device = torch.device("cpu")
        dev_name = "CPU"
        if torch.cuda.is_available():
            self.device = torch.device("cuda")
            dev_name = f"NVIDIA CUDA ({torch.cuda.get_device_name(0)})"
        else:
            try:
                import torch_directml
                self.device = torch_directml.device()
                dev_name = "AMD/Intel GPU (DirectML)"
            except: pass
        
        print(f"🚀 AI Engine utilizing: {dev_name}")
        self.model = None
        self.class_names = []
        self.load_model(model_path)

        # Nutrient Database (Same as before)
        self.NUTRIENT_DB = {
            'banana': {
                1: {'name': 'Very Unripe', 'color': '#90EE90', 'rotten': False, 'sugar_g': 19, 'vitamin_c_mg': 0.2, 'fiber_g': 1.5, 'calories': 89, 'benefits': 'High in resistant starch'},
                2: {'name': 'Unripe', 'color': '#98FB98', 'rotten': False, 'sugar_g': 28, 'vitamin_c_mg': 0.2, 'fiber_g': 2.5, 'calories': 95, 'benefits': 'Prebiotic fiber source'},
                3: {'name': 'Slightly Ripe', 'color': '#ADFF2F', 'rotten': False, 'sugar_g': 52, 'vitamin_c_mg': 0.3, 'fiber_g': 2.0, 'calories': 105, 'benefits': 'Balanced starch/sugar'},
                4: {'name': 'Moderately Ripe', 'color': '#FFFF00', 'rotten': False, 'sugar_g': 183, 'vitamin_c_mg': 0.3, 'fiber_g': 3.0, 'calories': 110, 'benefits': 'Good energy source'},
                5: {'name': 'Ripe', 'color': '#FFD700', 'rotten': False, 'sugar_g': 272, 'vitamin_c_mg': 0.3, 'fiber_g': 1.2, 'calories': 115, 'benefits': 'Easy to digest'},
                6: {'name': 'Very Ripe', 'color': '#FFA500', 'rotten': False, 'sugar_g': 316, 'vitamin_c_mg': 0.3, 'fiber_g': 1.0, 'calories': 120, 'benefits': 'High antioxidants'},
                7: {'name': 'Fully Ripe', 'color': '#FF8C00', 'rotten': False, 'sugar_g': 323, 'vitamin_c_mg': 0.3, 'fiber_g': 0.8, 'calories': 125, 'benefits': 'Maximum sweetness'},
                8: {'name': 'Overripe', 'color': '#FF6347', 'rotten': False, 'sugar_g': 361, 'vitamin_c_mg': 0.3, 'fiber_g': 0.6, 'calories': 130, 'benefits': 'Great for baking'},
                9: {'name': 'Rotten', 'color': '#8B0000', 'rotten': True, 'sugar_g': 373, 'vitamin_c_mg': 0.1, 'fiber_g': 0.3, 'calories': 135, 'benefits': 'Do not consume'}
            },
            'apple': {
                1: {'name': 'Unripe', 'color': '#90EE90', 'rotten': False, 'sugar_g': 8, 'vitamin_c_mg': 5, 'fiber_g': 2.5, 'calories': 52, 'benefits': 'Firm and tart'},
                2: {'name': 'Ripe', 'color': '#ADFF2F', 'rotten': False, 'sugar_g': 12, 'vitamin_c_mg': 7, 'fiber_g': 3.0, 'calories': 58, 'benefits': 'Balanced flavor'},
                3: {'name': 'Rotten', 'color': '#8B0000', 'rotten': True, 'sugar_g': 18, 'vitamin_c_mg': 4, 'fiber_g': 1.5, 'calories': 65, 'benefits': 'Do not consume'}
            },
            'orange': {
                1: {'name': 'Very Unripe', 'color': '#90EE90', 'rotten': False, 'sugar_g': 6, 'vitamin_c_mg': 57, 'fiber_g': 2.0, 'calories': 45, 'benefits': 'High citric acid'},
                2: {'name': 'Unripe', 'color': '#98FB98', 'rotten': False, 'sugar_g': 7, 'vitamin_c_mg': 52, 'fiber_g': 2.2, 'calories': 50, 'benefits': 'Tart flavor'},
                3: {'name': 'Ripe', 'color': '#FFA500', 'rotten': False, 'sugar_g': 9, 'vitamin_c_mg': 47, 'fiber_g': 2.5, 'calories': 60, 'benefits': 'Sweet and tangy'},
                4: {'name': 'Very Ripe', 'color': '#FF8C00', 'rotten': False, 'sugar_g': 8, 'vitamin_c_mg': 48, 'fiber_g': 2.3, 'calories': 65, 'benefits': 'Max juiciness'},
                5: {'name': 'Rotten', 'color': '#8B0000', 'rotten': True, 'sugar_g': 8, 'vitamin_c_mg': 50, 'fiber_g': 1.5, 'calories': 70, 'benefits': 'Do not consume'}
            },
            'mango': {
                1: {'name': 'Very Unripe', 'color': '#90EE90', 'rotten': False, 'sugar_g': 5, 'vitamin_c_mg': 20, 'fiber_g': 3.0, 'calories': 50, 'benefits': 'Crunchy, for salads'},
                2: {'name': 'Unripe', 'color': '#98FB98', 'rotten': False, 'sugar_g': 10, 'vitamin_c_mg': 30, 'fiber_g': 2.5, 'calories': 65, 'benefits': 'Firm texture'},
                3: {'name': 'Ripe', 'color': '#FFD700', 'rotten': False, 'sugar_g': 18, 'vitamin_c_mg': 45, 'fiber_g': 2.0, 'calories': 80, 'benefits': 'Sweet and juicy'},
                4: {'name': 'Rotten', 'color': '#8B0000', 'rotten': True, 'sugar_g': 22, 'vitamin_c_mg': 25, 'fiber_g': 1.0, 'calories': 90, 'benefits': 'Do not consume'}
            }
        }

    def load_model(self, model_path):
        if not os.path.exists(model_path):
            raise FileNotFoundError(f"Model file {model_path} not found.")
        try:
            print(f"🔄 Loading PyTorch model from {model_path}...")
            checkpoint = torch.load(model_path, map_location="cpu", weights_only=False)
            self.class_names = checkpoint['class_names']
            num_classes = checkpoint['num_classes']
            self.model = models.resnet18(weights=None)
            self.model.fc = nn.Linear(self.model.fc.in_features, num_classes)
            self.model.load_state_dict(checkpoint['model_state_dict'])
            self.model.to(self.device)
            self.model.eval()
            print(f"✅ Model loaded. Classes: {self.class_names}")
        except Exception as e:
            print(f"❌ Failed to load model: {e}")
            raise

    def is_rotten(self, image_path, brown_threshold=0.40, dark_threshold=0.60):
        try:
            img = cv2.imread(image_path)
            if img is None: return False
            img_hsv = cv2.cvtColor(img, cv2.COLOR_BGR2HSV)
            img_lab = cv2.cvtColor(img, cv2.COLOR_BGR2LAB)
            h, s, v = cv2.split(img_hsv)
            l, a, b = cv2.split(img_lab)

            brown_mask_hsv = ((h >= 5) & (h <= 30) & (s >= 80) & (v <= 150))
            brown_mask_lab = ((a >= 130) & (a <= 160) & (b >= 130) & (b <= 160))
            brown_ratio = max(np.sum(brown_mask_hsv), np.sum(brown_mask_lab)) / (img.shape[0] * img.shape[1])
            dark_mask = (v < 40)
            dark_ratio = np.sum(dark_mask) / (img.shape[0] * img.shape[1])
            mold_mask = ((h >= 75) & (h <= 95) & (s >= 60) & (v >= 60))
            mold_ratio = np.sum(mold_mask) / (img.shape[0] * img.shape[1])

            is_rotten = (brown_ratio >= brown_threshold) or (dark_ratio >= dark_threshold) or (mold_ratio >= 0.05)
            print(f"CV Debug -> Brown: {brown_ratio:.2f}, Dark: {dark_ratio:.2f}, Mold: {mold_ratio:.2f}")
            return is_rotten
        except: return False

    def parse_label(self, label_str):
        parts = label_str.split('_stage_')
        if len(parts) == 2: return parts[0], int(parts[1])
        return None, None

    def predict(self, image_path, selected_fruit=None):
        if not self.model: return None
        
        # --- TTA (Test-Time Augmentation) Setup ---
        # 1. Standard Transform
        base_transform = transforms.Compose([
            transforms.Resize((224, 224)),
            transforms.ToTensor(),
            transforms.Normalize([0.485, 0.456, 0.406], [0.229, 0.224, 0.225])
        ])
        
        # 2. Flipped Transform (The Boost!)
        flip_transform = transforms.Compose([
            transforms.Resize((224, 224)),
            transforms.RandomHorizontalFlip(p=1.0), # Force flip
            transforms.ToTensor(),
            transforms.Normalize([0.485, 0.456, 0.406], [0.229, 0.224, 0.225])
        ])

        try:
            raw_image = Image.open(image_path).convert('RGB')
            
            # Create a batch of 2 images: [Original, Flipped]
            img_tensors = torch.stack([
                base_transform(raw_image),
                flip_transform(raw_image)
            ]).to(self.device)

            with torch.no_grad():
                outputs = self.model(img_tensors)
                probs = torch.nn.functional.softmax(outputs, dim=1)
                
                # --- TTA AVERAGING ---
                # Average the probabilities of Original + Flipped
                avg_probs = torch.mean(probs, dim=0) 
                
                # Manual filtering (on averaged probs)
                if selected_fruit and selected_fruit != 'auto':
                    mask = torch.tensor([1.0 if selected_fruit in c else 0.0 for c in self.class_names], device=self.device)
                    if mask.sum() > 0:
                        avg_probs = avg_probs * mask
                        if avg_probs.sum() > 0: avg_probs = avg_probs / avg_probs.sum()

                # Rank predictions from averaged results
                all_probs, all_idxs = torch.sort(avg_probs, descending=True)
                
                # Top 1
                idx_1 = all_idxs[0].item()
                label_1 = self.class_names[idx_1]
                conf_1 = all_probs[0].item()

            print(f"🤖 AI Top 1 (TTA): {label_1} ({conf_1:.2%})")
            
            # CV Check
            is_rotten_cv = self.is_rotten(image_path)
            print(f"👁️ CV Inspection: {'Rotten' if is_rotten_cv else 'Clean'}")

            final_label = label_1
            final_conf = conf_1
            fruit, stage = self.parse_label(final_label)
            if not fruit: fruit, stage = final_label.split('_')[0], 1

            # Check if AI says rotten
            db_says_rotten = False
            if fruit in self.NUTRIENT_DB:
                stage_info = self.NUTRIENT_DB[fruit].get(stage, {})
                db_says_rotten = stage_info.get('rotten', False)

            # --- SMART CORRECTION V6 (Safety Ratio + TTA) ---
            # If AI says ROTTEN, but CV says CLEAN...
            if db_says_rotten and not is_rotten_cv and conf_1 < 0.95:
                print("🤔 Conflict: AI says Rotten, CV says Clean. Checking safety ratios...")
                
                # Dynamic Thresholds
                required_fresh_conf = 0.15 if conf_1 < 0.60 else 0.30
                
                found_better = False
                for i in range(1, len(self.class_names)): 
                    idx_curr = all_idxs[i].item()
                    label_curr = self.class_names[idx_curr]
                    conf_curr = all_probs[i].item()
                    f_curr, s_curr = self.parse_label(label_curr)
                    
                    if f_curr == fruit:
                        info_curr = self.NUTRIENT_DB[fruit].get(s_curr, {})
                        if not info_curr.get('rotten', False):
                            # 1. Must meet absolute threshold
                            if conf_curr > required_fresh_conf:
                                # 2. Must be close to the Rotten score (Safety Check)
                                if conf_curr > (conf_1 * 0.7):
                                    print(f"✨ SMART FIX: Switched from {label_1} to {label_curr} ({conf_curr:.1%})")
                                    final_label = label_curr
                                    final_conf = conf_curr
                                    stage = s_curr
                                    db_says_rotten = False
                                    found_better = True
                                    break
                                else:
                                    print(f"🔒 Blocked Switch: Fresh {label_curr} ({conf_curr:.1%}) too weak vs Rotten ({conf_1:.1%}). Ratio < 0.7.")
                            else:
                                print(f"⚠️ Candidate {label_curr} ({conf_curr:.1%}) too weak (Need >{required_fresh_conf:.0%}).")

            is_rotten_final = db_says_rotten or is_rotten_cv
            if not db_says_rotten and not is_rotten_cv: is_rotten_final = False

            result = {
                'fruit': fruit, 'stage': stage,
                'stage_name': self.NUTRIENT_DB.get(fruit, {}).get(stage, {}).get('name', 'Unknown'),
                'label': final_label, 'confidence': float(final_conf),
                'is_rotten': is_rotten_final,
                'nutrients': None,
                'color': self.NUTRIENT_DB.get(fruit, {}).get(stage, {}).get('color', '#3498db'),
                'message': '🚫 ROTTEN DETECTED' if is_rotten_final else '✅ FRESH FRUIT',
                'timestamp': datetime.now().strftime("%H:%M:%S"),
                'cv_rotten_detected': is_rotten_cv
            }
            if not is_rotten_final and fruit in self.NUTRIENT_DB and stage in self.NUTRIENT_DB[fruit]:
                result['nutrients'] = self.NUTRIENT_DB[fruit][stage]
            return result

        except Exception as e:
            print(f"Prediction error: {e}")
            raise
# ----------------------------
# 4. GUI CLASSES (Login, Settings, Main)
# ----------------------------
class LoginFrame:
    def __init__(self, root, auth_system, on_login_success):
        self.root = root
        self.auth = auth_system
        self.on_login_success = on_login_success
        self.setup_login_gui()

    def setup_login_gui(self):
        for widget in self.root.winfo_children():
            widget.destroy()

        self.root.configure(bg='#2c3e50')
        main_frame = tk.Frame(self.root, bg='#2c3e50')
        main_frame.pack(expand=True, fill=tk.BOTH, padx=50, pady=50)

        title_label = tk.Label(main_frame, text="🍎 Fruit Analyzer Pro", font=('Arial', 28, 'bold'), bg='#2c3e50', fg='#ecf0f1')
        title_label.pack(pady=(0, 10))
        subtitle_label = tk.Label(main_frame, text="AI-Powered Quality Assessment", font=('Arial', 14), bg='#2c3e50', fg='#bdc3c7')
        subtitle_label.pack(pady=(0, 40))

        login_container = tk.Frame(main_frame, bg='#34495e', relief=tk.RAISED, bd=2)
        login_container.pack(expand=True, fill=tk.BOTH)

        self.notebook = ttk.Notebook(login_container)
        self.notebook.pack(expand=True, fill=tk.BOTH, padx=20, pady=20)

        self.login_frame = tk.Frame(self.notebook, bg='#34495e')
        self.notebook.add(self.login_frame, text='🔐 Login')

        self.signup_frame = tk.Frame(self.notebook, bg='#34495e')
        self.notebook.add(self.signup_frame, text='📝 Sign Up')

        self.setup_login_tab()
        self.setup_signup_tab()

    def setup_login_tab(self):
        tk.Label(self.login_frame, text="Username:", font=('Arial', 12, 'bold'), bg='#34495e', fg='#ecf0f1').pack(pady=(20, 5))
        self.login_username = tk.Entry(self.login_frame, font=('Arial', 12), width=25)
        self.login_username.pack(pady=5, padx=50)
        self.login_username.bind('<Return>', lambda e: self.login())

        tk.Label(self.login_frame, text="Password:", font=('Arial', 12, 'bold'), bg='#34495e', fg='#ecf0f1').pack(pady=(15, 5))
        self.login_password = tk.Entry(self.login_frame, font=('Arial', 12), width=25, show='•')
        self.login_password.pack(pady=5, padx=50)
        self.login_password.bind('<Return>', lambda e: self.login())

        login_btn = tk.Button(self.login_frame, text="🚀 Login", font=('Arial', 14, 'bold'), bg='#27ae60', fg='white', padx=30, pady=10, command=self.login)
        login_btn.pack(pady=30)
        
        self.login_status = tk.Label(self.login_frame, text="", font=('Arial', 10), bg='#34495e', fg='#e74c3c')
        self.login_status.pack(pady=10)

    def setup_signup_tab(self):
        tk.Label(self.signup_frame, text="Username:", font=('Arial', 12, 'bold'), bg='#34495e', fg='#ecf0f1').pack(pady=(20, 5))
        self.signup_username = tk.Entry(self.signup_frame, font=('Arial', 12), width=25)
        self.signup_username.pack(pady=5, padx=50)

        tk.Label(self.signup_frame, text="Email (optional):", font=('Arial', 12, 'bold'), bg='#34495e', fg='#ecf0f1').pack(pady=(15, 5))
        self.signup_email = tk.Entry(self.signup_frame, font=('Arial', 12), width=25)
        self.signup_email.pack(pady=5, padx=50)

        tk.Label(self.signup_frame, text="Password:", font=('Arial', 12, 'bold'), bg='#34495e', fg='#ecf0f1').pack(pady=(15, 5))
        self.signup_password = tk.Entry(self.signup_frame, font=('Arial', 12), width=25, show='•')
        self.signup_password.pack(pady=5, padx=50)

        tk.Label(self.signup_frame, text="Confirm Password:", font=('Arial', 12, 'bold'), bg='#34495e', fg='#ecf0f1').pack(pady=(15, 5))
        self.signup_confirm = tk.Entry(self.signup_frame, font=('Arial', 12), width=25, show='•')
        self.signup_confirm.pack(pady=5, padx=50)

        signup_btn = tk.Button(self.signup_frame, text="✨ Create Account", font=('Arial', 14, 'bold'), bg='#3498db', fg='white', padx=20, pady=10, command=self.signup)
        signup_btn.pack(pady=30)

        self.signup_status = tk.Label(self.signup_frame, text="", font=('Arial', 10), bg='#34495e', fg='#e74c3c')
        self.signup_status.pack(pady=10)

    def login(self):
        username = self.login_username.get().strip()
        password = self.login_password.get()
        if not username or not password:
            self.login_status.config(text="❌ Please fill in all fields")
            return
        success, message = self.auth.login(username, password)
        if success:
            self.login_status.config(text=f"✅ {message}", fg='#27ae60')
            self.root.after(1000, self.on_login_success)
        else:
            self.login_status.config(text=f"❌ {message}")

    def signup(self):
        username = self.signup_username.get().strip()
        email = self.signup_email.get().strip()
        password = self.signup_password.get()
        confirm = self.signup_confirm.get()
        if not username or not password:
            self.signup_status.config(text="❌ Please fill in all required fields")
            return
        if password != confirm:
            self.signup_status.config(text="❌ Passwords do not match")
            return
        success, message = self.auth.signup(username, password, email)
        if success:
            self.signup_status.config(text=f"✅ {message}", fg='#27ae60')
            self.root.after(1500, lambda: self.notebook.select(0))
        else:
            self.signup_status.config(text=f"❌ {message}")


class NotificationSettingsWindow:
    def __init__(self, parent, notification_manager):
        self.parent = parent
        self.notification_manager = notification_manager
        self.setup_window()

    def setup_window(self):
        self.window = tk.Toplevel(self.parent)
        self.window.title("🔔 Notification Settings")
        self.window.geometry("800x900")
        self.window.configure(bg='#2c3e50')
        self.window.resizable(False, False)
        self.window.transient(self.parent)
        self.window.grab_set()

        main_frame = tk.Frame(self.window, bg='#2c3e50')
        main_frame.pack(fill=tk.BOTH, expand=True, padx=20, pady=20)

        tk.Label(main_frame, text="🔔 Notification Settings", font=('Arial', 18, 'bold'), bg='#2c3e50', fg='#ecf0f1').pack(pady=(0, 20))

        # Telegram
        telegram_frame = tk.LabelFrame(main_frame, text="📱 Telegram Settings", font=('Arial', 12, 'bold'), bg='#34495e', fg='#ecf0f1')
        telegram_frame.pack(fill=tk.X, pady=(0, 15))
        
        tk.Label(telegram_frame, text="Bot Token:", bg='#34495e', fg='#ecf0f1').pack(anchor=tk.W, pady=(10, 5))
        self.telegram_token = tk.Entry(telegram_frame, width=50, show='•')
        self.telegram_token.insert(0, self.notification_manager.telegram_config.get('bot_token', ''))
        self.telegram_token.pack(fill=tk.X, padx=10, pady=5)
        
        tk.Label(telegram_frame, text="Chat ID:", bg='#34495e', fg='#ecf0f1').pack(anchor=tk.W, pady=(10, 5))
        self.telegram_chat_id = tk.Entry(telegram_frame, width=50)
        self.telegram_chat_id.insert(0, self.notification_manager.telegram_config.get('chat_id', ''))
        self.telegram_chat_id.pack(fill=tk.X, padx=10, pady=5)
        
        self.telegram_enabled = tk.BooleanVar(value=self.notification_manager.telegram_config.get('enabled', False))
        tk.Checkbutton(telegram_frame, text="Enable Telegram", variable=self.telegram_enabled, bg='#34495e', fg='#ecf0f1', selectcolor='#2c3e50').pack(anchor=tk.W, pady=10)

        # Email
        email_frame = tk.LabelFrame(main_frame, text="📧 Email Settings", font=('Arial', 12, 'bold'), bg='#34495e', fg='#ecf0f1')
        email_frame.pack(fill=tk.X, pady=(0, 15))
        
        tk.Label(email_frame, text="SMTP Server:", bg='#34495e', fg='#ecf0f1').pack(anchor=tk.W, pady=(10, 5))
        self.smtp_server = tk.Entry(email_frame, width=50)
        self.smtp_server.insert(0, self.notification_manager.email_config.get('smtp_server', ''))
        self.smtp_server.pack(fill=tk.X, padx=10, pady=5)
        
        tk.Label(email_frame, text="SMTP Port:", bg='#34495e', fg='#ecf0f1').pack(anchor=tk.W, pady=(10, 5))
        self.smtp_port = tk.Entry(email_frame, width=50)
        self.smtp_port.insert(0, str(self.notification_manager.email_config.get('smtp_port', 587)))
        self.smtp_port.pack(fill=tk.X, padx=10, pady=5)
        
        tk.Label(email_frame, text="Email Address:", bg='#34495e', fg='#ecf0f1').pack(anchor=tk.W, pady=(10, 5))
        self.email_addr = tk.Entry(email_frame, width=50)
        self.email_addr.insert(0, self.notification_manager.email_config.get('email', ''))
        self.email_addr.pack(fill=tk.X, padx=10, pady=5)
        
        tk.Label(email_frame, text="Email Password:", bg='#34495e', fg='#ecf0f1').pack(anchor=tk.W, pady=(10, 5))
        self.email_password = tk.Entry(email_frame, width=50, show='•')
        self.email_password.insert(0, self.notification_manager.email_config.get('password', ''))
        self.email_password.pack(fill=tk.X, padx=10, pady=5)
        
        self.email_enabled = tk.BooleanVar(value=self.notification_manager.email_config.get('enabled', False))
        tk.Checkbutton(email_frame, text="Enable Email", variable=self.email_enabled, bg='#34495e', fg='#ecf0f1', selectcolor='#2c3e50').pack(anchor=tk.W, pady=10)

        # Buttons
        button_frame = tk.Frame(main_frame, bg='#2c3e50')
        button_frame.pack(fill=tk.X, pady=20)
        tk.Button(button_frame, text="💾 Save", bg='#27ae60', fg='white', padx=20, pady=10, command=self.save_settings).pack(side=tk.LEFT, padx=5)
        tk.Button(button_frame, text="🧪 Test", bg='#3498db', fg='white', padx=20, pady=10, command=self.test_notifications).pack(side=tk.LEFT, padx=5)
        tk.Button(button_frame, text="❌ Close", bg='#e74c3c', fg='white', padx=20, pady=10, command=self.window.destroy).pack(side=tk.LEFT, padx=5)

    def save_settings(self):
        try:
            self.notification_manager.save_telegram_config(self.telegram_token.get().strip(), self.telegram_chat_id.get().strip(), self.telegram_enabled.get())
            self.notification_manager.save_email_config(self.smtp_server.get().strip(), int(self.smtp_port.get().strip()), self.email_addr.get().strip(), self.email_password.get().strip(), self.email_enabled.get())
            messagebox.showinfo("Success", "Settings saved!")
        except Exception as e:
            messagebox.showerror("Error", f"Failed to save: {e}")

    def test_notifications(self):
        test_msg = "🧪 Test Notification from Fruit Analyzer"
        if self.telegram_enabled.get():
            success, msg = self.notification_manager.send_telegram_alert(test_msg)
            if success: messagebox.showinfo("Telegram", "Sent!")
            else: messagebox.showerror("Telegram Error", msg)
        if self.email_enabled.get():
            success, msg = self.notification_manager.send_email_alert("Test", test_msg)
            if success: messagebox.showinfo("Email", "Sent!")
            else: messagebox.showerror("Email Error", msg)


class UltraFruitGUI:
    def __init__(self, root, auth_system, on_logout_callback):
        self.root = root
        self.auth = auth_system
        self.on_logout_callback = on_logout_callback
        self.notification_manager = NotificationManager()
        self.root.title("🍎🍊🥭 Ultra Fruit Ripeness Analyzer")
        self.root.geometry("1200x800")
        self.root.configure(bg='#2c3e50')

        try:
            # UPDATED: Load .pth model via PyTorch Predictor
            self.predictor = FruitPredictor('fruit_resnet_model.pth')
            self.model_loaded = True
        except Exception as e:
            messagebox.showerror("Error", f"Failed to load model: {e}")
            self.model_loaded = False
            return

        self.camera_active = False
        self.cap = None
        self.current_camera_frame = None
        self.current_image = None
        self.processing = False
        self.selected_fruit = 'auto'
        self.history = []
        self.setup_gui()

    def setup_gui(self):
        for widget in self.root.winfo_children():
            widget.destroy()

        style = ttk.Style()
        style.theme_use('clam')
        style.configure('TButton', font=('Arial', 10))
        style.configure('TScrollbar', background='#34495e')
        style.configure('TCombobox', fieldbackground='white', background='white')

        main_container = tk.Frame(self.root, bg='#2c3e50')
        main_container.pack(fill=tk.BOTH, expand=True, padx=20, pady=20)

        # Header
        header_frame = tk.Frame(main_container, bg='#2c3e50')
        header_frame.pack(fill=tk.X, pady=(0, 20))
        
        title_frame = tk.Frame(header_frame, bg='#2c3e50')
        title_frame.pack(side=tk.LEFT)
        tk.Label(title_frame, text="🍎🍊🥭 ULTRA FRUIT RIPENESS ANALYZER", font=('Arial', 20, 'bold'), bg='#2c3e50', fg='#ecf0f1').pack(anchor=tk.W)
        tk.Label(title_frame, text="AI-Powered Fruit Quality Assessment (ResNet-18)", font=('Arial', 10), bg='#2c3e50', fg='#bdc3c7').pack(anchor=tk.W)

        user_frame = tk.Frame(header_frame, bg='#2c3e50')
        user_frame.pack(side=tk.RIGHT)
        
        user_stats = self.auth.get_user_stats()
        if user_stats:
            tk.Label(user_frame, text=f"👤 {self.auth.current_user} | 📊 Analyses: {user_stats.get('analysis_count', 0)}", font=('Arial', 10), bg='#2c3e50', fg='#ecf0f1').pack(side=tk.LEFT, padx=(0, 10))
            
        tk.Button(user_frame, text="🔔 Notifications", font=('Arial', 10), bg='#9b59b6', fg='white', padx=10, pady=5, command=self.show_notification_settings).pack(side=tk.LEFT, padx=(0, 10))
        tk.Button(user_frame, text="🚪 Logout", font=('Arial', 10), bg='#e74c3c', fg='white', padx=15, pady=5, command=self.logout).pack(side=tk.LEFT)

        # Content
        content_frame = tk.Frame(main_container, bg='#34495e')
        content_frame.pack(fill=tk.BOTH, expand=True)

        # Left Panel
        left_panel = tk.Frame(content_frame, bg='#34495e')
        left_panel.pack(side=tk.LEFT, fill=tk.BOTH, expand=True, padx=(0, 10))

        selection_frame = tk.Frame(left_panel, bg='#34495e')
        selection_frame.pack(fill=tk.X, pady=(0, 15))
        tk.Label(selection_frame, text="Select Fruit Type:", font=('Arial', 11, 'bold'), bg='#34495e', fg='#ecf0f1').pack(side=tk.LEFT, padx=(0, 10))
        
        self.fruit_var = tk.StringVar(value='banana')
        fruit_dropdown = ttk.Combobox(selection_frame, textvariable=self.fruit_var, values=[ 'banana', 'orange', 'mango', 'apple'], state='readonly', font=('Arial', 11), width=15)
        fruit_dropdown.pack(side=tk.LEFT)
        fruit_dropdown.bind('<<ComboboxSelected>>', self.on_fruit_selected)

        image_container = tk.Frame(left_panel, bg='#1a252f', relief=tk.RAISED, bd=2)
        image_container.pack(fill=tk.BOTH, expand=True, pady=(0, 15))
        self.image_label = tk.Label(image_container, text="📷 No Image Selected", bg='#1a252f', fg='#7f8c8d', font=('Arial', 14), justify=tk.CENTER)
        self.image_label.pack(expand=True, fill=tk.BOTH, padx=20, pady=20)

        control_frame = tk.Frame(left_panel, bg='#34495e')
        control_frame.pack(fill=tk.X, pady=10)
        
        btn_config = {'font': ('Arial', 11), 'padx': 20, 'pady': 12, 'bd': 0, 'relief': tk.RAISED}
        self.browse_btn = tk.Button(control_frame, text="📁 BROWSE", command=self.browse_image, bg='#3498db', fg='white', **btn_config)
        self.browse_btn.pack(side=tk.LEFT, padx=5)
        
        self.camera_btn = tk.Button(control_frame, text="📷 START CAMERA", command=self.toggle_camera, bg='#e74c3c', fg='white', **btn_config)
        self.camera_btn.pack(side=tk.LEFT, padx=5)
        
        self.predict_btn = tk.Button(control_frame, text="🔍 ANALYZE", command=self.predict_image, bg='#27ae60', fg='white', **btn_config)
        self.predict_btn.pack(side=tk.LEFT, padx=5)
        
        self.clear_btn = tk.Button(control_frame, text="🗑️ CLEAR", command=self.clear_all, bg='#95a5a6', fg='white', **btn_config)
        self.clear_btn.pack(side=tk.LEFT, padx=5)

        # Right Panel
        right_panel = tk.Frame(content_frame, bg='#34495e')
        right_panel.pack(side=tk.RIGHT, fill=tk.BOTH, expand=True)
        
        tk.Label(right_panel, text="📊 ANALYSIS RESULTS", font=('Arial', 16, 'bold'), bg='#1a252f', fg='#ecf0f1').pack(fill=tk.X, pady=(0, 10))

        results_container = tk.Frame(right_panel, bg='#2c3e50')
        results_container.pack(fill=tk.BOTH, expand=True)
        
        self.results_canvas = tk.Canvas(results_container, bg='#2c3e50', highlightthickness=0)
        scrollbar = ttk.Scrollbar(results_container, orient="vertical", command=self.results_canvas.yview)
        self.scrollable_frame = tk.Frame(self.results_canvas, bg='#2c3e50')
        self.scrollable_frame.bind("<Configure>", lambda e: self.results_canvas.configure(scrollregion=self.results_canvas.bbox("all")))
        self.results_canvas.create_window((0, 0), window=self.scrollable_frame, anchor="nw")
        self.results_canvas.configure(yscrollcommand=scrollbar.set)
        self.results_canvas.pack(side="left", fill="both", expand=True)
        scrollbar.pack(side="right", fill="y")

        self.status_var = tk.StringVar(value=f"🟢 Ready - Welcome {self.auth.current_user}!")
        tk.Label(self.root, textvariable=self.status_var, relief=tk.SUNKEN, anchor=tk.W, bg='#1a252f', fg='#ecf0f1', font=('Arial', 10)).pack(side=tk.BOTTOM, fill=tk.X)
        self.results_canvas.bind("<MouseWheel>", lambda e: self.results_canvas.yview_scroll(int(-1 * (e.delta / 120)), "units"))

    def show_notification_settings(self):
        NotificationSettingsWindow(self.root, self.notification_manager)

    def on_fruit_selected(self, event):
        self.selected_fruit = self.fruit_var.get()
        self.status_var.set(f"🟡 Detection Mode: {self.selected_fruit.title()}")

    def browse_image(self):
        if self.processing: return
        file_path = filedialog.askopenfilename(title="Select Fruit Image", filetypes=[("Image files", "*.jpg *.jpeg *.png *.bmp *.webp")])
        if file_path:
            self.display_image(file_path)
            self.current_image_path = file_path
            self.status_var.set(f"📁 Loaded: {os.path.basename(file_path)}")

    def display_image(self, image_path):
        try:
            image = Image.open(image_path)
            image.thumbnail((400, 400), Image.Resampling.LANCZOS)
            photo = ImageTk.PhotoImage(image)
            self.image_label.configure(image=photo, text="")
            self.image_label.image = photo
        except Exception as e:
            messagebox.showerror("Error", str(e))

    def toggle_camera(self):
        if self.processing: return
        if not self.camera_active: self.start_camera()
        else: self.stop_camera()

    def start_camera(self):
        self.cap = cv2.VideoCapture(1)
        if not self.cap.isOpened():
            messagebox.showerror("Error", "Camera not accessible")
            return
        self.camera_active = True
        self.camera_btn.config(text="📷 STOP CAMERA", bg='#c0392b')
        self.update_camera()

    def stop_camera(self):
        self.camera_active = False
        if self.cap: self.cap.release()
        self.camera_btn.config(text="📷 START CAMERA", bg='#e74c3c')
        self.image_label.config(image='', text="📷 No Image Selected")

    def update_camera(self):
        if self.camera_active and self.cap:
            ret, frame = self.cap.read()
            if ret:
                rgb_frame = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
                image = Image.fromarray(rgb_frame)
                image.thumbnail((400, 400), Image.Resampling.LANCZOS)
                photo = ImageTk.PhotoImage(image)
                self.image_label.configure(image=photo)
                self.image_label.image = photo
                self.current_camera_frame = frame
            self.root.after(10, self.update_camera)

    def capture_camera_image(self):
        if hasattr(self, 'current_camera_frame'):
            temp_path = "temp_capture.jpg"
            cv2.imwrite(temp_path, self.current_camera_frame)
            return temp_path
        return None

    def predict_image(self):
        if not hasattr(self, 'current_image_path') and not self.camera_active:
            messagebox.showwarning("Warning", "Select image or start camera")
            return
        if self.processing: return
        self.processing = True
        self.status_var.set("🔍 Analyzing...")
        self.predict_btn.config(state=tk.DISABLED, bg='#7f8c8d')
        
        thread = threading.Thread(target=self._predict_thread)
        thread.daemon = True
        thread.start()

    def _predict_thread(self):
        try:
            if self.camera_active:
                image_path = self.capture_camera_image()
            else:
                image_path = self.current_image_path

            result = self.predictor.predict(image_path, self.selected_fruit)
            self.history.append(result)

            if result['is_rotten']:
                self.send_rotten_notifications(result, image_path)

            self.root.after(0, lambda: self._prediction_done(True, result))
        except Exception as e:
            self.root.after(0, lambda: self._prediction_done(False, str(e)))

    def send_rotten_notifications(self, result, image_path):
        msg = f"🚨 ROTTEN ALERT!\nFruit: {result['fruit']}\nConf: {result['confidence']:.2%}"
        self.notification_manager.send_telegram_alert(msg, image_path)
        self.notification_manager.send_email_alert("Rotten Detected", msg, image_path)

    def _prediction_done(self, success, result):
        self.processing = False
        self.predict_btn.config(state=tk.NORMAL, bg='#27ae60')
        if success:
            self.display_results(result)
            self.auth.increment_analysis_count()
            self.status_var.set(f"✅ Done - {result['message']}")
        else:
            self.status_var.set("❌ Failed")
            messagebox.showerror("Error", str(result))

    def display_results(self, result):
        for widget in self.scrollable_frame.winfo_children(): widget.destroy()
        
        bg_color = '#e74c3c' if result['is_rotten'] else result.get('color', '#3498db')
        card = tk.Frame(self.scrollable_frame, bg=bg_color, relief=tk.RAISED, bd=2)
        card.pack(fill=tk.X, padx=10, pady=10)
        
        # Header
        header = f"{'🚫' if result['is_rotten'] else '✅'} {result['fruit'].upper()}"
        tk.Label(card, text=header, font=('Arial', 16, 'bold'), bg=bg_color, fg='black').pack(anchor=tk.W, padx=15, pady=15)
        
        # Details
        det_frame = tk.Frame(card, bg=bg_color)
        det_frame.pack(fill=tk.X, padx=15, pady=5)
        tk.Label(det_frame, text=f"Stage: {result['stage']} ({result['stage_name']})", font=('Arial', 12), bg=bg_color, fg='black').pack(anchor=tk.W)
        tk.Label(det_frame, text=f"Confidence: {result['confidence']:.1%}", font=('Arial', 12), bg=bg_color, fg='black').pack(anchor=tk.W)

        # Bar
        bar_frame = tk.Frame(card, bg=bg_color)
        bar_frame.pack(fill=tk.X, padx=15, pady=5)
        prog = ttk.Progressbar(bar_frame, orient="horizontal", length=200, mode="determinate")
        prog['value'] = result['confidence'] * 100
        prog.pack(fill=tk.X)

        if result['is_rotten']:
            warn_bg = '#8B0000'
            warn_f = tk.Frame(card, bg=warn_bg)
            warn_f.pack(fill=tk.X, padx=10, pady=10)
            msg = "⚠️ DO NOT CONSUME. \nRotten fruit detected."
            tk.Label(warn_f, text=msg, font=('Arial', 12, 'bold'), bg=warn_bg, fg='white').pack(padx=10, pady=10)
        elif result['nutrients']:
            nut_f = tk.Frame(card, bg='#ecf0f1')
            nut_f.pack(fill=tk.X, padx=10, pady=10)
            tk.Label(nut_f, text="📊 Nutrition (per 100g)", font=('Arial', 12, 'bold'), bg='#ecf0f1', fg='black').pack(anchor=tk.W)
            
            n = result['nutrients']
            stats = [
                f"Sugar: {n['sugar_g']}g", 
                f"Vit C: {n['vitamin_c_mg']}mg",
                f"Fiber: {n['fiber_g']}g",
                f"Cal: {n['calories']}"
            ]
            for s in stats:
                tk.Label(nut_f, text=f"• {s}", bg='#ecf0f1', fg='black').pack(anchor=tk.W, padx=10)
                
            tk.Label(nut_f, text=f"\n💡 {n['benefits']}", bg='#ecf0f1', fg='#2c3e50', wraplength=300, justify=tk.LEFT).pack(anchor=tk.W, padx=10, pady=5)

    def clear_all(self):
        if self.processing: return
        if self.camera_active: self.stop_camera()
        self.image_label.config(image='', text="📷 No Image")
        for widget in self.scrollable_frame.winfo_children(): widget.destroy()
        if hasattr(self, 'current_image_path'): delattr(self, 'current_image_path')
        self.status_var.set("🟢 Cleared")

    def logout(self):
        if self.camera_active: self.stop_camera()
        self.auth.logout()
        self.on_logout_callback()


def main():
    root = tk.Tk()
    root.title("Fruit Analyzer Pro")
    root.geometry("800x600")
    
    auth_system = UserAuth()

    def show_login():
        for w in root.winfo_children(): w.destroy()
        LoginFrame(root, auth_system, show_app)

    def show_app():
        for w in root.winfo_children(): w.destroy()
        UltraFruitGUI(root, auth_system, show_login)

    show_login()
    
    # Center
    root.update_idletasks()
    x = (root.winfo_screenwidth() - root.winfo_width()) // 2
    y = (root.winfo_screenheight() - root.winfo_height()) // 2
    root.geometry(f"+{x}+{y}")
    
    root.mainloop()

if __name__ == "__main__":
    main()