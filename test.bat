@if not exist lua-lang\bin\lua.exe echo Error: lua.exe not found
:: Expressions seem to be evaluated from the root directory of the repo containing this file
@set LUA_PATH="?;?.lua;.\?;fa\?;tests\?;fa\tests\?"
@lua-lang\bin\lua.exe tests\test_allocator.lua