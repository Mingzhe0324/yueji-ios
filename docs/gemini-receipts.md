# Gemini receipt recognition

The receipt screen defaults to on-device OCR. Enabling Gemini explicitly discloses that the photo goes to Google. Each scan sends a resized JPEG (maximum 2000 pixels, 4 MB) through the authenticated Supabase function. Results remain editable drafts; the existing totals check and review step are required to save. Unknown/non-MYR currencies are rejected rather than silently relabelled as RM. Disabling Gemini restores local OCR. Network errors never silently upload elsewhere or post expenses.

## Deployment

1. Run `backend/receipt-gemini.sql` in the project's SQL editor. It adds a persistent limit of 20 attempts per user per UTC day; failed model requests also consume attempts. It does not change ledger backups.
2. In Supabase **Edge Functions → Secrets**, set `GEMINI_API_KEY` and `GEMINI_RECEIPT_MODEL` to a currently available Gemini model supporting images and structured JSON. Never place the Gemini key in Info.plist, the app, git, screenshots or chat. The function uses the platform's `SUPABASE_URL` and `SUPABASE_ANON_KEY`.
3. From the repository root, deploy with `supabase functions deploy receipt-gemini --project-ref YOUR_PROJECT_REF`. The handler independently verifies the user's token through Supabase Auth; keep gateway JWT verification enabled where supported by the project's signing keys.
4. Sign in to YueJi, open receipt scanning, enable Gemini, and scan a test receipt. Verify merchant, line totals, tax, rounding and final amount. Test logged-out access, non-MYR receipts and the daily limit before wider rollout.

No receipt images or model responses are logged or stored by this function. Google processes uploaded images under the selected Gemini API project's terms. Review those terms and project pricing before enabling production use; this is not a promise of free or unlimited service. Set project quotas/budget controls as appropriate. The feature requires the function and secrets to be deployed; an app update alone does not enable the backend.

Run backend tests with `node --test backend/tests/receipt-gemini.test.mjs`. iOS draft decoding tests run in GitHub Actions.

References: [Gemini image input](https://ai.google.dev/gemini-api/docs/generate-content/image-understanding), [structured output](https://ai.google.dev/gemini-api/docs/structured-output), [Supabase function secrets](https://supabase.com/docs/guides/functions/secrets).
