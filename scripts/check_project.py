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
