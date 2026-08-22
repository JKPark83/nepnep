import { Hono } from 'hono'
import { verifySessionToken } from '../lib/session.js'

// POST /v1/cloud/summarize — Claude 프록시 (07-m5 §3)
// 요청: { transcript, meetingTypeName? } → 응답: FinalSummary와 동일 구조
// { oneLiner, keyPoints[], decisions[], actionItems[] } — actionItems는 '내용|담당자|기한'
export const cloudSummarize = new Hono()

const SUMMARY_TOOL = {
  name: 'final_summary',
  description: '회의 전사에서 최종 요약을 추출한다',
  input_schema: {
    type: 'object',
    properties: {
      oneLiner: { type: 'string', description: '회의 전체 한 줄 요약, 한국어 60자 이내' },
      keyPoints: {
        type: 'array', items: { type: 'string' },
        description: '주요 논의 불릿 3~6개, 한국어 한 문장씩',
      },
      decisions: {
        type: 'array', items: { type: 'string' },
        description: '결정사항 불릿, 없으면 빈 배열',
      },
      actionItems: {
        type: 'array', items: { type: 'string' },
        description: "할 일. '내용|담당자|기한' 형태, 담당자·기한을 모르면 빈칸",
      },
    },
    required: ['oneLiner', 'keyPoints', 'decisions', 'actionItems'],
  },
} as const

cloudSummarize.post('/', async (c) => {
  const auth = c.req.header('Authorization') ?? ''
  const token = auth.startsWith('Bearer ') ? auth.slice(7) : ''
  if (!token || !verifySessionToken(token)) return c.json({ error: 'unauthorized' }, 401)

  const apiKey = process.env.ANTHROPIC_API_KEY
  if (!apiKey) return c.json({ error: 'summarize is not configured' }, 500)

  const { transcript, meetingTypeName } = await c.req.json<{
    transcript?: string
    meetingTypeName?: string
  }>()
  if (!transcript) return c.json({ error: 'transcript is required' }, 400)

  const r = await fetch('https://api.anthropic.com/v1/messages', {
    method: 'POST',
    headers: {
      'x-api-key': apiKey,
      'anthropic-version': '2023-06-01',
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      model: 'claude-sonnet-5',
      max_tokens: 2000,
      tools: [SUMMARY_TOOL],
      tool_choice: { type: 'tool', name: 'final_summary' },
      messages: [
        {
          role: 'user',
          content:
            `다음은 ${meetingTypeName ?? '회의'} 녹음의 화자별 전사입니다. ` +
            `final_summary 도구로 한국어 요약을 작성하세요.\n\n${transcript}`,
        },
      ],
    }),
  })

  if (!r.ok) {
    return c.json({ error: `summarize failed ${r.status}` }, 502)
  }
  const body = (await r.json()) as {
    content: { type: string; input?: unknown }[]
  }
  const toolUse = body.content.find((b) => b.type === 'tool_use')
  if (!toolUse?.input) return c.json({ error: 'no summary produced' }, 502)
  return c.json(toolUse.input)
})
