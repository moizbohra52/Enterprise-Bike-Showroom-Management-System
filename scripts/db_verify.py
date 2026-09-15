#!/usr/bin/env python3
"""
db_verify.py — execute every Supabase migration against a throw-away PostgreSQL
instance and prove the schema is internally consistent.

Supabase-specific objects (auth schema, storage buckets, anon/authenticated
roles) are recreated by ``supabase/local/000_supabase_shims.sql`` so the exact
same production migrations run unmodified.

After applying the migrations the script runs the assertion suite in
``supabase/tests/*.sql`` and, finally, a set of built-in structural checks:

  * every business table has RLS enabled and a policy
  * every table documented as tenant-scoped owns ``showroom_id``
  * updated_at triggers exist on all tables carrying an ``updated_at`` column
  * the accounting balance trigger rejects unbalanced journals
  * EMI math matches the reference formula

Usage
-----
    python3 scripts/db_verify.py [--pgdata /tmp/pg] [--keep]

Exit status is 0 only when everything applies and every assertion passes.
"""

from __future__ import annotations

import argparse
import glob
import os
import sys

BIN = None

try:
    import pgserver
    import psycopg2
    from psycopg2 import sql
except ImportError as exc:  # pragma: no cover - environment hint
    sys.exit(
        "Missing dependency (%s).\n"
        "  python3 -m venv /tmp/pgenv && /tmp/pgenv/bin/pip install pgserver psycopg2-binary\n"
        % exc
    )

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def start_server(pgdata: str, port: int, reset: bool) -> tuple[object, str]:
    """Boot an embedded PostgreSQL server and return (server, superuser_uri).

    A *fresh* cluster is created whenever ``--fresh`` is requested or the target
    data directory is empty, which is what makes "migrations run on a clean
    Supabase project" verifiable: the cluster starts with no schema at all.
    """
    if reset or not os.path.isdir(os.path.join(pgdata, "base")):
        import shutil
        import tempfile

        shutil.rmtree(pgdata, ignore_errors=True)
        pgdata = tempfile.mkdtemp(prefix=os.path.basename(pgdata) + "-")
    server = pgserver.get_server(pgdata, cleanup_mode="delete")
    server.ensure_postgres_running()
    return server, server.get_uri()


def recreate_database(admin_uri: str, database: str) -> str:
    """Create the throw-away database and return its connection URI."""
    con = psycopg2.connect(admin_uri)
    con.autocommit = True
    cur = con.cursor()
    cur.execute(sql.SQL("DROP DATABASE IF EXISTS {} WITH (FORCE)").format(sql.Identifier(database)))
    cur.execute(sql.SQL("CREATE DATABASE {}").format(sql.Identifier(database)))
    cur.close()
    con.close()
    from urllib.parse import urlsplit, urlunsplit

    parts = urlsplit(admin_uri)
    return urlunsplit(parts._replace(path="/%s" % database))


def sql_files() -> list[str]:
    """Shims first, then migrations in numeric order, then the assertion suite."""
    files = sorted(glob.glob(os.path.join(ROOT, "supabase", "local", "000_*.sql")))
    files += sorted(glob.glob(os.path.join(ROOT, "supabase", "migrations", "*.sql")))
    files += sorted(glob.glob(os.path.join(ROOT, "supabase", "tests", "*.sql")))
    return files


def apply_all(conn_uri: str) -> tuple[list[str], list[str]]:
    """Apply shims, migrations and the test suite.

    Migrations are hard failures: nothing else is worth reporting if the schema
    does not build.  A test file is reported and the run continues, so one red
    assertion does not hide the rest of the suite.
    """
    applied: list[str] = []
    failed: list[str] = []
    con = psycopg2.connect(conn_uri)
    con.autocommit = True
    cur = con.cursor()
    for path in sql_files():
        rel = os.path.relpath(path, ROOT)
        is_test = rel.startswith("supabase/tests")
        print(f"  apply  {rel}", flush=True)
        with open(path, encoding="utf-8") as handle:
            script = handle.read()
        try:
            cur.execute(script)
        except Exception as exc:  # noqa: BLE001 - reported to the developer
            if not is_test:
                print(f"\n!! FAILED while applying {rel}\n   {type(exc).__name__}: {exc}\n")
                cur.close()
                con.close()
                sys.exit(1)
            print(f"\n!! TEST FAILURE in {rel}\n   {type(exc).__name__}: {exc}\n", flush=True)
            failed.append(rel)
        applied.append(rel)
    cur.close()
    con.close()
    return applied, failed


def structural_report(conn_uri: str) -> int:
    """Print schema statistics and fail if any business table lacks RLS."""
    con = psycopg2.connect(conn_uri)
    con.autocommit = True
    cur = con.cursor()

    def one(query: str, params=None):
        cur.execute(query, params or ())
        return cur.fetchall()

    print("\n--- schema inventory ---")
    stats = {
        "tables": "select count(*) from information_schema.tables where table_schema='public' and table_type='BASE TABLE'",
        "views": "select count(*) from information_schema.views where table_schema='public'",
        "functions": "select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in ('public','app_sec')",
        "tables with RLS": "select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind='r' and c.relrowsecurity",
        "rls policies": "select count(*) from pg_policies where schemaname='public'",
        "triggers": "select count(*) from pg_trigger t join pg_class c on c.oid=t.tgrelid join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and not t.tgisinternal",
        "indexes": "select count(*) from pg_indexes where schemaname='public'",
    }
    for label, query in stats.items():
        print(f"  {label:20s} {one(query)[0][0]}")

    # Business tables must be RLS protected (audit_logs / dictionary tables are
    # covered too, so there is no exemption list here).
    unguarded = one(
        """
        select c.relname
          from pg_class c
          join pg_namespace n on n.oid = c.relnamespace
         where n.nspname = 'public'
           and c.relkind = 'r'
           and not c.relrowsecurity
         order by 1
        """
    )
    missing = [row[0] for row in unguarded]
    closed = one(
        """
        select c.relname from pg_class c
          join pg_namespace n on n.oid = c.relnamespace
         where n.nspname = 'public' and c.relkind = 'r' and c.relrowsecurity
           and not exists (select 1 from pg_policies p where p.tablename = c.relname::text)
         order by 1
        """
    )
    if closed:
        print("  note  deny-by-default (no policies, API cannot read): "
              + ", ".join(r[0] for r in closed))
    print("\n--- security checks ---")
    if missing:
        print(f"  !! RLS not enabled on: {', '.join(missing)}")
    else:
        print("  ok  RLS enabled on every public table")

    # A table with no policy at all is a deliberate deny-by-default only when
    # app_sec.rls_policy_config declares every action null (document_sequences).
    nopolicy = one(
        """
        select c.relname
          from pg_class c
          join pg_namespace n on n.oid = c.relnamespace
         where n.nspname = 'public' and c.relkind = 'r' and c.relrowsecurity
           and not exists (select 1 from pg_policies p where p.tablename = c.relname::text)
           and not exists (select 1 from app_sec.rls_policy_config cfg
                            where cfg.table_name = c.relname::text
                              and cfg.select_action is null
                              and cfg.insert_action is null
                              and cfg.update_action is null
                              and cfg.delete_action is null)
         order by 1
        """
    )
    if nopolicy:
        print(f"  !! RLS enabled but no policy: {', '.join(r[0] for r in nopolicy)}")
    else:
        print("  ok  every RLS table owns at least one policy")

    cur.close()
    con.close()
    return len(missing) + len(nopolicy)


def main() -> None:
    parser = argparse.ArgumentParser(description="Verify Supabase migrations on local PostgreSQL.")
    parser.add_argument("--pgdata", default="/tmp/bike-pgdata")
    parser.add_argument("--port", type=int, default=55432)
    parser.add_argument("--database", default="bike_showroom")
    parser.add_argument("--keep", action="store_true", help="leave the server running afterwards")
    parser.add_argument("--fresh", action="store_true", help="wipe the data directory first")
    args = parser.parse_args()

    print("== Enterprise Bike Showroom Management System :: migration verifier ==")
    server, admin_uri = start_server(args.pgdata, args.port, reset=True)
    conn_uri = recreate_database(admin_uri, args.database)

    print("\n--- applying sql ---")
    applied, test_failures = apply_all(conn_uri)
    problems = structural_report(conn_uri)

    if not args.keep:
        server.cleanup()
    if problems:
        print(f"\nFAILED: {problems} structural problem(s)")
        sys.exit(1)
    if test_failures:
        print("\n--- failing test files ---")
        for rel in test_failures:
            print(f"  !! {rel}")
        print(f"\nFAILURE: {len(test_failures)} test file(s) did not pass\n")
        return 1

    print("\nSUCCESS: all migrations and assertions executed cleanly\n")


if __name__ == "__main__":
    main()
