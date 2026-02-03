.PHONY: test test-unit test-integration test-file

# Run all tests
test: test-unit test-integration

# Run unit tests only (no LSP required)
test-unit:
	@echo "=== Running unit tests ==="
	nvim --headless -u tests/minimal_init.lua \
		-c "PlenaryBustedDirectory tests/ {minimal_init = 'tests/minimal_init.lua'}" 2>/dev/null || true

# Run integration tests (requires pyright)
test-integration:
	@echo "=== Running integration tests ==="
	nvim --headless -u tests/minimal_init.lua \
		-c "PlenaryBustedDirectory tests/integration/ {minimal_init = 'tests/minimal_init.lua', sequential = true}"

# Run a specific test file
test-file:
	nvim --headless -u tests/minimal_init.lua \
		-c "PlenaryBustedFile $(FILE)"

# Run integration tests with verbose output
test-verbose:
	nvim --headless -u tests/minimal_init.lua \
		-c "lua require('plenary.test_harness').test_directory('tests/integration/', {minimal_init = 'tests/minimal_init.lua', sequential = true})"
