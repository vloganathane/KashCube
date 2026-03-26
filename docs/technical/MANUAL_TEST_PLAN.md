# KashCube Manual Testing Plan

**Version:** 1.0  
**Date:** 26 Mar 2026  
**Owner:** QA / Product / Dev

## 1) Purpose

This is a practical manual QA checklist for KashCube covering:
- All current screens in `lib/presentation/screens/**`
- Major forms and validation flows
- Core product features (privacy-first local finance workflows)

---

## 2) Test Setup (before every pass)

- [ ] Run latest build on target device(s) (Android primary, macOS/web companion if needed).
- [ ] Start with a clean DB and also run one pass with realistic seeded data.
- [ ] Verify app is offline (airplane mode) for privacy/local-first validation.
- [ ] Grant/deny permissions in separate runs (SMS, notifications, local auth).
- [ ] Enable dark mode and verify key screens.
- [ ] Validate Indian locale formatting (`₹1,23,456`, `24 Mar 2026`, `6:30 PM`).

---

## 3) Screen-by-Screen Smoke Checklist

Use this default smoke expectation for each screen unless noted otherwise:
- Screen opens without crash/red screen
- Core UI loads with expected empty/data state
- Back/navigation works correctly
- No dispose/mounted errors in logs after navigation

Legend:
- `[Form]` = screen contains a primary data-entry or configuration form that should be validated beyond smoke testing

### Screen Count Summary

| Feature Area | Screen Count |
|---|---:|
| Auth & Onboarding | 6 |
| Home, Search, Navigation Hubs | 7 |
| Transactions & Ledger | 10 |
| Invoices, Quotes, Catalog, Challans | 8 |
| GST & Compliance | 6 |
| Reports & Analytics | 3 |
| Bills, Recurring, Notifications | 4 |
| Bookings & Staff | 6 |
| Inventory, Contacts, Business Utilities | 4 |
| Settings & Admin | 15 |
| **Total Implemented Screens** | **69** |

### 3.1 Auth & Onboarding (6 screens)

Form screens: `auth/setup_wizard_screen.dart`, `auth/staff_pin_screen.dart`, `auth/terms_gate_screen.dart`, `settings/pin_lock_screen.dart`, `settings/sms_permission_screen.dart`

- [ ] `auth/user_selection_screen.dart` — select user/business profile, proceed.
- [ ] `auth/setup_wizard_screen.dart` [Form] — complete initial setup steps end-to-end.
- [ ] `auth/staff_pin_screen.dart` [Form] — PIN entry/validation and failure states.
- [ ] `auth/terms_gate_screen.dart` [Form] — accept terms flow and continue.
- [ ] `settings/pin_lock_screen.dart` [Form] — lock/unlock and retry flow.
- [ ] `settings/sms_permission_screen.dart` [Form] — allow/deny flows both work.

### 3.2 Home, Search, Navigation Hubs (7 screens)

Form screens: `home/customize_home_screen.dart`, `search/search_screen.dart`

- [ ] `home/home_screen.dart` — dashboard summary cards and recent activity render.
- [ ] `home/action_center_screen.dart` — quick actions navigate correctly.
- [ ] `home/customize_home_screen.dart` [Form] — save/reload home configuration.
- [ ] `search/search_screen.dart` [Form] — global search returns expected entities.
- [ ] `transactions/transactions_hub_screen.dart` — section navigation works.
- [ ] `contacts/contacts_hub_screen.dart` — section navigation works.
- [ ] `business/business_hub_screen.dart` — business modules open correctly.

### 3.3 Transactions & Ledger (10 screens)

Form screens: `transactions/add_edit_transaction_screen.dart`, `transactions/category_management_screen.dart`, `ledger/credits_screen.dart`, `loans/loans_screen.dart`, `parties/parties_screen.dart`, `parties/party_360_screen.dart`

- [ ] `transactions/transactions_screen.dart` — list, filter, empty state.
- [ ] `transactions/add_edit_transaction_screen.dart` [Form] — add/edit transaction flow.
- [ ] `transactions/transaction_detail_screen.dart` — details, actions, delete confirm.
- [ ] `transactions/bill_viewer_screen.dart` — attachment preview/open/share.
- [ ] `transactions/category_management_screen.dart` [Form] — add/edit/delete category flow.
- [ ] `ledger/ledger_screen.dart` — balances and party rollups.
- [ ] `ledger/credits_screen.dart` [Form] — active/settled credits, totals.
- [ ] `loans/loans_screen.dart` [Form] — loan list, status, basic actions.
- [ ] `parties/parties_screen.dart` [Form] — party list, search, open detail.
- [ ] `parties/party_360_screen.dart` [Form] — consolidated party timeline/details.

### 3.4 Invoices, Quotes, Catalog, Challans (8 screens)

Form screens: `invoices/quote_builder_screen.dart`, `invoices/item_catalog_screen.dart`, `invoices/invoice_detail_screen.dart`, `invoices/quote_detail_screen.dart`, `invoices/delivery_challan_detail_screen.dart`

- [ ] `invoices/invoices_screen.dart` — invoice list and status chips.
- [ ] `invoices/invoice_detail_screen.dart` [Form] — detail card, actions, PDF/share.
- [ ] `invoices/quote_builder_screen.dart` [Form] — create/edit quote, totals, save.
- [ ] `invoices/quote_detail_screen.dart` [Form] — sent/convert/reject actions + activity card.
- [ ] `invoices/item_catalog_screen.dart` [Form] — item CRUD, pricing/tax consistency.
- [ ] `invoices/delivery_challans_screen.dart` — challan list and status.
- [ ] `invoices/delivery_challan_detail_screen.dart` [Form] — detail and linked invoice actions.
- [ ] `invoices/ewb_preview_screen.dart` — e-way bill preview rendering.

### 3.5 GST & Compliance (6 screens)

Form screens: `gst/add_purchase_bill_screen.dart`, `gst/gstr3b_offset_screen.dart`, `gst/gstr_period_picker.dart`

- [ ] `gst/purchase_bills_screen.dart` — list and filters.
- [ ] `gst/add_purchase_bill_screen.dart` [Form] — add/edit bill with tax fields.
- [ ] `gst/purchase_bill_detail_screen.dart` — details and action flow.
- [ ] `gst/gstr1_screen.dart` — period data and export actions.
- [ ] `gst/gstr3b_offset_screen.dart` [Form] — offset calculation and confirm flow.
- [ ] `gst/gstr_period_picker.dart` [Form] — period selection UX and state sync.

### 3.6 Reports & Analytics (3 screens)

Form screens: `reports/budget_screen.dart`

- [ ] `reports/reports_screen.dart` — report cards and navigation.
- [ ] `reports/cash_flow_screen.dart` — trend chart/date-range updates.
- [ ] `reports/budget_screen.dart` [Form] — budget set/edit/overspend visuals.

### 3.7 Bills, Recurring, Notifications (4 screens)

Form screens: `recurring/recurring_transactions_screen.dart`, `settings/notification_settings_screen.dart`

- [ ] `bills/bills_screen.dart` — bill list and status progression.
- [ ] `bills/bills_and_payments_screen.dart` — bills/payments reconciliation.
- [ ] `recurring/recurring_transactions_screen.dart` [Form] — recurring rules CRUD.
- [ ] `notifications/` related screens (if routed) — render and action handling.
- [ ] `settings/notification_settings_screen.dart` [Form] — preference persistence.

### 3.8 Bookings & Staff (6 screens)

Form screens: `bookings/create_booking_screen.dart`, `staff/staff_screen.dart`, `staff/staff_detail_screen.dart`

- [ ] `bookings/bookings_screen.dart` — booking list and status flow.
- [ ] `bookings/create_booking_screen.dart` [Form] — create/edit booking validation.
- [ ] `bookings/booking_detail_screen.dart` — booking details and actions.
- [ ] `staff/staff_screen.dart` [Form] — entry screen and navigation.
- [ ] `staff/staff_list_screen.dart` — list/search/filter.
- [ ] `staff/staff_detail_screen.dart` [Form] — profile details and update actions.

### 3.9 Inventory, Contacts, Business Utilities (4 screens)

Form screens: `inventory/inventory_screen.dart`, `business/tally_export_screen.dart`, `settings/open_on_laptop_screen.dart`

- [ ] `inventory/inventory_screen.dart` [Form] — stock levels and adjustment actions.
- [ ] `business/global_document_ledger_screen.dart` — document timeline integrity.
- [ ] `business/tally_export_screen.dart` [Form] — export trigger/file generation.
- [ ] `settings/open_on_laptop_screen.dart` [Form] — LAN/connectivity UX.

### 3.10 Settings & Admin (15 screens)

Form screens: `settings/settings_screen.dart`, `settings/profile_screen.dart`, `settings/businesses_screen.dart`, `settings/manage_users_screen.dart`, `settings/user_permissions_screen.dart`, `settings/accounts_manage_screen.dart`, `settings/unit_types_screen.dart`, `settings/document_terms_screen.dart`, `settings/template_list_screen.dart`, `settings/template_builder_screen.dart`, `settings/encrypted_backup_screen.dart`, `settings/storage_health_screen.dart`, `settings/fy_close_wizard_screen.dart`, `settings/my_personal_card_screen.dart`, `settings/upgrade_screen.dart`

- [ ] `settings/settings_screen.dart` [Form] — all sections accessible.
- [ ] `settings/profile_screen.dart` [Form] — profile save and reload.
- [ ] `settings/businesses_screen.dart` [Form] — add/switch business context.
- [ ] `settings/manage_users_screen.dart` [Form] — user CRUD and constraints.
- [ ] `settings/user_permissions_screen.dart` [Form] — role-based toggles persist.
- [ ] `settings/accounts_manage_screen.dart` [Form] — account CRUD and active state.
- [ ] `settings/unit_types_screen.dart` [Form] — unit type CRUD.
- [ ] `settings/document_terms_screen.dart` [Form] — terms save + document usage.
- [ ] `settings/template_list_screen.dart` [Form] — template listing and open flow.
- [ ] `settings/template_builder_screen.dart` [Form] — create/edit template.
- [ ] `settings/encrypted_backup_screen.dart` [Form] — backup/restore happy+failure paths.
- [ ] `settings/storage_health_screen.dart` [Form] — storage stats and cleanup actions.
- [ ] `settings/fy_close_wizard_screen.dart` [Form] — fiscal-year close flow safety checks.
- [ ] `settings/my_personal_card_screen.dart` [Form] — profile/business card rendering.
- [ ] `settings/upgrade_screen.dart` [Form] — paywall display and gated action fallback.

### 3.11 Detailed Test Cases By Screen

Each screen below should be tested in both empty/minimal-data and realistic-data states where applicable.

#### 3.11.1 Auth & Onboarding

`auth/user_selection_screen.dart`
- Open with one user and multiple users; verify the correct profiles are shown.
- Select a user/business and continue; verify the correct context is loaded afterward.
- Back out and reopen; verify no duplicate selection side effects or wrong persisted user.

`auth/setup_wizard_screen.dart` [Form]
- Complete the full wizard with valid inputs; verify app lands on the expected home flow.
- Leave required fields empty on each step; verify inline validation and blocked progression.
- Cancel or background the app mid-wizard, return, and verify draft state/resume behavior.

`auth/staff_pin_screen.dart` [Form]
- Enter correct PIN and verify access is granted immediately.
- Enter wrong PIN repeatedly and verify error feedback and retry handling.
- Use short PIN, non-complete PIN, and backspace flows; verify no crash and correct field behavior.

`auth/terms_gate_screen.dart` [Form]
- Open terms gate on fresh setup and verify continue is blocked until acceptance if required.
- Accept terms and continue; verify acceptance persists after app relaunch.
- Dismiss/back navigation and verify user cannot bypass the gate unintentionally.

`settings/pin_lock_screen.dart` [Form]
- Lock and unlock with valid PIN; verify protected content is inaccessible until unlock.
- Test invalid PIN entry, partial entry, and retry states.
- Resume app from background and verify lock behavior matches current settings.

`settings/sms_permission_screen.dart` [Form]
- Choose allow and verify permission request is shown and result is handled correctly.
- Choose deny/skip and verify the app remains usable with manual-entry fallback.
- Reopen permission screen after prior choice and verify state messaging is accurate.

#### 3.11.2 Home, Search, Navigation Hubs

`home/home_screen.dart`
- Open with no business data and verify empty state, CTA visibility, and no layout overflow.
- Open with transactions/invoices/credits present and verify all summary cards match stored data.
- Use top-level actions/FAB/navigation from home and verify correct target screens open.

`home/action_center_screen.dart`
- Open action center and verify each quick action routes to the correct module.
- Trigger actions from both empty and populated data states.
- Verify unavailable/gated actions show the correct disabled state or upsell flow.

`home/customize_home_screen.dart` [Form]
- Change visible widgets/cards and save; verify home screen reflects the new configuration.
- Toggle options rapidly and navigate back without saving; verify expected persistence behavior.
- Reopen after relaunch and confirm settings were stored correctly.

`search/search_screen.dart` [Form]
- Search for transactions, parties, invoices, and quotes using partial and exact terms.
- Verify empty query, no-results query, and special characters do not break the screen.
- Tap results from different entity types and confirm correct deep navigation.

`transactions/transactions_hub_screen.dart`
- Open the hub and verify all expected entry points are visible.
- Tap each navigation card/button and confirm the correct module opens.
- Return from child screens and verify hub state remains stable.

`contacts/contacts_hub_screen.dart`
- Open with no contacts and verify empty messaging.
- Open with contacts/parties data and verify cards/counts are correct.
- Navigate to linked contact/party workflows and verify correct context is passed.

`business/business_hub_screen.dart`
- Open hub and verify business modules, summaries, and CTAs render.
- Enter each linked business utility and verify correct navigation.
- Switch active business, reopen hub, and verify values refresh correctly.

#### 3.11.3 Transactions & Ledger

`transactions/transactions_screen.dart`
- Verify list renders correctly with many items, no items, and mixed income/expense entries.
- Apply search/filter/sort options and confirm result counts and totals update correctly.
- Tap item rows, FAB, and filter reset; verify navigation and state restoration.

`transactions/add_edit_transaction_screen.dart` [Form]
- Create income and expense transactions with valid values and verify persistence in list/detail.
- Test required-field validation, zero/negative amount, long notes, and missing category.
- Edit an existing transaction and confirm updates propagate to home/reports/search.

`transactions/transaction_detail_screen.dart`
- Open an existing transaction and verify amount, category, method, notes, and timestamps.
- Use edit/delete/share or attachment actions if available and confirm outcomes.
- Delete with cancel and confirm flows; verify list updates only on confirm.

`transactions/bill_viewer_screen.dart`
- Open supported bill/attachment files and verify rendering or file-open flow works.
- Try share/open/download actions and verify platform-specific behavior is stable.
- Test invalid or missing file references and verify graceful error handling.

`transactions/category_management_screen.dart` [Form]
- Add a new category and verify it appears in transaction forms immediately.
- Edit and delete categories where allowed; verify linked transactions behave correctly.
- Test duplicate names and empty input validation.

`ledger/ledger_screen.dart`
- Open with no parties and verify empty state messaging.
- Open with multiple parties and verify balances, ordering, and totals.
- Navigate to party-specific details and back; verify list state remains correct.

`ledger/credits_screen.dart` [Form]
- Add a new credit and verify it appears in active credits and related party views.
- Record partial and full repayment if supported; verify remaining balance and status.
- Test invalid amount, due-date edge cases, and cancel flow.

`loans/loans_screen.dart` [Form]
- Create or update a loan entry and verify list totals/status values refresh.
- Test repayment or closure actions if available.
- Validate required fields and boundary amounts/dates.

`parties/parties_screen.dart` [Form]
- Add or edit a party and verify it becomes selectable from invoice/transaction forms.
- Search/filter parties and verify results are accurate.
- Test duplicate names/contact values and deletion/merge flows if available.

`parties/party_360_screen.dart` [Form]
- Open a party with linked transactions, invoices, credits, and verify consolidated timeline accuracy.
- Use inline actions like note/update/contact/document actions if available.
- Verify totals remain consistent with underlying modules after edits.

#### 3.11.4 Invoices, Quotes, Catalog, Challans

`invoices/invoices_screen.dart`
- Open with no invoices and verify empty state + create CTA.
- Open with draft, sent, paid, overdue, and cancelled invoices; verify status chips and ordering.
- Use filters/search and verify correct subsets are shown.

`invoices/invoice_detail_screen.dart` [Form]
- Open invoice details and verify amounts, taxes, party info, and payment state are accurate.
- Use edit/share/PDF/mark-paid or related actions if available; verify all side effects.
- Confirm linked stock, reports, and list status remain synchronized after changes.

`invoices/quote_builder_screen.dart` [Form]
- Create a quote with one and multiple items; verify subtotal, tax, and total calculations.
- Save as draft, reopen, edit, and verify all fields persist correctly.
- Test invalid states: no customer, no items, zero qty/rate, and rounding edge cases.

`invoices/quote_detail_screen.dart` [Form]
- Open quotes in draft, sent, accepted, and rejected states; verify bottom bar actions per status.
- Share a draft and verify sent state, activity log entry, and no lifecycle crash.
- Reject with preset reason and custom reason; verify history updates immediately.
- Convert to invoice and verify invoice creation, quote status update, and linked navigation.

`invoices/item_catalog_screen.dart` [Form]
- Add, edit, and delete item catalog entries; verify fields like price, tax, and unit persist.
- Reuse catalog item in quote/invoice forms and verify values auto-fill correctly.
- Test duplicate SKU/name cases and invalid price/tax boundaries.

`invoices/delivery_challans_screen.dart`
- Open with empty and populated data sets; verify challan statuses and filters.
- Open challan detail from list and verify correct document is shown.
- Verify any create/convert/list action updates list state correctly.

`invoices/delivery_challan_detail_screen.dart` [Form]
- Open a challan and verify items, party details, and linked-document information.
- Convert/link to invoice if supported and verify stock/document state changes.
- Test edit/cancel/close flows and confirmation prompts.

`invoices/ewb_preview_screen.dart`
- Open preview with valid data and verify all e-way bill fields render correctly.
- Test large/long values and verify layout remains readable.
- Trigger export/share/print if available and verify no crash.

#### 3.11.5 GST & Compliance

`gst/purchase_bills_screen.dart`
- Verify empty state, populated state, filters, and status/tax summaries.
- Navigate to add/detail screens and verify return-to-list refresh.
- Confirm list totals match created purchase bills.

`gst/add_purchase_bill_screen.dart` [Form]
- Create purchase bills with taxable and non-taxable items; verify totals and tax breakdown.
- Edit existing bills and confirm list/detail/stock effects refresh correctly.
- Test supplier required fields, invalid tax values, and date/invoice-number validation.

`gst/purchase_bill_detail_screen.dart`
- Verify supplier, line items, taxes, totals, and metadata render correctly.
- Use edit/delete/share actions if available and verify behavior.
- Confirm related stock changes remain correct after edits or deletion.

`gst/gstr1_screen.dart`
- Select different periods and verify tables/cards update with correct data.
- Test with no eligible records and ensure empty state is clear.
- Trigger export/download actions and verify the generated output is valid.

`gst/gstr3b_offset_screen.dart` [Form]
- Open with available liability/input data and verify computed offsets are sensible.
- Change offset inputs/options and verify recalculated values update correctly.
- Attempt invalid confirmation states and verify blocking/validation messaging.

`gst/gstr_period_picker.dart` [Form]
- Select month/year combinations and verify linked GST screens update correctly.
- Reopen picker and verify previous selection is preserved where expected.
- Test cancel/reset flows and invalid edge navigation across periods.

#### 3.11.6 Reports & Analytics

`reports/reports_screen.dart`
- Open with no data and verify report cards handle empty states without error.
- Open with realistic data and verify KPI cards align with underlying modules.
- Navigate to sub-reports and verify filters/context pass through.

`reports/cash_flow_screen.dart`
- Change date range and verify chart/list data updates correctly.
- Test very small and very large datasets for rendering performance and readability.
- Verify totals align with transactions for the same date range.

`reports/budget_screen.dart` [Form]
- Create or edit a budget and verify amounts persist and affect report visuals.
- Test overspend/under-budget states and verify color/status cues.
- Validate required fields and amount boundaries.

#### 3.11.7 Bills, Recurring, Notifications

`bills/bills_screen.dart`
- Open with upcoming, overdue, and paid bills; verify status labels and sorting.
- Create/open related bill actions if available and confirm list refresh.
- Verify reminder indicators and due-date presentation.

`bills/bills_and_payments_screen.dart`
- Verify bill/payment linkage and aggregate summaries are correct.
- Apply filters/date scopes if available and verify resulting balances.
- Navigate to linked bill/payment detail items and back.

`recurring/recurring_transactions_screen.dart` [Form]
- Create recurring rules with different frequencies and verify they save correctly.
- Edit, pause, resume, and delete rules if supported.
- Validate recurrence parameters, next-run dates, and duplicate-prevention behavior.

`notifications/` related screens (if routed)
- Open every routed notification-related screen and verify no broken navigation.
- Trigger notification-origin deep links and verify correct destination state.
- Verify empty and populated notification states if a list exists.

`settings/notification_settings_screen.dart` [Form]
- Toggle reminder/notification preferences and verify persistence after relaunch.
- Disable notifications at OS level and verify the screen handles denied permission gracefully.
- Verify settings affect actual reminder scheduling behavior.

#### 3.11.8 Bookings & Staff

`bookings/bookings_screen.dart`
- Open with empty and populated booking data and verify statuses and list ordering.
- Use search/filter actions if available and verify results.
- Navigate to create/detail flows and confirm list refresh on return.

`bookings/create_booking_screen.dart` [Form]
- Create a booking with valid party/date/time inputs and verify detail/list persistence.
- Edit existing booking and confirm changes propagate correctly.
- Test missing required fields, past-date edge cases, and invalid schedule combinations.

`bookings/booking_detail_screen.dart`
- Verify booking metadata, linked party/contact, and status timeline render correctly.
- Perform status changes or linked actions if available and confirm updates.
- Verify back navigation returns to the expected filtered list state.

`staff/staff_screen.dart` [Form]
- Use entry actions to add or configure staff and verify navigation to the correct subflow.
- Verify permissions or gating if staff features depend on business/user state.
- Test cancel/submit flows and post-save refresh.

`staff/staff_list_screen.dart`
- Verify staff list renders correct names, roles, statuses, and search/filter behavior.
- Open staff detail and back; verify state retention.
- Test empty state when no staff exist.

`staff/staff_detail_screen.dart` [Form]
- Edit staff details/permissions/PIN-related attributes if supported and verify persistence.
- Test invalid contact/role combinations and blocked destructive actions.
- Verify changes are reflected immediately in staff list and permissions flow.

#### 3.11.9 Inventory, Contacts, Business Utilities

`inventory/inventory_screen.dart` [Form]
- Verify stock list renders correctly with zero, low, and healthy stock states.
- Perform stock adjustment or related actions if supported and verify totals update.
- Cross-check stock changes against invoice and purchase bill flows.

`business/global_document_ledger_screen.dart`
- Open with mixed document types and verify timeline ordering and linking.
- Filter/search by document type if available and verify results.
- Open linked document details and return without state loss.

`business/tally_export_screen.dart` [Form]
- Trigger export with valid dataset and verify file generation succeeds.
- Test no-data export and verify clear messaging.
- Validate key export settings/format choices and resulting file naming.

`settings/open_on_laptop_screen.dart` [Form]
- Open the screen and verify LAN/local companion instructions are visible and accurate.
- Start the flow if interactive and verify generated URL/code updates correctly.
- Test unavailable network/LAN conditions and verify graceful handling.

#### 3.11.10 Settings & Admin

`settings/settings_screen.dart` [Form]
- Open settings and verify all major sections are visible and navigable.
- Change lightweight toggles/preferences if present and verify persistence.
- Return to settings after other operations and confirm no stale state.

`settings/profile_screen.dart` [Form]
- Update profile fields and verify changes persist after relaunch.
- Test invalid input formats and required-field constraints.
- Verify profile data is reused correctly in documents/settings summaries.

`settings/businesses_screen.dart` [Form]
- Add a new business and verify it becomes selectable as active context.
- Edit and switch businesses; verify business-scoped data refreshes correctly.
- Test required identity/tax fields and duplicate business naming edge cases.

`settings/manage_users_screen.dart` [Form]
- Add, edit, and remove users if supported; verify role constraints are enforced.
- Test duplicate identifiers and permission-bound actions.
- Verify user changes appear correctly in user-selection/auth flows.

`settings/user_permissions_screen.dart` [Form]
- Toggle permissions by role/user and save; verify persistence.
- Test restricted actions in-app afterward and confirm enforcement.
- Reopen the screen and verify saved permission state is accurate.

`settings/accounts_manage_screen.dart` [Form]
- Add/edit/deactivate accounts and verify lists/forms use updated account data.
- Test duplicate names, zero/opening balance boundaries, and active/inactive filtering.
- Confirm account changes reflect in transaction-related screens.

`settings/unit_types_screen.dart` [Form]
- Add/edit/delete unit types and verify usage in item catalog/forms.
- Test duplicate names/abbreviations and empty values.
- Reopen dependent forms and confirm unit values are available immediately.

`settings/document_terms_screen.dart` [Form]
- Update quote/invoice terms and verify saved values are used in generated documents.
- Test long text, multiline content, and empty reset behavior.
- Reopen and verify persistence after app relaunch.

`settings/template_list_screen.dart` [Form]
- Verify templates list loads correctly and opens the selected template for edit/use.
- Create, duplicate, rename, or delete templates if supported.
- Test empty-template state and duplicate-name handling.

`settings/template_builder_screen.dart` [Form]
- Create/edit a template and verify placeholders, formatting, and save/reopen behavior.
- Test invalid placeholder syntax or unsupported tokens and verify handling.
- Preview/use resulting template in the related feature if available.

`settings/encrypted_backup_screen.dart` [Form]
- Create an encrypted backup with valid password flow and verify file creation.
- Attempt restore with correct and incorrect password and verify responses.
- Test cancel, missing file, and corrupted-file handling.

`settings/storage_health_screen.dart` [Form]
- Verify storage metrics render and update after cleanup or backup actions.
- Trigger cleanup/archive actions if available and verify results.
- Test low-storage or empty-state behavior gracefully.

`settings/fy_close_wizard_screen.dart` [Form]
- Walk through fiscal-year close with valid preconditions and verify confirmation safeguards.
- Test blocked close when prerequisites are missing or inconsistent.
- Verify post-close reporting/context behavior matches selected fiscal year.

`settings/my_personal_card_screen.dart` [Form]
- Update personal/business card details and verify rendered preview accuracy.
- Test share/export action if available.
- Validate persistence and formatting of phone/address/social/contact fields.

`settings/upgrade_screen.dart` [Form]
- Open from a gated feature and verify the correct plan context/reason is shown.
- Test back/cancel flow and verify the original gated action does not proceed unintentionally.
- Verify fallback options like continue with watermark or limited mode when applicable.

---

## 4) Forms & Validation Checklist

For each form, test: required fields, invalid values, boundary values, cancel flow, edit flow, persistence after relaunch.

- [ ] Transaction form (`add_edit_transaction_screen.dart`)
  - Required: amount, type/category as applicable
  - Validation: negative/zero amount, large amount, long notes
- [ ] Credit entry/edit flow (`credits_screen.dart` dialogs/forms)
  - Required: party/customer + amount
  - Validation: due date before created date, settle partial/full
- [ ] Quote builder form (`quote_builder_screen.dart`)
  - Required: customer, at least one item, qty/rate > 0
  - Validation: tax/discount rounding, draft vs sent transitions
- [ ] Invoice create/edit flow (invoice module forms/dialogs)
  - Validation: numbering, linked quote conversion, payment status changes
- [ ] Purchase bill form (`add_purchase_bill_screen.dart`)
  - Validation: GST fields, tax totals, supplier selection
- [ ] Booking create form (`create_booking_screen.dart`)
  - Validation: date/time consistency and mandatory party/contact
- [ ] Staff profile form (staff module add/edit)
  - Validation: role constraints, duplicate contact, PIN/auth checks
- [ ] Account management form (`accounts_manage_screen.dart`)
  - Validation: opening balance, duplicate names, active/inactive
- [ ] Business profile/setup forms (`businesses_screen.dart`, setup wizard)
  - Validation: mandatory business identity fields, GSTIN/PAN format
- [ ] Template builder form (`template_builder_screen.dart`)
  - Validation: placeholder integrity and save/reload consistency

---

## 5) Feature-Level Test Cases (Core)

### 5.1 Privacy & Offline Guarantees
- [ ] App remains fully functional for core CRUD in offline mode.
- [ ] No network dependency for transactions, credits, invoices, reports.
- [ ] SMS parsing happens locally; no sensitive payload shown in logs/events.

### 5.2 Authentication & Access
- [ ] PIN lock gates app resume/open.
- [ ] Incorrect PIN retry and lock behavior works.
- [ ] User permissions restrict sensitive actions correctly.

### 5.3 Transaction Lifecycle
- [ ] Manual transaction create/edit/delete updates dashboard and reports.
- [ ] Category changes reflect in existing/new transactions appropriately.
- [ ] Search and filters return expected result sets.

### 5.4 Credit/Udhar Lifecycle
- [ ] Create credit -> appears in active list and party ledger.
- [ ] Record repayment (partial/full) updates balance accurately.
- [ ] Overdue tagging/visual state works by due date.

### 5.5 Quote Lifecycle (Recent Changes)
- [ ] Draft quote shows **Edit + Send** actions.
- [ ] Sending quote changes status to sent and writes activity entry.
- [ ] Sent quote shows **Convert to Invoice + Rejected** actions.
- [ ] Reject flow captures reason and logs it in activity history.
- [ ] Convert flow creates invoice and marks quote accepted.
- [ ] Activity log timestamps show date + time and refresh immediately.

### 5.6 Invoice Lifecycle
- [ ] Invoice creation from scratch and from quote both work.
- [ ] PDF/share opens system share sheet without crash.
- [ ] Invoice status updates reflect in list/detail/reports.

### 5.7 Inventory & Stock
- [ ] Purchase bill increases tracked stock.
- [ ] Invoice/delivery challan reduces stock where applicable.
- [ ] Edit/reversal paths keep stock ledger consistent.

### 5.8 GST & Compliance
- [ ] GSTR screens render expected summaries for selected period.
- [ ] Export actions generate valid files and no crash.
- [ ] Tax totals match underlying invoices/purchase bills.

### 5.9 Backup, Restore, and Data Health
- [ ] Encrypted backup completes and file is restorable.
- [ ] Restore preserves linked entities (party/invoice/quote/ledger).
- [ ] Storage health metrics refresh after cleanup.

### 5.10 Notifications & Reminders
- [ ] Reminder scheduling creates upcoming notifications correctly.
- [ ] Notification settings toggles are honored.
- [ ] Due reminders open the correct target screen.

---

## 6) Regression Focus for Current Cycle

Prioritize these in every run:
- [ ] Provider lifecycle stability: no `Tried to use XNotifier after dispose` in logs.
- [ ] Quote detail activity card rendering (no `NoSuchMethodError`).
- [ ] Quote status action bar logic by status (draft/sent/accepted/rejected).
- [ ] Activity log refresh after share/reject/convert actions.

---

## 7) Defect Logging Format

Use this template for each issue:
- **ID:** QA-YYYYMMDD-###
- **Area:** screen/form/feature
- **Build:** commit hash + platform
- **Steps to Reproduce:** numbered steps
- **Expected:**
- **Actual:**
- **Severity:** blocker/high/medium/low
- **Evidence:** screenshot/video/log snippet

---

## 8) Exit Criteria (Manual Pass)

- [ ] 100% screen smoke checklist complete
- [ ] 100% form validation checklist complete
- [ ] Core feature checklist complete
- [ ] No blocker/high severity open defects
- [ ] No crash/red-screen in critical flows
- [ ] Regression focus items pass on final build

---

## Notes

This is a living document. Add module-specific deep test cases under each section as new features ship.