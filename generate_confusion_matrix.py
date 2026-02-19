import torch
import torch.nn as nn
from torchvision import datasets, models, transforms
from torch.utils.data import DataLoader
import matplotlib.pyplot as plt
from sklearn.metrics import confusion_matrix, ConfusionMatrixDisplay
import os
import sys
import numpy as np

# ----------------------------
# DEVICE (GPU -> CPU FALLBACK)
# ----------------------------
try:
    import torch_directml
    dml_available = True
except ImportError:
    dml_available = False

def get_device():
    if torch.cuda.is_available():
        print(f"✅ NVIDIA GPU: {torch.cuda.get_device_name(0)}")
        return torch.device("cuda")
    if dml_available:
        print("✅ AMD GPU (DirectML)")
        return torch_directml.device()

    print("⚠ No GPU found → Using CPU")
    return torch.device("cpu")

# ----------------------------
# CONFIG
# ----------------------------
MODEL_PATH = "fruit_resnet_model.pth"
DATASET_PATH = os.path.join("augmented_dataset", "val")
INPUT_SIZE = 224
BATCH_SIZE = 32
OUTPUT_DIR = "fruit_confusion_matrices_blue"

os.makedirs(OUTPUT_DIR, exist_ok=True)

# ----------------------------
# TRANSFORMS
# ----------------------------
transform = transforms.Compose([
    transforms.Resize((INPUT_SIZE, INPUT_SIZE)),
    transforms.ToTensor(),
    transforms.Normalize([0.485, 0.456, 0.406],
                         [0.229, 0.224, 0.225])
])

# ----------------------------
# LOAD DATA
# ----------------------------
if not os.path.exists(DATASET_PATH):
    print(f"⛔ VAL FOLDER NOT FOUND: {DATASET_PATH}")
    sys.exit()

dataset = datasets.ImageFolder(DATASET_PATH, transform=transform)
dataloader = DataLoader(dataset, batch_size=BATCH_SIZE, shuffle=False)

dataset_classes = dataset.classes
print("✅ Dataset Classes:\n", dataset_classes)

# ----------------------------
# LOAD MODEL
# ----------------------------
device = get_device()

# Load Checkpoint
try:
    # FIX: Always load to CPU first to avoid DirectML crash
    print("🚀 Loading checkpoint to CPU...")
    checkpoint = torch.load(MODEL_PATH, map_location="cpu")
except FileNotFoundError:
    print(f"❌ Model file not found: {MODEL_PATH}")
    sys.exit()

# Handle different checkpoint formats
if isinstance(checkpoint, dict) and 'class_names' in checkpoint:
    class_names = checkpoint["class_names"]
    num_classes = checkpoint["num_classes"]
else:
    # Fallback if checkpoint is just state_dict or missing keys
    class_names = dataset_classes
    num_classes = len(class_names)

print("✅ Model Classes:\n", class_names)

model = models.resnet18(weights=None)
model.fc = nn.Linear(model.fc.in_features, num_classes)

if isinstance(checkpoint, dict) and 'model_state_dict' in checkpoint:
    model.load_state_dict(checkpoint["model_state_dict"])
else:
    model.load_state_dict(checkpoint)

# Move to GPU (DirectML or NVIDIA) explicitly after loading
print(f"🚀 Moving model to device: {device}")
model.to(device)
model.eval()

# ----------------------------
# PREDICTION
# ----------------------------
print("📈 Running model predictions...")

all_preds = []
all_labels = []

with torch.no_grad():
    for imgs, labels in dataloader:
        imgs = imgs.to(device)
        labels = labels.to(device)

        outputs = model(imgs)
        _, preds = torch.max(outputs, 1)

        all_preds.extend(preds.cpu().numpy())
        all_labels.extend(labels.cpu().numpy())

all_preds  = np.array(all_preds)
all_labels = np.array(all_labels)

# ----------------------------
# GROUP CLASSES BY FRUIT
# ----------------------------
fruit_groups = {}

for idx, cname in enumerate(class_names):
    # Splits "apple_stage_1" -> "apple"
    fruit = cname.split("_")[0]
    fruit_groups.setdefault(fruit, []).append(idx)

print("\n🍎 Fruit groups:", fruit_groups)

# ----------------------------
# CONFUSION MATRIX PER FRUIT (FIXED)
# ----------------------------
print("\n📊 Creating BLUE confusion matrices")

for fruit, idxs in fruit_groups.items():
    
    # Filter: Get only the True Labels belonging to this fruit
    mask = np.isin(all_labels, idxs)

    fruit_labels = all_labels[mask]
    fruit_preds  = all_preds[mask]

    if len(fruit_labels) == 0:
        print(f"⚠ No samples for {fruit}")
        continue

    # Create mapping: Global Index -> Local Index (0, 1, 2...)
    remap = {old: new for new, old in enumerate(idxs)}

    # Map Labels (Safe because of mask)
    remap_labels = np.array([remap[x] for x in fruit_labels])
    
    # Map Predictions (CRITICAL FIX: Handle predictions outside the group)
    # If the model predicted 'Orange' (16) for an 'Apple' image, 
    # remap.get(16, -1) returns -1 instead of crashing.
    remap_preds = np.array([remap.get(x, -1) for x in fruit_preds])

    # Check for "Out of Family" errors (e.g. Apple predicted as Orange)
    missed_count = np.sum(remap_preds == -1)
    if missed_count > 0:
        print(f"   ℹ️  Note: {missed_count} {fruit} images were misclassified as other fruits (omitted from plot).")

    fruit_classes = [class_names[i] for i in idxs]

    # Generate Confusion Matrix
    # We specify labels=range(len(fruit_classes)) so that '-1' values are ignored automatically
    cm = confusion_matrix(
        remap_labels,
        remap_preds,
        labels=range(len(fruit_classes))
    )

    disp = ConfusionMatrixDisplay(
        confusion_matrix=cm,
        display_labels=fruit_classes
    )

    # Plot
    plt.figure(figsize=(10,8))
    disp.plot(cmap="Blues", xticks_rotation=45)

    plt.title(f"{fruit.capitalize()} – Confusion Matrix", fontsize=14)
    plt.tight_layout()

    save_path = os.path.join(
        OUTPUT_DIR,
        f"{fruit}_confusion_matrix_blue.png"
    )

    plt.savefig(save_path, dpi=300)
    plt.close()

    print(f"✅ {fruit.capitalize()} saved → {save_path}")

print("\n🎯 SUCCESS — Blue confusion matrices generated!")