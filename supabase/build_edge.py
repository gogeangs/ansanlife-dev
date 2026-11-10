#!/usr/bin/env python3
"""server/worker.js(Cloudflare Worker) → supabase/functions/api/index.ts(Supabase Edge Function) 생성.

서버 로직은 server/worker.js 한 곳에서만 고치고, 이 스크립트로 Edge Function 파일을 다시 만드세요.
  python3 supabase/build_edge.py
"""
from pathlib import Path
ROOT = Path(__file__).resolve().parent.parent
src = (ROOT / "server" / "worker.js").read_text(encoding="utf-8")
assert src.count("export default {") == 1
src = src.replace("export default {", "const worker = {")
src = src.replace("export const ", "const ").replace("export function ", "function ").replace("export async function ", "async function ")

ADAPTER = r'''

/* ===================== Supabase Edge Function 어댑터 =====================
   - 주소: https://<프로젝트>.supabase.co/functions/v1/api/<경로>  (앱 API_URL = …/functions/v1/api)
   - 설정(Edge Functions › Secrets): ANTHROPIC_API_KEY, DATA_GO_KR_KEY, (선택) BUS_KEY, MODEL, VISION_MODEL, ALLOWED_ORIGIN
   - SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_SERVICE_ROLE_KEY 는 Supabase 가 자동으로 넣어 줌
   - Cloudflare KV → public.kv_cache 표, Rate Limiting → public.rate_hit() (supabase/edge.sql)
   - "Verify JWT" 는 끄고 배포 (앱은 로그인 없이 부름. 대신 ALLOWED_ORIGIN + IP 횟수 제한) */
const SB_URL = Deno.env.get('SUPABASE_URL') || '';
const SB_SERVICE = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || '';
const SB_ANON = Deno.env.get('SUPABASE_ANON_KEY') || '';
const svc = { apikey: SB_SERVICE, authorization: `Bearer ${SB_SERVICE}`, 'content-type': 'application/json' };

const TR_KV = SB_URL && SB_SERVICE ? {
  async get(key, type) {
    const r = await fetch(`${SB_URL}/rest/v1/kv_cache?select=value&key=eq.${encodeURIComponent(key)}&expires_at=gt.${encodeURIComponent(new Date().toISOString())}`, { headers: svc });
    if (!r.ok) return null;
    const rows = await r.json();
    return rows.length ? (type === 'json' ? rows[0].value : JSON.stringify(rows[0].value)) : null;
  },
  async put(key, value, opt = {}) {
    const ttl = opt.expirationTtl || 60 * 60 * 24 * 30;
    await fetch(`${SB_URL}/rest/v1/kv_cache?on_conflict=key`, {
      method: 'POST', headers: { ...svc, prefer: 'resolution=merge-duplicates,return=minimal' },
      body: JSON.stringify({ key, value: JSON.parse(value), expires_at: new Date(Date.now() + ttl * 1000).toISOString() }),
    });
  },
} : undefined;

const LIMITER = SB_URL && SB_SERVICE ? {
  async limit({ key }) {
    try {
      const r = await fetch(`${SB_URL}/rest/v1/rpc/rate_hit`, { method: 'POST', headers: svc, body: JSON.stringify({ p_key: key, p_limit: 20, p_window_seconds: 60 }) });
      return { success: r.ok ? (await r.json()) !== false : true };   // 제한 기능이 고장 나면 서비스는 계속
    } catch { return { success: true }; }
  },
} : undefined;

const DEFAULTS = {
  ALLOWED_ORIGIN: 'https://gogeangs.github.io,https://eugenekimkim.github.io',
  NOTICES_URL: SB_URL ? `${SB_URL}/rest/v1/notices?select=id,type,title,body,date,url,sample&published=is.true&order=sort.desc,created_at.desc&limit=30` : '',
  NOTICES_KEY: SB_ANON,
};
const ENV = new Proxy({}, {
  get(_, k) {
    if (k === 'TR_KV') return TR_KV;
    if (k === 'LIMITER') return LIMITER;
    return Deno.env.get(String(k)) || DEFAULTS[k];
  },
});

Deno.serve((req) => {
  const u = new URL(req.url);
  // /functions/v1/api/bus/stops 또는 /api/bus/stops → /bus/stops
  const path = u.pathname.replace(/^\/functions\/v1/, '').replace(/^\/api(?=\/|$)/, '') || '/';
  const headers = new Headers(req.headers);
  const ip = (req.headers.get('x-forwarded-for') || '').split(',')[0].trim();
  if (ip) headers.set('cf-connecting-ip', ip);
  const init = { method: req.method, headers };
  if (req.method !== 'GET' && req.method !== 'HEAD') { init.body = req.body; init.duplex = 'half'; }
  return worker.fetch(new Request(`https://api.local${path}${u.search}`, init), ENV);
});
'''
out = "// @ts-nocheck\n// 자동 생성 파일 — 고치지 말고 server/worker.js 를 고친 뒤 python3 supabase/build_edge.py\n" + src + ADAPTER
(ROOT / "supabase" / "functions" / "api" / "index.ts").write_text(out, encoding="utf-8")
print("built supabase/functions/api/index.ts", len(out), "bytes")
