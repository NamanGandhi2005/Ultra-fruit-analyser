import os
import numpy as np
import tensorflow as tf
from tensorflow.keras.preprocessing.image import ImageDataGenerator
import cv2
from PIL import Image
import shutil
import random

class DatasetGenerator:
    def __init__(self):
        self.fruits = ['banana', 'orange', 'mango', 'apple']
        self.stages = {
            'banana': 9,
            'orange': 5,
            'mango': 4,
            'apple': 3
        }

    def create_directories(self):
        """Creates a fresh folder structure."""
        base_dir = 'augmented_dataset'
        if os.path.exists(base_dir):
            print("🧹 Cleaning up old dataset...")
            shutil.rmtree(base_dir)
            
        os.makedirs(base_dir)

        for split in ['train', 'val']:
            split_dir = os.path.join(base_dir, split)
            os.makedirs(split_dir, exist_ok=True)

            for fruit in self.fruits:
                for stage in range(1, self.stages[fruit] + 1):
                    class_dir = os.path.join(split_dir, f'{fruit}_stage_{stage}')
                    os.makedirs(class_dir, exist_ok=True)
        return base_dir

    def get_augmentation_params(self, fruit_name):
        """Returns specific parameters based on fruit sensitivity."""
        if fruit_name == 'banana':
            return {
                'rotation_range': 20,       # Less rotation for long fruits
                'width_shift_range': 0.1,   
                'height_shift_range': 0.1,
                'shear_range': 0.1,
                'zoom_range': 0.1,
                'horizontal_flip': True,
                'vertical_flip': False,     
                'brightness_range': [0.9, 1.1], 
                'channel_shift_range': 5.0,     # Strict color
                'fill_mode': 'nearest'
            }
        else:
            return {
                'rotation_range': 45,       
                'width_shift_range': 0.2,
                'height_shift_range': 0.2,
                'shear_range': 0.1,
                'zoom_range': 0.2,
                'horizontal_flip': True,
                'vertical_flip': True,      
                'brightness_range': [0.8, 1.2],
                'channel_shift_range': 15.0, 
                'fill_mode': 'nearest'
            }

    def augment_images(self, input_image_path, output_dir, num_augmented, prefix, params):
        """Augments a single image using Keras ImageDataGenerator."""
        try:
            image = cv2.imread(input_image_path)
            if image is None: 
                print(f"⚠️ Could not read: {input_image_path}")
                return

            image = cv2.cvtColor(image, cv2.COLOR_BGR2RGB)
            image = cv2.resize(image, (224, 224))
            image = image.reshape((1,) + image.shape)

            datagen = ImageDataGenerator(**params)

            i = 0
            # Generate unique augmented images
            for batch in datagen.flow(image, batch_size=1,
                                      save_to_dir=output_dir,
                                      save_prefix=prefix,
                                      save_format='jpeg'):
                i += 1
                if i >= num_augmented:
                    break
        except Exception as e:
            print(f"❌ Error augmenting {input_image_path}: {e}")

    def generate_dataset(self, base_images_dir):
        base_dir = self.create_directories()
        
        # TARGET: Roughly this many images per class total (higher since we duplicate)
        TARGET_PER_CLASS = 600

        for fruit, num_stages in self.stages.items():
            print(f"\n--- Processing {fruit.upper()} ---")
            
            for stage in range(1, num_stages + 1):
                # 1. FIND SOURCE FOLDER
                possible_dirs = [
                    os.path.join(base_images_dir, fruit.capitalize(), f'stage_{stage}'),
                    os.path.join(base_images_dir, fruit.lower(), f'stage_{stage}')
                ]
                stage_dir = next((p for p in possible_dirs if os.path.exists(p)), None)
                
                if not stage_dir:
                    print(f"⚠️ Missing source folder: {fruit} Stage {stage}")
                    continue

                image_files = [f for f in os.listdir(stage_dir) if f.lower().endswith(('.jpg', '.jpeg', '.png'))]
                num_source = len(image_files)
                
                if num_source == 0:
                    print(f"⚠️ Folder empty: {fruit} Stage {stage}")
                    continue

                print(f"Stage {stage}: Using {num_source} source images for BOTH Train and Val")

                train_out = os.path.join(base_dir, 'train', f'{fruit}_stage_{stage}')
                val_out = os.path.join(base_dir, 'val', f'{fruit}_stage_{stage}')
                
                aug_params = self.get_augmentation_params(fruit)

                # Calculate counts to hit target size
                # 80% of target volume goes to train folder, 20% to val folder
                # BUT both are generated from the SAME source images
                count_train = int(TARGET_PER_CLASS * 0.8 / num_source)
                count_train = max(5, min(count_train, 100)) # Cap range 5-100 per image
                
                count_val = int(TARGET_PER_CLASS * 0.2 / num_source)
                count_val = max(2, min(count_val, 50))      # Cap range 2-50 per image

                # Generate data
                for img_name in image_files:
                    src_path = os.path.join(stage_dir, img_name)
                    base_name = os.path.splitext(img_name)[0]
                    
                    # 1. Generate Training Set (Heavy Augmentation)
                    self.augment_images(src_path, train_out, count_train, f"aug_{base_name}", aug_params)
                    
                    # 2. Generate Validation Set (Different Random Augmentations)
                    # Even though source is same, specific distortions will differ
                    self.augment_images(src_path, val_out, count_val, f"val_{base_name}", aug_params)

        return base_dir

if __name__ == "__main__":
    generator = DatasetGenerator()
    base_images_dir = 'data' 
    
    if os.path.exists(base_images_dir):
        path = generator.generate_dataset(base_images_dir)
        print(f"\n✅ Generation Complete! Dataset saved to: {path}")
        print("➡️  Ready for training (Small Dataset Mode)")
    else:
        print(f"❌ Error: Source folder '{base_images_dir}' not found.")