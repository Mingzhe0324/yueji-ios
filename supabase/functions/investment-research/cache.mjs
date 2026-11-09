// Account-scoped cache. Source collection still runs first so changed evidence
// invalidates the report. Never include credentials or client-supplied documents.
export const REPORT_VERSION = 'official-v4-fragments';
export async function reportKey(symbols, evidence, model) {
  const canonical = JSON.stringify({version:REPORT_VERSION,model,symbols,
    evidence:evidence.map(({id,symbol,company,url,scope,text})=>({id,symbol,company,url,scope,text}))});
  const bytes = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(canonical));
  return Array.from(new Uint8Array(bytes), b=>b.toString(16).padStart(2,'0')).join('');
}
export function validCachedReport(value, symbols, now = Date.now()) {
  const age = now - Date.parse(value?.generatedAt);
  return value && Number.isFinite(age) && age >= 0 && age < 86400000 &&
    value.symbol === symbols[0] && JSON.stringify(value.symbols) === JSON.stringify(symbols) &&
    value.candidate?.finishReason === 'STOP' && JSON.stringify(value.candidate).length <= 200000;
}
