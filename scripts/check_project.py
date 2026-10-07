"""Structural checks only; Xcode in CI remains the native compiler/test gate."""
from pathlib import Path
import json, re, plistlib, xml.etree.ElementTree as ET
root = Path(__file__).resolve().parents[1]
text = (root / 'YueJi.xcodeproj/project.pbxproj').read_text()
tokens = re.findall(r'"(?:\\.|[^"\\])*"|[{}()=;,]|\d+', text.split('\n', 1)[1])
pos = 0

def take(wanted=None):
    global pos
    token = tokens[pos]; pos += 1
    if wanted is not None:
        assert token == wanted, (wanted, token)
    return token

def value():
    token = take()
    if token == '{':
        result = {}
        while tokens[pos] != '}':
            key = json.loads(take()); take('='); result[key] = value(); take(';')
        take('}'); return result
    if token == '(':
        result = []
        while tokens[pos] != ')':
            result.append(value()); take(',')
        take(')'); return result
    return json.loads(token)

project = value(); assert pos == len(tokens)
objects = project['objects']
assert objects[project['rootObject']]['isa'] == 'PBXProject'
for obj in objects.values():
    for key in ('fileRef', 'productReference', 'mainGroup', 'productRefGroup', 'buildConfigurationList', 'targetProxy', 'target'):
        if key in obj: assert obj[key] in objects, (key, obj[key])
    for key in ('children', 'files', 'buildPhases', 'targets', 'dependencies', 'buildConfigurations'):
        for ref in obj.get(key, []): assert ref in objects, (key, ref)
app = next(o for o in objects.values() if o['isa'] == 'PBXNativeTarget' and o['name'] == 'YueJi')
phases = [objects[i] for i in app['buildPhases']]
source_phase = next(o for o in phases if o['isa'] == 'PBXSourcesBuildPhase')
compiled = {objects[objects[i]['fileRef']]['path'] for i in source_phase['files']}
assert compiled == {p.name for p in (root / 'YueJi').glob('*.swift')}
resource_phase = next(o for o in phases if o['isa'] == 'PBXResourcesBuildPhase')
resources = {objects[objects[i]['fileRef']]['path'] for i in resource_phase['files']}
assert {'Assets.xcassets', 'Localizable.xcstrings'} <= resources
plistlib.loads((root / 'YueJi/Info.plist').read_bytes())
ET.parse(root / 'YueJi.xcodeproj/xcshareddata/xcschemes/YueJi.xcscheme')
catalog = json.loads((root / 'YueJi/Localizable.xcstrings').read_text())
assert all({'en', 'ms'} <= set(v['localizations']) for v in catalog['strings'].values())
print(f'PASS: {len(compiled)} app Swift files in build, localized resources, references, Info.plist and shared scheme.')

# Brand resources must reach the existing asset catalog build phase.
import struct, wave
icon = root / 'YueJi/Assets.xcassets/AppIcon.appiconset/Icon.png'
header = icon.read_bytes()[:33]
assert header[:8] == b'\x89PNG\r\n\x1a\n'
assert struct.unpack('>II', header[16:24]) == (1024, 1024)
assert header[25] == 2, 'App icon must be opaque RGB'
for name in ('LaunchChime', 'SavedChime', 'GoalChime', 'DeleteCue', 'RestoreCue', 'DepositCue'):
    asset = root / 'YueJi/Assets.xcassets' / (name + '.dataset')
    metadata = json.loads((asset / 'Contents.json').read_text())
    audio = asset / metadata['data'][0]['filename']
    with wave.open(str(audio)) as wav:
        assert wav.getnchannels() == 1 and wav.getsampwidth() == 2
        assert 0.15 < wav.getnframes() / wav.getframerate() < (1.7 if name == 'LaunchChime' else 1.2)
        samples = struct.unpack('<' + 'h' * wav.getnframes(), wav.readframes(wav.getnframes()))
        peak = max(abs(x) for x in samples)
        assert 1000 < peak < 16000, 'Missing sound or excessive peak'
print('PASS: 1024px opaque icon and six decodable PCM sound assets.')

# Regression from build 53: overview still referenced removed deletion state.
for source in (root / 'YueJi').glob('*.swift'):
    assert 'removingExpenseIDs' not in source.read_text(), f'Stale deletion state in {source.name}'
print('PASS: no references to removed delayed-deletion state.')

# System notification sounds must be standalone resources, not catalog-only data.
assert 'YueJiMoonDrop.wav' in resources
with wave.open(str(root / 'YueJi/YueJiMoonDrop.wav')) as wav:
    assert wav.getnchannels() == 1 and wav.getsampwidth() == 2 and wav.getframerate() == 44100
    assert 1.0 <= wav.getnframes() / wav.getframerate() <= 1.2
    pcm = struct.unpack('<' + 'h' * wav.getnframes(), wav.readframes(wav.getnframes()))
    assert max(abs(v) for v in pcm) == 12000
    assert pcm[0] == 0 and pcm[-1] == 0
print('PASS: bundled original notification sound, PCM format, duration, peak and silent endpoints.')

# Catch invalid Swift Unicode escapes before launching an expensive Xcode build.
for source in (root / 'YueJi').glob('*.swift'):
    assert re.search(r'(?<!\\)\\u(?!\{)', source.read_text()) is None, f'Invalid Swift Unicode escape: {source.name}'
print('PASS: app Swift Unicode escapes use braces.')

# Direction sounds must be standalone bundle resources, distinct and short PCM.
direction_audio = []
for stem in ('YueJiIncoming', 'YueJiOutgoing'):
    assert stem + '.wav' in resources, f'Missing bundle resource: {stem}'
    path = root / 'YueJi' / (stem + '.wav')
    with wave.open(str(path), 'rb') as wav:
        assert wav.getnchannels() == 1 and wav.getsampwidth() == 2 and wav.getframerate() == 44100
        assert 0.7 < wav.getnframes() / wav.getframerate() < 1.2
        raw = wav.readframes(wav.getnframes())
        pcm = struct.unpack('<' + 'h' * (len(raw) // 2), raw)
        assert max(map(abs, pcm)) == 11000
        assert pcm[0] == pcm[-1] == 0
        direction_audio.append(raw)
assert direction_audio[0] != direction_audio[1]
print('PASS: two distinct incoming/outgoing PCM system sounds are in the app resource phase.')
