-- One row per grid slot (0-11). The board is the whole set, written as one upsert.
CREATE TABLE IF NOT EXISTS quick_stick_cells (
    slot        SMALLINT PRIMARY KEY CHECK (slot BETWEEN 0 AND 11),
    title       TEXT NOT NULL DEFAULT '',
    content     TEXT NOT NULL DEFAULT '',
    color       TEXT NOT NULL,
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
