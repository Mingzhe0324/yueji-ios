"""Packaging checks; Swift compilation remains the Xcode CI gate."""
from pathlib import Path
import json,plistlib
import struct
p=Path(__file__).resolve().parents[1]
info=plistlib.loads((p/'YueJi/Info.plist').read_bytes())
assert (info['CFBundleShortVersionString'],info['CFBundleVersion'])==('1.41.1','56')
icons=p/'YueJi/Assets.xcassets/AppIcon.appiconset'
entries=json.loads((icons/'Contents.json').read_text())['images']
for entry in entries:
    size=float(entry['size'].split('x')[0])*int(entry['scale'][0])
    data=(icons/entry['filename']).read_bytes()
    assert struct.unpack('>II',data[16:24])==(int(size),int(size))
    assert data[25]==2 # RGB, opaque
assert any(x['idiom']=='iphone' and x['size']=='60x60' and x['scale']=='3x' for x in entries)
for scale in (2,3):
    data=(p/f'YueJi/YueJiIcon@{scale}x.png').read_bytes()
    assert struct.unpack('>II',data[16:24])==(60*scale,60*scale)
assert info['CFBundleIcons']['CFBundlePrimaryIcon']['CFBundleIconName']=='AppIcon'
assert 'YueJiIcon' in info['CFBundleIcons']['CFBundlePrimaryIcon']['CFBundleIconFiles']
assert info['YueJiSupabaseURL']=='' and info['YueJiSupabasePublicKey']=='' # no credentials in delivery
sql=(p/'backend/supabase.sql').read_text()
assert 'enable row level security' in sql and 'security invoker' in sql
assert 'previous_revision <> p_expected_revision' in sql
assert 'service_role' not in sql
print('PASS: version, all icon dimensions, IPA icon fallbacks, unconfigured cloud defaults and RLS/revision SQL markers.')

source=(p/'YueJi/Views.swift').read_text()
for removed in ['QuickPurposeView','BatchLedgerView','NotificationImportView','BackupHealthView','BackupReminderView','MonthlySummaryView']:
    assert removed not in source
assert not (p/'YueJi/LedgerTools.swift').exists()
assert 'AccountEntryView().font' in (p/'YueJi/YueJiApp.swift').read_text()
cloud=(p/'YueJi/CloudAccount.swift').read_text()
assert 'else if cloud.signedIn { MainView() }' in cloud
assert 'else { LoginSignupView() }' in cloud
assert 'SecItemCopyMatching' in cloud and 'signedIn = false' in cloud
print('PASS: removed feature entries and account-controlled app entry.')
