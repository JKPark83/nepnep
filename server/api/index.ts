import { getRequestListener } from '@hono/node-server'
import app from '../src/index.js'

// Node 런타임 — getRequestListener가 fetch 핸들러를 Node (req, res) 리스너로 감싼다.
// (hono/vercel의 Edge용 handle은 Node에서 POST body 처리가 멈춘다)
export default getRequestListener(app.fetch)
