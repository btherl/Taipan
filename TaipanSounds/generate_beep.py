import wave
import math
import struct

# Parameters
filename = "apple_ii_beep.wav"
sample_rate = 44100  # CD quality
frequency = 1000.0   # 1 kHz
duration = 0.1       # 0.1 seconds
amplitude = 0.5      # Volume (max 1.0)

num_samples = int(sample_rate * duration)
period_samples = sample_rate / frequency

with wave.open(filename, "w") as wav_file:
    # Set channels (1 = mono), sample width (2 bytes = 16-bit), and sample rate
    wav_file.setnchannels(1)
    wav_file.setsampwidth(2)
    wav_file.setframerate(sample_rate)
    
    for i in range(num_samples):
        # Determine if we are in the high or low part of the square wave cycle
        if (i % period_samples) < (period_samples / 2):
            sample = int(amplitude * 32767)
        else:
            sample = int(-amplitude * 32767)
            
        # Pack the integer into 16-bit binary data
        data = struct.pack('<h', sample)
        wav_file.writeframesraw(data)

print(f"File saved successfully as '{filename}'")
