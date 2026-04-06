# P3 Management Screens Specification

**Date**: 6 April 2026  
**Version**: 1.0  
**Status**: Design Specification (Not Implemented)  
**Dependencies**: P3 schema.org/Product tables (v90), models, and repositories  

---

## Overview

This document specifies the user interface requirements for managing P3 schema.org/Product features: **Product Variants** (ProductGroups), **Product Relationships**, and **Product Reviews**. These advanced commerce features require dedicated management screens beyond the basic item catalog editor.

**Foundation Status**: ✅ Complete
- Database tables created (v90 migration)
- Models implemented (ProductGroup, ProductRelationship, ProductReview)
- Repository layer complete with CRUD operations
- ItemCatalog.productGroupId FK wired through UI

**Remaining Work**: Management UIs for creating groups, linking products, and collecting reviews.

---

## 1. Product Variant Management

### 1.1 Use Case

Enable users to group related products that vary by attributes (color, size, material, etc.) into a single **ProductGroup** for easier management and customer browsing.

**Example**: "Classic Cotton T-Shirt" product group with 12 variants (3 colors × 4 sizes).

### 1.2 Screen: Product Groups List

**Location**: New screen accessible from bottom navigation or Item Catalog screen FAB menu.

**UI Requirements**:
- List all product groups (non-deleted) ordered by name
- Each list tile shows:
  - Group name
  - Description (first line, ellipsized)
  - Variant count badge (e.g., "12 variants")
  - variesBy attributes as chips (e.g., `color`, `size`)
- Search bar filtering by group name
- FAB (+) to create new product group
- Tap tile → navigate to Product Group Detail screen
- Long-press → context menu (Edit, Delete)

**Empty State**:
```
Icon: palette_outlined
Title: "No Product Groups Yet"
Subtitle: "Create variant families for products with multiple color/size options"
Action: "Create Product Group" button
```

### 1.3 Screen: Product Group Editor (Add/Edit)

**Form Fields**:

1. **Name** (required)
   - Text field
   - Example: "Classic Cotton T-Shirt"
   - Validation: Non-empty

2. **Description** (optional)
   - Multi-line text field
   - Example: "Premium cotton t-shirt available in multiple colors and sizes"

3. **Varies By** (required)
   - Multi-select chips or checkbox list
   - Options: `color`, `size`, `material`, `pattern`, `weight`, `custom`
   - Stored as JSON array: `["color", "size"]`
   - Validation: At least one attribute selected

4. **Variant Products** (read-only in editor, managed separately)
   - Show count: "12 products in this group"
   - Button: "Manage Variants" → navigate to Variant Manager

**Actions**:
- Save button (creates/updates ProductGroup)
- Cancel button

**Validation**:
- Name must be unique
- At least one variesBy attribute

### 1.4 Screen: Variant Manager

**Purpose**: Assign/unassign items from item_catalog to a product group.

**UI Requirements**:
- Two-column layout or tabbed view:
  - **In Group**: List of items with `product_group_id = thisGroupId`
  - **Available**: List of items with `product_group_id IS NULL` matching category

**Item Display**:
- Product name
- SKU
- Variant attributes (color, size) displayed as chips
- Remove/Add button

**Bulk Actions**:
- Select multiple items
- Bulk assign/unassign

**Filter**:
- Filter available items by category (Product, Material, etc.)
- Search by name/SKU

**Workflow**:
1. User selects items from "Available" list
2. Taps "Add to Group"
3. Items' `product_group_id` updated via ItemCatalogRepository
4. Items move to "In Group" column

---

## 2. Product Relationship Management

### 2.1 Use Case

Link products as accessories, spare parts, consumables, or related items to enable cross-selling and improve customer experience.

**Examples**:
- Smartphone → Charger (accessory)
- Printer → Ink cartridge (consumable)
- Laptop → Extended warranty (related product)

### 2.2 Screen: Product Detail (Enhanced)

**Location**: Existing item catalog detail screen, add new "Relationships" section.

**UI Requirements**:
- Accordion: "Related Products"
- Shows existing relationships grouped by type:
  - **Accessories** (relationship_type = 'accessory')
  - **Spare Parts** (relationship_type = 'spare_part')
  - **Consumables** (relationship_type = 'consumable')
  - **Related Products** (relationship_type = 'related_product')

**Each Relationship Tile**:
- Related product name
- SKU
- Thumbnail image (if available)
- Price
- Remove button (deletes ProductRelationship)

**Add Relationship**:
- Button: "+ Add Related Product"
- Opens bottom sheet with:
  - Dropdown: Select relationship type
  - Searchable product picker (excludes current product)
  - Save button

**Data Flow**:
- Insert ProductRelationship: `{ product_id, related_product_id, relationship_type }`
- Repository: `ProductRelationshipRepository.insert()`

### 2.3 Screen: Relationship Manager (Optional Standalone)

**Purpose**: Bulk relationship management for power users.

**UI**:
- Two-pane master-detail layout
- Left pane: Product list (searchable, filterable)
- Right pane: Selected product's relationships (editable grid)

**Features**:
- Quick add/remove relationships
- Copy relationships from similar products
- Bulk operations

---

## 3. Product Review Management

### 3.1 Use Case

Collect and display customer reviews with star ratings to build trust and provide social proof. Calculate aggregate ratings per schema.org specifications.

### 3.2 Screen: Product Detail (Review Section)

**Location**: Item catalog detail screen, new "Reviews & Ratings" section.

**UI Requirements**:

**Aggregate Rating Display**:
```
★★★★☆ 4.3   (127 reviews)
─────────────────────────────
5 stars  [████████████████─] 89
4 stars  [████████─────────] 24
3 stars  [███──────────────] 10
2 stars  [█────────────────]  3
1 star   [█────────────────]  1
```

**Individual Reviews**:
- List of ProductReview entries
- Each review shows:
  - Star rating (1-5)
  - Review text (expandable if long)
  - Reviewer name (or "Anonymous")
  - Date created
  - Delete button (soft delete, owner only)

**Add Review** (bottom of list):
- Button: "+ Add Review"
- Opens review submission form

### 3.3 Screen: Review Submission Form

**Form Fields**:

1. **Rating** (required)
   - 5-star tappable widget
   - Default: 0 (unselected)
   - Validation: Must select 1-5 stars

2. **Review Text** (optional)
   - Multi-line text field (200-500 chars recommended)
   - Placeholder: "Share your experience with this product..."

3. **Reviewer Name** (optional)
   - Text field
   - Default: Device owner name or "Anonymous"
   - Validation: Max 50 chars

**Actions**:
- Submit button → Insert ProductReview
- Cancel button

**Validation**:
- Rating required (1-5)
- Review text max 1000 characters

**Post-Submit**:
- Close form
- Refresh product detail to show new review
- Recalculate aggregate rating via `ProductReviewRepository.getAggregateRating()`

### 3.4 Aggregate Rating Calculation

**Repository Method**: `ProductReviewRepository.getAggregateRating(productId)`

**Returns**:
```dart
{
  'averageRating': 4.3,  // AVG(rating)
  'reviewCount': 127,    // COUNT(*)
}
```

**Usage**:
- Display on product list tiles: "★ 4.3 (127)"
- Export to schema.org JSON:
  ```json
  "aggregateRating": {
    "@type": "AggregateRating",
    "ratingValue": 4.3,
    "reviewCount": 127
  }
  ```

---

## 4. Navigation & Entry Points

### 4.1 Access from Item Catalog Screen

**Enhanced Item Catalog Detail Screen** (existing screen):

Add three new sections (accordions or tabs):

1. **Variant Group** (if productGroupId != null)
   - Shows: "Part of: [Group Name]"
   - Button: "View All Variants" → navigate to Product Group Detail
   - Button: "Remove from Group" → set productGroupId = null

2. **Related Products**
   - Shows list of relationships
   - Button: "+ Add Related Product"

3. **Reviews & Ratings**
   - Shows aggregate rating + review list
   - Button: "+ Add Review"

### 4.2 New Bottom Navigation Tab (Optional)

**"Commerce" Tab** (if P3 features heavily used):
- Product Groups list
- Relationship Manager
- Review Analytics (future: review statistics dashboard)

### 4.3 FAB Menu Enhancement

**Item Catalog Screen FAB**:
- Add Item (existing)
- **New**: Create Product Group
- **New**: Manage Relationships

---

## 5. Data Synchronization

All P3 tables include sync metadata (`sync_id`, `version`, `context_id`). Ensure sync coordinator handles:

- ProductGroups: Sync group definitions
- ProductRelationships: Sync cross-device
- ProductReviews: Sync as read-only from other devices (reviews tied to original device)

**Conflict Resolution**:
- ProductGroups: LWW by `updated_at`
- ProductRelationships: LWW, dedup by (product_id, related_product_id, relationship_type)
- ProductReviews: Append-only (no conflicts, reviews are immutable once created)

---

## 6. Implementation Priority

### Phase 1: Product Groups (2-3 weeks)
- Product Groups list screen
- Product Group editor
- Variant manager (assign/unassign items)
- Update item catalog detail to show group membership

### Phase 2: Product Relationships (1-2 weeks)
- Add relationships section to item catalog detail
- Relationship creation bottom sheet
- Delete relationship functionality

### Phase 3: Product Reviews (1-2 weeks)
- Review submission form
- Review display in item catalog detail
- Aggregate rating calculation + display
- Star rating visualization

---

## 7. UI/UX Considerations

### 7.1 Theme Compliance

- Use `AppSpacing` constants for all padding/margins
- Use `KashCubeColors` for semantic colors
- Material Design 3 components (Card, BottomSheet, Dialog)
- All touch targets ≥ 48dp

### 7.2 Empty States

Every list screen needs an empty state with:
- Icon (160x160 gray outline)
- Title (1-2 words)
- Subtitle (1 sentence explaining benefit)
- Primary action button

### 7.3 Loading States

- Shimmer placeholders for list loading
- Circular progress indicator for form submissions
- Skeleton screens for detail views

### 7.4 Error Handling

- Toast messages for CRUD operation failures
- Inline validation errors on forms
- Retry buttons for network/database errors

---

## 8. Testing Requirements

### 8.1 Unit Tests

- ProductGroupRepository CRUD operations
- ProductRelationshipRepository getAllForProduct()
- ProductReviewRepository getAggregateRating() with various scenarios:
  - No reviews (0.0, count 0)
  - Single review
  - Mixed ratings
  - All 5-star reviews

### 8.2 Widget Tests

- Product Groups list (empty + populated)
- Product Group editor form validation
- Review submission form (star rating widget, text validation)
- Aggregate rating display accuracy

### 8.3 Integration Tests

- Create product group → assign variants → verify product_group_id
- Add relationship → delete relationship → verify soft delete
- Submit review → refresh → verify aggregate rating updates

---

## 9. Future Enhancements (Post-P3)

### 9.1 Variant Matrix Editor

Visual grid for creating variants:
```
           Size
        S   M   L   XL
Color
Red    [✓] [✓] [✓] [ ]
Blue   [✓] [✓] [✓] [✓]
Green  [✓] [ ] [✓] [ ]
```
- Auto-generate SKUs for selected combinations
- Bulk price assignment
- Stock level matrix

### 9.2 Review Moderation

- Flag inappropriate reviews
- Admin approval workflow
- Review responses (seller replies to reviews)

### 9.3 Review Analytics

- Review sentiment analysis
- Review trend dashboard
- Most reviewed products

### 9.4 Relationship Recommendations

- ML-based "Customers also bought" suggestions
- Auto-suggest relationships based on purchase patterns

---

## 10. Success Metrics

- **Adoption**: % of products with assigned ProductGroup
- **Engagement**: # of product relationships created per user
- **Quality**: Average review length (target: 50+ chars)
- **Coverage**: % of products with ≥1 review

---

## Appendix A: Wireframe Sketches

**Product Groups List**:
```
┌─────────────────────────────────┐
│ [Search Product Groups...]      │
├─────────────────────────────────┤
│ Classic Cotton T-Shirt      [12]│
│ 100% cotton, multiple colors    │
│ [color] [size]                  │
├─────────────────────────────────┤
│ Leather Wallet Collection    [6]│
│ Genuine leather, 2 colors       │
│ [color] [material]              │
└─────────────────────────────────┘
                               [+]
```

**Review Submission Form**:
```
┌─────────────────────────────────┐
│ Add Review                      │
├─────────────────────────────────┤
│ Rating *                        │
│ ☆ ☆ ☆ ☆ ☆                      │
├─────────────────────────────────┤
│ Review Text (optional)          │
│ ┌───────────────────────────┐   │
│ │ Share your experience...  │   │
│ │                           │   │
│ └───────────────────────────┘   │
├─────────────────────────────┤
│ Your Name                       │
│ [Anonymous            ]         │
├─────────────────────────────────┤
│        [Cancel]  [Submit]       │
└─────────────────────────────────┘
```

---

## Appendix B: Code Templates

### B.1 ProductGroupProvider (Riverpod)

```dart
final productGroupRepositoryProvider = Provider<ProductGroupRepository>((ref) {
  final contextId = ref.watch(activeBusinessContextProvider);
  return ProductGroupRepositoryImpl(contextId: contextId);
});

final productGroupListProvider = 
    StateNotifierProvider<ProductGroupNotifier, AsyncValue<List<ProductGroup>>>(
  (ref) => ProductGroupNotifier(ref.read(productGroupRepositoryProvider)),
);

class ProductGroupNotifier extends StateNotifier<AsyncValue<List<ProductGroup>>> {
  ProductGroupNotifier(this._repository) : super(const AsyncValue.loading()) {
    loadAll();
  }

  final ProductGroupRepository _repository;

  Future<void> loadAll() async {
    state = const AsyncValue.loading();
    try {
      final groups = await _repository.getAll();
      state = AsyncValue.data(groups);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> save(ProductGroup group) async {
    if (group.id == null) {
      await _repository.insert(group);
    } else {
      await _repository.update(group);
    }
    await loadAll();
  }

  Future<void> delete(int id) async {
    await _repository.delete(id);
    await loadAll();
  }
}
```

### B.2 Review Submission Form Widget

```dart
class ReviewSubmissionForm extends StatefulWidget {
  final int productId;
  final VoidCallback onSubmit;

  const ReviewSubmissionForm({
    required this.productId,
    required this.onSubmit,
  });

  @override
  State<ReviewSubmissionForm> createState() => _ReviewSubmissionFormState();
}

class _ReviewSubmissionFormState extends State<ReviewSubmissionForm> {
  final _formKey = GlobalKey<FormState>();
  final _reviewTextCtrl = TextEditingController();
  final _reviewerNameCtrl = TextEditingController(text: 'Anonymous');
  int _rating = 0;

  @override
  void dispose() {
    _reviewTextCtrl.dispose();
    _reviewerNameCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_rating == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a rating')),
      );
      return;
    }

    final review = ProductReview(
      productId: widget.productId,
      rating: _rating,
      reviewText: _reviewTextCtrl.text.trim().isEmpty 
          ? null 
          : _reviewTextCtrl.text.trim(),
      reviewerName: _reviewerNameCtrl.text.trim().isEmpty 
          ? null 
          : _reviewerNameCtrl.text.trim(),
      createdAt: DateTime.now(),
    );

    final repo = context.read<ProductReviewRepository>();
    await repo.insert(review);
    
    widget.onSubmit();
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Rating *', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(5, (i) {
              final starIndex = i + 1;
              return IconButton(
                icon: Icon(
                  starIndex <= _rating ? Icons.star : Icons.star_border,
                  color: Colors.amber,
                ),
                iconSize: 40,
                onPressed: () => setState(() => _rating = starIndex),
              );
            }),
          ),
          const SizedBox(height: AppSpacing.base),
          TextFormField(
            controller: _reviewTextCtrl,
            maxLines: 4,
            maxLength: 1000,
            decoration: const InputDecoration(
              labelText: 'Review Text (optional)',
              hintText: 'Share your experience with this product...',
            ),
          ),
          const SizedBox(height: AppSpacing.base),
          TextFormField(
            controller: _reviewerNameCtrl,
            decoration: const InputDecoration(labelText: 'Your Name'),
            validator: (v) => (v?.length ?? 0) > 50 
                ? 'Max 50 characters' 
                : null,
          ),
          const SizedBox(height: AppSpacing.base),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              const SizedBox(width: AppSpacing.md),
              ElevatedButton(
                onPressed: _submit,
                child: const Text('Submit'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
```

---

**End of Specification**
