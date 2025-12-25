import argparse
import json
import sys
from db_common import get_db

def ingest_discovery(data):
    print(f"Ingesting discovery results: {len(data.get('new_candidates', []))} new candidates found.")
    # TODO: INSERT INTO sources / listings

def ingest_scrape(data):
    print(f"Ingesting scrape results: {data}")
    # TODO: INSERT INTO observations

def ingest_analysis(data):
    print(f"Ingesting analysis results: {data}")
    # TODO: INSERT INTO alerts

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
