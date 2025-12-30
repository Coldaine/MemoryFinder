import sqlite3
import os

# Allow override via environment variable for test isolation
DB_PATH = os.environ.get(
    "MEMORYFINDER_DB",
    os.path.join(os.path.dirname(__file__), "..", "data", "memoryfinder.db")
)

def get_db():
    os.makedirs(os.path.dirname(DB_PATH), exist_ok=True)
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    return conn

def init_db():
    conn = get_db()
    c = conn.cursor()
    # Simplified schema for SQLite prototype
    c.execute('''CREATE TABLE IF NOT EXISTS runs (id TEXT PRIMARY KEY, timestamp DATETIME)''')
    c.execute('''CREATE TABLE IF NOT EXISTS sources (id INTEGER PRIMARY KEY, domain TEXT, trust_score INTEGER)''')
    c.execute('''CREATE TABLE IF NOT EXISTS listings (id INTEGER PRIMARY KEY, url TEXT, last_scraped DATETIME)''')
    c.execute('''CREATE TABLE IF NOT EXISTS observations (id INTEGER PRIMARY KEY, listing_id INTEGER, price REAL, stock TEXT, timestamp DATETIME)''')
    conn.commit()
    conn.close()

if __name__ == "__main__":
    init_db()
    print(f"Database initialized at {DB_PATH}")
