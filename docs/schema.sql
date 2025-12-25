-- TR9-RPM: Threadripper 9000 RDIMM Price Monitor
-- Enhanced PostgreSQL Schema with OOS tracking, trust scoring, and quota management

-- ============================================================================
-- CORE TABLES
-- ============================================================================

-- Canonical product identity (MPN-based)
CREATE TABLE products (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    mpn             TEXT UNIQUE,                    -- Manufacturer part number (primary key for identity)
    sku             TEXT,                           -- Vendor-specific SKU if known
    name            TEXT NOT NULL,                  -- Human-readable name
    brand           TEXT,                           -- Micron, Samsung, SK Hynix, etc.
    capacity_gb     INT NOT NULL,                   -- Total kit capacity
    module_count    INT,                            -- e.g., 4 for quad-channel kits
    module_size_gb  INT,                            -- e.g., 32 for 4x32GB
    speed_mt        INT,                            -- e.g., 4800, 5600
    dimm_type       TEXT DEFAULT 'RDIMM',           -- RDIMM or UDIMM
    ecc             BOOLEAN DEFAULT TRUE,           -- RDIMMs are typically ECC
    cas_latency     TEXT,                           -- e.g., "CL46"
    identity_confidence INT DEFAULT 50,             -- 0-100, how certain we are this is correct
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    updated_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_products_capacity ON products(capacity_gb);
CREATE INDEX idx_products_mpn ON products(mpn);
CREATE INDEX idx_products_brand ON products(brand);

-- Source/retailer tracking with trust scoring
CREATE TABLE sources (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name                TEXT NOT NULL,
    domain              TEXT UNIQUE,
    source_type         TEXT NOT NULL,              -- major_retailer|reseller|surplus|marketplace|forum|international
    scrape_method       TEXT DEFAULT 'zai_reader',  -- zai_reader|zai_vision|firecrawl|serpapi
    trust_score         INT DEFAULT 50 CHECK (trust_score >= 0 AND trust_score <= 100),
    deal_potential      INT DEFAULT 50 CHECK (deal_potential >= 0 AND deal_potential <= 100),
    discovery_frequency TEXT DEFAULT '6h',          -- How often to include in discovery
    verification_frequency TEXT DEFAULT '1h',       -- How often to verify known listings
    max_verifications_per_day INT DEFAULT 24,       -- Rate limiting
    rate_limit_ms       INT DEFAULT 2000,
    last_crawled        TIMESTAMPTZ,
    discovered_at       TIMESTAMPTZ DEFAULT NOW(),
    discovered_via      TEXT,                       -- Query or method that found this source
    notes               TEXT,
    enabled             BOOLEAN DEFAULT TRUE
);

CREATE INDEX idx_sources_type ON sources(source_type);
CREATE INDEX idx_sources_trust ON sources(trust_score DESC);

-- Product listings (URL-level tracking)
CREATE TABLE product_listings (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    product_id      UUID REFERENCES products(id),
    source_id       UUID REFERENCES sources(id),
    url             TEXT NOT NULL,
    vendor_sku      TEXT,                           -- Retailer's SKU
    condition       TEXT DEFAULT 'new',             -- new|open_box|refurbished|used|pulls
    region          TEXT DEFAULT 'US',
    currency        TEXT DEFAULT 'USD',
    -- OOS tracking (critical for efficiency)
    oos_streak_hours INT DEFAULT 0,                 -- Hours continuously out of stock
    last_in_stock_at TIMESTAMPTZ,
    last_verified_at TIMESTAMPTZ,
    last_verified_price_cents INT,
    -- Metadata
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(product_id, source_id, url)
);

CREATE INDEX idx_listings_product ON product_listings(product_id);
CREATE INDEX idx_listings_source ON product_listings(source_id);
CREATE INDEX idx_listings_oos ON product_listings(oos_streak_hours);
CREATE INDEX idx_listings_verified ON product_listings(last_verified_at DESC);

-- Price observations (time series)
CREATE TABLE price_observations (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    listing_id      UUID REFERENCES product_listings(id),
    observed_at     TIMESTAMPTZ DEFAULT NOW(),
    price_cents     INT,                            -- Price in cents to avoid float issues
    original_price_cents INT,                       -- MSRP/crossed-out price if shown
    shipping_cents  INT DEFAULT 0,                  -- 0 if free
    coupon_cents    INT DEFAULT 0,                  -- Discount applied
    in_stock        BOOLEAN,
    quantity_available INT,                         -- If shown (bulk sources)
    -- Extraction metadata
    extraction_confidence INT DEFAULT 50,           -- 0-100
    extraction_method TEXT,                         -- zai_reader|zai_vision|firecrawl
    raw_response    JSONB                           -- Full extraction for debugging
);

CREATE INDEX idx_observations_listing ON price_observations(listing_id);
CREATE INDEX idx_observations_time ON price_observations(observed_at DESC);

-- ============================================================================
-- TARGET RECIPES
-- ============================================================================

CREATE TABLE targets (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name            TEXT UNIQUE NOT NULL,           -- e.g., TR9-128Q
    description     TEXT,
    total_capacity_gb INT NOT NULL,
    module_count    INT NOT NULL,
    module_size_gb  INT NOT NULL,
    dimm_type       TEXT DEFAULT 'RDIMM',
    priority        TEXT DEFAULT 'primary',         -- primary|secondary
    enabled         BOOLEAN DEFAULT TRUE
);

-- Seed the target recipes
INSERT INTO targets (name, description, total_capacity_gb, module_count, module_size_gb, priority) VALUES
    ('TR9-128Q', '128GB = 4×32GB DDR5 RDIMM (quad-channel)', 128, 4, 32, 'primary'),
    ('TR9-256Q', '256GB = 4×64GB DDR5 RDIMM (quad-channel)', 256, 4, 64, 'primary'),
    ('TR9-512Q', '512GB = 4×128GB DDR5 RDIMM (quad-channel)', 512, 4, 128, 'primary'),
    ('TR9-256-8D', '256GB = 8×32GB DDR5 RDIMM (2DPC)', 256, 8, 32, 'secondary'),
    ('TR9-512-8D', '512GB = 8×64GB DDR5 RDIMM (2DPC)', 512, 8, 64, 'secondary');

-- ============================================================================
-- BENCHMARKS & BASELINES
-- ============================================================================

CREATE TABLE benchmarks (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    target_id       UUID REFERENCES targets(id),
    computed_at     TIMESTAMPTZ DEFAULT NOW(),
    period          TEXT NOT NULL,                  -- 24h|7d|30d
    median_price_cents INT,
    p25_price_cents INT,
    p75_price_cents INT,
    min_price_cents INT,
    max_price_cents INT,
    observation_count INT,
    major_retailer_baseline_cents INT              -- Newegg/Amazon baseline
);

CREATE INDEX idx_benchmarks_target ON benchmarks(target_id);
CREATE INDEX idx_benchmarks_period ON benchmarks(period);

-- ============================================================================
-- RUN TRACKING & ALERTS
-- ============================================================================

CREATE TABLE run_log (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    run_id          TEXT UNIQUE,                    -- External run ID
    started_at      TIMESTAMPTZ DEFAULT NOW(),
    completed_at    TIMESTAMPTZ,
    status          TEXT DEFAULT 'running',         -- running|completed|degraded|failed
    discovery_ran   BOOLEAN DEFAULT FALSE,
    candidates_found INT DEFAULT 0,
    urls_verified   INT DEFAULT 0,
    observations_written INT DEFAULT 0,
    deals_found     INT DEFAULT 0,
    errors          JSONB DEFAULT '[]'::JSONB,
    metrics         JSONB DEFAULT '{}'::JSONB       -- Tool usage stats
);

CREATE TABLE alert_history (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    run_id          TEXT,
    listing_id      UUID REFERENCES product_listings(id),
    alert_type      TEXT NOT NULL,                  -- price_drop|arbitrage|stale_pricing|back_in_stock
    score           FLOAT,                          -- Priority score
    triggered_at    TIMESTAMPTZ DEFAULT NOW(),
    current_price_cents INT,
    baseline_price_cents INT,
    discount_pct    FLOAT,
    message         TEXT,
    evidence_url    TEXT,
    confidence      TEXT DEFAULT 'medium',          -- high|medium|low
    delivered       BOOLEAN DEFAULT FALSE,
    delivery_channel TEXT,                          -- stdout|email|discord|home_assistant
    suppressed_until TIMESTAMPTZ                    -- For alert deduplication
);

CREATE INDEX idx_alerts_type ON alert_history(alert_type);
CREATE INDEX idx_alerts_time ON alert_history(triggered_at DESC);

-- ============================================================================
-- QUOTA TRACKING
-- ============================================================================

CREATE TABLE quota_usage (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    period_start    DATE NOT NULL,                  -- Start of billing period
    zai_search_calls INT DEFAULT 0,
    zai_reader_calls INT DEFAULT 0,
    zai_vision_calls INT DEFAULT 0,
    firecrawl_calls INT DEFAULT 0,
    serpapi_calls   INT DEFAULT 0,
    tier_limit      INT DEFAULT 4000,               -- Max Plan default
    updated_at      TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(period_start)
);

-- ============================================================================
-- DISCOVERY TRACKING
-- ============================================================================

CREATE TABLE discovered_sources (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    domain          TEXT UNIQUE,
    discovered_at   TIMESTAMPTZ DEFAULT NOW(),
    discovered_via  TEXT,                           -- Query that found it
    sample_urls     JSONB DEFAULT '[]'::JSONB,
    has_checkout    BOOLEAN,
    has_pricing     BOOLEAN,
    has_contact     BOOLEAN,
    promoted_to_sources BOOLEAN DEFAULT FALSE,
    notes           TEXT
);

CREATE TABLE discovery_runs (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    run_id          TEXT,
    ran_at          TIMESTAMPTZ DEFAULT NOW(),
    query           TEXT,
    engine          TEXT,                           -- zai_search|serpapi|firecrawl
    results_count   INT,
    new_candidates  INT DEFAULT 0,
    new_sources     INT DEFAULT 0
);

-- ============================================================================
-- ANALYTICAL VIEWS
-- ============================================================================

CREATE VIEW latest_prices AS
SELECT DISTINCT ON (listing_id)
    po.*,
    pl.url,
    pl.oos_streak_hours,
    p.name AS product_name,
    p.mpn,
    p.capacity_gb,
    p.module_count,
    p.module_size_gb,
    s.name AS source_name,
    s.source_type,
    s.trust_score
FROM price_observations po
JOIN product_listings pl ON po.listing_id = pl.id
JOIN products p ON pl.product_id = p.id
JOIN sources s ON pl.source_id = s.id
ORDER BY listing_id, observed_at DESC;

CREATE VIEW price_history_7d AS
SELECT
    pl.id AS listing_id,
    p.mpn,
    p.capacity_gb,
    DATE(po.observed_at) AS date,
    MIN(po.price_cents) AS min_price,
    MAX(po.price_cents) AS max_price,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY po.price_cents)::INT AS median_price,
    COUNT(*) AS observations
FROM price_observations po
JOIN product_listings pl ON po.listing_id = pl.id
JOIN products p ON pl.product_id = p.id
WHERE po.observed_at >= NOW() - INTERVAL '7 days'
  AND po.price_cents IS NOT NULL
GROUP BY pl.id, p.mpn, p.capacity_gb, DATE(po.observed_at);

-- Verification candidates (not verified recently, not perma-OOS)
CREATE VIEW verification_candidates AS
SELECT
    pl.*,
    p.name AS product_name,
    p.mpn,
    s.name AS source_name,
    s.trust_score,
    s.deal_potential
FROM product_listings pl
JOIN products p ON pl.product_id = p.id
JOIN sources s ON pl.source_id = s.id
WHERE s.enabled = TRUE
  AND (pl.oos_streak_hours < 72 OR pl.last_in_stock_at > NOW() - INTERVAL '72 hours')
  AND (pl.last_verified_at IS NULL OR pl.last_verified_at < NOW() - INTERVAL '1 hour')
ORDER BY s.deal_potential DESC, s.trust_score DESC;
