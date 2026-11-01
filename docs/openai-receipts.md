# OpenAI receipt recognition

Current iOS builds use `receipt-openai`; bank notifications and automatic category
suggestions continue to use their existing Gemini functions.

## Deploy in Supabase

1. In the same project as the app, open Edge Functions → Secrets and add:
   - `OPENAI_API_KEY`: your server-side OpenAI API key.
   - `OPENAI_RECEIPT_MODEL`: `gpt-4.1-mini` as an initial model. It supports image
     input and structured output; model availability depends on your API project.
   Keep Gemini keys/model settings for the other features. Never put API keys in
   app code, Git, screenshots or chat. OpenAI API usage requires available API
   quota/billing; this integration does not provide free usage.
2. Reuse the existing `claim_receipt_scan` database function. If it was already
   installed for receipts, no new SQL is needed. Otherwise run the existing
   `backend/receipt-gemini.sql` once. Both legacy and current receipt endpoints
   share the 20-attempt per-user UTC daily allowance, including failed attempts.
3. Create an Edge Function named **receipt-openai**. Copy the COMPLETE contents of
   `supabase/functions/receipt-openai/index.ts` and `handler.mjs` into files with
   those exact names. Deploy updates. Alternatively:
   `supabase functions deploy receipt-openai --project-ref YOUR_PROJECT_REF`
   The function validates the user session using Supabase Auth and rejects anonymous
   users. Preserve the project's working gateway JWT/signing-key configuration.
4. Build the new iOS app via Actions → Build YueJi iPhone App → Run workflow on
   `insights-backup-opening`. Install it and explicitly enable Use OpenAI recognition.
   The old Gemini preference is not carried over to a new data recipient.
5. Test a non-sensitive MYR receipt while signed in. Confirm merchant, item totals,
   tax, rounding and final amount before saving. Test offline/local OCR as well.

Do not paste the new handler into `receipt-gemini`: older app versions disclose
Google as the recipient. That legacy endpoint remains unchanged. The updated app
calls only `receipt-openai` and never silently falls back to another cloud provider.

## Implementation and privacy

Uses the OpenAI Responses API with a base64 JPEG, high image detail, strict JSON
schema, `store: false`, an 8192 output-token cap, and a 25-second total timeout.
The function does not log/store receipt photos or provider responses. `store: false`
disables response application-state storage; it is not a claim of zero retention
by OpenAI. Review your provider account's applicable data controls and terms.

Authentication, image size checks, persistent quota, MYR/money validation and
editable draft review are preserved. Refusals, incomplete output, invalid JSON,
upstream errors and quota failures never create ledger entries. No automatic
retries are made. Errors return stable codes, not provider response text or keys.

Tests: `node --test backend/tests/receipt-openai.test.mjs` (mocked provider).
The iOS decode tests and app compilation run in Xcode CI. A real scan must still
be tested after secrets and deployment are ready.

Official references:
- https://developers.openai.com/api/docs/guides/images-vision
- https://developers.openai.com/api/docs/guides/structured-outputs
- https://developers.openai.com/api/docs/models/gpt-4.1-mini
