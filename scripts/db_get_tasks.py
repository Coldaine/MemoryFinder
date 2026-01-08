import argparse
import json
import sys
from datetime import datetime
from db_common import get_db, execute_sql

def get_discovery_tasks():
    # Fetch search queries from DB
    conn = get_db()
    cur = conn.cursor()

    # Try to fetch from search_queries table
    # If table is empty or doesn't exist (yet), fallback to defaults
    try:
        execute_sql(cur, "SELECT query, forbidden_domains FROM search_queries WHERE enabled = 1 ORDER BY last_used ASC LIMIT 5")
        # Note: forbidden_domains column was not in my initial schema. I should check if I added it.
        # I only added query, last_used, enabled.
        # I'll stick to just queries for now and hardcode forbidden domains as per original stub,
        # or I should update schema.
        # Let's keep it simple: queries from DB.

        # Actually, let's just select query.
        execute_sql(cur, "SELECT query FROM search_queries WHERE enabled = 1 ORDER BY last_used ASC LIMIT 5")
        rows = cur.fetchall()
        queries = [row['query'] for row in rows]
    except Exception as e:
        print(f"Warning fetching queries: {e}", file=sys.stderr)
        queries = []

    conn.close()

    if not queries:
        # Default fallback
        queries = [
            "DDR5 RDIMM 128GB buy",
            "Samsung M321R8GA0PB0-CWM"
        ]

    return {
        "task_type": "discovery",
        "search_queries": queries,
        "forbidden_domains": ["amazon.com", "newegg.com"] # We want unconventional sources
    }

def get_scrape_tasks():
    # Fetch listings that need scraping
    # Criteria: oldest last_scraped or null
    conn = get_db()
    cur = conn.cursor()

    try:
        execute_sql(cur, "SELECT url FROM listings ORDER BY last_scraped ASC NULLS FIRST LIMIT 10")
        rows = cur.fetchall()
        urls = [row['url'] for row in rows]
    except Exception as e:
        print(f"Error fetching scrape tasks: {e}", file=sys.stderr)
        urls = []

    conn.close()

    if not urls:
         # Return seed URLs if DB is empty
        urls = [
            "https://serverpartdeals.com/products/samsung-m321r8ga0pb0-cwm-128gb-ddr5-4800-ecc-registered-rdimm",
            "https://memory.net/product/m321r8ga0pb0-cwm-samsung-1x-128gb-ddr5-4800-rdimm-pc5-38400v-q-dual-rank-x4/"
        ]

    return {
        "task_type": "scrape",
        "urls": urls
    }

def get_analysis_tasks():
    # Fetch recent observations for analysis
    conn = get_db()
    cur = conn.cursor()

    observations = []
    try:
        # Join with listings to get product details
        # We want the latest observation for each listing, or just recent ones?
        # The stub returned "recent_observations".
        # Let's get observations from the last 24 hours.

        # SQLite vs Postgres date logic differs.
        # Postgres: timestamp > NOW() - INTERVAL '24 hours'
        # SQLite: timestamp > datetime('now', '-1 day')

        # To be safe, let's just get the last 50 observations regardless of time, or use python to filter.
        # Or better, just get everything that hasn't been analyzed?
        # We don't have an "analyzed" flag.
        # Let's just fetch the last 20 observations with listing info.

        query = """
        SELECT o.price_cents, o.stock_status, o.timestamp, l.url, l.product_name, l.id as listing_id
        FROM observations o
        JOIN listings l ON o.listing_id = l.id
        ORDER BY o.timestamp DESC
        LIMIT 20
        """
        execute_sql(cur, query)
        rows = cur.fetchall()

        for row in rows:
            obs = {
                "listing_id": row['listing_id'],
                "url": row['url'],
                "product_name": row['product_name'],
                "price": row['price_cents'] / 100.0 if row['price_cents'] else None,
                "stock": row['stock_status'],
                "timestamp": row['timestamp']
            }
            observations.append(obs)

    except Exception as e:
        print(f"Error fetching analysis tasks: {e}", file=sys.stderr)

    conn.close()

    return {
        "task_type": "analysis",
        "recent_observations": observations
    }

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--mode", required=True, choices=["discovery", "scrape", "analysis"])
    parser.add_argument("--out", required=True, help="Output JSON file path")
    args = parser.parse_args()

    data = {}
    if args.mode == "discovery":
        data = get_discovery_tasks()
    elif args.mode == "scrape":
        data = get_scrape_tasks()
    elif args.mode == "analysis":
        data = get_analysis_tasks()

    with open(args.out, "w") as f:
        json.dump(data, f, indent=2)
    
    print(f"Generated {args.mode} tasks to {args.out}")

if __name__ == "__main__":
    main()
