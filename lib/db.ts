import { Pool } from 'pg'

// Cached on globalThis so Next dev HMR does not leak a new pool on every reload.
const globalForDb = globalThis as unknown as { pgPool?: Pool }

const pool =
  globalForDb.pgPool ??
  new Pool({
    connectionString: process.env.DATABASE_URL,
    ssl: { rejectUnauthorized: false },
  })

if (process.env.NODE_ENV !== 'production') {
  globalForDb.pgPool = pool
}

export async function query<T>(sql: string, params?: unknown[]): Promise<T[]> {
  const res = await pool.query(sql, params)
  return res.rows as T[]
}
