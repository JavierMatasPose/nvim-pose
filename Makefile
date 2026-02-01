test:
	nvim --headless --noplugin -u tests/minimal_init.lua -c "PlenaryBustedDirectory tests/ { minimal_init = 'tests/minimal_init.lua' }"

fmt:
	stylua lua/ --config-path=.stylua.toml

lint:
	luacheck lua/ --globals vim
