// RTZR(VITO) STT — 인증(JWT 6h 캐시)·제출·폴링 (07-m5 §3)

const BASE = 'https://openapi.vito.ai'

let cachedToken: { token: string; expireAt: number } | null = null

async function accessToken(): Promise<string> {
  if (cachedToken && cachedToken.expireAt - 60_000 > Date.now()) {
    return cachedToken.token
  }
  const clientId = process.env.RTZR_CLIENT_ID
  const clientSecret = process.env.RTZR_CLIENT_SECRET
  if (!clientId || !clientSecret) throw new Error('rtzr is not configured')

  const form = new URLSearchParams({ client_id: clientId, client_secret: clientSecret })
  const r = await fetch(`${BASE}/v1/authenticate`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: form,
  })
  if (!r.ok) throw new Error(`rtzr auth failed ${r.status}`)
  const body = (await r.json()) as { access_token: string; expire_at: number }
  cachedToken = { token: body.access_token, expireAt: body.expire_at * 1000 }
  return body.access_token
}

/// 오디오 바이트 제출 → jobId. use_diarization로 화자분리까지 한 번에.
export async function submitTranscription(audio: ArrayBuffer, fileName: string): Promise<string> {
  const token = await accessToken()
  const config = {
    use_diarization: true,
    use_itn: true,
    use_disfluency_filter: false,
    use_profanity_filter: false,
    use_paragraph_splitter: false,
  }
  const form = new FormData()
  form.append('config', JSON.stringify(config))
  form.append('file', new Blob([audio], { type: 'audio/mp4' }), fileName)

  const r = await fetch(`${BASE}/v1/transcribe`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${token}` },
    body: form,
  })
  if (!r.ok) throw new Error(`rtzr submit failed ${r.status}: ${await r.text()}`)
  const body = (await r.json()) as { id: string }
  return body.id
}

export interface RTZRUtterance {
  start_at: number   // ms
  duration: number   // ms
  msg: string
  spk: number
}

export interface RTZRResult {
  status: 'registered' | 'transcribing' | 'completed' | 'failed'
  utterances?: RTZRUtterance[]
}

// RTZR 429 회피용 서버측 캐시 (warm 인스턴스 한정, 5s)
const pollCache = new Map<string, { at: number; result: RTZRResult }>()

export async function pollTranscription(jobId: string): Promise<RTZRResult> {
  const cached = pollCache.get(jobId)
  if (cached && Date.now() - cached.at < 5_000) return cached.result

  const token = await accessToken()
  const r = await fetch(`${BASE}/v1/transcribe/${jobId}`, {
    headers: { Authorization: `Bearer ${token}` },
  })
  if (!r.ok) throw new Error(`rtzr poll failed ${r.status}`)
  const body = (await r.json()) as {
    status: RTZRResult['status']
    results?: { utterances: RTZRUtterance[] }
  }
  const result: RTZRResult = { status: body.status, utterances: body.results?.utterances }
  pollCache.set(jobId, { at: Date.now(), result })
  return result
}
