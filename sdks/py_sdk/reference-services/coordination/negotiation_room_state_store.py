# Copyright 2025 Rahul Rajaram
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

"""SQLite-backed state store for the NegotiationRoom reference service.

Implements the crash-recovery contract: proposals, votes, and decisions
survive process death. All writes are committed synchronously (WAL,
synchronous=FULL) before the RPC response is returned, so a kill after a
successful RPC leaves the row on disk. Startup replays rows into the
in-memory working set.
"""

import sqlite3
import time
from pathlib import Path
from typing import Dict, List, Optional, Tuple


def _connect(path: Path) -> sqlite3.Connection:
    path.parent.mkdir(parents=True, exist_ok=True)
    con = sqlite3.connect(str(path), timeout=30.0)
    con.execute("PRAGMA journal_mode=WAL")
    con.execute("PRAGMA synchronous=FULL")
    con.execute("PRAGMA busy_timeout=5000")
    return con


class NegotiationRoomStateStore:
    """Durable store for negotiation proposals, votes, and decisions."""

    def __init__(self, db_path: str):
        self.path = Path(db_path)
        con = _connect(self.path)
        try:
            con.execute(
                """
                CREATE TABLE IF NOT EXISTS nr_proposals (
                    artifact_id TEXT PRIMARY KEY,
                    proposal_blob BLOB NOT NULL,
                    created_at REAL NOT NULL
                );
                """
            )
            con.execute(
                """
                CREATE TABLE IF NOT EXISTS nr_votes (
                    artifact_id TEXT NOT NULL,
                    critic_id TEXT NOT NULL,
                    vote_blob BLOB NOT NULL,
                    created_at REAL NOT NULL,
                    PRIMARY KEY (artifact_id, critic_id)
                );
                """
            )
            con.execute(
                """
                CREATE TABLE IF NOT EXISTS nr_decisions (
                    artifact_id TEXT PRIMARY KEY,
                    decision_blob BLOB NOT NULL,
                    decided_at REAL NOT NULL
                );
                """
            )
            con.commit()
        finally:
            con.close()

    # --- proposals -----------------------------------------------------

    def upsert_proposal(self, artifact_id: str, blob: bytes) -> None:
        now = time.time()
        con = _connect(self.path)
        try:
            con.execute(
                """
                INSERT INTO nr_proposals (artifact_id, proposal_blob, created_at)
                VALUES (?, ?, ?)
                ON CONFLICT(artifact_id) DO UPDATE SET proposal_blob = excluded.proposal_blob
                """,
                (artifact_id, sqlite3.Binary(blob), now),
            )
            con.commit()
        finally:
            con.close()

    def delete_proposal(self, artifact_id: str) -> None:
        con = _connect(self.path)
        try:
            con.execute("DELETE FROM nr_proposals WHERE artifact_id = ?", (artifact_id,))
            con.execute("DELETE FROM nr_votes WHERE artifact_id = ?", (artifact_id,))
            con.execute("DELETE FROM nr_decisions WHERE artifact_id = ?", (artifact_id,))
            con.commit()
        finally:
            con.close()

    def load_proposals(self) -> Dict[str, bytes]:
        con = _connect(self.path)
        try:
            rows = con.execute(
                "SELECT artifact_id, proposal_blob FROM nr_proposals ORDER BY created_at ASC"
            ).fetchall()
            return {str(r[0]): bytes(r[1] or b"") for r in rows}
        finally:
            con.close()

    # --- votes ---------------------------------------------------------

    def insert_vote(self, artifact_id: str, critic_id: str, blob: bytes) -> None:
        now = time.time()
        con = _connect(self.path)
        try:
            con.execute(
                """
                INSERT INTO nr_votes (artifact_id, critic_id, vote_blob, created_at)
                VALUES (?, ?, ?, ?)
                """,
                (artifact_id, critic_id, sqlite3.Binary(blob), now),
            )
            con.commit()
        finally:
            con.close()

    def load_votes(self) -> Dict[str, List[Tuple[str, bytes]]]:
        con = _connect(self.path)
        try:
            rows = con.execute(
                """
                SELECT artifact_id, critic_id, vote_blob FROM nr_votes
                ORDER BY created_at ASC
                """
            ).fetchall()
            votes: Dict[str, List[Tuple[str, bytes]]] = {}
            for artifact_id, critic_id, blob in rows:
                votes.setdefault(str(artifact_id), []).append(
                    (str(critic_id), bytes(blob or b""))
                )
            return votes
        finally:
            con.close()

    # --- decisions -----------------------------------------------------

    def upsert_decision(self, artifact_id: str, blob: bytes) -> None:
        now = time.time()
        con = _connect(self.path)
        try:
            con.execute(
                """
                INSERT INTO nr_decisions (artifact_id, decision_blob, decided_at)
                VALUES (?, ?, ?)
                ON CONFLICT(artifact_id) DO UPDATE SET decision_blob = excluded.decision_blob
                """,
                (artifact_id, sqlite3.Binary(blob), now),
            )
            con.commit()
        finally:
            con.close()

    def load_decisions(self) -> Dict[str, bytes]:
        con = _connect(self.path)
        try:
            rows = con.execute(
                "SELECT artifact_id, decision_blob FROM nr_decisions ORDER BY decided_at ASC"
            ).fetchall()
            return {str(r[0]): bytes(r[1] or b"") for r in rows}
        finally:
            con.close()

    # --- whole-store ops -----------------------------------------------

    def clear_all(self) -> None:
        con = _connect(self.path)
        try:
            con.execute("DELETE FROM nr_proposals")
            con.execute("DELETE FROM nr_votes")
            con.execute("DELETE FROM nr_decisions")
            con.commit()
        finally:
            con.close()
