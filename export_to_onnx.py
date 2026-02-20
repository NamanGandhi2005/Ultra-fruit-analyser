import torch
import torch.nn as nn
from torchvision import models
import json
import os

def export_model(model_path='fruit_resnet_model.pth', onnx_path='fruit_model.onnx', info_path='model_info.json'):
    if not os.path.exists(model_path):
        print(f"❌ Error: {model_path} not found.")
        return

    print(f"🔄 Loading PyTorch model from {model_path}...")
    checkpoint = torch.load(model_path, map_location="cpu")
    
    class_names = checkpoint['class_names']
    num_classes = checkpoint['num_classes']
    
    # Recreate architecture
    model = models.resnet18(weights=None)
    model.fc = nn.Linear(model.fc.in_features, num_classes)
    model.load_state_dict(checkpoint['model_state_dict'])
    model.eval()

    # Create dummy input for ONNX trace (Shape: [Batch, Channels, Width, Height])
    dummy_input = torch.randn(1, 3, 224, 224)

    print(f"⚡ Exporting to ONNX format...")
    torch.onnx.export(
        model,
        dummy_input,
        onnx_path,
        export_params=True,
        opset_version=12,
        do_constant_folding=True,
        input_names=['input'],
        output_names=['output'],
        dynamic_axes={'input': {0: 'batch_size'}, 'output': {0: 'batch_size'}}
    )

    # Save metadata for Flutter
    model_info = {
        'class_names': class_names,
        'input_size': 224,
        'normalization': {
            'mean': [0.485, 0.456, 0.406],
            'std': [0.229, 0.224, 0.225]
        }
    }
    
    with open(info_path, 'w') as f:
        json.dump(model_info, f, indent=4)

    print(f"✅ Success!")
    print(f"📂 ONNX Model: {onnx_path}")
    print(f"📂 Metadata: {info_path}")

if __name__ == "__main__":
    export_model()
