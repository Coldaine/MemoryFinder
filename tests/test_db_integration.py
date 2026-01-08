import os
import json
import sqlite3
import sys
import unittest
import uuid
from datetime import datetime

# Ensure scripts directory is in path
sys.path.append(os.path.join(os.path.dirname(__file__), "..", "scripts"))

from db_common import init_db, get_db, execute_sql
import db_ingest
import db_get_tasks

class TestDBIntegration(unittest.TestCase):
    def setUp(self):
        # Use a unique DB for each test or clear tables
        self.test_db_path = os.path.join(os.path.dirname(__file__), f"test_memoryfinder_{uuid.uuid4()}.db")
        os.environ["MEMORYFINDER_DB"] = self.test_db_path
        init_db()

    def tearDown(self):
        if os.path.exists(self.test_db_path):
            try:
                os.remove(self.test_db_path)
            except OSError:
                pass

    def test_discovery_ingest_and_retrieval(self):
        # 1. Ingest Discovery Data
        discovery_data = {
            "new_candidates": [
                {"url": "https://example.com/p1", "product_name": "Product 1"},
                {"url": "https://example.com/p2", "product_name": "Product 2"}
            ]
        }
        db_ingest.ingest_discovery(discovery_data)

        # 2. Verify in DB
        conn = get_db()
        cur = conn.cursor()
        cur.execute("SELECT * FROM listings")
        listings = cur.fetchall()
        self.assertEqual(len(listings), 2)

        # 3. Verify get_scrape_tasks returns these
        tasks = db_get_tasks.get_scrape_tasks()
        self.assertEqual(tasks["task_type"], "scrape")
        # Note: Order is not guaranteed by set/list checks, but urls list should contain them
        urls = tasks["urls"]
        self.assertIn("https://example.com/p1", urls)
        self.assertIn("https://example.com/p2", urls)
        conn.close()

    def test_scrape_ingest_and_retrieval(self):
        # 1. Setup Listing
        conn = get_db()
        cur = conn.cursor()
        execute_sql(cur, "INSERT INTO sources (id, domain) VALUES ('s1', 'example.com')")
        execute_sql(cur, "INSERT INTO listings (id, url, source_id, product_name) VALUES ('l1', 'https://example.com/p1', 's1', 'P1')")
        conn.commit()
        conn.close()

        # 2. Ingest Scrape Data
        scrape_data = {
            "scraped_results": [
                {"url": "https://example.com/p1", "price": 100.50, "stock": "In Stock"}
            ]
        }
        db_ingest.ingest_scrape(scrape_data)

        # 3. Verify Observation
        conn = get_db()
        cur = conn.cursor()
        cur.execute("SELECT * FROM observations")
        obs = cur.fetchall()
        self.assertEqual(len(obs), 1)
        self.assertEqual(obs[0]["price_cents"], 10050)

        # 4. Verify get_analysis_tasks
        tasks = db_get_tasks.get_analysis_tasks()
        self.assertEqual(tasks["task_type"], "analysis")
        self.assertEqual(len(tasks["recent_observations"]), 1)
        # Check float approx equality
        self.assertAlmostEqual(tasks["recent_observations"][0]["price"], 100.50)
        conn.close()

    def test_analysis_ingest(self):
        # 1. Setup Listing
        conn = get_db()
        cur = conn.cursor()
        execute_sql(cur, "INSERT INTO sources (id, domain) VALUES ('s1', 'example.com')")
        execute_sql(cur, "INSERT INTO listings (id, url, source_id, product_name) VALUES ('l1', 'https://example.com/p1', 's1', 'P1')")
        conn.commit()
        conn.close()

        # 2. Ingest Analysis Data
        analysis_data = {
            "deals": [
                {
                    "listing_id": "l1",
                    "alert_type": "price_drop",
                    "score": 90,
                    "confidence": "high"
                }
            ]
        }
        db_ingest.ingest_analysis(analysis_data)

        # 3. Verify Alerts
        conn = get_db()
        cur = conn.cursor()
        cur.execute("SELECT * FROM alerts")
        alerts = cur.fetchall()
        self.assertEqual(len(alerts), 1)
        self.assertEqual(alerts[0]["alert_type"], "price_drop")
        conn.close()

if __name__ == '__main__':
    unittest.main()
