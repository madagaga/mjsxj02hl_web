CROSS_COMPILE = arm-himix100-linux-
CCFLAGS = -march=armv7-a -mfpu=neon-vfpv4 -funsafe-math-optimizations

CC = $(CROSS_COMPILE)gcc
AR = $(CROSS_COMPILE)ar rcu
RANLIB = $(CROSS_COMPILE)ranlib

LUAVER = 5.5

TMPDIR = temp
BINDIR = bin
PATCHD = patches
LUALIB = lib/lua/$(LUAVER)
LUAMOD = share/lua/$(LUAVER)

# gzip-able static assets served by the SPA. Pre-compressed once at build
# time instead of at request time: busybox httpd serves the .gz sibling
# directly (Content-Encoding: gzip) when the browser accepts it, at zero
# runtime CPU cost -- see PROGRESS.md. The originals are kept alongside for
# clients that don't send Accept-Encoding: gzip.
GZIP_ASSETS = www/index.html www/css/app.css www/js/*.js www/vendor/*.js

all: mkdirs web gzip

# CGILua/WSAPI/rings/coxpcall/luafilesystem/luasocket are gone: the JSON API
# (www/cgi-bin/api*) is a handful of pure-Lua files plus the same three C
# modules the login/session/settings logic always needed (crypt, md5, INI
# parsing) -- no page-template engine, no request-dispatch framework.
web: lua lip luades md5

lua:
	git clone "https://github.com/lua/lua/" "$(TMPDIR)/lua" --branch "v5.5.0"
	make -C "$(TMPDIR)/lua" CC="$(CC)" AR="$(AR)" RANLIB="$(RANLIB)" CFLAGS="-Wall -O2 -std=c99 -DLUA_USE_LINUX -fno-stack-protector -fno-common $(CCFLAGS)" MYLIBS="-ldl"
	cp -f $(TMPDIR)/lua/lua $(BINDIR)/

lip:
	git clone "https://github.com/Dynodzzo/Lua_INI_Parser" "$(TMPDIR)/lip"
	git apply --directory="$(TMPDIR)/lip" "$(PATCHD)/lip.patch"
	cp -f $(TMPDIR)/lip/LIP.lua $(LUAMOD)/

luades:
	git clone "https://github.com/kasitoru/luades" "$(TMPDIR)/luades"
	make -C "$(TMPDIR)/luades" LUA_VERSION="$(LUAVER)" CC="$(CC)" CCFLAGS="-I./../lua -fPIC $(CCFLAGS)"
	cp -f $(TMPDIR)/luades/ldes.so $(LUALIB)/

md5:
	git clone "https://github.com/keplerproject/md5" "$(TMPDIR)/md5"
	make -C "$(TMPDIR)/md5" LUA_SYS_VER="$(LUAVER)" CC="$(CC)" INCS="-I./../lua $(CCFLAGS)"
	cp -f $(TMPDIR)/md5/src/md5.lua $(LUAMOD)/
	cp -f $(TMPDIR)/md5/src/core.so $(LUALIB)/md5/

gzip:
	for f in $(GZIP_ASSETS); do gzip -9 -k -f "$$f"; done

clean:
	-make -C "$(TMPDIR)/lua" clean
	-make -C "$(TMPDIR)/luades" clean
	-make -C "$(TMPDIR)/md5" clean
	-rm -rf $(TMPDIR)/* $(BINDIR)/* $(LUALIB)/* $(LUAMOD)/*
	-rm -f $(GZIP_ASSETS:=.gz)

mkdirs: clean
	-mkdir -p $(TMPDIR) $(BINDIR) $(LUALIB) $(LUALIB)/md5 $(LUAMOD)
