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
info = plistlib.loads((root / 'YueJi/Info.plist').read_bytes())
scheme = ET.parse(root / 'YueJi.xcodeproj/xcshareddata/xcschemes/YueJi.xcscheme')
testables = {ref.attrib['BlueprintName'] for ref in scheme.findall('.//TestableReference/BuildableReference')}
for name in ('YueJiTests', 'YueJiUITests'):
    assert name in testables, f'Missing test target in shared scheme: {name}'
    target = next(o for o in objects.values() if o['isa'] == 'PBXNativeTarget' and o['name'] == name)
    sources = next(objects[i] for i in target['buildPhases'] if objects[i]['isa'] == 'PBXSourcesBuildPhase')
    compiled_tests = {objects[objects[i]['fileRef']]['path'] for i in sources['files']}
    assert compiled_tests == {p.name for p in (root / name).glob('*.swift')}, f'Missing compiled test file: {name}'
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
logo_asset = root / 'YueJi/Assets.xcassets/YueJiLogo.imageset'
logo_metadata = json.loads((logo_asset / 'Contents.json').read_text())
logo = logo_asset / logo_metadata['images'][0]['filename']
assert logo_metadata['images'][0]['idiom'] == 'universal'
assert logo.read_bytes() == icon.read_bytes(), 'Opening logo must use the app brand image'
dark_logo = [item for item in logo_metadata['images'] if {'appearance': 'luminosity', 'value': 'dark'} in item.get('appearances', [])]
assert len(dark_logo) == 1, 'In-app logo needs the dark icon as its dark appearance'
assert (logo_asset / dark_logo[0]['filename']).read_bytes() == (icon.parent / 'Icon-dark.png').read_bytes(), 'Dark in-app logo must be the dark app icon'
# Every static in-app image name must resolve to a bundled imageset. AppIcon is not a normal Image asset.
for source in (root / 'YueJi').glob('*.swift'):
    for name in re.findall(r'\bImage\("([^"\\]+)"\)', source.read_text()):
        asset = root / 'YueJi/Assets.xcassets' / (name + '.imageset')
        assert (asset / 'Contents.json').is_file(), f'Missing image asset: {source.name} / {name}'
        metadata = json.loads((asset / 'Contents.json').read_text())
        filenames = [item['filename'] for item in metadata['images'] if 'filename' in item]
        assert filenames and all((asset / name).is_file() for name in filenames), f'Missing bundled image: {source.name} / {name}'
print('PASS: static SwiftUI image names resolve to bundled image assets.')
launch_color_name = info['UILaunchScreen']['UIColorName']
launch_color = json.loads((root / 'YueJi/Assets.xcassets' / (launch_color_name + '.colorset') / 'Contents.json').read_text())
assert any(not color.get('appearances') for color in launch_color['colors']), 'Launch background needs a default appearance'
assert any({'appearance': 'luminosity', 'value': 'dark'} in color.get('appearances', []) for color in launch_color['colors']), 'Launch background needs a dark appearance'
assert all(float(color['color']['components']['alpha']) == 1 for color in launch_color['colors']), 'Launch background must be opaque'
print('PASS: launch screen background resolves to bundled, opaque light and dark colors.')
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
print('PASS: 1024px opaque icon, dedicated opening logo and six decodable PCM sound assets.')

# AltStore and other sideloading tools read the loose CFBundleIconFiles icons.
def png_header(path):
    data = path.read_bytes()[:33]
    assert data[:8] == b'\x89PNG\r\n\x1a\n', f'Not a PNG: {path.name}'
    return struct.unpack('>II', data[16:24]), data[25]
for scale in (2, 3):
    name = f'YueJiIcon@{scale}x.png'
    assert name in resources, f'Missing icon fallback resource: {name}'
    assert png_header(root / 'YueJi' / name) == ((60 * scale, 60 * scale), 2), f'Icon fallback must be opaque {60 * scale}px: {name}'
notifications = (root / 'YueJi/Features.swift').read_text()
assert 'UNNotificationAttachment' not in notifications, 'System notifications must not add a right-side thumbnail.'
assert 'no-attachments-v1' in notifications, 'Existing daily reminders must migrate away from attachments.'
print('PASS: IPA/AltStore icon fallbacks are bundled; notification thumbnails are disabled.')

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

# These system-provided environment values are get-only in the supported Apple SDK.
# Writing them with .environment requires a WritableKeyPath and prevents the app compiling.
read_only_environment = ('colorSchemeContrast', 'accessibilityReduceMotion', 'accessibilityReduceTransparency')
for source in (root / 'YueJi').glob('*.swift'):
    writes = re.findall(r'\.\s*(?:environment|transformEnvironment)\s*\(\s*\\\.\s*(\w+)', source.read_text())
    invalid = set(writes).intersection(read_only_environment)
    assert not invalid, f'Read-only SwiftUI environment write in {source.name}: {sorted(invalid)}'
print('PASS: no writes to read-only SwiftUI contrast or accessibility environment values.')

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
