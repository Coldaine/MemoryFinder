import argparse
import json
import sys
from db_common import get_db

def get_discovery_tasks():
    # In a real system, this would rotate through search terms
    return {
        "task_type": "discovery",
        "search_queries": [
            "DDR5 RDIMM 128GB buy",
            "Samsung M321R8GA0PB0-CWM"
        ],
        "forbidden_domains": ["amazon.com", "newegg.com"] # We want unconventional sources
    }

def get_scrape_tasks():
    # Return seed URLs if DB is empty
    return {
        "task_type": "scrape",
        "urls": [
            "https://serverpartdeals.com/products/samsung-m321r8ga0pb0-cwm-128gb-ddr5-4800-ecc-registered-rdimm",
            "https://memory.net/product/m321r8ga0pb0-cwm-samsung-1x-128gb-ddr5-4800-rdimm-pc5-38400v-q-dual-rank-x4/"
        ]
    }

def get_analysis_tasks():
    return {
        "task_type": "analysis",
        "recent_observations": [] # Mock data
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
