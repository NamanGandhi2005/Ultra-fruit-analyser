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
    
    class_names = checkpoint.get('class_names', [])
    num_classes = checkpoint.get('num_classes', len(class_names))
    state_dict = checkpoint.get('model_state_dict', checkpoint) # Handle direct state_dicts too

    # Try ResNet18 first
    success = False
    error_log = ""

    # Attempt ResNet18
    try:
        model = models.resnet18(weights=None)
        model.fc = nn.Linear(model.fc.in_features, num_classes)
        model.load_state_dict(state_dict)
        print("💡 Architecture detected: ResNet18")
        success = True
    except Exception as e:
        error_log += f"ResNet18 failed: {str(e)}\n"

    # Attempt EfficientNet B0 if ResNet failed
    if not success:
        try:
            model = models.efficientnet_b0(weights=None)
            model.classifier[1] = nn.Linear(model.classifier[1].in_features, num_classes)
            model.load_state_dict(state_dict)
            print("💡 Architecture detected: EfficientNet B0")
            success = True
        except Exception as e:
            error_log += f"EfficientNet failed: {str(e)}\n"

    if not success:
        raise Exception(f"Could not match model architecture. Errors:\n{error_log}")

    model.eval()

    # Create dummy input for ONNX trace
    dummy_input = torch.randn(1, 3, 224, 224)

    print(f"⚡ Exporting to ONNX format...")
    torch.onnx.export(
        model,
        dummy_input,
        onnx_path,
        export_params=True,
        opset_version=13,
        do_constant_folding=True,
        input_names=['input'],
        output_names=['output'],
        dynamic_axes={'input': {0: 'batch_size'}, 'output': {0: 'batch_size'}}
    )

    # Save metadata
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

    # Optional: Copy to mobile assets for convenience
    mobile_assets_dir = 'fruit_analyzer_mobile/assets/model'
    if os.path.exists(mobile_assets_dir):
        import shutil
        shutil.copy(onnx_path, os.path.join(mobile_assets_dir, 'fruit_model.onnx'))
        
        # Also copy info to assets/data if it exists
        mobile_data_dir = 'fruit_analyzer_mobile/assets/data'
        if os.path.exists(mobile_data_dir):
            shutil.copy(info_path, os.path.join(mobile_data_dir, 'model_info.json'))
        
        print(f"📦 Also copied files to mobile assets.")

    print(f"✅ Success!")

if __name__ == "__main__":
    export_model()
