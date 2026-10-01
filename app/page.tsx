'use client'

import { useState, useEffect, useCallback, useRef } from 'react'

const PALETTE = [
  '#FF6B6B','#FF8F6B','#FFB84D','#FFE066','#E8EF7B','#6DDC8C',
  '#4DD9D2','#6CC4F0','#5EA3FF','#8B89E8','#C47EEA','#FF6B8A',
]

const LS_KEY = 'quick-stick'
const GRID_OPTIONS = [6, 9, 12] as const
const MAX = 12
type Sticky = { title: string; content: string; color: string }

// Always 12 cells. Showing 6 hides the last 6, it never drops them.
function makeGrid(count: number = MAX): Sticky[] {
  return Array.from({ length: count }, (_, i) => ({
    title: '',
    content: '',
    color: PALETTE[i % PALETTE.length],
  }))
}

// Older drafts were stored trimmed to the visible count. Pad them back to 12.
function padGrid(stickies: Sticky[]): Sticky[] {
  const blank = makeGrid()
  return blank.map((b, i) => stickies[i] ?? b)
}

type RemoteCell = { slot: number; title: string; content: string; color: string }

// Slots missing from the table stay blank with the palette color for that index.
function gridFromCells(cells: RemoteCell[]): Sticky[] {
  const grid = makeGrid()
  for (const c of cells) {
    if (c.slot >= 0 && c.slot < MAX) {
      grid[c.slot] = { title: c.title, content: c.content, color: c.color }
    }
  }
  return grid
}

function loadFromStorage(): { count: 6 | 9 | 12; stickies: Sticky[] } | null {
  try {
    const raw = localStorage.getItem(LS_KEY)
    if (!raw) return null
    const data = JSON.parse(raw)
    if (data?.stickies?.length) return data
  } catch {}
  return null
}

function saveToStorage(count: number, stickies: Sticky[]) {
  localStorage.setItem(LS_KEY, JSON.stringify({ count, stickies }))
}

export default function QuickCreate() {
  const [count, setCount] = useState<6 | 9 | 12>(9)
  const [stickies, setStickies] = useState<Sticky[]>(makeGrid())
  const [loaded, setLoaded] = useState(false)
  const [settingsOpen, setSettingsOpen] = useState(false)
  const [saving, setSaving] = useState(false)
  const [offline, setOffline] = useState(false)
  const bodyRefs = useRef<(HTMLTextAreaElement | null)[]>([])

  // Load from localStorage on mount. An empty board is fine if there is no draft yet.
  useEffect(() => {
    const saved = loadFromStorage()
    if (saved) {
      setCount(saved.count as 6 | 9 | 12)
      setStickies(padGrid(saved.stickies))
    }
    setLoaded(true)
  }, [])

  // Write through on every keystroke. A debounce here only bought a window
  // in which a reload or crash lost what was typed.
  useEffect(() => {
    if (!loaded) return
    saveToStorage(count, stickies)
  }, [stickies, count, loaded])

  // The table is the source of truth. Fetch it once on mount and override
  // the localStorage paint if it has anything. remoteLoaded gates the
  // write-through PUT below so this initial load never PUTs back, and
  // suppressSync skips the one stickies-change this fetch itself causes.
  const remoteLoaded = useRef(false)
  const suppressSync = useRef(false)
  const boardRef = useRef(stickies)
  boardRef.current = stickies

  useEffect(() => {
    let cancelled = false
    fetch('/api/board', { cache: 'no-store' })
      .then(res => {
        if (!res.ok) throw new Error('bad status')
        return res.json() as Promise<{ cells?: RemoteCell[] }>
      })
      .then(data => {
        if (cancelled) return
        setOffline(false)
        if (data.cells && data.cells.length > 0) {
          suppressSync.current = true
          setStickies(gridFromCells(data.cells))
        }
      })
      .catch(() => {
        if (!cancelled) setOffline(true)
      })
      .finally(() => {
        if (!cancelled) remoteLoaded.current = true
      })
    return () => {
      cancelled = true
    }
  }, [])

  // Only 1 PUT in flight at a time; a change that lands mid-PUT sends 1 more
  // once it finishes, always with the latest board.
  const putInFlight = useRef(false)
  const putPending = useRef(false)
  // Typed here and not yet written. A remote board is not applied over it.
  const dirty = useRef(false)
  const clientId = useRef(Math.random().toString(36).slice(2))

  const pushBoard = useCallback(() => {
    if (putInFlight.current) {
      putPending.current = true
      return
    }
    putInFlight.current = true
    setSaving(true)
    const cells = boardRef.current.map((s, slot) => ({ slot, title: s.title, content: s.content, color: s.color }))
    fetch('/api/board', {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ cells, client: clientId.current }),
    })
      .then(res => {
        if (!res.ok) throw new Error('bad status')
        setOffline(false)
      })
      .catch(() => setOffline(true))
      .finally(() => {
        putInFlight.current = false
        setSaving(false)
        if (putPending.current) {
          putPending.current = false
          pushBoard()
        } else {
          dirty.current = false
        }
      })
  }, [])

  // Debounced write-through to the table, once the initial server load is done.
  useEffect(() => {
    if (!remoteLoaded.current) return
    if (suppressSync.current) {
      suppressSync.current = false
      return
    }
    dirty.current = true
    const t = setTimeout(() => pushBoard(), 120)
    return () => clearTimeout(t)
  }, [stickies, pushBoard])

  // Live updates. Whatever another client writes lands here the moment the
  // table has it. Our own writes come back too and are ignored by id, and a
  // board with unsaved typing in it is left alone - the write wins.
  useEffect(() => {
    const es = new EventSource('/api/board/stream')
    es.onmessage = e => {
      let event: { client?: string | null; cells?: RemoteCell[] }
      try { event = JSON.parse(e.data) } catch { return }
      if (event.client === clientId.current || !event.cells?.length) return
      if (!remoteLoaded.current || dirty.current || putInFlight.current) return
      suppressSync.current = true
      setStickies(gridFromCells(event.cells))
    }
    return () => es.close()
  }, [])

  // Only changes how many cells are on screen. Anything typed into a cell
  // that scrolls out of view stays in state and comes back with it.
  const changeGrid = useCallback((n: 6 | 9 | 12) => setCount(n), [])

  const update = useCallback((i: number, field: 'title' | 'content', value: string) => {
    setStickies(prev => prev.map((s, idx) => idx === i ? { ...s, [field]: value } : s))
  }, [])

  // ── Drag to move ────────────────────────────────────────────────────────
  // No handle and no icon. A press on a field you are already editing is left
  // alone so text selection still works; anywhere else, moving past a small
  // threshold picks the sticky up. Colours belong to the slot, so only the
  // written content moves.
  const press = useRef<{ i: number; x: number; y: number } | null>(null)
  const [dragFrom, setDragFrom] = useState<number | null>(null)
  const [dragOver, setDragOver] = useState<number | null>(null)

  const onCellPointerDown = useCallback((i: number) => (e: React.PointerEvent) => {
    const t = e.target as HTMLElement
    const editing = (t.tagName === 'INPUT' || t.tagName === 'TEXTAREA') && document.activeElement === t
    if (editing || e.button !== 0) return
    press.current = { i, x: e.clientX, y: e.clientY }
  }, [])

  useEffect(() => {
    const cellAt = (x: number, y: number) => {
      const el = document.elementFromPoint(x, y)?.closest('[data-cell]')
      const n = el ? Number((el as HTMLElement).dataset.cell) : NaN
      return Number.isInteger(n) ? n : null
    }

    const onMove = (e: PointerEvent) => {
      const p = press.current
      if (!p) return
      if (dragFrom === null) {
        if (Math.hypot(e.clientX - p.x, e.clientY - p.y) < 8) return
        ;(document.activeElement as HTMLElement | null)?.blur()
        setDragFrom(p.i)
      }
      setDragOver(cellAt(e.clientX, e.clientY))
    }

    const onUp = (e: PointerEvent) => {
      const from = dragFrom
      press.current = null
      setDragFrom(null)
      setDragOver(null)
      if (from === null) return
      const to = cellAt(e.clientX, e.clientY)
      if (to === null || to === from) return
      // Swap what is written; each slot keeps its own colour.
      setStickies(prev => {
        const next = [...prev]
        const a = next[from], b = next[to]
        next[from] = { ...a, title: b.title, content: b.content }
        next[to] = { ...b, title: a.title, content: a.content }
        return next
      })
    }

    window.addEventListener('pointermove', onMove)
    window.addEventListener('pointerup', onUp)
    window.addEventListener('pointercancel', onUp)
    return () => {
      window.removeEventListener('pointermove', onMove)
      window.removeEventListener('pointerup', onUp)
      window.removeEventListener('pointercancel', onUp)
    }
  }, [dragFrom])

  // Escape puts the corner away.
  useEffect(() => {
    const handler = (e: KeyboardEvent) => {
      if (e.key === 'Escape') setSettingsOpen(false)
    }
    window.addEventListener('keydown', handler)
    return () => window.removeEventListener('keydown', handler)
  }, [])

  // Content sitting in cells that are currently hidden.
  const hidden = stickies.slice(count).filter(s => s.title.trim() || s.content.trim()).length

  const cols = count === 6 ? 3 : count === 9 ? 3 : 4
  const rows = Math.ceil(count / cols)

  return (
    <div className={`h-screen w-screen overflow-hidden relative ${dragFrom !== null ? 'select-none' : ''}`}>
      <div
        className="w-full h-full"
        style={{ display: 'grid', gridTemplateColumns: `repeat(${cols}, 1fr)`, gridTemplateRows: `repeat(${rows}, 1fr)` }}
      >
        {stickies.slice(0, count).map((s, i) => (
          <div
            key={i}
            data-cell={i}
            onPointerDown={onCellPointerDown(i)}
            className={`sticky-cell p-3 sm:p-4 flex flex-col gap-2 ${
              dragFrom === i ? 'is-dragging' : ''
            } ${dragOver === i && dragFrom !== null && dragFrom !== i ? 'is-target' : ''}`}
            style={{ backgroundColor: s.color, filter: 'brightness(0.7)' }}
          >
            <div className={`sticky-rule pb-1.5 ${!s.title.trim() && !s.content.trim() ? 'is-blank' : ''}`}>
              <input
                type="text"
                aria-label={`Title, note ${i + 1}`}
                value={s.title}
                onChange={e => update(i, 'title', e.target.value)}
                onKeyDown={e => { if (e.key === 'Enter') { e.preventDefault(); bodyRefs.current[i]?.focus() } }}
                className="sticky-title bg-transparent border-none outline-none w-full"
                style={{ color: '#000' }}
              />
            </div>
            <textarea
              ref={el => { bodyRefs.current[i] = el }}
              aria-label={`Body, note ${i + 1}`}
              value={s.content}
              onChange={e => update(i, 'content', e.target.value)}
              className="sticky-body sticky-scroll bg-transparent border-none outline-none flex-1 w-full resize-none"
              style={{ color: '#000' }}
            />
          </div>
        ))}
      </div>

      {/* ── Settings ──────────────────────────────────────────────────────
          The grid is the interface. Everything else is one hairline disc in
          the corner, drawn in the same ink as the rules inside the cells, so
          it sits in the colour rather than on top of it. Press it and the
          sizes come out; press it again and the board is bare. */}
      <div className="absolute bottom-3 right-3 flex items-center gap-2">
        {settingsOpen && (
          <div className="qs-panel flex items-center gap-3 bg-black/60 backdrop-blur-sm rounded-full px-3 py-1.5">
            <div className="flex gap-1">
              {GRID_OPTIONS.map(n => (
                <button
                  key={n}
                  onClick={() => changeGrid(n)}
                  className={`px-2.5 py-0.5 text-xs rounded-full transition-colors ${
                    count === n ? 'bg-white/20 text-white' : 'text-white/40 hover:text-white/60'
                  }`}
                >
                  {n}
                </button>
              ))}
            </div>

            {hidden > 0 && (
              <div className="w-px h-4 bg-white/20" />
            )}

            {hidden > 0 && (
              <span className="text-xs text-white/30" title={`${hidden} filled note${hidden > 1 ? 's' : ''} hidden - switch to 12 to see ${hidden > 1 ? 'them' : 'it'}`}>
                {hidden} hidden
              </span>
            )}
          </div>
        )}

        {(offline || saving) && (
          <span aria-hidden="true" className={`qs-status-dot ${offline ? 'is-offline' : 'is-saving'}`} />
        )}

        <button
          onClick={() => setSettingsOpen(o => !o)}
          aria-label="Settings"
          aria-expanded={settingsOpen}
          className={`qs-cog ${settingsOpen ? 'is-open' : ''}`}
        />
      </div>
    </div>
  )
}
