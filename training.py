import torch
import torch.nn as nn
import torch.optim as optim
from torchvision import datasets, models, transforms
from torch.utils.data import DataLoader, random_split, WeightedRandomSampler
import os
import time
import copy
import matplotlib.pyplot as plt
import seaborn as sns
from sklearn.metrics import confusion_matrix, classification_report
import numpy as np
import sys
import multiprocessing

# Try to import DirectML for AMD GPUs
try:
    import torch_directml
    dml_available = True
except ImportError:
    dml_available = False

# ----------------------------
# CONFIGURATION
# ----------------------------
CONFIG = {
    'batch_size': 32,
    'learning_rate': 0.0003,      # Increased slightly for better learning
    'num_epochs': 35,
    'input_size': 224,
    'patience': 8,
    'save_path': 'fruit_resnet_model.pth'
}

def get_device():
    """Checks for available devices (CUDA -> DirectML -> CPU)."""
    if torch.cuda.is_available():
        print(f"✅ NVIDIA GPU Detected: {torch.cuda.get_device_name(0)}")
        return torch.device("cuda")
    elif dml_available:
        print("✅ AMD GPU Detected (via DirectML)")
        return torch_directml.device()
    else:
        print("⚠️ No GPU detected. Training on CPU will be slow.")
        return torch.device("cpu")

def plot_confusion_matrix(y_true, y_pred, classes):
    """Generates and saves a confusion matrix heatmap."""
    try:
        cm = confusion_matrix(y_true, y_pred)
        plt.figure(figsize=(14, 12))
        sns.heatmap(cm, annot=True, fmt='d', cmap='Blues', 
                    xticklabels=classes, yticklabels=classes)
        plt.ylabel('Actual')
        plt.xlabel('Predicted')
        plt.title('Confusion Matrix')
        plt.xticks(rotation=45, ha='right')
        plt.tight_layout()
        plt.savefig('confusion_matrix.png')
        print("📊 Confusion Matrix saved to confusion_matrix.png")
    except Exception as e:
        print(f"⚠️ Could not generate confusion matrix: {e}")

def train_model(data_dir):
    device = get_device()
    print(f"🚀 Training started on DEVICE: {device}")

    if not os.path.exists(data_dir):
        print(f"❌ Error: Directory '{data_dir}' not found.")
        return

    # Auto-detect optimal workers
    num_workers = min(4, multiprocessing.cpu_count())

    # ----------------------------
    # 1. OPTIMIZED AUGMENTATION
    # ----------------------------
    data_transforms = {
        'train': transforms.Compose([
            transforms.Resize((CONFIG['input_size'], CONFIG['input_size'])),
            transforms.RandomHorizontalFlip(),
            transforms.RandomRotation(15),
            # Reduced Jitter slightly to keep features sharp
            transforms.ColorJitter(brightness=0.15, contrast=0.15, saturation=0.15, hue=0.01),
            transforms.RandomAffine(degrees=0, translate=(0.05, 0.05)),
            transforms.ToTensor(),
            transforms.Normalize([0.485, 0.456, 0.406], [0.229, 0.224, 0.225])
        ]),
        'val': transforms.Compose([
            transforms.Resize((CONFIG['input_size'], CONFIG['input_size'])),
            transforms.ToTensor(),
            transforms.Normalize([0.485, 0.456, 0.406], [0.229, 0.224, 0.225])
        ]),
    }

    # ----------------------------
    # 2. LOAD DATA
    # ----------------------------
    print("📂 Loading dataset...")
    train_dir = os.path.join(data_dir, 'train')
    val_dir = os.path.join(data_dir, 'val')
    
    if os.path.exists(train_dir) and os.path.exists(val_dir):
        train_dataset = datasets.ImageFolder(train_dir, data_transforms['train'])
        val_dataset = datasets.ImageFolder(val_dir, data_transforms['val'])
    else:
        full_dataset = datasets.ImageFolder(data_dir, data_transforms['train'])
        train_size = int(0.8 * len(full_dataset))
        val_size = len(full_dataset) - train_size
        train_dataset, val_dataset = random_split(full_dataset, [train_size, val_size])
        val_dataset.dataset.transform = data_transforms['val']

    # --- HANDLE CLASS IMBALANCE ---
    try:
        print("⚖️ Calculating class weights...")
        if isinstance(train_dataset, torch.utils.data.Subset):
            targets = [train_dataset.dataset.targets[i] for i in train_dataset.indices]
            classes = train_dataset.dataset.classes
        else:
            targets = train_dataset.targets
            classes = train_dataset.classes

        class_counts = np.bincount(targets)
        class_weights = 1. / (class_counts + 1e-5)
        sample_weights = [class_weights[t] for t in targets]
        
        sampler = WeightedRandomSampler(sample_weights, len(sample_weights))
        train_loader = DataLoader(train_dataset, batch_size=CONFIG['batch_size'], 
                                  sampler=sampler, num_workers=num_workers)
        print("✅ Weighted Sampling Enabled")
    except Exception as e:
        print(f"⚠️ Balancing failed ({e}). Defaulting to standard shuffle.")
        train_loader = DataLoader(train_dataset, batch_size=CONFIG['batch_size'], 
                                  shuffle=True, num_workers=num_workers)

    val_loader = DataLoader(val_dataset, batch_size=CONFIG['batch_size'], 
                            shuffle=False, num_workers=num_workers)
    
    dataloaders = {'train': train_loader, 'val': val_loader}
    dataset_sizes = {'train': len(train_dataset), 'val': len(val_dataset)}
    num_classes = len(classes)
    print(f"✅ Classes found: {num_classes}")

    # ----------------------------
    # 3. MODEL SETUP
    # ----------------------------
    print("🧠 Initializing ResNet-18...")
    model = models.resnet18(weights=models.ResNet18_Weights.DEFAULT)
    
    # Freeze initial layers (Layer 1 & 2)
    for param in model.parameters():
        param.requires_grad = False
        
    # Unfreeze Layer 3 AND Layer 4 to allow deeper learning
    for param in model.layer3.parameters():
        param.requires_grad = True
    for param in model.layer4.parameters():
        param.requires_grad = True
        
    # Replace Head
    num_ftrs = model.fc.in_features
    model.fc = nn.Linear(num_ftrs, num_classes)
    model = model.to(device)

    # REMOVED label_smoothing to allow higher confidence scores
    criterion = nn.CrossEntropyLoss()
    
    # Adjusted learning rates for deeper unfreezing
    optimizer = optim.Adam([
        {'params': model.layer3.parameters(), 'lr': CONFIG['learning_rate'] * 0.1},
        {'params': model.layer4.parameters(), 'lr': CONFIG['learning_rate'] * 0.2},
        {'params': model.fc.parameters(), 'lr': CONFIG['learning_rate']}
    ])
    
    scheduler = optim.lr_scheduler.ReduceLROnPlateau(optimizer, mode='max', factor=0.1, patience=3)

    # ----------------------------
    # 4. TRAINING LOOP
    # ----------------------------
    since = time.time()
    best_model_wts = copy.deepcopy(model.state_dict())
    best_acc = 0.0
    
    history = {'train_loss': [], 'val_loss': [], 'train_acc': [], 'val_acc': []}
    epochs_no_improve = 0
    
    print("\n🔥 STARTING TRAINING LOOP")
    print(f"   Max Epochs: {CONFIG['num_epochs']}")
    print("-" * 30)

    for epoch in range(CONFIG['num_epochs']):
        print(f'Epoch {epoch+1}/{CONFIG["num_epochs"]}', end=' ')

        for phase in ['train', 'val']:
            if phase == 'train':
                model.train()
            else:
                model.eval()

            running_loss = 0.0
            running_corrects = 0

            for inputs, labels in dataloaders[phase]:
                inputs = inputs.to(device)
                labels = labels.to(device)

                optimizer.zero_grad()

                with torch.set_grad_enabled(phase == 'train'):
                    outputs = model(inputs)
                    _, preds = torch.max(outputs, 1)
                    loss = criterion(outputs, labels)

                    if phase == 'train':
                        loss.backward()
                        optimizer.step()

                running_loss += loss.item() * inputs.size(0)
                running_corrects += torch.sum(preds == labels.data)

            epoch_loss = running_loss / dataset_sizes[phase]
            epoch_acc = running_corrects.double() / dataset_sizes[phase]

            if phase == 'train':
                history['train_loss'].append(epoch_loss)
                history['train_acc'].append(epoch_acc.item())
                print(f"| Train Loss: {epoch_loss:.4f} Acc: {epoch_acc:.4f}", end=' ')
            else:
                history['val_loss'].append(epoch_loss)
                history['val_acc'].append(epoch_acc.item())
                print(f"| Val Loss: {epoch_loss:.4f} Acc: {epoch_acc:.4f}")
                
                scheduler.step(epoch_acc)

            if phase == 'val':
                if epoch_acc > best_acc:
                    best_acc = epoch_acc
                    best_model_wts = copy.deepcopy(model.state_dict())
                    epochs_no_improve = 0
                else:
                    epochs_no_improve += 1

        if epochs_no_improve >= CONFIG['patience']:
            print(f"\n✋ Early Stopping triggered!")
            break

    time_elapsed = time.time() - since
    print(f'\n🏁 Training complete in {time_elapsed // 60:.0f}m {time_elapsed % 60:.0f}s')
    print(f'🏆 Best Validation Acc: {best_acc:4f}')

    # ----------------------------
    # 5. SAVING
    # ----------------------------
    model.load_state_dict(best_model_wts)
    
    print("🔎 Generating report...")
    all_preds = []
    all_labels = []
    model.eval()
    with torch.no_grad():
        for inputs, labels in dataloaders['val']:
            inputs = inputs.to(device)
            outputs = model(inputs)
            _, preds = torch.max(outputs, 1)
            all_preds.extend(preds.cpu().numpy())
            all_labels.extend(labels.cpu().numpy())
            
    print("\n" + classification_report(all_labels, all_preds, target_names=classes))
    plot_confusion_matrix(all_labels, all_preds, classes)

    model.to("cpu")
    save_data = {
        'model_state_dict': model.state_dict(),
        'class_names': classes,
        'num_classes': num_classes,
        'config': CONFIG
    }
    torch.save(save_data, CONFIG['save_path'])
    print(f"💾 Model saved to: {CONFIG['save_path']}")
    
    plot_history(history)

def plot_history(history):
    plt.figure(figsize=(12, 5))
    plt.subplot(1, 2, 1)
    plt.plot(history['train_loss'], label='Train Loss')
    plt.plot(history['val_loss'], label='Val Loss')
    plt.title('Loss')
    plt.legend()
    plt.grid(True)

    plt.subplot(1, 2, 2)
    plt.plot(history['train_acc'], label='Train Acc')
    plt.plot(history['val_acc'], label='Val Acc')
    plt.title('Accuracy')
    plt.legend()
    plt.grid(True)
    plt.savefig('training_results.png')
    print("📊 Graph saved to training_results.png")

if __name__ == "__main__":
    DATASET_PATH = "augmented_dataset" 
    train_model(DATASET_PATH)