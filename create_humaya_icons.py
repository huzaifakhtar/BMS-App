#!/usr/bin/env python3
import os
from PIL import Image, ImageDraw
import math

def create_app_icons_from_logo():
    # Load the Humaya logo
    logo_path = '/Users/admin/development/BMS App/lib/images/Humaya Logo.png'
    logo = Image.open(logo_path)
    
    # Icon sizes for different densities
    sizes = {
        'mipmap-mdpi': 48,
        'mipmap-hdpi': 72,
        'mipmap-xhdpi': 96,
        'mipmap-xxhdpi': 144,
        'mipmap-xxxhdpi': 192
    }
    
    base_path = '/Users/admin/development/BMS App/android/app/src/main/res'
    
    for folder, size in sizes.items():
        # Create a square canvas
        icon = Image.new('RGBA', (size, size), (255, 255, 255, 0))
        
        # Calculate scaling to fit the logo properly
        logo_aspect = logo.width / logo.height
        if logo_aspect > 1:  # Logo is wider than tall
            new_width = int(size * 0.8)  # 80% of icon size
            new_height = int(new_width / logo_aspect)
        else:  # Logo is taller than wide
            new_height = int(size * 0.8)  # 80% of icon size
            new_width = int(new_height * logo_aspect)
        
        # Resize logo
        resized_logo = logo.resize((new_width, new_height), Image.Resampling.LANCZOS)
        
        # Center the logo on the icon
        x = (size - new_width) // 2
        y = (size - new_height) // 2
        
        # Paste the logo onto the icon
        icon.paste(resized_logo, (x, y), resized_logo)
        
        # Save the icon
        icon_path = os.path.join(base_path, folder, 'ic_launcher.png')
        os.makedirs(os.path.dirname(icon_path), exist_ok=True)
        icon.save(icon_path, 'PNG')
        print(f"Created {icon_path} ({size}x{size})")

if __name__ == "__main__":
    create_app_icons_from_logo()
    print("All Humaya Connect icons created successfully from original logo!")