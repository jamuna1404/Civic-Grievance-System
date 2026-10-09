"""A minimal in-memory fake of the Supabase client's fluent query API.

Supports just the subset the auth router uses: table().insert/select/update
with .eq / .order / .limit / .execute. Enough to exercise the OTP flow without
a live database.
"""

import uuid
from datetime import datetime, timezone


class _Result:
    def __init__(self, data):
        self.data = data


class _Query:
    def __init__(self, table: "_Table"):
        self._table = table
        self._filters: list[tuple[str, object]] = []
        self._neq_filters: list[tuple[str, object]] = []
        self._lt_filters: list[tuple[str, object]] = []
        self._in_filters: list[tuple[str, list]] = []
        self._order_key: str | None = None
        self._order_desc = False
        self._limit: int | None = None

    def eq(self, column, value):
        self._filters.append((column, value))
        return self

    def neq(self, column, value):
        self._neq_filters.append((column, value))
        return self

    def in_(self, column, values):
        self._in_filters.append((column, list(values)))
        return self

    def lt(self, column, value):
        self._lt_filters.append((column, value))
        return self

    def order(self, column, desc: bool = False):
        self._order_key = column
        self._order_desc = desc
        return self

    def limit(self, n):
        self._limit = n
        return self

    def _matching(self):
        rows = [
            row
            for row in self._table.rows
            if all(row.get(c) == v for c, v in self._filters)
            and all(row.get(c) != v for c, v in self._neq_filters)
            and all(row.get(c) in vs for c, vs in self._in_filters)
            and all(row.get(c) is not None and row[c] < v for c, v in self._lt_filters)
        ]
        if self._order_key:
            rows.sort(
                key=lambda r: r.get(self._order_key) or "",
                reverse=self._order_desc,
            )
        if self._limit is not None:
            rows = rows[: self._limit]
        return rows

    def execute(self):
        return _Result([dict(r) for r in self._matching()])


class _UpdateQuery(_Query):
    def __init__(self, table, changes):
        super().__init__(table)
        self._changes = changes

    def execute(self):
        updated = []
        for row in self._table.rows:
            if all(row.get(c) == v for c, v in self._filters):
                row.update(self._changes)
                updated.append(dict(row))
        return _Result(updated)


class _Table:
    def __init__(self, name):
        self.name = name
        self.rows: list[dict] = []

    _PK_BY_TABLE = {
        "otp_verifications": "otp_id",
        "citizens": "citizen_id",
        "complaints": "complaint_id",
        "complaint_images": "image_id",
        "complaint_status_history": "history_id",
        "officers": "officer_id",
    }

    def _insert_one(self, payload):
        row = dict(payload)
        pk = self._PK_BY_TABLE.get(self.name, f"{self.name}_id")
        row.setdefault(pk, str(uuid.uuid4()))
        row.setdefault("created_at", datetime.now(timezone.utc).isoformat())
        # Emulate the complaints default status the trigger/DEFAULT would set.
        if self.name == "complaints":
            row.setdefault("status", "SUBMITTED")
        self.rows.append(row)
        return row

    def insert(self, payload):
        if isinstance(payload, list):
            rows = [self._insert_one(p) for p in payload]
            return _InsertResult(rows, many=True)
        return _InsertResult(self._insert_one(payload))

    def upsert(self, payload, on_conflict: str = ""):
        keys = [k.strip() for k in on_conflict.split(",") if k.strip()]
        for row in self.rows:
            if keys and all(row.get(k) == payload.get(k) for k in keys):
                row.update(payload)
                return _InsertResult(row)
        return self.insert(payload)

    def select(self, *_columns):
        return _Query(self)

    def update(self, changes):
        return _UpdateQuery(self, changes)


class _InsertResult:
    def __init__(self, row, many: bool = False):
        self._rows = row if many else [row]

    def execute(self):
        return _Result([dict(r) for r in self._rows])


class _RpcQuery:
    def __init__(self, data):
        self._data = data

    def execute(self):
        return _Result(self._data)


class FakeSupabase:
    def __init__(self):
        self._tables: dict[str, _Table] = {}
        self._rpc_results: dict[str, list] = {}

    def table(self, name):
        return self._tables.setdefault(name, _Table(name))

    def set_rpc_result(self, name: str, data: list):
        self._rpc_results[name] = data

    def rpc(self, name: str, params: dict):
        return _RpcQuery(self._rpc_results.get(name, []))
