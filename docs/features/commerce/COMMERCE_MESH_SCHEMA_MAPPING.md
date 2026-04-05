# Commerce Mesh Schema Mapping to KashCube

**Status:** CORE ARCHITECTURE REFERENCE  
**Date created:** 27 March 2026  
**Purpose:** Canonical field-by-field mapping from Commerce Mesh product-feed schema to KashCube's internal item model

---

## Core Decision

Commerce Mesh should be treated as an **export schema**, not KashCube's internal database schema. KashCube remains business-first: GST, HSN/SAC, stock, MRP, dealer price, and invoice workflows stay first-class in the local model. The Commerce Mesh / JSON-LD feed is generated from that internal source of truth.

**Rule of thumb:**
- Store business-critical item fields directly in `item_catalog`
- Add a small number of public-commerce fields only when they have clear product value
- Store long-tail metadata in JSON or child tables
- Compute schema wrappers and derived fields at export time

### Mapping Principle

```
KashCube internal model  →  Export mapper  →  Commerce Mesh / JSON-LD feed
```

Not:

```
Commerce Mesh schema  →  KashCube database design
```

If KashCube forced the internal DB to mirror the external spec 1:1, invoice workflows, GST handling, stock tracking, and Indian retail requirements would get worse.

---

## Current KashCube Source of Truth

Primary item sources today:
- `lib/data/models/item_catalog.dart`
- `lib/data/services/database_helper_tables.dart`
- `lib/data/repositories/item_catalog_repository_impl.dart`
- `lib/presentation/screens/invoices/item_catalog_screen.dart`

Current first-class item fields already cover the commercial core well:
- `name`, `description`, `sku`, `category`, `unit`
- `unit_price`, `tax_pct`
- `hsn_code`, `hsn_or_sac`
- `track_inventory`, `stock_qty`, `low_stock_threshold`
- `mrp`, `dealer_price`
- `is_active`, `created_at`, `updated_at`

---

## Top-Level Feed Object

| Commerce Mesh Field | Meaning | KashCube Mapping | Status | Recommendation |
|---|---|---|---|---|
| `@context` | Schema context | No DB field | Missing | Compute at export time |
| `@type = ItemList` | Feed wrapper type | No DB field | Missing | Compute at export time |
| `itemListElement` | Ordered array of items | Catalog query result set | Implicit only | Build from exported catalog list |

## ListItem Mapping

| Commerce Mesh Field | Meaning | KashCube Mapping | Status | Recommendation |
|---|---|---|---|---|
| `@type = ListItem` | Wrapper per item | No DB field | Missing | Compute at export time |
| `position` | Item order in feed | Repository sort order | Implicit only | Compute during export |
| `item` | `Product` or `ProductGroup` payload | `ItemCatalog` row or future variant group | Partial | Export `ItemCatalog` as `Product`; add `ProductGroup` later |

---

## Product Core Identity

| Commerce Mesh Field | Meaning | KashCube Mapping | Status | Recommendation |
|---|---|---|---|---|
| `@context` | Product schema context | No DB field | Missing | Compute at export time |
| `@type = Product` | Product type tag | `ItemCatalog` row | Implicit only | Compute at export time |
| `@id` | Stable URN (`urn:cmp:sku:*`) | Derive from `sku`, `sync_id`, or internal `id` | Missing | Derive initially; optional future `cmp_product_urn` |
| `name` | Product name | `item_catalog.name` | Exists | Keep first-class |
| `sku` | Seller SKU | `item_catalog.sku` | Exists | Keep first-class |

## Product Descriptive Fields

| Commerce Mesh Field | Meaning | KashCube Mapping | Status | Recommendation |
|---|---|---|---|---|
| `description` | Product description | `item_catalog.description` | Exists | Keep first-class |
| `image` | Primary image URL | No item image field today | Missing | Add optional local image path; export as LAN URL |
| `brand` | Brand object | No dedicated item brand field | Missing | Add optional `brand_name` |
| `category` | Public category string | `item_catalog.category` enum | Partial | Export enum label/string |
| `additionalProperty` | Long-tail metadata | No general metadata store | Missing | Add JSON field or child table |
| `isVariantOf` | Variant parent group | No variant model | Missing | Defer until variants are needed |
| `@cmp:media` | Rich media array | No item media model/table | Missing | Defer to dedicated media table |

---

## Offer / Pricing / Availability

| Commerce Mesh Field | Meaning | KashCube Mapping | Status | Recommendation |
|---|---|---|---|---|
| `offers` | Offer object | Derived from price + stock | Partial | Build at export time |
| `offers.@type = Offer` | Offer type tag | No DB field | Missing | Compute at export time |
| `offers.price` | Selling price | `item_catalog.unit_price` | Exists | Keep first-class |
| `offers.priceCurrency` | Currency code | Always `INR` in KashCube | Missing | Compute at export time |
| `offers.availability` | In stock / out of stock | Derived from `stock_qty` and/or `track_inventory` | Partial | Compute at export time |
| `offers.inventoryLevel` | Available quantity object | Derived from stock overlay | Partial | Compute at export time |
| `offers.priceValidUntil` | Price expiry | No field today | Missing | Add only if timed offers become a real feature |
| `offers.priceSpecification` | Structured pricing metadata | Derive from `unit_price`, `mrp`, `dealer_price` | Partial | Compute at export time unless pricing gets more complex |

## QuantitativeValue Mapping

| Commerce Mesh Field | Meaning | KashCube Mapping | Status | Recommendation |
|---|---|---|---|---|
| `inventoryLevel.@type = QuantitativeValue` | Type wrapper | No DB field | Missing | Compute at export time |
| `inventoryLevel.value` | Available quantity | `item_stock.stock_qty` / `stock_qty` | Exists | Compute at export time |

## PriceSpecification Mapping

| Commerce Mesh Field | Meaning | KashCube Mapping | Status | Recommendation |
|---|---|---|---|---|
| `@type = PriceSpecification` | Structured price wrapper | No DB field | Missing | Compute at export time |
| `price` | Price amount | `unit_price` | Exists | Compute/export |
| `priceCurrency` | Currency code | Always `INR` | Missing | Compute/export |

---

## India-Specific KashCube Fields Without First-Class Commerce Mesh Equivalents

These fields matter to KashCube more than they matter to the external schema, so they must remain first-class in the internal model.

| KashCube Field | Purpose | Commerce Mesh Strategy |
|---|---|---|
| `hsn_code` | GST compliance | Export via `additionalProperty` |
| `hsn_or_sac` | Product vs service tax code type | Export via `additionalProperty` |
| `tax_pct` | GST percentage | Export via `additionalProperty` or pricing extension |
| `mrp` | Legal retail ceiling | Export via `priceSpecification` or `additionalProperty` |
| `dealer_price` | Trade purchase price | Keep internal by default; export only if explicitly enabled |
| `low_stock_threshold` | Seller-side inventory behavior | Keep internal only; not required in public feed |

---

## PropertyValue / additionalProperty Mapping

| Commerce Mesh Field | Meaning | KashCube Mapping | Status | Recommendation |
|---|---|---|---|---|
| `PropertyValue.@type` | Type wrapper | No DB field | Missing | Compute at export time |
| `PropertyValue.name` | Metadata key | No generic key-value store | Missing | Store in JSON or child table |
| `PropertyValue.value` | Metadata value | No generic key-value store | Missing | Store in JSON or child table |

Best initial use of `additionalProperty` in KashCube exports:
- HSN code
- HSN/SAC type
- GST percentage
- MRP
- unit
- barcode / GTIN
- packaging info
- shelf / bin / lane identifiers

---

## Brand Mapping

| Commerce Mesh Field | Meaning | KashCube Mapping | Status | Recommendation |
|---|---|---|---|---|
| `brand.@type = Brand` | Type wrapper | No DB field | Missing | Compute at export time |
| `brand.name` | Brand name | No item field today | Missing | Add optional `brand_name` |

For Indian FMCG and kirana use cases, `brand_name` is worth adding early because it improves search, customer-facing catalog clarity, OCR matching, and future import normalization.

---

## MediaObject Mapping

| Commerce Mesh Field | Meaning | KashCube Mapping | Status | Recommendation |
|---|---|---|---|---|
| `@cmp:media` | Rich media array | No item media table | Missing | Defer to separate media model |
| `MediaObject.@type` | Media subtype (`ImageObject`, etc.) | No DB field | Missing | Compute at export time |
| `url` | Public/LAN media URL | No direct item media URL | Missing | Derive from local file path via local HTTP server |
| `contentUrl` | Direct asset URL | No field | Missing | Compute if media serving exists |
| `encodingFormat` | MIME type | No field | Missing | Compute from local file |
| `thumbnailUrl` | Thumbnail URL | No field | Missing | Defer |
| `width` | Pixel width | No field | Missing | Compute if needed |
| `height` | Pixel height | No field | Missing | Compute if needed |
| `duration` | Media duration | No field | Missing | Defer |
| `caption` | Human caption | No field | Missing | Optional later |
| `name` | Media label | No field | Missing | Optional later |
| `description` | Media description | No field | Missing | Optional later |
| `uploadDate` | Media upload date | No field | Missing | Optional later |

Important privacy rule: KashCube should store **local file paths**, not remote URLs. Export is where local media becomes a LAN URL, and only user opt-in should ever expose that beyond the LAN.

---

## ProductGroup / Variant Mapping

| Commerce Mesh Field | Meaning | KashCube Mapping | Status | Recommendation |
|---|---|---|---|---|
| `ProductGroup` | Parent group object | No variant/group model | Missing | Defer |
| `ProductGroup.@context` | Schema context | No DB field | Missing | Compute at export time |
| `ProductGroup.@type = ProductGroup` | Type tag | No DB field | Missing | Compute at export time |
| `ProductGroup.@id` | Stable group URN | No field | Missing | Add only when variants exist |
| `ProductGroup.name` | Group name | No field | Missing | Add only when variants exist |
| `ProductGroup.description` | Group description | No field | Missing | Add only when variants exist |
| `ProductGroup.brand` | Group brand | No field | Missing | Reuse future `brand_name` when added |
| `ProductGroup.category` | Group category | No field | Missing | Add only when variants exist |
| `productGroupID` | Stable group ID | No field | Missing | Add only when variants exist |
| `variesBy` | Variant axes (`size`, `color`, etc.) | No field | Missing | Add only when variants exist |
| `ProductGroup.@cmp:media` | Group media | No field | Missing | Defer |
| `isVariantOf.@type = ProductGroup` | Product-to-group reference type | No field | Missing | Defer |
| `isVariantOf.@id` | Product-to-group reference | No field | Missing | Defer |

KashCube today is essentially a **single sellable item model**, not a product-family / variant-matrix model. That is acceptable. Variants should only be added when there is a real product need such as sizes, colors, FMCG pack sizes, or pharma dosage families.

---

## Fields Already Editable in KashCube Today

Current item form already captures:
- `name`
- `sku`
- `description`
- `category`
- `unit`
- `unit_price`
- `tax_pct`
- `hsn_code`
- `hsn_or_sac`
- `mrp`
- `dealer_price`
- `track_inventory`

Still missing for deeper Commerce Mesh parity:
- variant group / variant axes
- rich media management (`item_media` + multi-asset mapping)

## Implementation Update (5 April 2026)

Implemented in app schema and item form:
- `item_catalog.brand_name` (TEXT, nullable)
- `item_catalog.primary_image_path` (TEXT, nullable)
- `item_catalog.barcode` (TEXT, nullable)
- `item_catalog.additional_properties_json` (TEXT, nullable)

Database migration:
- Schema upgraded to v86
- Migration adds the 4 columns above using additive `ALTER TABLE`
- Fresh installs include the columns in base `item_catalog` table creation

Item form information architecture (future-proof baseline):
- Tabs: Basic, Pricing, Inventory, Media, Advanced
- Accordions inside each tab to keep optional/long-tail fields discoverable without clutter
- All known item fields are now present in the form and can be saved even if not used in current workflows

This keeps KashCube's internal model business-first while making room for full Commerce Mesh export parity over time.

---

## Recommended Adoption Plan

| Priority | Change | Why |
|---|---|---|
| P0 | Keep current core item model as-is | Already covers the business-critical fields |
| P0 | Export derived Commerce Mesh feed from current model | Unlocks compatibility without schema churn |
| P1 | Add `brand_name`, `primary_image_path`, `barcode` | Highest-value commerce-facing item fields |
| P1 | Add `additional_properties_json` | Handles long-tail metadata cleanly |
| P2 | Add `item_media` table | Required for rich `@cmp:media` |
| P2 | Add `product_group_id`, variant axes/values | Only when real variants are required |
| P3 | Add timed pricing (`price_valid_until`, promotional price) | Only if public offer mechanics become real |

---

## Final Decision Matrix

| Schema Area | KashCube Strategy |
|---|---|
| Core product identity | Store directly in `item_catalog` |
| India-specific business fields | Keep directly in `item_catalog` even if Commerce Mesh does not model them cleanly |
| Public-commerce metadata | Add a small optional commerce profile |
| Long-tail product attributes | Store in JSON or child tables |
| Wrapper / typed schema objects | Compute at export time |
| Availability / inventory | Compute from per-business stock |
| Media URLs | Derive from local files via local HTTP server |
| Variants / ProductGroup | Defer until the app truly needs variants |

## Bottom Line

KashCube can support the full Commerce Mesh schema, but not every Commerce Mesh field should become a direct column on `item_catalog`.

The correct architecture is:

```
lean internal item model + optional commerce profile + export-time mapper
```

This preserves what KashCube is best at:
- privacy-first local storage
- Indian business compliance
- simple invoicing and stock workflows
- future protocol compatibility without schema bloat
