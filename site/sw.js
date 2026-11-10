// Cross-origin isolation for a host that cannot set response headers.
//
// The browser build of the game uses threads (SharedArrayBuffer), which a page
// only gets when it is served with these two headers. GitHub Pages cannot send
// them, so this worker adds them to every same-origin response it relays: the
// landing page, and the game under play/ that the landing page embeds.
//
// It caches nothing and changes nothing else. Requests to other sites (the
// release sizes from api.github.com) are left to the browser.

self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', (event) => event.waitUntil(self.clients.claim()));

self.addEventListener('fetch', (event) => {
  const request = event.request;
  if (request.method !== 'GET' || new URL(request.url).origin !== self.location.origin) return;
  // A request the browser may only answer from its cache cannot be re-fetched.
  if (request.cache === 'only-if-cached' && request.mode !== 'same-origin') return;

  event.respondWith(fetch(request).then((response) => {
    if (response.status === 0) return response;         // opaque: nothing to rewrite
    const headers = new Headers(response.headers);
    headers.set('Cross-Origin-Opener-Policy', 'same-origin');
    headers.set('Cross-Origin-Embedder-Policy', 'require-corp');
    // 204 and 304 carry no body, and a Response refuses one for them.
    const body = [101, 204, 205, 304].includes(response.status) ? null : response.body;
    return new Response(body, {
      status: response.status,
      statusText: response.statusText,
      headers,
    });
  }));
});
