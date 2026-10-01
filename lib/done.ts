// A done line carries an invisible mark at its start, so the text a user
// sees is the text they typed. Lines that still begin with the old visible
// check are read as done and rewritten to the mark the first time they pass.
export const DONE = '\u200B'
const OLD = '\u2713 '

export function isDone(line: string): boolean {
  return line.startsWith(DONE)
}

export function normalizeDone(text: string): string {
  if (!text.includes(OLD)) return text
  return text
    .split('\n')
    .map(l => (l.startsWith(OLD) ? DONE + l.slice(OLD.length) : l))
    .join('\n')
}

// Cmd+D. The lines under the selection (or the caret's line) go to the
// bottom, struck; a later batch stacks above an earlier one, so the first
// thing finished stays lowest. If every touched line is already done the
// same press undoes it, in place.
export function toggleDone(text: string, selStart: number, selEnd: number): { text: string; caret: number } {
  const lines = text.split('\n')
  const touched = new Set<number>()
  let pos = 0
  lines.forEach((line, i) => {
    const end = pos + line.length
    if (selStart <= end && selEnd >= pos) touched.add(i)
    pos = end + 1
  })
  if (touched.size === 0) return { text, caret: selStart }

  const picked = [...touched].map(i => lines[i])
  if (picked.every(isDone)) {
    const out = lines.map((l, i) => (touched.has(i) ? l.slice(DONE.length) : l))
    return { text: out.join('\n'), caret: Math.max(0, selStart - DONE.length) }
  }

  const open: string[] = []
  const done: string[] = []
  lines.forEach((l, i) => {
    if (touched.has(i)) return
    ;(isDone(l) ? done : open).push(l)
  })
  while (open.length && open[open.length - 1].trim() === '') open.pop()
  const fresh = picked.map(l => (isDone(l) ? l : DONE + l))
  const out = [...open, ...fresh, ...done]
  const caret = [...open, fresh[0]].join('\n').length
  return { text: out.join('\n'), caret }
}
