# After asking Gemini to account for ghosting too, it produced this:
# How to check if this is correct?  Need to ask it to render something.

def apple2_artifact_simulation(bits):
    """
    Simulates the 'bleeding' effect where spaces between 
    high-res bits can result in 'ghost' color pixels.
    """
    render = []
    
    for i in range(len(bits)):
        # Determine if this position is Even or Odd
        is_even = (i % 2 == 0)
        
        if bits[i] == 1:
            # Direct pixel: White if neighbors are on, otherwise Green/Purple
            left = bits[i-1] if i > 0 else 0
            right = bits[i+1] if i < len(bits)-1 else 0
            
            if left or right:
                render.append("White")
            else:
                render.append("Green" if is_even else "Purple")
        
        elif bits[i] == 0:
            # Ghost Pixel Logic: 
            # If flanked by 1s, the NTSC signal often 'bleeds' 
            # the color across the gap.
            left = bits[i-1] if i > 0 else 0
            right = bits[i+1] if i < len(bits)-1 else 0
            
            if left and right:
                # The 'Ghost' takes the color of its position
                render.append("Green (Ghost)" if is_even else "Purple (Ghost)")
            else:
                render.append("Black")
                
    return render

# Example: 1 (on), 0 (off), 1 (on)
# Position 0=Even, 1=Odd, 2=Even
input_data = [1, 0, 1] 
print(apple2_artifact_simulation(input_data))
