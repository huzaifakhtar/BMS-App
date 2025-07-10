#!/usr/bin/env python3
import os
from PIL import Image

def create_ios_icons_from_logo():
    # Load the Humaya logo
    logo_path = '/Users/admin/development/BMS App/lib/images/Humaya Logo.png'
    logo = Image.open(logo_path)
    
    # iOS icon sizes
    ios_sizes = {
        'Icon-App-20x20@1x.png': 20,
        'Icon-App-20x20@2x.png': 40,
        'Icon-App-20x20@3x.png': 60,
        'Icon-App-29x29@1x.png': 29,
        'Icon-App-29x29@2x.png': 58,
        'Icon-App-29x29@3x.png': 87,
        'Icon-App-40x40@1x.png': 40,
        'Icon-App-40x40@2x.png': 80,
        'Icon-App-40x40@3x.png': 120,
        'Icon-App-60x60@2x.png': 120,
        'Icon-App-60x60@3x.png': 180,
        'Icon-App-76x76@1x.png': 76,
        'Icon-App-76x76@2x.png': 152,
        'Icon-App-83.5x83.5@2x.png': 167,
        'Icon-App-1024x1024@1x.png': 1024,
    }
    
    base_path = '/Users/admin/development/BMS App/ios/Runner/Assets.xcassets/AppIcon.appiconset'
    
    for filename, size in ios_sizes.items():
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
        icon_path = os.path.join(base_path, filename)
        os.makedirs(os.path.dirname(icon_path), exist_ok=True)
        icon.save(icon_path, 'PNG')
        print(f"Created {filename} ({size}x{size})")

if __name__ == "__main__":
    create_ios_icons_from_logo()
    print("All iOS Humaya Connect icons created successfully!")