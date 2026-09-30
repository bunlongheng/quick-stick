'use client'

import { useState, useEffect, useCallback } from 'react'

const PALETTE = [
  '#FF6B6B','#FF8F6B','#FFB84D','#FFE066','#E8EF7B','#6DDC8C',
  '#4DD9D2','#6CC4F0','#5EA3FF','#8B89E8','#C47EEA','#FF6B8A',
]

const LS_KEY = 'quick-stick'
const GRID_OPTIONS = [6, 9, 12] as const
type Sticky = { title: string; content: string; color: string }

function makeGrid(count: number): Sticky[] {
  return Array.from({ length: count }, (_, i) => ({
    title: '',
    content: '',
    color: PALETTE[i % PALETTE.length],
  }))
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
  const [stickies, setStickies] = useState<Sticky[]>(makeGrid(9))
  const [loaded, setLoaded] = useState(false)
  const [status, setStatus] = useState<'idle' | 'saving' | 'saved' | 'error'>('idle')
  const [message, setMessage] = useState('')

  // Load from localStorage on mount
  useEffect(() => {
    const saved = loadFromStorage()
    if (saved) {
      setCount(saved.count as 6 | 9 | 12)
      setStickies(saved.stickies)
    }
    setLoaded(true)
  }, [])

  // Write through on every keystroke. A debounce here only bought a window
  // in which a reload or crash lost what was typed.
  useEffect(() => {
    if (!loaded) return
    saveToStorage(count, stickies)
  }, [stickies, count, loaded])

  const changeGrid = useCallback((n: 6 | 9 | 12) => {
    setCount(n)
    setStickies(prev => {
      if (n > prev.length) return [...prev, ...makeGrid(n - prev.length).map((s, i) => ({ ...s, color: PALETTE[(prev.length + i) % PALETTE.length] }))]
      return prev.slice(0, n)
    })
  }, [])

  const update = useCallback((i: number, field: 'title' | 'content', value: string) => {
    setStickies(prev => prev.map((s, idx) => idx === i ? { ...s, [field]: value } : s))
  }, [])

  // Send every filled cell to Stickies in one batch, then clear the grid.
  const send = useCallback(async () => {
    const notes = stickies
      .map(s => ({ title: s.title.trim(), content: s.content.trim(), color: s.color }))
      .filter(s => s.title || s.content)
      .map(s => ({
        type: 'note',
        title: s.title || s.content.split('\n')[0].slice(0, 60),
        content: s.content || s.title,
        color: s.color,
      }))

    if (notes.length === 0) {
      setStatus('error')
      setMessage('nothing to save')
      return
    }

    setStatus('saving')
    setMessage('')
    try {
      const res = await fetch('/api/save', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ notes }),
      })
      const data = await res.json().catch(() => null)
      if (!res.ok) throw new Error(data?.error || `save failed (${res.status})`)

      const failed = Array.isArray(data?.results)
        ? data.results.filter((r: { error?: string }) => r?.error).length
        : 0
      setStatus(failed ? 'error' : 'saved')
      setMessage(failed ? `${notes.length - failed}/${notes.length} saved` : `${notes.length} saved`)
      if (!failed) {
        setStickies(makeGrid(count))
        localStorage.removeItem(LS_KEY)
      }
    } catch (err) {
      setStatus('error')
      setMessage(err instanceof Error ? err.message : 'save failed')
    }
  }, [stickies, count])

  // Cmd/Ctrl+Enter saves from anywhere in the grid.
  useEffect(() => {
    const handler = (e: KeyboardEvent) => {
      if ((e.metaKey || e.ctrlKey) && e.key === 'Enter') { e.preventDefault(); send() }
    }
    window.addEventListener('keydown', handler)
    return () => window.removeEventListener('keydown', handler)
  }, [send])

  // Clear the status line a moment after it lands.
  useEffect(() => {
    if (status !== 'saved' && status !== 'error') return
    const t = setTimeout(() => { setStatus('idle'); setMessage('') }, 2500)
    return () => clearTimeout(t)
  }, [status])

  const cols = count === 6 ? 3 : count === 9 ? 3 : 4
  const rows = Math.ceil(count / cols)

  return (
    <div className="h-screen w-screen overflow-hidden relative">
      <div
        className="w-full h-full"
        style={{ display: 'grid', gridTemplateColumns: `repeat(${cols}, 1fr)`, gridTemplateRows: `repeat(${rows}, 1fr)` }}
      >
        {stickies.map((s, i) => (
          <div
            key={i}
            className="p-3 sm:p-4 flex flex-col gap-1 transition-opacity hover:opacity-95"
            style={{ backgroundColor: s.color, filter: 'brightness(0.7)' }}
          >
            <input
              type="text"
              placeholder=""
              value={s.title}
              onChange={e => update(i, 'title', e.target.value)}
              onKeyDown={e => { if (e.key === 'Enter') { e.preventDefault(); (e.currentTarget.nextElementSibling as HTMLTextAreaElement)?.focus() } }}
              className="bg-transparent border-none outline-none text-base sm:text-lg font-semibold w-full"
              style={{ color: '#000' }}
            />
            <textarea
              placeholder=""
              value={s.content}
              onChange={e => update(i, 'content', e.target.value)}
              className="sticky-scroll bg-transparent border-none outline-none text-base leading-relaxed flex-1 w-full resize-none"
              style={{ color: '#000' }}
            />
          </div>
        ))}
      </div>

      <div className="absolute bottom-3 left-1/2 -translate-x-1/2 flex items-center gap-3 bg-black/60 backdrop-blur-sm rounded-full px-4 py-1.5">
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

        <div className="w-px h-4 bg-white/20" />

        <button
          onClick={send}
          disabled={status === 'saving'}
          className="px-3 py-0.5 text-xs rounded-full text-white/70 hover:text-white hover:bg-white/10 disabled:opacity-40 transition-colors"
        >
          {status === 'saving' ? 'saving' : 'save'}
        </button>

        {message && (
          <span className={`text-xs ${status === 'error' ? 'text-red-400' : 'text-emerald-400'}`}>
            {message}
          </span>
        )}
      </div>
    </div>
  )
}
