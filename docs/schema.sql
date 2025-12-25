-- Core tables

CREATE TABLE products (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    sku             TEXT UNIQUE,                    -- Manufacturer SKU if known
    name            TEXT NOT NULL,                  -- Human-readable name
    capacity_gb     INT NOT NULL,                   -- Total kit capacity
    module_count    INT,                            -- e.g., 4 for quad-channel
    module_size_gb  INT,                            -- e.g., 32 for 4x32GB
    speed_mts       INT,                            -- e.g., 5600
    cas_latency     TEXT,                           -- e.g., "CL46"
    ecc             BOOLEAN DEFAULT TRUE,           -- RDIMMs are ECC
    brand           TEXT,
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    updated_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_products_capacity ON products(capacity_gb);

CREATE TABLE sources (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name            TEXT NOT NULL,
    domain          TEXT UNIQUE,
    source_type     TEXT NOT NULL,                  -- major_retailer|reseller|surplus|marketplace|forum|international
    scrape_method   TEXT DEFAULT 'zai_reader',      -- zai_reader|zai_vision|firecrawl|serpapi
    trust_score     INT DEFAULT 50,                 -- 0-100, based on fulfillment history
    deal_potential  INT DEFAULT 50,                 -- 0-100, likelihood of finding arbitrage
    rate_limit_ms   INT DEFAULT 2000,
    last_crawled    TIMESTAMPTZ,
    notes           TEXT,
    enabled         BOOLEAN DEFAULT TRUE
);

CREATE TABLE product_listings (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    product_id      UUID REFERENCES products(id),
    source_id       UUID REFERENCES sources(id),
    url             TEXT NOT NULL,
    last_seen       TIMESTAMPTZ,
    last_in_stock   TIMESTAMPTZ,
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(product_id, source_id, url)
);

CREATE INDEX idx_listings_product ON product_listings(product_id);
CREATE INDEX idx_listings_source ON product_listings(source_id);

CREATE TABLE price_observations (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    listing_id      UUID REFERENCES product_listings(id),
    observed_at     TIMESTAMPTZ DEFAULT NOW(),
    price_cents     INT,                            -- Price in cents to avoid float issues
    original_price_cents INT,                       -- MSRP/crossed-out price if shown
    in_stock        BOOLEAN,
    shipping_cents  INT,                            -- NULL if free or unknown
    condition       TEXT DEFAULT 'new',             -- new|open_box|refurbished
    source          TEXT,                           -- Which agent/tool captured this
    raw_response    JSONB                           -- Full scrape response for debugging
);

CREATE INDEX idx_observations_listing ON price_observations(listing_id);
CREATE INDEX idx_observations_time ON price_observations(observed_at DESC);

-- Analytical views

CREATE VIEW latest_prices AS
SELECT DISTINCT ON (listing_id)
    po.*,
    pl.url,
    p.name AS product_name,
    p.capacity_gb,
    s.name AS source_name,
    s.source_type
FROM price_observations po
JOIN product_listings pl ON po.listing_id = pl.id
JOIN products p ON pl.product_id = p.id
JOIN sources s ON pl.source_id = s.id
ORDER BY listing_id, observed_at DESC;

CREATE VIEW price_history_daily AS
SELECT
    listing_id,
    DATE(observed_at) AS date,
    MIN(price_cents) AS min_price,
    MAX(price_cents) AS max_price,
    AVG(price_cents)::INT AS avg_price,
    COUNT(*) AS observations
FROM price_observations
WHERE price_cents IS NOT NULL
GROUP BY listing_id, DATE(observed_at);

-- Run tracking

CREATE TABLE run_log (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    started_at      TIMESTAMPTZ DEFAULT NOW(),
    completed_at    TIMESTAMPTZ,
    status          TEXT DEFAULT 'running',         -- running|completed|failed
    discovery_ran   BOOLEAN DEFAULT FALSE,
    products_checked INT DEFAULT 0,
    new_observations INT DEFAULT 0,
    deals_found     INT DEFAULT 0,
    errors          JSONB DEFAULT '[]'::JSONB
);

CREATE TABLE alert_history (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    listing_id      UUID REFERENCES product_listings(id),
    alert_type      TEXT,                           -- price_drop|cross_retailer|back_in_stock
    triggered_at    TIMESTAMPTZ DEFAULT NOW(),
    message         TEXT,
    delivered       BOOLEAN DEFAULT FALSE,
    delivery_channel TEXT                           -- stdout|email|discord|home_assistant
);

-- Discovery tracking (for rate limiting)

CREATE TABLE discovery_runs (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ran_at          TIMESTAMPTZ DEFAULT NOW(),
    query           TEXT,
    engine          TEXT,                           -- google_shopping|walmart|ebay
    results_count   INT,
    new_products    INT DEFAULT 0
);
