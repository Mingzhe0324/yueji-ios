"""Original short, distinct incoming/outgoing motifs for iOS system notifications."""
import math, struct, wave
from pathlib import Path
rate=44100
motifs={
    'YueJiIncoming': (1.02, [(0.01,659.25,0.48,0.75),(0.17,830.61,0.53,0.72),(0.34,1108.73,0.64,0.66)]),
    'YueJiOutgoing': (0.84, [(0.01,523.25,0.43,0.8),(0.23,349.23,0.56,0.78)])
}
for name,(duration,notes) in motifs.items():
    values=[]
    for frame in range(round(rate*duration)):
        t=frame/rate; value=0
        for onset,freq,length,gain in notes:
            e=t-onset
            if 0<=e<length:
                envelope=min(1,e/0.009)*min(1,(length-e)/0.07)*math.exp(-4.8*e/length)
                tone=math.sin(2*math.pi*freq*e)+0.17*math.sin(4*math.pi*freq*e)*math.exp(-9*e)
                value+=gain*envelope*tone
        values.append(value)
    peak=max(map(abs,values));pcm=[round(v/peak*11000) for v in values]
    dest=Path(__file__).resolve().parents[1]/'YueJi'/f'{name}.wav'
    with wave.open(str(dest),'wb') as out:
        out.setnchannels(1);out.setsampwidth(2);out.setframerate(rate)
        out.writeframes(struct.pack('<'+'h'*len(pcm),*pcm))
    print(name,duration,'seconds; mono 16-bit PCM; peak',max(map(abs,pcm)))
