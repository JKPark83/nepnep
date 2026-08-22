import { Hono } from 'hono'
import { del } from '@vercel/blob'
import { generateClientTokenFromReadWriteToken } from '@vercel/blob/client'
import { verifySessionToken } from '../lib/session.js'
import { pollTranscription, submitTranscription } from '../lib/rtzr.js'
import { MONTHLY_LIMIT_SECONDS, chargeOnce, usedSeconds } from '../lib/usage.js'

// 클라우드 전사 (07-m5 §3, F9)
// 업로드는 Vercel Blob 직접 업로드(4.5MB body 제한 대응) — 여기서는 토큰만 발급.
// 서버 무저장: Blob은 완료·실패 즉시 삭제, 결과는 응답으로만 전달.
export const cloudTranscribe = new Hono<{ Variables: { otid: string } }>()

cloudTranscribe.use('*', async (c, next) => {
  const auth = c.req.header('Authorization') ?? ''
  const token = auth.startsWith('Bearer ') ? auth.slice(7) : ''
  const otid = token ? verifySessionToken(token) : null
  if (!otid) return c.json({ error: 'unauthorized' }, 401)
  c.set('otid', otid)
  await next()
})

// POST /v1/cloud/upload-token { fileName } → { token, pathname }
cloudTranscribe.post('/upload-token', async (c) => {
  const rw = process.env.BLOB_READ_WRITE_TOKEN
  if (!rw) return c.json({ error: 'blob store is not configured' }, 500)

  const { fileName } = await c.req.json<{ fileName?: string }>()
  const pathname = `audio/${crypto.randomUUID()}-${fileName ?? 'audio.m4a'}`
  const token = await generateClientTokenFromReadWriteToken({
    token: rw,
    pathname,
    validUntil: Date.now() + 60 * 60 * 1000,
    maximumSizeInBytes: 300 * 1024 * 1024,
    allowedContentTypes: ['audio/mp4', 'audio/m4a', 'audio/x-m4a'],
  })
  return c.json({ token, pathname })
})

// POST /v1/cloud/transcribe { blobUrl, durationSec } → { jobId }
cloudTranscribe.post('/', async (c) => {
  const { blobUrl, durationSec } = await c.req.json<{ blobUrl?: string; durationSec?: number }>()
  if (!blobUrl || !durationSec) {
    return c.json({ error: 'blobUrl and durationSec are required' }, 400)
  }

  // 사용량 선검증 (F8-3): 잔여 < duration → 402
  try {
    const used = await usedSeconds(c.get('otid'))
    if (MONTHLY_LIMIT_SECONDS - used < durationSec) {
      return c.json({ error: 'monthly quota exceeded' }, 402)
    }
  } catch (e) {
    return c.json({ error: e instanceof Error ? e.message : 'usage check failed' }, 500)
  }

  const audio = await fetch(blobUrl)
  if (!audio.ok) return c.json({ error: 'audio fetch failed' }, 400)

  try {
    const jobId = await submitTranscription(await audio.arrayBuffer(), 'meeting.m4a')
    return c.json({ jobId })
  } catch (e) {
    const message = e instanceof Error ? e.message : 'transcribe submit failed'
    return c.json({ error: message }, message.includes('not configured') ? 500 : 502)
  }
})

// GET /v1/cloud/transcribe/:jobId?blobUrl=&durationSec=
// → { status, utterances? } — 완료 시 사용량 차감 + Blob 삭제 (무상태 유지를 위해 쿼리로 전달)
cloudTranscribe.get('/:jobId', async (c) => {
  const jobId = c.req.param('jobId')
  const blobUrl = c.req.query('blobUrl')
  const durationSec = Number(c.req.query('durationSec') ?? 0)

  let result
  try {
    result = await pollTranscription(jobId)
  } catch (e) {
    return c.json({ error: e instanceof Error ? e.message : 'poll failed' }, 502)
  }

  if (result.status === 'completed' || result.status === 'failed') {
    if (blobUrl) await del(blobUrl).catch(() => {})
    if (result.status === 'completed' && durationSec > 0) {
      await chargeOnce(c.get('otid'), jobId, durationSec).catch(() => {})
    }
  }
  return c.json(result)
})
