import { Hono } from 'hono'
import { verifySignedTransaction } from '../lib/appstore.js'
import { issueSessionToken } from '../lib/session.js'
import { MONTHLY_LIMIT_SECONDS, usedSeconds } from '../lib/usage.js'

// POST /v1/subscription/verify { signedTransaction }
// → { active, originalTransactionId, expiresAt, usedSeconds, limitSeconds, sessionToken }
// 검증 결과로 24h 세션 토큰을 발급해 클라우드 API 호출에 쓴다 (07-m5 §1).
export const subscription = new Hono()

subscription.post('/verify', async (c) => {
  const { signedTransaction } = await c.req.json<{ signedTransaction?: string }>()
  if (!signedTransaction) {
    return c.json({ error: 'signedTransaction is required' }, 400)
  }

  let verified
  try {
    verified = await verifySignedTransaction(signedTransaction)
  } catch (e) {
    const message = e instanceof Error ? e.message : 'verification failed'
    if (message.includes('not configured')) return c.json({ error: message }, 500)
    return c.json({ error: 'verification failed' }, 401)
  }

  if (!verified.active) {
    return c.json({ active: false })
  }

  let used = 0
  try {
    used = await usedSeconds(verified.originalTransactionId)
  } catch {
    // 사용량 스토어 미설정 시에도 구독 검증 자체는 성공시킨다
  }

  return c.json({
    active: true,
    originalTransactionId: verified.originalTransactionId,
    expiresAt: verified.expiresAt,
    usedSeconds: used,
    limitSeconds: MONTHLY_LIMIT_SECONDS,
    sessionToken: issueSessionToken(verified.originalTransactionId),
  })
})
