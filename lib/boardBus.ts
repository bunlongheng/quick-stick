import { EventEmitter } from 'node:events'

// One emitter per server process, kept on globalThis so dev HMR and separate
// route bundles all share it. A PUT emits; every open stream forwards it.
const g = globalThis as unknown as { boardBus?: EventEmitter }
export const boardBus = g.boardBus ?? (g.boardBus = new EventEmitter())
boardBus.setMaxListeners(100)
