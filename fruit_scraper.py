import json
import os
from icrawler.builtin import BingImageCrawler

def load_json(filename):
    with open(filename, 'r') as file:
        return json.load(file)

def main():
    # 1. Load the provided JSON files
    model_info = load_json('model_info.json')
    nutrients = load_json('nutrients.json')
    
    classes = model_info.get('class_names', [])
    
    # 2. Set the base directory for your dataset
    base_dir = "fruit_dataset"
    if not os.path.exists(base_dir):
        os.makedirs(base_dir)

    print(f"Starting image scraping for {len(classes)} classes...\n")

    # 3. Iterate through each class and scrape images
    for class_name in classes:
        # Extract the fruit name and stage number (e.g., 'banana_stage_1' -> 'banana', '1')
        parts = class_name.split('_stage_')
        if len(parts) != 2:
            continue
            
        fruit = parts[0]
        stage = parts[1]
        
        # Cross-reference with nutrients.json to get the descriptive name
        stage_info = nutrients.get(fruit, {}).get(stage, {})
        descriptive_name = stage_info.get('name', f"stage {stage}")
        
        # Build a smart search query (e.g., "Very Unripe banana fruit")
        search_query = f"{descriptive_name} {fruit} fruit"
        
        # Create a specific folder for this class
        output_dir = os.path.join(base_dir, class_name)
        if not os.path.exists(output_dir):
            os.makedirs(output_dir)
            
        print(f"--- Scraping for '{class_name}' ---")
        print(f"Query: {search_query}")
        print(f"Saving to: {output_dir}")
        
        # 4. Initialize the crawler and download images
        crawler = BingImageCrawler(
            feeder_threads=1,
            parser_threads=1,
            downloader_threads=4,
            storage={'root_dir': output_dir}
        )
        
        crawler.crawl(
            keyword=search_query, 
            max_num=100, 
            file_idx_offset=0
        )
        print("\n")

if __name__ == "__main__":
    main()