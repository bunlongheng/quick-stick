import { boardBus } from '@/lib/boardBus'

export const dynamic = 'force-dynamic'

// Server-Sent Events. Every board write is pushed to every open client as one
// `data:` line; a comment every 15 s keeps idle connections from timing out.
export async function GET(req: Request) {
  const enc = new TextEncoder()
  const stream = new ReadableStream({
    start(controller) {
      const send = (event: unknown) => {
        try { controller.enqueue(enc.encode(`data: ${JSON.stringify(event)}\n\n`)) } catch {}
      }
      const ping = setInterval(() => {
        try { controller.enqueue(enc.encode(': ping\n\n')) } catch {}
      }, 15000)
      boardBus.on('board', send)
      req.signal.addEventListener('abort', () => {
        clearInterval(ping)
        boardBus.off('board', send)
        try { controller.close() } catch {}
      })
    },
  })
  return new Response(stream, {
    headers: {
      'Content-Type': 'text/event-stream',
      'Cache-Control': 'no-cache, no-transform',
      Connection: 'keep-alive',
    },
  })
}
