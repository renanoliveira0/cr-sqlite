COMMIT=$(shell git rev-parse HEAD)
VERSION=$(shell cat VERSION)
DATE=$(shell date +'%FT%TZ%z')

LOADABLE_CFLAGS=-fPIC -shared

ifeq ($(shell uname -s),Darwin)
CONFIG_DARWIN=y
else ifeq ($(OS),Windows_NT)
CONFIG_WINDOWS=y
else
CONFIG_LINUX=y
endif

ifdef CONFIG_DARWIN
LOADABLE_EXTENSION=dylib
endif

ifdef CONFIG_LINUX
LOADABLE_EXTENSION=so
endif

ifdef CONFIG_WINDOWS
LOADABLE_EXTENSION=dll
endif

DEFINE_SQLITE_PATH_DATE=-DSQLITE_PATH_DATE="\"$(DATE)\""
DEFINE_SQLITE_PATH_VERSION=-DSQLITE_PATH_VERSION="\"$(VERSION)\""
DEFINE_SQLITE_PATH_SOURCE=-DSQLITE_PATH_SOURCE="\"$(COMMIT)\""
DEFINE_SQLITE_PATH=$(DEFINE_SQLITE_PATH_DATE) $(DEFINE_SQLITE_PATH_VERSION) $(DEFINE_SQLITE_PATH_SOURCE)

prefix=dist

TARGET_LOADABLE=dist/path0.$(LOADABLE_EXTENSION)
TARGET_SQLITE3_EXTRA_C=$(prefix)/sqlite3-extra.c
TARGET_SQLITE3=$(prefix)/sqlite3
TARGET_SQLJS_JS=$(prefix)/sqljs.js
TARGET_SQLJS_WASM=$(prefix)/sqljs.wasm
TARGET_SQLJS=$(TARGET_SQLJS_JS) $(TARGET_SQLJS_WASM)
TARGET_TEST=$(prefix)/test

ext_files=cfsqlite.c cfsqlite-util.c cfsqlite-tableinfo.c cfsqlite-triggers.c uuid.c
ext_headers=cfsqlite.h csflite-utils.h cfsqlite-tablinfo.h cfsqlite-triggers.h uuid.h

$(prefix):
	mkdir -p $(prefix)

clean:
	rm -rf dist/*

FORMAT_FILES=$(ext_files) $(ext_headers) core_init.c
format: $(FORMAT_FILES)
	clang-format -i $(FORMAT_FILES)

loadable: $(TARGET_LOADABLE) $(TARGET_LOADABLE_NOFS)
sqlite3: $(TARGET_SQLITE3)
sqljs: $(TARGET_SQLJS)
test: $(TARGET_TEST)
	./dist/test

$(TARGET_LOADABLE): $(ext_files)
	gcc -Isqlite \
	$(LOADABLE_CFLAGS) \
	$(DEFINE_SQLITE_PATH) \
	$< -o $@

$(TARGET_SQLITE3): $(prefix) $(TARGET_SQLITE3_EXTRA_C) sqlite/shell.c $(ext_files)
	gcc -g \
	$(DEFINE_SQLITE_PATH) \
	-DSQLITE_THREADSAFE=0 -DSQLITE_OMIT_LOAD_EXTENSION=1 \
	-DSQLITE_ENABLE_NORMALIZE \
	-DSQLITE_EXTRA_INIT=core_init \
	-I./ -I./sqlite \
	$(TARGET_SQLITE3_EXTRA_C) sqlite/shell.c $(ext_files) \
	-o $@

$(TARGET_SQLITE3_EXTRA_C): sqlite/sqlite3.c core_init.c
	cat sqlite/sqlite3.c core_init.c > $@

$(TARGET_TEST): $(prefix) $(TARGET_SQLITE3_EXTRA_C) tests.c cfsqlite.test.c cfsqlite-tableinfo.test.c cfsqlite-util.test.c cfsqlite-triggers.test.c $(ext_files)
	gcc -g \
	$(DEFINE_SQLITE_PATH) \
	-DSQLITE_THREADSAFE=0 -DSQLITE_OMIT_LOAD_EXTENSION=1 \
	-DSQLITE_ENABLE_NORMALIZE \
	-DSQLITE_EXTRA_INIT=core_init \
	-DUNIT_TEST=1 \
	-I./ -I./sqlite \
	$(TARGET_SQLITE3_EXTRA_C) tests.c cfsqlite.test.c cfsqlite-tableinfo.test.c cfsqlite-util.test.c cfsqlite-triggers.test.c $(ext_files) \
	-o $@

# test-format: SHELL:=/bin/bash
# test-format:
# 	diff -u <(cat $(FORMAT_FILES)) <(clang-format $(FORMAT_FILES))

# test-loadable: $(TARGET_LOADABLE)
# 	python3 tests/test-loadable.py

# test-loadable-watch: $(TARGET_LOADABLE)
# 	watchexec -w $(ext_files) -w $(TARGET_LOADABLE) -w tests/test-loadable.py --clear -- make test-loadable

# test-sqlite3: $(TARGET_SQLITE3)
# 	python3 tests/test-sqlite3.py

# test-sqlite3-watch: $(TARAGET_SQLITE3)
# 	watchexec -w $(TARAGET_SQLITE3) -w tests/test-sqlite3.py --clear -- make test-sqlite3

# test-sqljs: $(TARGET_SQLJS)
# 	python3 -m http.server & open http://localhost:8000/tests/test-sqljs.html

.PHONY: all clean format \
	test test-watch test-format \
	loadable test-loadable test-loadable-watch

# The below is mostly borrowed from https://github.com/sql-js/sql.js/blob/master/Makefile

# WASM has no (easy) filesystem for the demo, so disable lines_read
SQLJS_CFLAGS = \
	-O2 \
	-DSQLITE_OMIT_LOAD_EXTENSION \
	-DSQLITE_DISABLE_LFS \
	-DSQLITE_ENABLE_JSON1 \
	-DSQLITE_THREADSAFE=0 \
	-DSQLITE_ENABLE_NORMALIZE \
	$(DEFINE_SQLITE_PATH) -DSQLITE_LINES_DISABLE_FILESYSTEM \
	-DSQLITE_EXTRA_INIT=core_init

SQLJS_EMFLAGS = \
	--memory-init-file 0 \
	-s RESERVED_FUNCTION_POINTERS=64 \
	-s ALLOW_TABLE_GROWTH=1 \
	-s EXPORTED_FUNCTIONS=@wasm/exported_functions.json \
	-s EXPORTED_RUNTIME_METHODS=@wasm/exported_runtime_methods.json \
	-s SINGLE_FILE=0 \
	-s NODEJS_CATCH_EXIT=0 \
	-s NODEJS_CATCH_REJECTION=0 \
	-s LLD_REPORT_UNDEFINED

SQLJS_EMFLAGS_WASM = \
	-s WASM=1 \
	-s ALLOW_MEMORY_GROWTH=1

SQLJS_EMFLAGS_OPTIMIZED= \
	-s INLINING_LIMIT=50 \
	-O3 \
	-flto \
	--closure 1

SQLJS_EMFLAGS_DEBUG = \
	-s INLINING_LIMIT=10 \
	-s ASSERTIONS=1 \
	-O1

$(TARGET_SQLJS): $(prefix) $(shell find wasm/ -type f) $(ext_files) $(TARGET_SQLITE3_EXTRA_C)
	emcc $(SQLJS_CFLAGS) $(SQLJS_EMFLAGS) $(SQLJS_EMFLAGS_DEBUG) $(SQLJS_EMFLAGS_WASM) \
		-I./sqlite -I./ $(ext_files) $(TARGET_SQLITE3_EXTRA_C) \
		--pre-js wasm/api.js \
		-o $(TARGET_SQLJS_JS)
	mv $(TARGET_SQLJS_JS) tmp.js
	cat wasm/shell-pre.js tmp.js wasm/shell-post.js > $(TARGET_SQLJS_JS)
	rm tmp.js