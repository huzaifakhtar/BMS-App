#!/usr/bin/env python3
import os
from PIL import Image, ImageDraw, ImageFont
import math

def create_humaya_logo(size):
    # Create image with transparent background
    img = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    
    # Humaya orange color
    orange_color = (255, 102, 0, 255)  # Bright orange
    
    # Draw circular background
    margin = size // 10
    circle_size = size - 2 * margin
    draw.ellipse([margin, margin, margin + circle_size, margin + circle_size], 
                 fill=orange_color, outline=None)
    
    # Draw stylized "H" in white
    white_color = (255, 255, 255, 255)
    
    # H dimensions
    h_width = size // 3
    h_height = size // 2
    h_thickness = size // 12
    
    # Calculate H position (centered)
    h_x = (size - h_width) // 2
    h_y = (size - h_height) // 2
    
    # Draw left vertical line of H
    draw.rectangle([h_x, h_y, h_x + h_thickness, h_y + h_height], fill=white_color)
    
    # Draw right vertical line of H
    draw.rectangle([h_x + h_width - h_thickness, h_y, h_x + h_width, h_y + h_height], fill=white_color)
    
    # Draw horizontal line of H (middle)
    h_middle_y = h_y + h_height // 2 - h_thickness // 2
    draw.rectangle([h_x, h_middle_y, h_x + h_width, h_middle_y + h_thickness], fill=white_color)
    
    return img

def create_app_icons():
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
        logo = create_humaya_logo(size)
        icon_path = os.path.join(base_path, folder, 'ic_launcher.png')
        
        # Create directory if it doesn't exist
        os.makedirs(os.path.dirname(icon_path), exist_ok=True)
        
        # Save the icon
        logo.save(icon_path, 'PNG')
        print(f"Created {icon_path} ({size}x{size})")

if __name__ == "__main__":
    create_app_icons()
    print("All Humaya Connect icons created successfully!")