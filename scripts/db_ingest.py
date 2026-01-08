import argparse
import json
import sys
import uuid
from datetime import datetime
from urllib.parse import urlparse
from db_common import get_db, execute_sql

def ingest_discovery(data):
    """
    Ingests discovery results: new candidates found.
    Input: { "new_candidates": [ { "url": "...", "product_name": "..." }, ... ] }
    """
    candidates = data.get('new_candidates', [])
    print(f"Ingesting discovery results: {len(candidates)} new candidates found.")

    conn = get_db()
    cur = conn.cursor()

    try:
        for item in candidates:
            url = item.get('url')
            if not url:
                continue

            # Extract domain for source
            domain = urlparse(url).netloc

            # Check if source exists, insert if not
            execute_sql(cur, "SELECT id FROM sources WHERE domain = ?", (domain,))
            row = cur.fetchone()
            if row:
                source_id = row['id']
            else:
                source_id = str(uuid.uuid4())
                try:
                    execute_sql(cur, "INSERT INTO sources (id, domain) VALUES (?, ?)", (source_id, domain))
                except Exception:
                    # Likely race condition (already exists), select again
                    execute_sql(cur, "SELECT id FROM sources WHERE domain = ?", (domain,))
                    row = cur.fetchone()
                    if row:
                        source_id = row['id']
                    else:
                        raise # Something else failed

            # Check if listing exists
            execute_sql(cur, "SELECT id FROM listings WHERE url = ?", (url,))
            row = cur.fetchone()
            if not row:
                listing_id = str(uuid.uuid4())
                product_name = item.get('product_name')
                try:
                    execute_sql(cur, "INSERT INTO listings (id, url, source_id, product_name) VALUES (?, ?, ?, ?)",
                                (listing_id, url, source_id, product_name))
                except Exception:
                     # Race condition
                     pass

        conn.commit()
    except Exception as e:
        conn.rollback()
        print(f"Error ingesting discovery: {e}", file=sys.stderr)
        raise
    finally:
        conn.close()

def ingest_scrape(data):
    """
    Ingests scrape results: observations.
    Input: { "scraped_results": [ { "url": "...", "price": 123.45, "stock": "In Stock", ... } ] }
    """
    results = data.get('scraped_results', []) if isinstance(data, dict) else data
    if not isinstance(results, list):
        results = [results]

    print(f"Ingesting scrape results: {len(results)} items.")

    conn = get_db()
    cur = conn.cursor()

    try:
        for item in results:
            url = item.get('url')
            if not url:
                continue

            # Find listing
            execute_sql(cur, "SELECT id FROM listings WHERE url = ?", (url,))
            row = cur.fetchone()
            if not row:
                # Create listing/source on the fly if needed
                domain = urlparse(url).netloc
                execute_sql(cur, "SELECT id FROM sources WHERE domain = ?", (domain,))
                s_row = cur.fetchone()
                if s_row:
                    source_id = s_row['id']
                else:
                    source_id = str(uuid.uuid4())
                    try:
                        execute_sql(cur, "INSERT INTO sources (id, domain) VALUES (?, ?)", (source_id, domain))
                    except Exception:
                        execute_sql(cur, "SELECT id FROM sources WHERE domain = ?", (domain,))
                        s_row = cur.fetchone()
                        if s_row:
                            source_id = s_row['id']
                        else:
                            # If strictly scrape, maybe we skip or fail. But let's skip.
                            continue

                listing_id = str(uuid.uuid4())
                product_name = item.get('product_name', 'Unknown')
                try:
                    execute_sql(cur, "INSERT INTO listings (id, url, source_id, product_name) VALUES (?, ?, ?, ?)",
                                (listing_id, url, source_id, product_name))
                except Exception:
                    # Race condition, fetch it
                    execute_sql(cur, "SELECT id FROM listings WHERE url = ?", (url,))
                    row = cur.fetchone()
                    if row:
                        listing_id = row['id']
                    else:
                        continue
            else:
                listing_id = row['id']

            # Insert Observation
            obs_id = str(uuid.uuid4())
            price = item.get('price')

            # Handle price parsing
            price_cents = None
            if price is not None:
                try:
                    if isinstance(price, str):
                        price = float(price.replace('$', '').replace(',', ''))
                    # Fix: Use round() for correct cent conversion
                    price_cents = int(round(price * 100))
                except (ValueError, TypeError):
                    pass

            stock_status = item.get('stock') or item.get('stock_status')
            timestamp = datetime.now().isoformat()

            execute_sql(cur, "INSERT INTO observations (id, listing_id, price_cents, stock_status, timestamp, metadata) VALUES (?, ?, ?, ?, ?, ?)",
                        (obs_id, listing_id, price_cents, stock_status, timestamp, json.dumps(item)))

            execute_sql(cur, "UPDATE listings SET last_scraped = ?, current_price_cents = ? WHERE id = ?",
                        (timestamp, price_cents, listing_id))

        conn.commit()
    except Exception as e:
        conn.rollback()
        print(f"Error ingesting scrape: {e}", file=sys.stderr)
        raise
    finally:
        conn.close()

def ingest_analysis(data):
    """
    Ingests analysis results: alerts/deals.
    Input: { "deals": [ { "listing_id": "...", "alert_type": "...", ... } ] }
    """
    deals = data.get('deals', [])
    print(f"Ingesting analysis results: {len(deals)} deals found.")

    conn = get_db()
    cur = conn.cursor()

    try:
        for deal in deals:
            listing_id = deal.get('listing_id')
            if not listing_id and deal.get('url'):
                url = deal.get('url')
                execute_sql(cur, "SELECT id FROM listings WHERE url = ?", (url,))
                row = cur.fetchone()
                if row:
                    listing_id = row['id']

            if not listing_id:
                print(f"Warning: Deal missing listing_id/url, skipping: {deal}")
                continue

            alert_id = str(uuid.uuid4())
            alert_type = deal.get('alert_type')
            score = deal.get('score')
            confidence = deal.get('confidence')

            execute_sql(cur, "INSERT INTO alerts (id, listing_id, alert_type, score, confidence, details) VALUES (?, ?, ?, ?, ?, ?)",
                        (alert_id, listing_id, alert_type, score, confidence, json.dumps(deal)))

        conn.commit()
    except Exception as e:
        conn.rollback()
        print(f"Error ingesting analysis: {e}", file=sys.stderr)
        raise
    finally:
        conn.close()

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--mode", required=True, choices=["discovery", "scrape", "analysis"])
    parser.add_argument("--in", dest="input_file", required=True, help="Input JSON file path")
    args = parser.parse_args()

    try:
        with open(args.input_file, "r") as f:
            data = json.load(f)
    except FileNotFoundError:
        print(f"Error: Input file {args.input_file} not found.")
        return
    except json.JSONDecodeError:
        print(f"Error: Invalid JSON in {args.input_file}")
        return

    if args.mode == "discovery":
        ingest_discovery(data)
    elif args.mode == "scrape":
        ingest_scrape(data)
    elif args.mode == "analysis":
        ingest_analysis(data)

if __name__ == "__main__":
    main()
