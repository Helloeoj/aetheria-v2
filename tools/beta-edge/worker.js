// Free workers.dev HTTPS facade. Secrets are deployment bindings, never source.
const routes = new Map([
  ['/api/register', 'POST'], ['/api/login', 'POST'], ['/api/logout', 'POST'],
  ['/api/character', 'GET'], ['/api/admit', 'POST'], ['/api/release', 'GET'],
  ['/health', 'GET'],
]);
const unavailable = (status = 404) => Response.json(
  {ok: false, message: 'The beta server is unavailable. Retry shortly.'},
  {status, headers: {'Cache-Control': 'no-store'}});

async function boundedBody(stream, limit) {
  if (!stream) return new Uint8Array();
  const reader = stream.getReader();
  const chunks = [];
  let length = 0;
  try {
    while (true) {
      const {done, value} = await reader.read();
      if (done) break;
      length += value.byteLength;
      if (length > limit) {
        await reader.cancel();
        return null;
      }
      chunks.push(value);
    }
  } finally {
    reader.releaseLock();
  }
  const bytes = new Uint8Array(length);
  let offset = 0;
  for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.byteLength; }
  return bytes;
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (routes.get(url.pathname) !== request.method || url.search) return unavailable();
    if (!env.ORIGIN_URL || !env.INGRESS_TOKEN || env.INGRESS_TOKEN.length < 40) return unavailable(503);
    let origin;
    try { origin = new URL(env.ORIGIN_URL); } catch { return unavailable(503); }
    if (origin.protocol !== 'https:' || origin.username || origin.password ||
        origin.pathname !== '/' || origin.search || origin.hash) return unavailable(503);
    const ip = request.headers.get('CF-Connecting-IP');
    if (!ip) return unavailable(503);
    const declared = Number(request.headers.get('Content-Length') || 0);
    if (!Number.isSafeInteger(declared) || declared < 0 || declared > 262144) return unavailable(413);
    const headers = new Headers({
      'X-Aetheria-Ingress': env.INGRESS_TOKEN, 'X-Aetheria-Client-IP': ip,
      'Content-Type': 'application/json',
    });
    const authorization = request.headers.get('Authorization');
    if (authorization && authorization.length <= 128) headers.set('Authorization', authorization);
    try {
      const body = request.method === 'POST' ? await boundedBody(request.body, 262144) : undefined;
      if (body === null) return unavailable(413);
      const result = await fetch(new URL(url.pathname, origin), {
        method: request.method, body, headers, redirect: 'error',
        signal: AbortSignal.timeout(10000),
      });
      const payload = await boundedBody(result.body, 65536);
      if (payload === null) return unavailable(502);
      return new Response(payload, {status: result.status, headers: {
        'Content-Type': 'application/json', 'Cache-Control': 'no-store',
        'X-Content-Type-Options': 'nosniff',
      }});
    } catch {
      return unavailable(503);
    }
  },
};
