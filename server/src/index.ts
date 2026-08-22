import { Hono } from 'hono'
import { notionOAuth } from './routes/notionOAuth.js'

// 무상태 최소 서버 (06-m4 §1): 토큰 저장·로깅 금지.
const app = new Hono()

app.get('/', (c) => c.json({ service: 'nepnep-server', status: 'ok' }))
app.route('/v1/oauth/notion', notionOAuth)

export default app
