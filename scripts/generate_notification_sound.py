"""Original YueJi 'Moon Drop' notification motif, PCM WAV for iOS system alerts."""
import math
import struct
import wave
from pathlib import Path

rate = 44100
duration = 1.08
# A warm rounded strike, rising glass notes, then a short soft tail: D5-A5-D6.
notes = [(0.015, 587.33, 0.62, 0.65), (0.17, 880.00, 0.65, 0.72),
         (0.34, 1174.66, 0.70, 0.64)]
samples = []
for frame in range(round(rate * duration)):
    t = frame / rate
    value = 0.0
    for start, frequency, length, gain in notes:
        e = t - start
        if 0 <= e < length:
            attack = min(1.0, e / 0.008)
            release = min(1.0, (length - e) / 0.065)
            envelope = attack * release * math.exp(-5.4 * e / length)
            tone = (math.sin(2 * math.pi * frequency * e)
                    + 0.20 * math.sin(2 * math.pi * frequency * 2 * e) * math.exp(-8 * e)
                    + 0.06 * math.sin(2 * math.pi * frequency * 3 * e) * math.exp(-12 * e))
            value += gain * envelope * tone
    samples.append(value)
peak = max(abs(v) for v in samples)
pcm = [round(v / peak * 12000) for v in samples]
target = Path(__file__).resolve().parents[1] / 'YueJi/YueJiMoonDrop.wav'
with wave.open(str(target), 'wb') as f:
    f.setnchannels(1)
    f.setsampwidth(2)
    f.setframerate(rate)
    f.writeframes(struct.pack('<' + 'h' * len(pcm), *pcm))
print(f'{target.name}: {duration:.2f}s, mono 16-bit PCM, peak 12000/32767')
