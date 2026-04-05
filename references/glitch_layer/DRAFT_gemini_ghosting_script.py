from PIL import Image
import numpy as np

def process_apple_ii_ghosting(input_path, output_path):
    # 1. Load image and convert to grayscale to calculate averages
    img = Image.open(input_path).convert('L')
    width, height = img.size
    
    # Create a new RGB image for the output
    output_img = Image.new('RGB', (width, height))
    pixels = img.load()
    out_pixels = output_img.load()

    # Define the Apple II HGR Palette (simplified NTSC)
    BLACK = (0, 0, 0)
    WHITE = (255, 255, 255)
    GREEN = (32, 192, 0)   # Classic Apple II Green
    PURPLE = (160, 32, 255) # Classic Apple II Purple

    for y in range(height):
        # Extract the row and threshold it to 0s and 1s (Black or White)
        row_bits = []
        for x in range(width):
            # Threshold at 50% brightness (128)
            row_bits.append(1 if pixels[x, y] > 127 else 0)

        # 2. Apply the HGR Artifact and Ghosting Logic
        for x in range(width):
            bit = row_bits[x]
            is_even = (x % 2 == 0)
            
            # Look at neighbors for bleeding/ghosting
            left = row_bits[x-1] if x > 0 else 0
            right = row_bits[x+1] if x < width - 1 else 0

            if bit == 1:
                # If a 1 is next to another 1, it bleeds into White
                if left == 1 or right == 1:
                    out_pixels[x, y] = WHITE
                else:
                    # Isolated 1s become Green or Purple based on column
                    out_pixels[x, y] = GREEN if is_even else PURPLE
            else:
                # Ghosting Logic: A 0 flanked by 1s becomes a colored ghost
                if left == 1 and right == 1:
                    out_pixels[x, y] = GREEN if is_even else PURPLE
                else:
                    out_pixels[x, y] = BLACK

    output_img.save(output_path)
    print(f"Rendered Apple II artifact image to {output_path}")

# Run the script
if __name__ == "__main__":
    process_apple_ii_ghosting("input.png", "apple2_output.png")
