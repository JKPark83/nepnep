import { Environment, SignedDataVerifier } from '@apple/app-store-server-library'

// App Store 구독 JWS 검증 (07-m5 §1)
// 앱이 보낸 signedTransaction(JWS)을 Apple 루트 인증서 체인으로 검증한다.

const APPLE_ROOT_CA_URLS = [
  'https://www.apple.com/appleca/AppleIncRootCertificate.cer',
  'https://www.apple.com/certificateauthority/AppleRootCA-G2.cer',
  'https://www.apple.com/certificateauthority/AppleRootCA-G3.cer',
]

let cachedVerifier: SignedDataVerifier | null = null

async function verifier(): Promise<SignedDataVerifier> {
  if (cachedVerifier) return cachedVerifier

  const bundleId = process.env.APP_BUNDLE_ID ?? 'com.nepnep.NepNep'
  const isProduction = process.env.APPLE_ENVIRONMENT === 'Production'
  const appAppleId = process.env.APP_APPLE_ID ? Number(process.env.APP_APPLE_ID) : undefined

  const roots = await Promise.all(
    APPLE_ROOT_CA_URLS.map(async (url) => {
      const r = await fetch(url)
      if (!r.ok) throw new Error(`apple root ca fetch failed ${r.status}`)
      return Buffer.from(await r.arrayBuffer())
    }),
  )
  cachedVerifier = new SignedDataVerifier(
    roots,
    true,   // 온라인 폐기 확인
    isProduction ? Environment.PRODUCTION : Environment.SANDBOX,
    bundleId,
    appAppleId,
  )
  return cachedVerifier
}

export interface VerifiedSubscription {
  active: boolean
  originalTransactionId: string
  expiresAt: number | null   // epoch ms
}

export async function verifySignedTransaction(signedTransaction: string): Promise<VerifiedSubscription> {
  const v = await verifier()
  const t = await v.verifyAndDecodeTransaction(signedTransaction)
  const expiresAt = t.expiresDate ?? null
  const active =
    t.revocationDate == null && expiresAt != null && expiresAt > Date.now()
  return {
    active,
    originalTransactionId: String(t.originalTransactionId ?? ''),
    expiresAt,
  }
}
