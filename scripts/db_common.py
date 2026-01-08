import sqlite3
import os
import sys
import uuid
from datetime import datetime

# Optional postgres support
try:
    import psycopg2
    from psycopg2.extras import RealDictCursor
    HAS_POSTGRES = True
except ImportError:
    HAS_POSTGRES = False

def get_db_path():
    return os.environ.get(
        "MEMORYFINDER_DB",
        os.path.join(os.path.dirname(__file__), "..", "data", "memoryfinder.db")
    )

def get_db_connection():
    """
    Returns a database connection object.
    Prefers PostgreSQL if DATABASE_URL is set.
    Otherwise uses SQLite.
    """
    database_url = os.environ.get("DATABASE_URL")

    if database_url:
        if not HAS_POSTGRES:
            raise ImportError("DATABASE_URL is set but psycopg2 is not installed. Please install psycopg2-binary.")

        try:
            conn = psycopg2.connect(database_url, cursor_factory=RealDictCursor)
            return conn
        except Exception as e:
            print(f"Error connecting to Postgres: {e}", file=sys.stderr)
            raise e
    else:
        db_path = get_db_path()
        os.makedirs(os.path.dirname(db_path), exist_ok=True)
        conn = sqlite3.connect(db_path, timeout=10.0)
        conn.row_factory = sqlite3.Row
        return conn

def execute_sql(cursor, query, params=None):
    """
    Executes SQL handling placeholder differences.
    SQLite uses '?', Postgres uses '%s'.

    WARNING: This uses string replacement for placeholders which is potentially fragile
    if '?' appears in string literals. Use with caution or ensure queries are simple.
    """
    if params is None:
        params = ()

    # Check if cursor is from sqlite or psycopg2
    is_sqlite = False
    if hasattr(cursor, 'connection') and isinstance(cursor.connection, sqlite3.Connection):
        is_sqlite = True

    if not is_sqlite:
        # Postgres
        if '?' in query:
            # Simple replacement.
            # Ideally we should use a proper SQL builder or stick to one syntax and convert.
            # But for this project's simple queries, this suffices.
            query = query.replace('?', '%s')

    cursor.execute(query, params)
    return cursor

def init_db():
    conn = get_db_connection()
    try:
        cur = conn.cursor()

        # Read schema.sql
        schema_path = os.path.join(os.path.dirname(__file__), "..", "schema.sql")
        with open(schema_path, 'r') as f:
            schema_sql = f.read()

        if isinstance(conn, sqlite3.Connection):
            # SQLite executescript handles multiple statements
            cur.executescript(schema_sql)
        else:
            # Postgres needs execution of statements.
            # Splitting by ';' is unsafe if ';' is in strings.
            # But schema.sql usually contains safe statements.
            # Let's try executing the whole block if possible, or split.
            # psycopg2 cursor.execute() can execute multiple statements?
            # Standard DBI says no, but psycopg2 might.
            # Actually, psycopg2 usually requires one statement per execute unless configured?
            # Let's just execute the whole thing and see. Postgres supports it.
            cur.execute(schema_sql)

        conn.commit()
    finally:
        conn.close()

def get_db():
    return get_db_connection()

if __name__ == "__main__":
    init_db()
    if os.environ.get("DATABASE_URL"):
        print("Database initialized (PostgreSQL)")
    else:
        print(f"Database initialized at {get_db_path()} (SQLite)")
