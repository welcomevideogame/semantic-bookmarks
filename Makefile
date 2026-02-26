# Run the test suite with plenary.nvim.
#
# Override PLENARY_PATH if plenary is not at the lazy.nvim default:
#   make test PLENARY_PATH=~/.local/share/nvim/plugged/plenary.nvim

PLENARY_PATH ?= $(HOME)/.local/share/nvim/lazy/plenary.nvim

.PHONY: test
test:
	PLENARY_PATH=$(PLENARY_PATH) nvim --headless \
		-u tests/minimal_init.lua \
		-c "PlenaryBustedDirectory tests/ {minimal_init = 'tests/minimal_init.lua'}"
