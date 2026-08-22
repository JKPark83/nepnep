import { Hono } from 'hono'

// POST /v1/oauth/notion/exchange
// { code, redirectUri } → { accessToken, workspaceName, botId }
// 클라이언트 secret을 앱에 넣지 않기 위한 프록시. 토큰은 저장하지 않고 반환만 한다.
export const notionOAuth = new Hono()

// GET /v1/oauth/notion/callback?code=...
// Notion은 리다이렉트 URI로 HTTPS만 허용하므로, 여기서 앱의 커스텀 스킴으로 되돌린다.
// ASWebAuthenticationSession(callbackURLScheme: "nepnep")이 이 리다이렉트를 받는다.
notionOAuth.get('/callback', (c) => {
  const incoming = new URL(c.req.url)
  const target = new URL('nepnep://oauth/notion')
  incoming.searchParams.forEach((v, k) => target.searchParams.set(k, v))
  return c.redirect(target.toString(), 302)
})

notionOAuth.post('/exchange', async (c) => {
  const { code, redirectUri } = await c.req.json<{ code?: string; redirectUri?: string }>()
  if (!code || !redirectUri) {
    return c.json({ error: 'code and redirectUri are required' }, 400)
  }

  const clientId = process.env.NOTION_CLIENT_ID
  const clientSecret = process.env.NOTION_CLIENT_SECRET
  if (!clientId || !clientSecret) {
    return c.json({ error: 'server is not configured' }, 500)
  }

  // Notion 공개 통합의 토큰 교환은 Basic 인증 필수 (btoa: Edge 런타임에는 Buffer가 없다)
  const basic = btoa(`${clientId}:${clientSecret}`)
  const r = await fetch('https://api.notion.com/v1/oauth/token', {
    method: 'POST',
    headers: {
      Authorization: `Basic ${basic}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      grant_type: 'authorization_code',
      code,
      redirect_uri: redirectUri,
    }),
  })

  if (!r.ok) {
    // 실패 시 상태코드 그대로 전달 (본문은 Notion 에러 코드만)
    const body = (await r.json().catch(() => ({}))) as { error?: string }
    return c.json({ error: body.error ?? 'token exchange failed' }, r.status as 400)
  }

  const token = (await r.json()) as {
    access_token: string
    workspace_name?: string
    bot_id?: string
  }
  return c.json({
    accessToken: token.access_token,
    workspaceName: token.workspace_name ?? '',
    botId: token.bot_id ?? '',
  })
})
