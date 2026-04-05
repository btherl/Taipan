from PIL import Image

def process_apple_ii_correct_ghosting(input_path, output_path):
    img = Image.open(input_path).convert('L')
    width, height = img.size
    output_img = Image.new('RGB', (width, height))
    pixels = img.load()
    out_pixels = output_img.load()

    # Palette
    BLACK, WHITE = (0, 0, 0), (255, 255, 255)
    GREEN, PURPLE = (32, 192, 0), (160, 32, 255)

    for y in range(0, height, 2):
        row_bits = []
        for x in range(0, width, 2):
            row_bits.append(1 if pixels[x, y] > 127 else 0)

        for x_idx in range(len(row_bits)):
            bit = row_bits[x_idx]
            is_even = (x_idx % 2 == 0)
            
            left = row_bits[x_idx-1] if x_idx > 0 else 0
            right = row_bits[x_idx+1] if x_idx < len(row_bits) - 1 else 0

            color = BLACK # Default

            if bit == 1:
                if left == 1 or right == 1:
                    color = WHITE
                else:
                    color = GREEN if is_even else PURPLE
            
            elif bit == 0:
                # CORRECTED GHOSTING: 
                # If flanked by two 1s of the SAME color, the ghost matches them.
                # In Apple II HGR, 1-0-1 always means the 1s are the same color 
                # (since they are both even or both odd indices).
                if left == 1 and right == 1:
                    # Look to the left neighbor's color to lock the phase
                    # Since left was at (x_idx - 1), its 'evenness' is opposite
                    color = GREEN if not is_even else PURPLE

            # Fill 2x2 block
            for dy in range(2):
                for dx in range(2):
                    out_x, out_y = (x_idx * 2) + dx, y + dy
                    if out_x < width and out_y < height:
                        out_pixels[out_x, out_y] = color

    output_img.save(output_path)
    print(f"Corrected Phase-Locking Render: {output_path}")

if __name__ == "__main__":
    process_apple_ii_correct_ghosting("input.png", "apple2_fixed_ghosts.png")
