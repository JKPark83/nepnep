import { createHmac, timingSafeEqual } from 'node:crypto'

// 클라우드 API용 단기 세션 토큰 (07-m5 §1)
// 요청마다 Apple 검증을 반복하지 않기 위해 verify 성공 시 HMAC 토큰(24h)을 발급한다.
// 형식: base64url(otid.exp) + '.' + hmac

const TTL_MS = 24 * 60 * 60 * 1000

function secret(): string {
  const s = process.env.SESSION_SECRET
  if (!s) throw new Error('SESSION_SECRET is not configured')
  return s
}

function sign(payload: string): string {
  return createHmac('sha256', secret()).update(payload).digest('base64url')
}

export function issueSessionToken(originalTransactionId: string, now = Date.now()): string {
  const payload = Buffer.from(`${originalTransactionId}.${now + TTL_MS}`).toString('base64url')
  return `${payload}.${sign(payload)}`
}

/// 유효하면 originalTransactionId, 아니면 null
export function verifySessionToken(token: string, now = Date.now()): string | null {
  const dot = token.lastIndexOf('.')
  if (dot < 0) return null
  const payload = token.slice(0, dot)
  const mac = token.slice(dot + 1)
  const expected = sign(payload)
  if (mac.length !== expected.length) return null
  if (!timingSafeEqual(Buffer.from(mac), Buffer.from(expected))) return null

  const decoded = Buffer.from(payload, 'base64url').toString()
  const sep = decoded.lastIndexOf('.')
  if (sep < 0) return null
  const otid = decoded.slice(0, sep)
  const exp = Number(decoded.slice(sep + 1))
  if (!otid || !Number.isFinite(exp) || exp < now) return null
  return otid
}
