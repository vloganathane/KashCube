#!/usr/bin/env python3
"""
Generate a detailed auto-inventory of SQLite tables from
lib/data/services/database_helper_tables.dart.

Output: Markdown grouped by domain, including per-column purpose hints.

Usage:
  python3 scripts/generate_db_inventory.py
  python3 scripts/generate_db_inventory.py --output docs/codebase/DATABASE_INVENTORY_AUTO.md
  python3 scripts/generate_db_inventory.py --source lib/data/services/database_helper_tables.dart
"""

from __future__ import annotations

import argparse
import re
from collections import OrderedDict, defaultdict
from dataclasses import dataclass
from datetime import UTC, datetime
from pathlib import Path
from typing import Iterable


@dataclass
class ColumnInfo:
    name: str
    col_type: str
    constraints: str


@dataclass
class TableInfo:
    name: str
    columns: list[ColumnInfo]
    table_constraints: list[str]
    indexes: list[str]


DOMAIN_GROUPS: OrderedDict[str, list[str]] = OrderedDict(
    {
        "Core Finance Ledger": [
            "transactions",
            "credits",
            "credit_payments",
            "loans",
            "loan_payments",
            "accounts",
            "categories",
            "budgets",
            "recurring_transactions",
            "scheduled_payments",
            "bills",
            "bill_attachments",
        ],
        "Parties and Communication": [
            "parties",
            "party_addresses",
            "party_reminders",
        ],
        "Business Docs and Revenue Flows": [
            "businesses",
            "quotes",
            "quote_items",
            "invoices",
            "invoice_items",
            "bookings",
            "booking_items",
            "delivery_challans",
            "delivery_challan_items",
            "purchase_bills",
            "purchase_bill_items",
            "invoice_number_cursors",
            "document_templates",
        ],
        "Catalog, Stock, and Units": [
            "item_catalog",
            "unit_types",
            "stock_movements",
            "item_stock",
            "stock_lots",
            "lot_movements",
            "transporters",
            "hsn_master",
        ],
        "Staff and Payroll": [
            "staff",
            "salary_payments",
            "payroll_notifications",
        ],
        "Settings, Auth, Permissions, Plans": [
            "settings",
            "app_users",
            "user_permissions",
            "subscription",
            "plan_features",
            "activity_log",
        ],
        "Device Identity and Sync Infrastructure": [
            "linked_devices",
            "device_recovery",
            "pairing_history",
            "device_session",
            "my_identity",
            "linked_business_sessions",
            "trusted_peers",
            "sync_outbox",
            "sync_watermarks",
            "sync_table_state",
            "invoice_events",
        ],
    }
)


def split_top_level_csv(body: str) -> list[str]:
    parts: list[str] = []
    token = []
    depth = 0
    for ch in body:
        if ch == "(":
            depth += 1
        elif ch == ")":
            depth -= 1
        if ch == "," and depth == 0:
            part = "".join(token).strip()
            if part:
                parts.append(part)
            token = []
            continue
        token.append(ch)
    tail = "".join(token).strip()
    if tail:
        parts.append(tail)
    return parts


def normalize_whitespace(s: str) -> str:
    return re.sub(r"\s+", " ", s.strip())


def parse_column(part: str) -> ColumnInfo:
    part = normalize_whitespace(part)
    pieces = part.split(" ", 2)
    name = pieces[0]
    col_type = pieces[1] if len(pieces) > 1 else ""
    constraints = pieces[2] if len(pieces) > 2 else ""
    return ColumnInfo(name=name, col_type=col_type, constraints=constraints)


def infer_column_purpose(col: ColumnInfo, table: str) -> str:
    name = col.name.lower()

    exact_map = {
        "id": "Primary row identifier",
        "sync_id": "Cross-device immutable row identity",
        "version": "Monotonic version for merge/conflict handling",
        "date": "Business date field",
        "created_at": "Row creation timestamp",
        "updated_at": "Last update timestamp",
        "deleted_at": "Soft-delete timestamp",
        "context_id": "Linked business session scope",
        "created_by_device_id": "Device that created the row",
        "updated_by_device_id": "Device that last updated the row",
        "status": "Current lifecycle/status state",
        "notes": "Free-form user notes",
        "tags": "Tag list / metadata",
    }
    if name in exact_map:
        return exact_map[name]

    if name.endswith("_id"):
        return "Reference to related entity"
    if name.endswith("_at"):
        return "Timestamp field"
    if name.endswith("_date"):
        return "Business date field"
    if "phone" in name:
        return "Phone/contact value"
    if "email" in name:
        return "Email/contact value"
    if name.endswith("_no") or "number" in name:
        return "Human-readable document/reference number"
    if "amount" in name or name in {"total", "subtotal", "balance", "price", "salary"}:
        return "Monetary value"
    if name.endswith("_pct") or name.endswith("_rate"):
        return "Rate/percentage value"
    if name.startswith("is_"):
        return "Boolean-like flag (0/1)"
    if name.startswith("can_"):
        return "Permission flag (0/1)"
    if name in {"name", "display_name", "customer_name", "vendor_name", "party_name"}:
        return "Display name / label"
    if name in {"payload", "event_data", "token_payload", "token_signature", "permission_scope", "business_scope"}:
        return "Serialized JSON/text payload"
    if "gst" in name or name in {"irn", "ewb_no", "hsn_code", "hsn_or_sac", "sac_code"}:
        return "Tax/compliance identifier"
    if "qty" in name:
        return "Quantity measure"
    if "sync" in name and "id" not in name:
        return "Sync progress/control metadata"
    if name == "key" and table == "settings":
        return "Settings key"
    if name == "value" and table == "settings":
        return "Settings value"

    return "Domain-specific field"


def parse_tables(source_text: str) -> OrderedDict[str, TableInfo]:
    triple_sql_blocks = re.findall(r"await\s+db\.execute\('''(.*?)'''\);", source_text, flags=re.S)
    one_line_sql_blocks = re.findall(r"await\s+db\.execute\((['\"])(CREATE\s+(?:UNIQUE\s+)?INDEX.*?|INSERT\s+OR\s+IGNORE.*?)\1\);", source_text)

    tables: OrderedDict[str, TableInfo] = OrderedDict()
    indexes: dict[str, list[str]] = defaultdict(list)

    for block in triple_sql_blocks:
        sql = normalize_whitespace(block)
        if sql.upper().startswith("CREATE TABLE"):
            match = re.match(
                r"CREATE TABLE(?: IF NOT EXISTS)?\s+([a-zA-Z_][a-zA-Z0-9_]*)\s*\((.*)\)",
                sql,
                flags=re.S | re.I,
            )
            if not match:
                continue

            table_name = match.group(1)
            body = match.group(2)
            parts = split_top_level_csv(body)

            columns: list[ColumnInfo] = []
            table_constraints: list[str] = []
            for part in parts:
                normalized_part = normalize_whitespace(part)
                upper = normalized_part.upper()
                is_table_constraint = bool(
                    re.match(r"^(FOREIGN KEY|UNIQUE\s*\(|PRIMARY KEY\s*\()", upper)
                )
                if is_table_constraint:
                    table_constraints.append(normalized_part)
                else:
                    columns.append(parse_column(part))

            tables[table_name] = TableInfo(
                name=table_name,
                columns=columns,
                table_constraints=table_constraints,
                indexes=[],
            )

        elif sql.upper().startswith("CREATE INDEX") or sql.upper().startswith("CREATE UNIQUE INDEX"):
            idx_match = re.search(r"ON\s+([a-zA-Z_][a-zA-Z0-9_]*)\s*\((.*?)\)", sql, flags=re.I)
            if idx_match:
                indexes[idx_match.group(1)].append(sql)

    for _, sql in one_line_sql_blocks:
        sql = normalize_whitespace(sql)
        if sql.upper().startswith("CREATE INDEX") or sql.upper().startswith("CREATE UNIQUE INDEX"):
            idx_match = re.search(r"ON\s+([a-zA-Z_][a-zA-Z0-9_]*)\s*\((.*?)\)", sql, flags=re.I)
            if idx_match:
                indexes[idx_match.group(1)].append(sql)

    for table_name, table in tables.items():
        table.indexes = indexes.get(table_name, [])

    return tables


def domain_lookup(tables: Iterable[str]) -> dict[str, str]:
    mapping: dict[str, str] = {}
    for domain, domain_tables in DOMAIN_GROUPS.items():
        for table in domain_tables:
            mapping[table] = domain
    for table in tables:
        mapping.setdefault(table, "Ungrouped")
    return mapping


def generate_markdown(source_path: Path, tables: OrderedDict[str, TableInfo]) -> str:
    domain_by_table = domain_lookup(tables.keys())

    lines: list[str] = []
    lines.append("# Auto-Generated Database Table Inventory")
    lines.append("")
    lines.append(f"Generated at: `{datetime.now(UTC).isoformat(timespec='seconds')}`")
    lines.append(f"Source: `{source_path.as_posix()}`")
    lines.append("")
    lines.append(f"Total tables: **{len(tables)}**")
    lines.append("")
    lines.append("## Domain Summary")
    lines.append("")

    for domain, grouped_tables in DOMAIN_GROUPS.items():
        present = [t for t in grouped_tables if t in tables]
        lines.append(f"- **{domain}**: {len(present)} tables")

    ungrouped = [t for t in tables if domain_by_table[t] == "Ungrouped"]
    if ungrouped:
        lines.append(f"- **Ungrouped**: {len(ungrouped)} tables")

    for domain, grouped_tables in DOMAIN_GROUPS.items():
        present = [t for t in grouped_tables if t in tables]
        if not present:
            continue

        lines.append("")
        lines.append(f"## {domain}")
        lines.append("")

        for table_name in present:
            table = tables[table_name]
            lines.append(f"### `{table_name}`")
            lines.append("")
            lines.append(
                f"- Columns: **{len(table.columns)}** | Table constraints: **{len(table.table_constraints)}** | Indexes: **{len(table.indexes)}**"
            )
            lines.append("")
            lines.append("| Column | Type | Constraints | Purpose |")
            lines.append("|---|---|---|---|")
            for col in table.columns:
                constraints = col.constraints or "—"
                purpose = infer_column_purpose(col, table_name)
                lines.append(
                    f"| `{col.name}` | `{col.col_type}` | {constraints} | {purpose} |"
                )

            if table.table_constraints:
                lines.append("")
                lines.append("**Table-level constraints**")
                for constraint in table.table_constraints:
                    lines.append(f"- `{constraint}`")

            if table.indexes:
                lines.append("")
                lines.append("**Indexes**")
                for idx in table.indexes:
                    lines.append(f"- `{idx}`")

            lines.append("")

    if ungrouped:
        lines.append("## Ungrouped")
        lines.append("")
        for table_name in ungrouped:
            lines.append(f"- `{table_name}`")

    return "\n".join(lines).strip() + "\n"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Generate DB table inventory markdown")
    parser.add_argument(
        "--source",
        default="lib/data/services/database_helper_tables.dart",
        help="Path to database schema source file",
    )
    parser.add_argument(
        "--output",
        default="docs/codebase/DATABASE_INVENTORY_AUTO.md",
        help="Output markdown file",
    )
    parser.add_argument(
        "--expect-table-count",
        type=int,
        default=None,
        help="Fail with non-zero exit code if parsed table count differs",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()

    source_path = Path(args.source)
    output_path = Path(args.output)

    if not source_path.exists():
        raise SystemExit(f"Source file not found: {source_path}")

    source_text = source_path.read_text(encoding="utf-8")
    tables = parse_tables(source_text)

    if args.expect_table_count is not None and len(tables) != args.expect_table_count:
        raise SystemExit(
            f"Table count mismatch: expected {args.expect_table_count}, got {len(tables)}"
        )

    markdown = generate_markdown(source_path, tables)

    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(markdown, encoding="utf-8")

    print(f"Generated: {output_path}")
    print(f"Tables parsed: {len(tables)}")


if __name__ == "__main__":
    main()
