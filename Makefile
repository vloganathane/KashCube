.PHONY: db-inventory db-inventory-check

db-inventory:
	python3 scripts/generate_db_inventory.py --output docs/codebase/DATABASE_INVENTORY_AUTO.md
	@echo "Generated docs/codebase/DATABASE_INVENTORY_AUTO.md"

db-inventory-check:
	python3 scripts/generate_db_inventory.py --output /tmp/kashcube_db_inventory_check.md --expect-table-count 56
	@echo "Table count check passed (56)"
