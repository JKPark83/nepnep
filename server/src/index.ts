import { Hono } from 'hono'
import { notionOAuth } from './routes/notionOAuth.js'
import { subscription } from './routes/subscription.js'
import { cloudTranscribe } from './routes/cloudTranscribe.js'
import { cloudSummarize } from './routes/cloudSummarize.js'

// 무상태 최소 서버 (06-m4 §1): 토큰 저장·로깅 금지.
const app = new Hono()

app.get('/', (c) => c.json({ service: 'nepnep-server', status: 'ok' }))
app.route('/v1/oauth/notion', notionOAuth)
app.route('/v1/subscription', subscription)
app.route('/v1/cloud/transcribe', cloudTranscribe)
app.route('/v1/cloud/summarize', cloudSummarize)

export default app
