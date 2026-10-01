import { NextResponse } from 'next/server'
import { query } from '@/lib/db'
import { boardBus } from '@/lib/boardBus'

export const dynamic = 'force-dynamic'

type Cell = { slot: number; title: string; content: string; color: string }

export async function GET() {
  try {
    const cells = await query<Cell>(
      'SELECT slot, title, content, color FROM quick_stick_cells ORDER BY slot'
    )
    return NextResponse.json({ cells })
  } catch (err) {
    console.error('GET /api/board failed:', err)
    return NextResponse.json({ error: 'board unavailable' }, { status: 502 })
  }
}

export async function PUT(req: Request) {
  let body: unknown
  try {
    body = await req.json()
  } catch {
    return NextResponse.json({ error: 'Invalid JSON body' }, { status: 400 })
  }

  const { cells, client } = (body ?? {}) as { cells?: unknown; client?: unknown }
  if (!Array.isArray(cells) || cells.length === 0 || cells.length > 12) {
    return NextResponse.json({ error: 'Invalid cells' }, { status: 400 })
  }

  for (const c of cells) {
    const { slot, title, content, color } = c as Record<string, unknown>
    if (!Number.isInteger(slot) || (slot as number) < 0 || (slot as number) > 11) {
      return NextResponse.json({ error: 'Invalid slot' }, { status: 400 })
    }
    if (typeof title !== 'string' || typeof content !== 'string' || typeof color !== 'string') {
      return NextResponse.json({ error: 'Invalid cell fields' }, { status: 400 })
    }
  }

  const rows = cells as Cell[]
  const values: unknown[] = []
  const tuples = rows.map((c, i) => {
    const n = i * 4
    values.push(c.slot, c.title, c.content, c.color)
    return `($${n + 1}, $${n + 2}, $${n + 3}, $${n + 4})`
  })

  const sql = `
    INSERT INTO quick_stick_cells (slot, title, content, color)
    VALUES ${tuples.join(', ')}
    ON CONFLICT (slot) DO UPDATE SET
      title = EXCLUDED.title,
      content = EXCLUDED.content,
      color = EXCLUDED.color,
      updated_at = now()
  `

  try {
    await query(sql, values)
    boardBus.emit('board', { client: typeof client === 'string' ? client : null, cells: rows })
    return NextResponse.json({ ok: true })
  } catch (err) {
    console.error('PUT /api/board failed:', err)
    return NextResponse.json({ error: 'board unavailable' }, { status: 502 })
  }
}
