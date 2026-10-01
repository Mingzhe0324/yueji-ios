"""Generate original soft bell cues; standard-library only, no downloaded audio."""
import math, struct, wave, json
from pathlib import Path
root = Path(__file__).resolve().parents[1] / 'YueJi/Assets.xcassets'
rate = 44100
cues = {
    'LaunchChime': [(0, 329.63, .7), (.22, 493.88, .65), (.48, 659.25, .65),
                    (.85, 783.99, .65), (1.05, 987.77, .55), (1.3, 1318.51, .65),
                    (1.6, 659.25, .9), (1.6, 830.61, .9), (1.6, 987.77, .9),
                    (2.55, 987.77, .35), (2.72, 1174.66, .4), (2.9, 1318.51, .65),
                    (3.65, 659.25, .7), (3.65, 987.77, .7)],
    'HelloChime': [(0, 659.25, .18), (.13, 880, .25)],
    'DanceChime': [(0, 523.25, .17), (.17, 659.25, .17), (.34, 783.99, .2), (.55, 659.25, .17), (.73, 1046.5, .3)],
    'StarChime': [(0, 987.77, .2), (.12, 1318.51, .25), (.26, 1567.98, .38)],
    'HugChime': [(0, 392, .65), (.12, 493.88, .65), (.24, 587.33, .7)],
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
    peak = max(abs(value) for value in samples) or 1
    if peak > 14000:
        samples = [round(value * 14000 / peak) for value in samples]
    with wave.open(str(folder/'cue.wav'), 'wb') as f:
        f.setnchannels(1); f.setsampwidth(2); f.setframerate(rate)
        f.writeframes(struct.pack('<'+'h'*len(samples), *samples))
    (folder/'Contents.json').write_text(json.dumps({'data':[{'filename':'cue.wav','idiom':'universal'}], 'info':{'author':'xcode','version':1}},indent=2)+'\n')
