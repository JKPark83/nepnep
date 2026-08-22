// 월 사용량 카운터 (07-m5 §4)
// Upstash Redis REST (Vercel Marketplace) — KV에는 사용량 숫자만 저장한다.
// 키: usage:{originalTransactionID}:{yyyy-MM} (UTC)

export const MONTHLY_LIMIT_SECONDS = 20 * 3600

function redisConfig(): { url: string; token: string } {
  const url = process.env.KV_REST_API_URL ?? process.env.UPSTASH_REDIS_REST_URL
  const token = process.env.KV_REST_API_TOKEN ?? process.env.UPSTASH_REDIS_REST_TOKEN
  if (!url || !token) throw new Error('usage store is not configured')
  return { url, token }
}

async function redis(command: (string | number)[]): Promise<unknown> {
  const { url, token } = redisConfig()
  const r = await fetch(url, {
    method: 'POST',
    headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
    body: JSON.stringify(command),
  })
  if (!r.ok) throw new Error(`usage store error ${r.status}`)
  const body = (await r.json()) as { result?: unknown; error?: string }
  if (body.error) throw new Error(body.error)
  return body.result
}

export function monthKey(now = new Date()): string {
  const y = now.getUTCFullYear()
  const m = String(now.getUTCMonth() + 1).padStart(2, '0')
  return `${y}-${m}`
}

function usageKey(otid: string, now = new Date()): string {
  return `usage:${otid}:${monthKey(now)}`
}

export async function usedSeconds(otid: string): Promise<number> {
  const v = await redis(['GET', usageKey(otid)])
  return v == null ? 0 : Number(v)
}

/// 완료 시 차감. jobId 가드로 같은 작업의 중복 차감을 막는다.
export async function chargeOnce(otid: string, jobId: string, seconds: number): Promise<void> {
  const guard = await redis(['SET', `charged:${jobId}`, '1', 'NX', 'EX', 7 * 24 * 3600])
  if (guard !== 'OK') return   // 이미 차감됨
  const key = usageKey(otid)
  await redis(['INCRBY', key, Math.ceil(seconds)])
  // 월 경계 이후 자연 소멸 (62일)
  await redis(['EXPIRE', key, 62 * 24 * 3600])
}
