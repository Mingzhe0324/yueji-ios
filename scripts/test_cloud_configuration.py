import base64
import io
import json
import os
from pathlib import Path
import plistlib
import tempfile
import unittest
from unittest.mock import patch
from urllib.error import HTTPError, URLError
from configure_cloud import validate, configured_values
from check_cloud_connection import check

class CloudConfigurationTests(unittest.TestCase):
    url = 'https://example.supabase.co'
    key = 'sb_publishable_example_public_key'

    def test_public_config_is_used_without_changing_simulator_plist(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            path = root / 'Info.plist'
            original = plistlib.dumps({'YueJiSupabaseURL': '', 'YueJiSupabasePublicKey': ''})
            path.write_bytes(original)
            (root / 'CloudConfig.json').write_text(json.dumps({'url': self.url, 'publishable_key': self.key}), encoding='utf-8')
            with patch('configure_cloud.ROOT', root), patch.dict(os.environ, {}, clear=True):
                self.assertEqual(configured_values(path), (self.url, self.key))
            self.assertEqual(path.read_bytes(), original)

    def test_environment_pair_overrides_config_but_partial_override_fails(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'Info.plist'
            path.write_bytes(plistlib.dumps({}))
            with patch.dict(os.environ, {'YUEJI_SUPABASE_URL': self.url, 'YUEJI_SUPABASE_PUBLIC_KEY': self.key}, clear=True):
                self.assertEqual(configured_values(path), (self.url, self.key))
            with patch.dict(os.environ, {'YUEJI_SUPABASE_URL': self.url}, clear=True):
                with self.assertRaises(ValueError):
                    configured_values(path)

    def test_valid_project_url_and_public_key(self):
        self.assertEqual(validate(self.url + '/', self.key), (self.url, self.key))

    def test_unsafe_or_wrong_configuration_is_rejected(self):
        for url in ['http://example.supabase.co', self.url + '/rest/v1', self.url + '?key=bad', 'https://user:password@example.com', '$(MISSING)']:
            with self.subTest(url=url), self.assertRaises(ValueError):
                validate(url, self.key)
        for key in ['', 'sb_secret_example', '$(MISSING)']:
            with self.subTest(key=key), self.assertRaises(ValueError):
                validate(self.url, key)

    def test_legacy_anon_is_accepted_and_service_role_rejected(self):
        def jwt(role):
            claims = base64.urlsafe_b64encode(json.dumps({'role': role}).encode()).decode().rstrip('=')
            return 'header.' + claims + '.signature'
        validate(self.url, jwt('anon'))
        with self.assertRaises(ValueError):
            validate(self.url, jwt('service_role'))

    def test_probe_never_sends_email_or_accesses_ledgers(self):
        requests = []
        def opener(request, timeout):
            requests.append(request)
            return io.BytesIO(b'{}' if request.method == 'GET' else b'1')
        self.assertIn('PASS', check(self.url, self.key, opener))
        self.assertEqual([request.full_url for request in requests], [self.url + '/auth/v1/settings', self.url + '/rest/v1/rpc/yueji_sync_health'])
        self.assertTrue(all(not request.has_header('Authorization') for request in requests))

    def test_missing_schema_and_wrong_key_are_distinguished(self):
        def missing(request, timeout):
            if request.method == 'GET':
                return io.BytesIO(b'{}')
            raise HTTPError(request.full_url, 404, '', {}, None)
        with self.assertRaisesRegex(ValueError, 'database setup is missing'):
            check(self.url, self.key, missing)
        def wrong(request, timeout):
            raise HTTPError(request.full_url, 401, '', {}, None)
        with self.assertRaisesRegex(ValueError, 'API key rejected'):
            check(self.url, self.key, wrong)
        def offline(request, timeout):
            raise URLError('offline')
        with self.assertRaisesRegex(ValueError, 'Cannot reach'):
            check(self.url, self.key, offline)

if __name__ == '__main__':
    unittest.main()
