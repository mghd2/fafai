# Build the FAF version of lua
LUA_DIR?=lua-lang
LUA?=$(LUA_DIR)/bin/lua
$(LUA):
	$(MAKE) -C $(LUA_DIR)

# Run tests
.PHONY: test
test: $(LUA)
	LUA_PATH="?;?.lua;fa/?;fa/tests/?" $(LUA) tests/test_allocator.lua

# Create dev build (with arbitrary name for A/B testing)

# Create release build (with arbitrary name for A/B testing)
