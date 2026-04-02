'use client'

import { useState, useEffect, useCallback } from 'react'

const PALETTE = [
  '#FF6B6B','#FF8F6B','#FFB84D','#FFE066','#E8EF7B','#6DDC8C',
  '#4DD9D2','#6CC4F0','#5EA3FF','#8B89E8','#C47EEA','#FF6B8A',
]

const GRID_OPTIONS = [6, 9, 12] as const
type Sticky = { title: string; content: string; color: string }

function makeGrid(count: number): Sticky[] {
  return Array.from({ length: count }, (_, i) => ({
    title: '',
    content: '',
    color: PALETTE[i % PALETTE.length],
  }))
}

export default function QuickCreate() {
  const [count, setCount] = useState<6 | 9 | 12>(9)
  const [stickies, setStickies] = useState<Sticky[]>(makeGrid(9))
  const [status, setStatus] = useState<'idle' | 'saving' | 'saved' | 'error'>('idle')

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

  const save = useCallback(async () => {
    const filled = stickies.filter(s => s.title.trim() || s.content.trim())
    if (!filled.length) return

    setStatus('saving')
    try {
      const batch = filled.map(s => ({
        type: 'note' as const,
        name: s.title.trim() || 'Untitled',
        content: s.content.trim() || s.title.trim(),
        folder: new Date().toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' }),
        color: s.color,
      }))
      const res = await fetch('/api/save', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ batch }),
      })
      if (!res.ok) { const t = await res.text(); console.error('Save failed:', res.status, t); throw new Error(t || `HTTP ${res.status}`) }
      setStatus('saved')
      setTimeout(() => {
        setStickies(makeGrid(count))
        setStatus('idle')
      }, 1500)
    } catch {
      setStatus('error')
      setTimeout(() => setStatus('idle'), 2000)
    }
  }, [stickies, count])

  useEffect(() => {
    const handler = (e: KeyboardEvent) => {
      if ((e.metaKey || e.ctrlKey) && e.key === 'Enter') { e.preventDefault(); save() }
    }
    window.addEventListener('keydown', handler)
    return () => window.removeEventListener('keydown', handler)
  }, [save])

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
              className="bg-transparent border-none outline-none text-sm sm:text-base font-semibold w-full"
              style={{ color: '#000' }}
            />
            <textarea
              placeholder=""
              value={s.content}
              onChange={e => update(i, 'content', e.target.value)}
              className="bg-transparent border-none outline-none text-xs sm:text-sm flex-1 w-full resize-none"
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
        {status === 'saved' && <span className="text-green-400 text-xs">Saved</span>}
        {status === 'error' && <span className="text-red-400 text-xs">Failed</span>}
        {status === 'saving' && <span className="text-white/40 text-xs">Saving...</span>}
        <span className="text-white/20 text-[10px]"><kbd className="px-1 py-0.5 bg-white/10 rounded">Cmd+Enter</kbd></span>
      </div>
    </div>
  )
}
