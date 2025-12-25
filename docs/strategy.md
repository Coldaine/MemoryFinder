# Unconventional Source Strategy

The deals won't come from Newegg, Amazon, or B&H. Those retailers have automated pricing systems that adjust in lockstep with the market. The arbitrage opportunities exist in:

- **Regional resellers** who bought inventory 6-18 months ago and haven't repriced
- **Surplus/liquidation sellers** offloading datacenter pulls or cancelled orders
- **Small e-commerce shops** that don't monitor competitor pricing
- **International sellers** with currency arbitrage or different regional pricing
- **eBay/marketplace sellers** with old listings they forgot about
- **Direct-from-distributor** sites with stale catalog pricing

## Discovery Strategy: Cast a Wide Net

The Discovery Agent needs to go beyond the obvious shopping engines.

### Tier 1: Shopping Aggregators (SerpAPI)
- google_shopping: "DDR5 RDIMM 128GB" (standard)
- google_shopping: "DDR5 RDIMM ECC 4x32GB" 
- walmart, ebay: same queries

### Tier 2: Deep Web Search (Z.ai Web Search)
Use webSearchPrime to find pages that shopping engines miss:
- "DDR5 RDIMM 128GB buy" 
- "DDR5 ECC memory 256GB in stock"
- "server memory DDR5 RDIMM wholesale"
- "DDR5 RDIMM 512GB price"
- "Micron MTC20F104XS1RC48* buy" (search by part number pattern)
- "Samsung M321R8GA0* RDIMM" (Samsung part number prefix)
- "Hynix HMCG94 buy" (SK Hynix part prefix)

### Tier 3: Targeted Domain Crawling (Firecrawl)
Use firecrawl_map to discover product pages on known reseller domains:
- memory.net, memoryx.com, datamemorysystems.com
- serverpartdeals.com, savemyserver.com
- bargainhardware.co.uk, serverplus.com
- itcreations.com, yourserverparts.com
- alibaba.com (for wholesale pricing baseline)

### Tier 4: Forum/Deal Site Monitoring
Search for recent posts mentioning deals:
- site:reddit.com/r/homelabsales "RDIMM DDR5"
- site:reddit.com/r/hardwareswap "RDIMM"
- site:forums.servethehome.com "DDR5 RDIMM deal"
- site:slickdeals.net "server memory"

## Source Verification Checklist

Before promoting discovered_source to sources table:

1. **Basic Legitimacy**
   - [ ] Site has contact information (phone, address)
   - [ ] Site has SSL certificate
   - [ ] Business name searchable (BBB, state registration)
   - [ ] Not on known scam lists

2. **E-commerce Signals**
   - [ ] Accepts credit card (chargeback protection)
   - [ ] Has return policy visible
   - [ ] Shows actual inventory quantities (not "call for availability" on everything)
   - [ ] Prices are in expected range (not 90% below market = likely scam)

3. **Historical Signals** (if available)
   - [ ] Web Archive shows site existed >1 year ago
   - [ ] Reviews exist on external sites (ResellerRatings, Trustpilot)
   - [ ] Forum mentions from real users
