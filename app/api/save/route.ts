import { NextResponse } from 'next/server'

const STICKIES_API = process.env.STICKIES_API_URL || 'http://localhost:4444'
const API_KEY = process.env.STICKIES_API_KEY || ''

export async function POST(req: Request) {
  const body = await req.json()
  const res = await fetch(`${STICKIES_API}/api/stickies/ext`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${API_KEY}`,
    },
    body: JSON.stringify(body),
  })
  const data = await res.text()
  return new NextResponse(data, {
    status: res.status,
    headers: { 'Content-Type': 'application/json' },
  })
}
