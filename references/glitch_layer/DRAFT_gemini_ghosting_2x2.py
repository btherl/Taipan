from PIL import Image

def process_apple_ii_blocks(input_path, output_path):
    # 1. Load image and convert to grayscale
    img = Image.open(input_path).convert('L')
    width, height = img.size
    
    # Create a new RGB image for the output
    output_img = Image.new('RGB', (width, height))
    pixels = img.load()
    out_pixels = output_img.load()

    # Define the Apple II HGR Palette
    BLACK = (0, 0, 0)
    WHITE = (255, 255, 255)
    GREEN = (32, 192, 0)   
    PURPLE = (160, 32, 255)

    # Process in 2x2 steps
    for y in range(0, height, 2):
        row_bits = []
        
        # Step A: Sample the top-left of each 2x2 block to build the bit-row
        for x in range(0, width, 2):
            # Sample only (x, y); ignore (x+1, y), (x, y+1), and (x+1, y+1)
            is_on = 1 if pixels[x, y] > 127 else 0
            row_bits.append(is_on)

        # Step B: Apply Apple II logic to the sampled row
        # Note: row_bits length is now width // 2
        for x_idx in range(len(row_bits)):
            bit = row_bits[x_idx]
            is_even = (x_idx % 2 == 0)
            
            left = row_bits[x_idx-1] if x_idx > 0 else 0
            right = row_bits[x_idx+1] if x_idx < len(row_bits) - 1 else 0

            # Determine the color for this 2x2 block
            if bit == 1:
                if left == 1 or right == 1:
                    color = WHITE
                else:
                    color = GREEN if is_even else PURPLE
            else:
                # The "Ghosting" effect
                if left == 1 and right == 1:
                    color = GREEN if is_even else PURPLE
                else:
                    color = BLACK

            # Step C: Fill the entire 2x2 output block with the calculated color
            for dy in range(2):
                for dx in range(2):
                    out_x, out_y = (x_idx * 2) + dx, y + dy
                    if out_x < width and out_y < height:
                        out_pixels[out_x, out_y] = color

    output_img.save(output_path)
    print(f"Processed 2x2 blocks. Rendered to {output_path}")

if __name__ == "__main__":
    process_apple_ii_blocks("input.png", "apple2_blocks_output.png")
