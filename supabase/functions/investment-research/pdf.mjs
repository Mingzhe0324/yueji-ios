// Only server-owned allowlisted URLs reach this function. No OCR.
export async function officialPDF(url, fetcher, loader = () => import('npm:unpdf@2.1.0')) {
  const response = await fetcher(url, {redirect:'error', headers:{Accept:'application/pdf'}});
  if (!response.ok || !response.headers.get('content-type')?.toLowerCase().includes('application/pdf') || !response.body) throw new Error('source_unavailable');
  const reader = response.body.getReader(), chunks = []; let size = 0;
  try {
    while (true) {
      const {done,value} = await reader.read(); if (done) break;
      size += value.byteLength;
      if (size > 8000000) { await reader.cancel(); throw new Error('source_too_large'); }
      chunks.push(value);
    }
  } finally { reader.releaseLock(); }
  const bytes = new Uint8Array(size); let offset = 0;
  for (const chunk of chunks) { bytes.set(chunk,offset); offset += chunk.length; }
  if (new TextDecoder().decode(bytes.slice(0,5)) !== '%PDF-') throw new Error('source_unavailable');
  const {getDocumentProxy} = await loader();
  const pdf = await getDocumentProxy(bytes, {isEvalSupported:false, useSystemFonts:false, useWorkerFetch:false, disableFontFace:true});
  try {
    if (!Number.isInteger(pdf.numPages) || pdf.numPages < 1 || pdf.numPages > 60) throw new Error('source_too_large');
    const pages = []; let length = 0;
    for (let number = 1; number <= pdf.numPages; number++) {
      const page = await pdf.getPage(number), content = await page.getTextContent();
      const text = content.items.map(item => typeof item.str === 'string' ? item.str + (item.hasEOL ? '\n' : ' | ') : '').join('').trim();
      if (text.length < 20) throw new Error('pdf_text_unavailable');
      length += text.length;
      if (length > 60000) throw new Error('source_too_large');
      pages.push(`[PDF page ${number}/${pdf.numPages}]\n${text}`);
      page.cleanup();
    }
    return pages.join('\n\n');
  } finally { await pdf.loadingTask.destroy(); }
}
