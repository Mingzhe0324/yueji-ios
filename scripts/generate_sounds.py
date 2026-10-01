"""Generate original soft bell cues; standard-library only, no downloaded audio."""
import math, struct, wave, json
from pathlib import Path
root = Path(__file__).resolve().parents[1] / 'YueJi/Assets.xcassets'
rate = 44100
cues = {
    'LaunchChime': [(0, 659.25, .32), (.15, 987.77, .4), (.31, 1318.51, .43)],
    'SavedChime': [(0, 880, .18), (.085, 1174.66, .24)],
    'GoalChime': [(0, 659.25, .36), (.14, 830.61, .36), (.28, 987.77, .4), (.43, 1318.51, .5)]
}
for name, notes in cues.items():
    folder = root / (name + '.dataset'); folder.mkdir(exist_ok=True)
    length = max(start + duration for start, _, duration in notes) + .04
    samples = []
    for i in range(round(length * rate)):
        t = i / rate; value = 0
        for start, hz, duration in notes:
            elapsed = t - start
            if 0 <= elapsed < duration:
                envelope = min(elapsed / .012, 1) * math.exp(-6 * elapsed / duration) * min((duration-elapsed)/.035, 1)
                value += envelope * (math.sin(2*math.pi*hz*elapsed) + .18*math.sin(2*math.pi*hz*2*elapsed)) * .19
        samples.append(int(max(-1, min(1, value))*32767))
    with wave.open(str(folder/'cue.wav'), 'wb') as f:
        f.setnchannels(1); f.setsampwidth(2); f.setframerate(rate)
        f.writeframes(struct.pack('<'+'h'*len(samples), *samples))
    (folder/'Contents.json').write_text(json.dumps({'data':[{'filename':'cue.wav','idiom':'universal'}], 'info':{'author':'xcode','version':1}},indent=2)+'\n')
