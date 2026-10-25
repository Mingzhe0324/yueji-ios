"""Read-only cloud setup check: no sign-in emails, account access or ledger writes."""
import json
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen
from configure_cloud import ROOT, configured_values

def check(url, key, opener=urlopen):
    for path, method in [('/auth/v1/settings', 'GET'), ('/rest/v1/rpc/yueji_sync_health', 'POST')]:
        request = Request(url + path, method=method, data=b'{}' if method == 'POST' else None,
                          headers={'apikey': key, 'Content-Type': 'application/json'})
        try:
            with opener(request, timeout=20) as response:
                data = response.read(100_000)
        except HTTPError as error:
            if error.code in (401, 403):
                raise ValueError('API key rejected. Check that the Project URL and publishable key belong to the same project.') from None
            if path.endswith('yueji_sync_health') and error.code in (400, 404):
                raise ValueError('Auth is reachable, but database setup is missing. Run backend/supabase.sql completely, then retry.') from None
            if error.code == 429:
                raise ValueError('Service rate limit reached. Retry later.') from None
            raise ValueError(f'Service returned HTTP {error.code}. Check project status in Supabase.') from None
        except (URLError, TimeoutError):
            raise ValueError('Cannot reach the project. Check the URL, network/DNS and whether the project is paused.') from None
        if path.endswith('yueji_sync_health') and json.loads(data) != 1:
            raise ValueError('Unexpected database health version. Re-run backend/supabase.sql.')
    return 'PASS: Auth and ledger schema are reachable. No user data was read or changed.'

if __name__ == '__main__':
    try:
        values = configured_values(ROOT / 'YueJi/Info.plist')
        if values is None:
            raise ValueError('No cloud configuration. Set YUEJI_SUPABASE_URL and YUEJI_SUPABASE_PUBLIC_KEY first.')
        print(check(*values))
    except (ValueError, OSError) as error:
        raise SystemExit(str(error))
