"""Inject public cloud configuration before building. No secrets or user data are used."""
import argparse
import base64
import json
import os
from pathlib import Path
import plistlib
from urllib.parse import urlsplit

ROOT = Path(__file__).resolve().parents[1]

def validate(url, key):
    url, key = url.strip().rstrip('/'), key.strip()
    parts = urlsplit(url)
    if parts.scheme != 'https' or not parts.hostname or parts.username or parts.password or parts.path or parts.query or parts.fragment or '$(' in url:
        raise ValueError('Use the HTTPS Project URL, without /rest/v1 or a dashboard path.')
    public = key.startswith('sb_publishable_') and len(key) > 20
    if not public:
        try:
            segments = key.split('.')
            claims = json.loads(base64.urlsafe_b64decode(segments[1] + '=' * (-len(segments[1]) % 4)))
            public = len(segments) == 3 and claims.get('role') == 'anon'
        except (ValueError, IndexError, TypeError):
            pass
    if not public:
        raise ValueError('Use a publishable key (or legacy anon key), never a secret/service_role key.')
    return url, key

def configured_values(path):
    info = plistlib.loads(path.read_bytes())
    env_url = os.environ.get('YUEJI_SUPABASE_URL', '')
    env_key = os.environ.get('YUEJI_SUPABASE_PUBLIC_KEY', '')
    if env_url or env_key:
        return validate(env_url, env_key)
    url, key = info.get('YueJiSupabaseURL', ''), info.get('YueJiSupabasePublicKey', '')
    if url or key:
        return validate(url, key)
    config_path = ROOT / 'CloudConfig.json'
    if config_path.exists():
        config = json.loads(config_path.read_text(encoding='utf-8'))
        return validate(config.get('url', ''), config.get('publishable_key', ''))
    return None

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--require', action='store_true', help='Fail if cloud configuration is missing.')
    parser.add_argument('--check', action='store_true', help='Validate without writing Info.plist.')
    args = parser.parse_args()
    path = ROOT / 'YueJi/Info.plist'
    values = configured_values(path)
    if values is None:
        if args.require or os.environ.get('YUEJI_REQUIRE_CLOUD') == '1':
            raise ValueError('Cloud is required: set YUEJI_SUPABASE_URL and YUEJI_SUPABASE_PUBLIC_KEY in this build environment.')
        print('LOCAL MODE: cloud is not configured. This build cannot recover an account ledger.')
        return
    if not args.check:
        info = plistlib.loads(path.read_bytes())
        info['YueJiSupabaseURL'], info['YueJiSupabasePublicKey'] = values
        path.write_bytes(plistlib.dumps(info, sort_keys=False))
    print('PASS: cloud URL and public key are configured (values not printed).')

if __name__ == '__main__':
    try:
        main()
    except (ValueError, OSError) as error:
        raise SystemExit(str(error))
