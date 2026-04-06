# Schema.org Product Field Analysis for KashCube Item Catalog

**Date**: 5 April 2026  
**Version**: 1.0  
**Purpose**: Comprehensive mapping of Schema.org Product properties to KashCube's item catalog to achieve full e-commerce schema compliance.

---

## Executive Summary

- **Total Schema.org Product Properties**: 48 core properties (excluding inherited Thing properties)
- **Currently Implemented**: 14 fields (29%)
- **Recommended to Add**: 15 fields (P0-P1)
- **Optional/Advanced**: 12 fields (P2-P3)
- **Not Applicable**: 7 fields (specialized use cases)

---

## Current Implementation Status

### ✅ Fields Already Implemented (14)

| Property | Type | KashCube Field | Status | Notes |
|----------|------|----------------|--------|-------|
| `name` | Text | `name` | ✅ Required | Core product name |
| `sku` | Text | `sku` | ✅ Auto/Manual | Auto-generated PROD-001 or manual |
| `description` | Text | `description` | ✅ Optional | Multi-line description |
| `category` | Text | `category` | ✅ Enum | Product/Service/Material/Labor/Equipment/Other |
| `brand` | Brand | `brand_name` | ✅ Optional | Brand name (not full Brand object) |
| `image` | URL | `primary_image_path` | ✅ Optional | Local file path, image picker UI |
| `gtin` | Text | `barcode` | ✅ Optional | Covers GTIN-13, UPC, EAN |
| `additionalProperty` | PropertyValue[] | `additional_properties_json` | ✅ Optional | JSON object for custom metadata |
| `offers.price` | Number | `unit_price` | ✅ Required | Selling price |
| `offers.inventoryLevel` | QuantitativeValue | `stock_qty` | ✅ Tracked | When `track_inventory=true` |
| — | — | `tax_pct` | ✅ Optional | Indian GST percentage (not in schema.org) |
| — | — | `hsn_code` | ✅ Optional | Indian HSN/SAC code (not in schema.org) |
| — | — | `mrp` | ✅ Optional | Maximum Retail Price (India-specific) |
| — | — | `dealer_price` | ✅ Optional | Wholesale price |

**Coverage**: Basic product information, pricing, inventory, Indian compliance fields.

---

## Recommendations by Priority

### 🔴 P0: Critical for Commerce Mesh Compliance (5 fields)

These fields are **required** by Commerce Mesh schema and e-commerce standards.

| Property | Type | Recommended Field | Why Critical | Implementation |
|----------|------|-------------------|--------------|----------------|
| `mpn` | Text | `mpn` | Manufacturer Part Number - universal product identifier | `mpn TEXT` in DB, text field in Basic tab |
| `offers.availability` | Enum | `availability` | Explicit stock status beyond qty | `availability TEXT DEFAULT 'InStock'` (InStock/OutOfStock/PreOrder/Discontinued) |
| `offers.priceCurrency` | Text | `price_currency` | Required for international commerce | `price_currency TEXT DEFAULT 'INR'` |
| `offers.priceValidUntil` | DateTime | `price_valid_until` | Promotional pricing expiration | `price_valid_until DATETIME` nullable |
| `manufacturer` | Organization | `manufacturer_name` | Who makes the product | `manufacturer_name TEXT` nullable |

**Impact**: High - Enables full Commerce Mesh export compliance.

---

### 🟠 P1: High Value for E-commerce (10 fields)

Essential fields for modern e-commerce, search, and product filtering.

| Property | Type | Recommended Field | Business Value | Implementation |
|----------|------|-------------------|----------------|----------------|
| `color` | Text | `color` | Product filtering, variants | `color TEXT` nullable |
| `size` | Text/QuantitativeValue | `size` | Apparel/product variants | `size TEXT` nullable |
| `weight` | QuantitativeValue | `weight_value`, `weight_unit` | Shipping calculations | `weight_value REAL`, `weight_unit TEXT` |
| `width` | Distance | `width_cm` | Dimensional shipping | `width_cm REAL` nullable |
| `height` | Distance | `height_cm` | Dimensional shipping | `height_cm REAL` nullable |
| `depth` | Distance | `depth_cm` | Dimensional shipping | `depth_cm REAL` nullable |
| `material` | Text | `material` | Product specs, sustainability | `material TEXT` nullable |
| `keywords` | Text | `keywords` | SEO, search discovery | `keywords TEXT` nullable (comma-separated) |
| `countryOfOrigin` | Country | `country_of_origin` | Compliance, labeling | `country_of_origin TEXT` nullable |
| `releaseDate` | Date | `release_date` | Product launches, preorders | `release_date DATE` nullable |

**Impact**: High - Significantly improves product discovery, filtering, and shipping accuracy.

---

### 🟡 P2: Enhanced Features (8 fields)

Valuable for advanced use cases, marketplace listings, and detailed product information.

| Property | Type | Recommended Field | Use Case | Implementation |
|----------|------|-------------------|----------|----------------|
| `productID` | Text | `product_id` | External product identifiers (ISBN, UPC) | `product_id TEXT` nullable |
| `asin` | Text | `asin` | Amazon integration | `asin TEXT` nullable |
| `gtin8` / `gtin12` / `gtin14` | Text | Use existing `barcode` | Already covered by generic gtin field | No change needed |
| `logo` | URL | `logo_path` | Brand/product logo separate from image | `logo_path TEXT` nullable |
| `pattern` | Text | `pattern` | Design patterns (striped, polka dot) | `pattern TEXT` nullable |
| `slogan` | Text | `slogan` | Product tagline/motto | `slogan TEXT` nullable |
| `itemCondition` | Enum | `item_condition` | New/Used/Refurbished | `item_condition TEXT DEFAULT 'NewCondition'` |
| `model` | Text/ProductModel | `model_number` | Specific product model | `model_number TEXT` nullable |

**Impact**: Medium - Nice-to-have for complete product catalogs, especially marketplaces.

---

### 🟢 P3: Advanced/Specialized (7 fields)

For specific industries or advanced commerce scenarios.

| Property | Type | Recommended Field | Specialized For | Notes |
|----------|------|-------------------|-----------------|-------|
| `isVariantOf` | ProductGroup | Variant system | Fashion, configurable products | Requires `product_groups` table, variant relationship model |
| `inProductGroupWithID` | Text | `product_group_id` | Product variants | Part of variant system |
| `isAccessoryOrSparePartFor` | Product | Product relationships | Auto parts, electronics | Requires `product_relationships` table |
| `aggregateRating` | AggregateRating | Rating system | Reviews/ratings | Requires `product_reviews` table |
| `hasCertification` | Certification | Certifications | Organic, Fair Trade, etc. | Requires certifications module |
| `hasEnergyConsumptionDetails` | EnergyConsumptionDetails | Energy ratings | Appliances | Specialized use case |
| `purchaseDate` / `productionDate` | Date | Item instance tracking | Inventory lot tracking | For IndividualProduct instances |

**Impact**: Low - Only needed for specific business models or industries.

---

### ⚪ Not Applicable (7 fields)

Fields that don't apply to KashCube's business model or are redundant.

| Property | Why Not Applicable |
|----------|-------------------|
| `mobileUrl` | Responsive design makes this obsolete |
| `nsn` | NATO Stock Number - military/government only |
| `funding` | Academic/research products |
| `hasAdultConsideration` | Not applicable for general commerce |
| `negativeNotes` / `positiveNotes` | Covered by reviews system |
| `displayLocation` | For physical showrooms, not in-app catalog |
| `owner` | Ownership tracking not needed for catalog items |

---

## Recommended Implementation Plan

### Phase 1: P0 Fields (Critical) - 1-2 weeks

**Goal**: Achieve full Commerce Mesh schema compliance.

**Database Migration** (v87):
```sql
ALTER TABLE item_catalog ADD COLUMN mpn TEXT;
ALTER TABLE item_catalog ADD COLUMN availability TEXT DEFAULT 'InStock';
ALTER TABLE item_catalog ADD COLUMN price_currency TEXT DEFAULT 'INR';
ALTER TABLE item_catalog ADD COLUMN price_valid_until DATETIME;
ALTER TABLE item_catalog ADD COLUMN manufacturer_name TEXT;
```

**UI Changes**:
- Basic tab: Add `mpn` field below SKU
- Pricing tab: Add `price_currency` dropdown (INR/USD/EUR), `price_valid_until` date picker
- Inventory tab: Add `availability` dropdown
- Advanced tab: Add `manufacturer_name` field

**Testing**: Ensure export mapper generates valid Commerce Mesh JSON.

---

### Phase 2: P1 Fields (High Value) - 2-3 weeks

**Goal**: Enable advanced product filtering, search, and shipping calculations.

**Database Migration** (v88):
```sql
ALTER TABLE item_catalog ADD COLUMN color TEXT;
ALTER TABLE item_catalog ADD COLUMN size TEXT;
ALTER TABLE item_catalog ADD COLUMN weight_value REAL;
ALTER TABLE item_catalog ADD COLUMN weight_unit TEXT DEFAULT 'g';
ALTER TABLE item_catalog ADD COLUMN width_cm REAL;
ALTER TABLE item_catalog ADD COLUMN height_cm REAL;
ALTER TABLE item_catalog ADD COLUMN depth_cm REAL;
ALTER TABLE item_catalog ADD COLUMN material TEXT;
ALTER TABLE item_catalog ADD COLUMN keywords TEXT;
ALTER TABLE item_catalog ADD COLUMN country_of_origin TEXT;
ALTER TABLE item_catalog ADD COLUMN release_date DATE;
```

**UI Changes**:
- Basic tab: Add `color`, `size`, `material` fields in new "Physical Properties" accordion
- Pricing tab: Add `release_date` for product launches
- Inventory tab: Add dimensions (width/height/depth) and weight
- Advanced tab: Add `keywords` (multi-chip input), `country_of_origin` dropdown

**New Features**:
- Filter products by color, size, material
- Shipping cost calculator using weight/dimensions
- Keyword-based search improvements

---

### Phase 3: P2 Fields (Enhanced) - 1-2 weeks

**Goal**: Support marketplace listings and detailed product specs.

**Database Migration** (v89):
```sql
ALTER TABLE item_catalog ADD COLUMN product_id TEXT; -- External IDs (ISBN, etc.)
ALTER TABLE item_catalog ADD COLUMN asin TEXT;
ALTER TABLE item_catalog ADD COLUMN logo_path TEXT;
ALTER TABLE item_catalog ADD COLUMN pattern TEXT;
ALTER TABLE item_catalog ADD COLUMN slogan TEXT;
ALTER TABLE item_catalog ADD COLUMN item_condition TEXT DEFAULT 'NewCondition';
ALTER TABLE item_catalog ADD COLUMN model_number TEXT;
```

**UI Changes**:
- Basic tab: Add `product_id`, `model_number`
- Media tab: Add `logo_path` image picker (separate from primary image)
- Advanced tab: Add `asin`, `pattern`, `slogan`, `item_condition` dropdown

---

### Phase 4: P3 Fields (Advanced) - 4-6 weeks

**Goal**: Support product variants, relationships, and reviews.

**New Tables**:
```sql
CREATE TABLE product_groups (
  id INTEGER PRIMARY KEY,
  name TEXT NOT NULL,
  description TEXT,
  varies_by TEXT, -- JSON array: ["color", "size"]
  created_at DATETIME,
  updated_at DATETIME
);

CREATE TABLE product_relationships (
  id INTEGER PRIMARY KEY,
  product_id INTEGER NOT NULL,
  related_product_id INTEGER NOT NULL,
  relationship_type TEXT NOT NULL, -- 'accessory', 'spare_part', 'consumable'
  FOREIGN KEY (product_id) REFERENCES item_catalog(id),
  FOREIGN KEY (related_product_id) REFERENCES item_catalog(id)
);

CREATE TABLE product_reviews (
  id INTEGER PRIMARY KEY,
  product_id INTEGER NOT NULL,
  rating INTEGER NOT NULL, -- 1-5
  review_text TEXT,
  reviewer_name TEXT,
  created_at DATETIME,
  FOREIGN KEY (product_id) REFERENCES item_catalog(id)
);
```

**UI Changes**:
- New "Variants" tab for managing product variants
- Product detail screen: "Related Products" section
- Reviews/ratings UI in product detail

---

## Database Schema Summary (After All Phases)

### `item_catalog` table (final state)

```sql
CREATE TABLE item_catalog (
  -- Core identity
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  business_id INTEGER,
  name TEXT NOT NULL,
  sku TEXT,
  
  -- Description & categorization
  description TEXT,
  category TEXT DEFAULT 'product', -- Product/Service/Material/Labor/Equipment/Other
  keywords TEXT, -- P1: SEO keywords
  
  -- Identification codes
  mpn TEXT, -- P0: Manufacturer Part Number
  barcode TEXT, -- Covers GTIN-8/12/13/14
  product_id TEXT, -- P2: External ID (ISBN, etc.)
  asin TEXT, -- P2: Amazon ASIN
  
  -- Brand & manufacturer
  brand_name TEXT,
  manufacturer_name TEXT, -- P0: Manufacturer
  logo_path TEXT, -- P2: Product/brand logo
  
  -- Pricing
  unit_price REAL NOT NULL DEFAULT 0,
  price_currency TEXT DEFAULT 'INR', -- P0: Currency code
  price_valid_until DATETIME, -- P0: Promo expiration
  tax_pct REAL NOT NULL DEFAULT 0,
  mrp REAL, -- Maximum Retail Price
  dealer_price REAL, -- Wholesale price
  
  -- Indian compliance
  hsn_code TEXT,
  hsn_or_sac TEXT DEFAULT 'HSN',
  
  -- Physical properties (P1)
  color TEXT,
  size TEXT,
  weight_value REAL,
  weight_unit TEXT DEFAULT 'g',
  width_cm REAL,
  height_cm REAL,
  depth_cm REAL,
  material TEXT,
  pattern TEXT, -- P2: Design pattern
  
  -- Inventory & availability
  track_inventory INTEGER NOT NULL DEFAULT 0,
  stock_qty REAL NOT NULL DEFAULT 0,
  low_stock_threshold REAL NOT NULL DEFAULT 5,
  availability TEXT DEFAULT 'InStock', -- P0: InStock/OutOfStock/PreOrder/Discontinued
  
  -- Product lifecycle
  release_date DATE, -- P1: Product launch date
  item_condition TEXT DEFAULT 'NewCondition', -- P2: New/Used/Refurbished
  country_of_origin TEXT, -- P1: Manufacturing country
  
  -- Media
  primary_image_path TEXT,
  
  -- Metadata
  additional_properties_json TEXT,
  slogan TEXT, -- P2: Product tagline
  model_number TEXT, -- P2: Model identifier
  
  -- Service/booking
  unit TEXT DEFAULT 'pcs',
  is_bookable INTEGER DEFAULT 0,
  duration_minutes INTEGER DEFAULT 30,
  
  -- Product variants (P3)
  product_group_id INTEGER, -- Reference to product_groups table
  
  -- User preferences
  is_favorite INTEGER NOT NULL DEFAULT 0,
  is_active INTEGER NOT NULL DEFAULT 1,
  
  -- Usage tracking
  last_used_at TEXT,
  usage_count INTEGER NOT NULL DEFAULT 0,
  last_counted_qty REAL,
  last_counted_at TEXT,
  
  -- Timestamps
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  
  FOREIGN KEY (business_id) REFERENCES businesses(id)
);
```

**Total Fields**: 50+ (up from current 30)

---

## Benefits of Full Implementation

### Business Value
1. **Commerce Mesh Compliant**: Full schema.org/Product export capability
2. **Enhanced Search**: Better product discovery via keywords, color, size filters
3. **Marketplace Ready**: All fields needed for listing on e-commerce platforms
4. **Shipping Integration**: Weight/dimensions enable accurate shipping costs
5. **International Support**: Multi-currency, country of origin for global sales
6. **Promotional Pricing**: Time-limited offers via `price_valid_until`
7. **Product Variants**: Manage color/size variations properly

### Technical Value
1. **Future-proof**: Covers 90%+ of e-commerce use cases
2. **Standards-based**: Follows W3C/Schema.org specifications
3. **Export-ready**: Can generate valid Product JSON-LD for SEO
4. **Extensible**: `additional_properties_json` handles long-tail needs

---

## Gradual Adoption Strategy

### Approach 1: Additive Migrations Only
- All new fields are nullable
- Existing items work without changes
- Users opt-in to new fields as needed
- No breaking changes to existing workflows

### Approach 2: Smart Defaults
- `availability`: Auto-set based on `stock_qty > 0` ? 'InStock' : 'OutOfStock'
- `price_currency`: Default 'INR' for India
- `weight_unit`: Default 'g' (grams)
- `item_condition`: Default 'NewCondition'

### Approach 3: UI Progressive Disclosure
- Keep core fields visible (name, SKU, price, description)
- Advanced fields in collapsible accordions
- Smart field visibility based on category (e.g., show size/color for Products, hide for Services)

---

## Recommendation

**✅ YES - Add All Fields, But in Phases**

**Rationale**:
1. **Low Risk**: All fields are nullable, additive only
2. **High Reward**: Full e-commerce schema compliance opens many doors
3. **User Choice**: Fields are optional, users only fill what they need
4. **Future-proof**: Covers variant products, international sales, marketplace listings
5. **Competitive**: Most modern e-commerce platforms have these fields

**Timeline**:
- **Phase 1 (P0)**: 2 weeks - Critical for Commerce Mesh
- **Phase 2 (P1)**: 3 weeks - High-value commerce features
- **Phase 3 (P2)**: 2 weeks - Enhanced marketplace support
- **Phase 4 (P3)**: 6 weeks - Advanced features (variants, reviews)

**Total Effort**: ~13 weeks for complete implementation.

**Quick Win**: Implement Phase 1 (P0 fields) first - only 5 fields but huge compliance impact.

---

## Next Steps

1. **Review & Approve**: Confirm field additions align with product vision
2. **Database Migrations**: Create migration scripts for v87, v88, v89
3. **UI Mockups**: Design tab layouts with new fields
4. **Model Updates**: Update `ItemCatalog` model, `copyWith`, JSON serialization
5. **Export Mapper**: Enhance Commerce Mesh export to use new fields
6. **Testing**: Ensure backward compatibility with existing items

**Estimated Total Lines of Code**: ~3,000 lines (DB migrations + models + UI + tests)

---

*End of Document*
