import os
import sqlite3
from datetime import datetime, timezone
from typing import Any, Iterable

from fastapi import Depends, FastAPI, Header, HTTPException, status
from pydantic import BaseModel

app = FastAPI(title="Tier Monitor Self-Hosted Sync")

DB_PATH = os.getenv("DB_PATH", "data.db")


def _verify_token(x_api_token: str | None = Header(default=None)) -> None:
    expected = os.getenv("API_TOKEN")
    if expected and x_api_token != expected:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid API token",
        )


def _utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


def _get_conn() -> sqlite3.Connection:
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    return conn


def _init_db() -> None:
    db_dir = os.path.dirname(DB_PATH)
    if db_dir:
        os.makedirs(db_dir, exist_ok=True)
    conn = _get_conn()
    cur = conn.cursor()
    cur.execute(
        """
        CREATE TABLE IF NOT EXISTS tierdoku (
            uuid TEXT PRIMARY KEY,
            deleted_at TEXT,
            stallname TEXT,
            bucht TEXT,
            symptome TEXT,
            medikament TEXT,
            farbe TEXT,
            comment TEXT,
            date TEXT,
            second_medikament TEXT,
            second_comment TEXT,
            second_date TEXT,
            third_medikament TEXT,
            third_comment TEXT,
            third_date TEXT,
            end_comment TEXT,
            end_date TEXT,
            last_modified TEXT
        )
        """
    )
    cur.execute(
        """
        CREATE TABLE IF NOT EXISTS tierbewegungen (
            uuid TEXT PRIMARY KEY,
            deleted_at TEXT,
            stallname TEXT,
            anzahl INTEGER,
            zugang_abgang TEXT,
            comment TEXT,
            date TEXT,
            end TEXT,
            last_modified TEXT
        )
        """
    )
    cur.execute(
        """
        CREATE TABLE IF NOT EXISTS meta (
            key TEXT PRIMARY KEY,
            value TEXT
        )
        """
    )
    conn.commit()
    _ensure_column(conn, "tierdoku", "deleted_at", "TEXT")
    _ensure_column(conn, "tierbewegungen", "deleted_at", "TEXT")
    conn.close()


def _ensure_column(conn: sqlite3.Connection, table: str, column: str, col_type: str) -> None:
    cur = conn.cursor()
    cur.execute(f"PRAGMA table_info({table})")
    existing = {row["name"] for row in cur.fetchall()}
    if column in existing:
        return
    cur.execute(f"ALTER TABLE {table} ADD COLUMN {column} {col_type}")
    conn.commit()


_init_db()


class TierDokuRow(BaseModel):
    uuid: str
    last_modified: str
    deleted_at: str | None = None
    stallname: str | None = None
    bucht: str | None = None
    symptome: str | None = None
    medikament: str | None = None
    farbe: str | None = None
    comment: str | None = None
    date: str | None = None
    second_medikament: str | None = None
    second_comment: str | None = None
    second_date: str | None = None
    third_medikament: str | None = None
    third_comment: str | None = None
    third_date: str | None = None
    end_comment: str | None = None
    end_date: str | None = None


class TierBewegungRow(BaseModel):
    uuid: str
    last_modified: str
    deleted_at: str | None = None
    stallname: str | None = None
    anzahl: int | None = None
    zugang_abgang: str | None = None
    comment: str | None = None
    date: str | None = None
    end: str | None = None


class SyncUpload(BaseModel):
    device_name: str | None = None
    tierdoku: list[TierDokuRow]
    tierbewegungen: list[TierBewegungRow]


def _max_date(conn: sqlite3.Connection, table: str) -> str | None:
    cur = conn.cursor()
    cur.execute(f"SELECT MAX(date) AS max_date FROM {table} WHERE deleted_at IS NULL")
    row = cur.fetchone()
    return row["max_date"] if row else None


def _get_meta(conn: sqlite3.Connection, key: str) -> str | None:
    cur = conn.cursor()
    cur.execute("SELECT value FROM meta WHERE key = ?", (key,))
    row = cur.fetchone()
    return row["value"] if row else None


def _set_meta(conn: sqlite3.Connection, key: str, value: str) -> None:
    cur = conn.cursor()
    cur.execute(
        "INSERT INTO meta (key, value) VALUES (?, ?) "
        "ON CONFLICT(key) DO UPDATE SET value=excluded.value",
        (key, value),
    )


def _summary(conn: sqlite3.Connection) -> dict[str, Any]:
    return {
        "last_upload_at": _get_meta(conn, "last_upload_at"),
        "max_date_tierdoku": _max_date(conn, "tierdoku"),
        "max_date_tierbewegungen": _max_date(conn, "tierbewegungen"),
    }


def _insert_rows(
    conn: sqlite3.Connection,
    table: str,
    rows: Iterable[BaseModel],
) -> None:
    if table == "tierdoku":
        cols = (
            "uuid",
            "deleted_at",
            "stallname",
            "bucht",
            "symptome",
            "medikament",
            "farbe",
            "comment",
            "date",
            "second_medikament",
            "second_comment",
            "second_date",
            "third_medikament",
            "third_comment",
            "third_date",
            "end_comment",
            "end_date",
            "last_modified",
        )
    else:
        cols = (
            "uuid",
            "deleted_at",
            "stallname",
            "anzahl",
            "zugang_abgang",
            "comment",
            "date",
            "end",
            "last_modified",
        )
    placeholders = ",".join(["?"] * len(cols))
    sql = f"INSERT OR REPLACE INTO {table} ({','.join(cols)}) VALUES ({placeholders})"
    cur = conn.cursor()
    for row in rows:
        values = [getattr(row, col) for col in cols]
        cur.execute(sql, values)


@app.get("/health", dependencies=[Depends(_verify_token)])
async def health() -> dict[str, str]:
    return {"status": "ok"}


@app.get("/sync/summary", dependencies=[Depends(_verify_token)])
async def sync_summary() -> dict[str, Any]:
    conn = _get_conn()
    try:
        return _summary(conn)
    finally:
        conn.close()


@app.post("/sync/upload", dependencies=[Depends(_verify_token)])
async def sync_upload(payload: SyncUpload) -> dict[str, Any]:
    conn = _get_conn()
    try:
        cur = conn.cursor()
        cur.execute("DELETE FROM tierdoku")
        cur.execute("DELETE FROM tierbewegungen")
        _insert_rows(conn, "tierdoku", payload.tierdoku)
        _insert_rows(conn, "tierbewegungen", payload.tierbewegungen)
        _set_meta(conn, "last_upload_at", _utc_now())
        conn.commit()
        return _summary(conn)
    finally:
        conn.close()


@app.get("/sync/download", dependencies=[Depends(_verify_token)])
async def sync_download() -> dict[str, Any]:
    conn = _get_conn()
    try:
        cur = conn.cursor()
        cur.execute("SELECT * FROM tierdoku")
        tierdoku = [dict(row) for row in cur.fetchall()]
        cur.execute("SELECT * FROM tierbewegungen")
        tierbewegungen = [dict(row) for row in cur.fetchall()]
        return {
            "tierdoku": tierdoku,
            "tierbewegungen": tierbewegungen,
            **_summary(conn),
        }
    finally:
        conn.close()
