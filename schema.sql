-- Schema for MemoryFinder (PostgreSQL / SQLite compatible)

-- Runs
CREATE TABLE IF NOT EXISTS runs (
    id TEXT PRIMARY KEY,
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    status TEXT,
    metadata TEXT -- JSON
);

-- Search Queries (for Discovery)
CREATE TABLE IF NOT EXISTS search_queries (
    id TEXT PRIMARY KEY,
    query TEXT NOT NULL UNIQUE,
    last_used TIMESTAMP,
    enabled INTEGER DEFAULT 1 -- 1=true, 0=false
);

-- Sources (Retailers/Domains)
CREATE TABLE IF NOT EXISTS sources (
    id TEXT PRIMARY KEY,
    domain TEXT NOT NULL UNIQUE,
    trust_score INTEGER DEFAULT 0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Listings (Product Pages)
CREATE TABLE IF NOT EXISTS listings (
    id TEXT PRIMARY KEY,
    url TEXT NOT NULL UNIQUE,
    source_id TEXT,
    product_name TEXT,
    current_price_cents INTEGER,
    last_scraped TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY(source_id) REFERENCES sources(id)
);

-- Observations (Price/Stock History)
CREATE TABLE IF NOT EXISTS observations (
    id TEXT PRIMARY KEY,
    listing_id TEXT NOT NULL,
    price_cents INTEGER,
    stock_status TEXT,
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    metadata TEXT, -- JSON
    FOREIGN KEY(listing_id) REFERENCES listings(id)
);

-- Alerts (Deals found)
CREATE TABLE IF NOT EXISTS alerts (
    id TEXT PRIMARY KEY,
    listing_id TEXT NOT NULL,
    alert_type TEXT, -- price_drop, arbitrage, etc.
    score REAL,
    confidence TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    details TEXT, -- JSON
    FOREIGN KEY(listing_id) REFERENCES listings(id)
);
