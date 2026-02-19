import os

train_dir = "augmented_dataset/train"
print(f"Checking counts in: {train_dir}")

for root, dirs, files in os.walk(train_dir):
    for d in dirs:
        if "orange" in d:
            path = os.path.join(root, d)
            count = len(os.listdir(path))
            print(f"🍊 {d}: {count} images")