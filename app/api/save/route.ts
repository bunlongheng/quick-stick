import { NextResponse } from 'next/server'

const STICKIES_API = process.env.STICKIES_API_URL || 'http://localhost:4444'
const API_KEY = process.env.STICKIES_API_KEY || ''
const FOLDER = process.env.STICKIES_FOLDER || 'Quick'

// Proxies the grid to the Stickies batch endpoint. The key stays server-side.
export async function POST(req: Request) {
  if (!API_KEY) {
    return NextResponse.json({ error: 'STICKIES_API_KEY is not set' }, { status: 500 })
  }

  let body: unknown
  try {
    body = await req.json()
  } catch {
    return NextResponse.json({ error: 'Invalid JSON body' }, { status: 400 })
  }

  const notes = (body as { notes?: unknown })?.notes
  if (!Array.isArray(notes) || notes.length === 0) {
    return NextResponse.json({ error: 'Nothing to save' }, { status: 400 })
  }

  try {
    const res = await fetch(`${STICKIES_API}/api/stickies/ext`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${API_KEY}`,
      },
      body: JSON.stringify({
        batch: (notes as Record<string, unknown>[]).map(n => ({ ...n, folder: FOLDER })),
      }),
    })
    const data = await res.text()
    return new NextResponse(data, {
      status: res.status,
      headers: { 'Content-Type': 'application/json' },
    })
  } catch (err) {
    return NextResponse.json(
      { error: `Stickies unreachable at ${STICKIES_API}` },
      { status: 502 }
    )
  }
}
