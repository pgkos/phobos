# Makefile to build linux D runtime library libphobos2.a and its unit test
#
# make => makes release build of the library
#
# make clean => removes all targets built by the makefile
#
# make zip => creates a zip file of all the sources (not targets)
# referred to by the makefile, including the makefile
#
# make BUILD=debug => makes debug build of the library
#
# make unittest => builds all unittests (for debug AND release) and runs them
#
# make BUILD=debug unittest => builds all unittests (for debug) and runs them
#
# make DEBUGGER=ddd std/XXXXX.debug => builds the module XXXXX and executes it in the debugger ddd
#
# make html => makes html documentation
#
# make install => copies library to /usr/lib
#
# make std/somemodule.test => only builds and unittests std.somemodule
#

################################################################################
# Configurable stuff, usually from the command line
#
# OS can be linux, win32, win32wine, osx, or freebsd. The system will be
# determined by using uname

QUIET:=

DEBUGGER=gdb

include osmodel.mak

ifeq (osx,$(OS))
	export MACOSX_DEPLOYMENT_TARGET=10.7
endif

# Default to a release built, override with BUILD=debug
ifeq (,$(BUILD))
BUILD_WAS_SPECIFIED=0
BUILD=release
else
BUILD_WAS_SPECIFIED=1
endif

ifneq ($(BUILD),release)
    ifneq ($(BUILD),debug)
        $(error Unrecognized BUILD=$(BUILD), must be 'debug' or 'release')
    endif
endif

override PIC:=$(if $(PIC),-fPIC,)

# Configurable stuff that's rarely edited
INSTALL_DIR = ../install
DRUNTIME_PATH = ../druntime
ZIPFILE = phobos.zip
ROOT_OF_THEM_ALL = generated
ROOT = $(ROOT_OF_THEM_ALL)/$(OS)/$(BUILD)/$(MODEL)
DUB=dub
GIT_HOME=https://github.com/dlang
TOOLS_DIR=../tools

# Documentation-related stuff
DOCSRC = ../dlang.org
WEBSITE_DIR = ../web
DOC_OUTPUT_DIR = $(WEBSITE_DIR)/phobos-prerelease
BIGDOC_OUTPUT_DIR = /tmp
SRC_DOCUMENTABLES = index.d $(addsuffix .d,$(STD_MODULES) \
	$(EXTRA_DOCUMENTABLES))
STDDOC = $(DOCSRC)/html.ddoc $(DOCSRC)/dlang.org.ddoc $(DOCSRC)/std_navbar-prerelease.ddoc $(DOCSRC)/std.ddoc $(DOCSRC)/macros.ddoc $(DOCSRC)/.generated/modlist-prerelease.ddoc
BIGSTDDOC = $(DOCSRC)/std_consolidated.ddoc $(DOCSRC)/macros.ddoc
# Set DDOC, the documentation generator
DDOC=$(DMD) -conf= $(MODEL_FLAG) -w -c -o- -version=StdDdoc \
	-I$(DRUNTIME_PATH)/import $(DMDEXTRAFLAGS)

# Set DRUNTIME name and full path
ifneq (,$(DRUNTIME))
	CUSTOM_DRUNTIME=1
endif
ifeq (,$(findstring win,$(OS)))
	DRUNTIME = $(DRUNTIME_PATH)/generated/$(OS)/$(BUILD)/$(MODEL)/libdruntime.a
	DRUNTIMESO = $(basename $(DRUNTIME)).so.a
else
	DRUNTIME = $(DRUNTIME_PATH)/lib/druntime.lib
endif

# Set CC and DMD
ifeq ($(OS),win32wine)
	CC = wine dmc.exe
	DMD = wine dmd.exe
	RUN = wine
else
	DMD = ../dmd/generated/$(OS)/release/$(MODEL)/dmd
	ifeq ($(OS),win32)
		CC = dmc
	else
		CC = cc
	endif
	RUN =
endif

# Set CFLAGS
CFLAGS=$(MODEL_FLAG) -fPIC -DHAVE_UNISTD_H
ifeq ($(BUILD),debug)
	CFLAGS += -g
else
	CFLAGS += -O3
endif

# Set DFLAGS
DFLAGS=-conf= -I$(DRUNTIME_PATH)/import $(DMDEXTRAFLAGS) -w -dip25 $(MODEL_FLAG) $(PIC)
ifeq ($(BUILD),debug)
	DFLAGS += -g -debug
else
	DFLAGS += -O -release
endif

ifdef ENABLE_COVERAGE
DFLAGS  += -cov
endif

# Set DOTOBJ and DOTEXE
ifeq (,$(findstring win,$(OS)))
	DOTOBJ:=.o
	DOTEXE:=
	PATHSEP:=/
else
	DOTOBJ:=.obj
	DOTEXE:=.exe
	PATHSEP:=$(shell echo "\\")
endif

LINKDL:=$(if $(findstring $(OS),linux),-L-ldl,)

# use timelimit to avoid deadlocks if available
TIMELIMIT:=$(if $(shell which timelimit 2>/dev/null || true),timelimit -t 90 ,)

# Set VERSION, where the file is that contains the version string
VERSION=../dmd/VERSION

# Set LIB, the ultimate target
ifeq (,$(findstring win,$(OS)))
	LIB:=$(ROOT)/libphobos2.a
	# 2.064.2 => libphobos2.so.0.64.2
	# 2.065 => libphobos2.so.0.65.0
	# MAJOR version is 0 for now, which means the ABI is still unstable
	MAJOR:=0
	MINOR:=$(shell awk -F. '{ print int($$2) }' $(VERSION))
	PATCH:=$(shell awk -F. '{ print int($$3) }' $(VERSION))
	# SONAME doesn't use patch level (ABI compatible)
	SONAME:=libphobos2.so.$(MAJOR).$(MINOR)
	LIBSO:=$(ROOT)/$(SONAME).$(PATCH)
else
	LIB:=$(ROOT)/phobos.lib
endif

################################################################################
MAIN = $(ROOT)/emptymain.d

# Given one or more packages, returns the modules they contain
P2MODULES=$(foreach P,$1,$(addprefix $P/,$(PACKAGE_$(subst /,_,$P))))

# Packages in std. Just mention the package name here. The contents of package
# xy/zz is in variable PACKAGE_xy_zz. This allows automation in iterating
# packages and their modules.
STD_PACKAGES = std $(addprefix std/,\
  algorithm container datetime digest experimental/allocator \
  experimental/allocator/building_blocks experimental/logger \
  net \
  experimental range regex)

# Modules broken down per package

PACKAGE_std = array ascii base64 bigint bitmanip compiler complex concurrency \
  conv csv demangle encoding exception file format \
  functional getopt json math mathspecial meta mmfile numeric \
  outbuffer parallelism path process random signals socket stdint \
  stdio string system traits typecons typetuple uni \
  uri utf uuid variant xml zip zlib
PACKAGE_std_experimental = checkedint typecons
PACKAGE_std_algorithm = comparison iteration mutation package searching setops \
  sorting
PACKAGE_std_container = array binaryheap dlist package rbtree slist util
PACKAGE_std_datetime = date interval package stopwatch systime timezone
PACKAGE_std_digest = crc digest hmac md murmurhash ripemd sha
PACKAGE_std_experimental_logger = core filelogger \
  nulllogger multilogger package
PACKAGE_std_experimental_allocator = \
  common gc_allocator mallocator mmap_allocator package showcase typed
PACKAGE_std_experimental_allocator_building_blocks = \
  affix_allocator allocator_list bucketizer \
  fallback_allocator free_list free_tree bitmapped_block \
  kernighan_ritchie null_allocator package quantizer \
  region scoped_allocator segregator stats_collector
PACKAGE_std_net = curl isemail
PACKAGE_std_range = interfaces package primitives
PACKAGE_std_regex = package $(addprefix internal/,generator ir parser \
  backtracking tests thompson kickstart)

# Modules in std (including those in packages)
STD_MODULES=$(call P2MODULES,$(STD_PACKAGES))

# OS-specific D modules
EXTRA_MODULES_LINUX := $(addprefix std/c/linux/, linux socket)
EXTRA_MODULES_OSX := $(addprefix std/c/osx/, socket)
EXTRA_MODULES_FREEBSD := $(addprefix std/c/freebsd/, socket)
EXTRA_MODULES_WIN32 := $(addprefix std/c/windows/, com stat windows		\
		winsock) $(addprefix std/windows/, charset iunknown syserror)

# Other D modules that aren't under std/
EXTRA_MODULES_COMMON := $(addprefix etc/c/,curl odbc/sql odbc/sqlext \
  odbc/sqltypes odbc/sqlucode sqlite3 zlib) $(addprefix std/c/,fenv locale \
  math process stdarg stddef stdio stdlib string time wcharh)

EXTRA_DOCUMENTABLES := $(EXTRA_MODULES_LINUX) $(EXTRA_MODULES_WIN32) $(EXTRA_MODULES_COMMON)

EXTRA_MODULES_INTERNAL := $(addprefix std/, \
	algorithm/internal \
	$(addprefix internal/, \
		cstring digest/sha_SSSE3 \
		$(addprefix math/, biguintcore biguintnoasm biguintx86	\
						   errorfunction gammafunction ) \
		scopebuffer test/dummyrange \
		$(addprefix unicode_, comp decomp grapheme norm tables) \
	) \
)

EXTRA_MODULES += $(EXTRA_DOCUMENTABLES) $(EXTRA_MODULES_INTERNAL)

# Aggregate all D modules relevant to this build
D_MODULES = $(STD_MODULES) $(EXTRA_MODULES)

# Add the .d suffix to the module names
D_FILES = $(addsuffix .d,$(D_MODULES))
# Aggregate all D modules over all OSs (this is for the zip file)
ALL_D_FILES = $(addsuffix .d, $(STD_MODULES) $(EXTRA_MODULES_COMMON) \
  $(EXTRA_MODULES_LINUX) $(EXTRA_MODULES_OSX) $(EXTRA_MODULES_FREEBSD) \
  $(EXTRA_MODULES_WIN32) $(EXTRA_MODULES_INTERNAL)) \
  std/internal/windows/advapi32.d \
  std/windows/registry.d std/c/linux/pthread.d std/c/linux/termios.d \
  std/c/linux/tipc.d

# C files to be part of the build
C_MODULES = $(addprefix etc/c/zlib/, adler32 compress crc32 deflate	\
	gzclose gzlib gzread gzwrite infback inffast inflate inftrees trees uncompr zutil)

OBJS = $(addsuffix $(DOTOBJ),$(addprefix $(ROOT)/,$(C_MODULES)))

MAKEFILE = $(firstword $(MAKEFILE_LIST))

# build with shared library support (defaults to true on supported platforms)
SHARED=$(if $(findstring $(OS),linux freebsd),1,)

# Check for missing imports in public unittest examples.
# A blacklist of ignored module is provided as not all public unittest in
# Phobos are independently runnable yet
IGNORED_PUBLICTESTS= $(addprefix std/, \
						base64 $(addprefix experimental/allocator/, \
								building_blocks/free_list building_blocks/quantizer \
						) digest/hmac \
						file math stdio traits typecons uuid)
PUBLICTESTS= $(addsuffix .publictests,$(filter-out $(IGNORED_PUBLICTESTS), $(D_MODULES)))
TEST_EXTRACTOR=$(TOOLS_DIR)/styles/test_extractor
PUBLICTESTS_DIR=$(ROOT)/publictests

################################################################################
# Rules begin here
################################################################################

# Main target (builds the dll on linux, too)
ifeq (1,$(SHARED))
all : lib dll
else
all : lib
endif

install :
	$(MAKE) -f $(MAKEFILE) OS=$(OS) MODEL=$(MODEL) BUILD=release INSTALL_DIR=$(INSTALL_DIR) \
		DMD=$(DMD) install2

.PHONY : unittest
ifeq (1,$(BUILD_WAS_SPECIFIED))
unittest : $(addsuffix .run,$(addprefix unittest/,$(D_MODULES)))
else
unittest : unittest-debug unittest-release
unittest-%:
	$(MAKE) -f $(MAKEFILE) unittest OS=$(OS) MODEL=$(MODEL) DMD=$(DMD) BUILD=$*
endif

################################################################################
# Patterns begin here
################################################################################

.PHONY: lib dll
lib: $(LIB)
dll: $(ROOT)/libphobos2.so

$(ROOT)/%$(DOTOBJ): %.c
	@[ -d $(dir $@) ] || mkdir -p $(dir $@) || [ -d $(dir $@) ]
	$(CC) -c $(CFLAGS) $< -o$@

$(LIB): $(OBJS) $(ALL_D_FILES) $(DRUNTIME)
	$(DMD) $(DFLAGS) -lib -of$@ $(DRUNTIME) $(D_FILES) $(OBJS)

$(ROOT)/libphobos2.so: $(ROOT)/$(SONAME)
	ln -sf $(notdir $(LIBSO)) $@

$(ROOT)/$(SONAME): $(LIBSO)
	ln -sf $(notdir $(LIBSO)) $@

$(LIBSO): override PIC:=-fPIC
$(LIBSO): $(OBJS) $(ALL_D_FILES) $(DRUNTIMESO)
	$(DMD) $(DFLAGS) -shared -debuglib= -defaultlib= -of$@ -L-soname=$(SONAME) $(DRUNTIMESO) $(LINKDL) $(D_FILES) $(OBJS)

ifeq (osx,$(OS))
# Build fat library that combines the 32 bit and the 64 bit libraries
libphobos2.a: $(ROOT_OF_THEM_ALL)/osx/release/libphobos2.a
$(ROOT_OF_THEM_ALL)/osx/release/libphobos2.a:
	$(MAKE) -f $(MAKEFILE) OS=$(OS) MODEL=32 BUILD=release
	$(MAKE) -f $(MAKEFILE) OS=$(OS) MODEL=64 BUILD=release
	lipo $(ROOT_OF_THEM_ALL)/osx/release/32/libphobos2.a \
		$(ROOT_OF_THEM_ALL)/osx/release/64/libphobos2.a \
		-create -output $@
endif

################################################################################
# Unittests
################################################################################

$(addprefix $(ROOT)/unittest/,$(DISABLED_TESTS)) :
	@echo Testing $@ - disabled

UT_D_OBJS:=$(addprefix $(ROOT)/unittest/,$(addsuffix .o,$(D_MODULES)))
# need to recompile all unittest objects whenever sth. changes
$(UT_D_OBJS): $(ALL_D_FILES)
$(UT_D_OBJS): $(ROOT)/unittest/%.o: %.d
	@mkdir -p $(dir $@)
	$(DMD) $(DFLAGS) -unittest -c -of$@ $<

ifneq (1,$(SHARED))

$(UT_D_OBJS): $(DRUNTIME)

$(ROOT)/unittest/test_runner: $(DRUNTIME_PATH)/src/test_runner.d $(UT_D_OBJS) $(OBJS) $(DRUNTIME)
	$(DMD) $(DFLAGS) -unittest -of$@ $(DRUNTIME_PATH)/src/test_runner.d $(UT_D_OBJS) $(OBJS) $(DRUNTIME) $(LINKDL) -defaultlib= -debuglib=

else

UT_LIBSO:=$(ROOT)/unittest/libphobos2-ut.so

$(UT_D_OBJS): $(DRUNTIMESO)

$(UT_LIBSO): override PIC:=-fPIC
$(UT_LIBSO): $(UT_D_OBJS) $(OBJS) $(DRUNTIMESO)
	$(DMD) $(DFLAGS) -shared -unittest -of$@ $(UT_D_OBJS) $(OBJS) $(DRUNTIMESO) $(LINKDL) -defaultlib= -debuglib=

$(ROOT)/unittest/test_runner: $(DRUNTIME_PATH)/src/test_runner.d $(UT_LIBSO)
	$(DMD) $(DFLAGS) -of$@ $< -L$(UT_LIBSO) -defaultlib= -debuglib=

endif

# macro that returns the module name given the src path
moduleName=$(subst /,.,$(1))

# target for batch unittests (using shared phobos library and test_runner)
unittest/%.run : $(ROOT)/unittest/test_runner
	$(QUIET)$(TIMELIMIT)$(RUN) $< $(call moduleName,$*)

# Target for quickly running a single unittest (using static phobos library).
# For example: "make std/algorithm/mutation.test"
# The mktemp business is needed so .o files don't clash in concurrent unittesting.
%.test : %.d $(LIB)
	T=`mktemp -d /tmp/.dmd-run-test.XXXXXX` &&                                                              \
	  (                                                                                                     \
	    $(DMD) -od$$T $(DFLAGS) -main -unittest $(LIB) -defaultlib= -debuglib= $(LINKDL) -cov -run $< ;     \
	    RET=$$? ; rm -rf $$T ; exit $$RET                                                                   \
	  )

# Target for quickly unittesting all modules and packages within a package,
# transitively. For example: "make std/algorithm.test"
%.test : $(LIB)
	$(MAKE) -f $(MAKEFILE) $(addsuffix .test,$(patsubst %.d,%,$(wildcard $*/*)))

# Recursive target for %.debug
# It has to be recursive as %.debug depends on $(LIB) and we don't want to
# force the user to call make with BUILD=debug.
# Therefore we call %.debug_with_debugger and pass BUILD=debug from %.debug
# This forces all of phobos to have debug symbols, which we need as we don't
# know where debugging is leading us.
%.debug_with_debugger : %.d $(LIB)
	$(DMD) $(DFLAGS) -main -unittest $(LIB) -defaultlib= -debuglib= $(LINKDL) $<
	$(DEBUGGER) ./$(basename $(notdir $<))

# Target for quickly debugging a single module
# For example: make -f posix.mak DEBUGGER=ddd std/format.debug
# ddd in this case is a graphical frontend to gdb
%.debug : %.d
	 BUILD=debug $(MAKE) -f $(MAKEFILE) $(basename $<).debug_with_debugger

################################################################################
# More stuff
################################################################################

# Disable implicit rule
%$(DOTEXE) : %$(DOTOBJ)

%/.directory :
	mkdir -p $* || exists $*
	touch $@

clean :
	rm -rf $(ROOT_OF_THEM_ALL) $(ZIPFILE) $(DOC_OUTPUT_DIR)

gitzip:
	git archive --format=zip HEAD > $(ZIPFILE)

zip :
	-rm -f $(ZIPFILE)
	zip -r $(ZIPFILE) . -x .git\* -x generated\*

install2 : all
	$(eval lib_dir=$(if $(filter $(OS),osx), lib, lib$(MODEL)))
	mkdir -p $(INSTALL_DIR)/$(OS)/$(lib_dir)
	cp $(LIB) $(INSTALL_DIR)/$(OS)/$(lib_dir)/
ifeq (1,$(SHARED))
	cp -P $(LIBSO) $(INSTALL_DIR)/$(OS)/$(lib_dir)/
	ln -sf $(notdir $(LIBSO)) $(INSTALL_DIR)/$(OS)/$(lib_dir)/libphobos2.so
endif
	mkdir -p $(INSTALL_DIR)/src/phobos/etc
	mkdir -p $(INSTALL_DIR)/src/phobos/std
	cp -r std/* $(INSTALL_DIR)/src/phobos/std/
	cp -r etc/* $(INSTALL_DIR)/src/phobos/etc/
	cp LICENSE_1_0.txt $(INSTALL_DIR)/phobos-LICENSE.txt

ifeq (1,$(CUSTOM_DRUNTIME))
# We consider a custom-set DRUNTIME a sign they build druntime themselves
else
# This rule additionally produces $(DRUNTIMESO). Add a fake dependency
# to always invoke druntime's make. Use FORCE instead of .PHONY to
# avoid rebuilding phobos when $(DRUNTIME) didn't change.
$(DRUNTIME): FORCE
	$(MAKE) -C $(DRUNTIME_PATH) -f posix.mak MODEL=$(MODEL) DMD=$(DMD) OS=$(OS) BUILD=$(BUILD)

ifeq (,$(findstring win,$(OS)))
$(DRUNTIMESO): $(DRUNTIME)
endif

FORCE:

endif

JSON = phobos.json
json : $(JSON)
$(JSON) : $(ALL_D_FILES)
	$(DMD) $(DFLAGS) -o- -Xf$@ $^

###########################################################
# html documentation

# D file to html, e.g. std/conv.d -> std_conv.html
# But "package.d" is special cased: std/range/package.d -> std_range.html
D2HTML=$(foreach p,$1,$(if $(subst package.d,,$(notdir $p)),$(subst /,_,$(subst .d,.html,$p)),$(subst /,_,$(subst /package.d,.html,$p))))

HTMLS=$(addprefix $(DOC_OUTPUT_DIR)/, \
	$(call D2HTML, $(SRC_DOCUMENTABLES)))
BIGHTMLS=$(addprefix $(BIGDOC_OUTPUT_DIR)/, \
	$(call D2HTML, $(SRC_DOCUMENTABLES)))

$(DOC_OUTPUT_DIR)/. :
	mkdir -p $@

# For each module, define a rule e.g.:
# ../web/phobos/std_conv.html : std/conv.d $(STDDOC) ; ...
$(foreach p,$(SRC_DOCUMENTABLES),$(eval \
$(DOC_OUTPUT_DIR)/$(call D2HTML,$p) : $p $(STDDOC) ;\
  $(DDOC) project.ddoc $(STDDOC) -Df$$@ $$<))

html : $(DOC_OUTPUT_DIR)/. $(HTMLS) $(STYLECSS_TGT)

allmod :
	@echo $(SRC_DOCUMENTABLES)

rsync-prerelease : html
	rsync -avz $(DOC_OUTPUT_DIR)/ d-programming@digitalmars.com:data/phobos-prerelease/
	rsync -avz $(WEBSITE_DIR)/ d-programming@digitalmars.com:data/phobos-prerelase/

html_consolidated :
	$(DDOC) -Df$(DOCSRC)/std_consolidated_header.html $(DOCSRC)/std_consolidated_header.dd
	$(DDOC) -Df$(DOCSRC)/std_consolidated_footer.html $(DOCSRC)/std_consolidated_footer.dd
	$(MAKE) -f $(MAKEFILE) DOC_OUTPUT_DIR=$(BIGDOC_OUTPUT_DIR) STDDOC=$(BIGSTDDOC) html -j 8
	cat $(DOCSRC)/std_consolidated_header.html $(BIGHTMLS)	\
	$(DOCSRC)/std_consolidated_footer.html > $(DOC_OUTPUT_DIR)/std_consolidated.html

changelog.html: changelog.dd
	$(DMD) -Df$@ $<

################################################################################
# Automatically create dlang/tools repository if non-existent
################################################################################

${TOOLS_DIR}:
	git clone --depth=1 ${GIT_HOME}/$(@F) $@
$(TOOLS_DIR)/checkwhitespace.d: | $(TOOLS_DIR)
$(TOOLS_DIR)/styles/tests_extractor.d: | $(TOOLS_DIR)

#################### test for undesired white spaces ##########################
CWS_TOCHECK = posix.mak win32.mak win64.mak osmodel.mak
CWS_TOCHECK += $(ALL_D_FILES) index.d

checkwhitespace: $(LIB) $(TOOLS_DIR)/checkwhitespace.d
	$(DMD) $(DFLAGS) -defaultlib= -debuglib= $(LIB) -run $(TOOLS_DIR)/checkwhitespace.d $(CWS_TOCHECK)

#############################
# Submission to Phobos are required to conform to the DStyle
# The tests below automate some, but not all parts of the DStyle guidelines.
# See also: http://dlang.org/dstyle.html
#############################

../dscanner:
	git clone https://github.com/dlang-community/Dscanner ../dscanner
	git -C ../dscanner checkout 455cc3fe50e6d0742c866737b4ac24669d51a992
	git -C ../dscanner submodule update --init --recursive

../dscanner/dsc: ../dscanner $(DMD) $(LIB)
	# debug build is faster, but disable 'missing import' messages (missing core from druntime)
	sed 's/dparse_verbose/StdLoggerDisableWarning/' ../dscanner/makefile > dscanner_makefile_tmp
	mv dscanner_makefile_tmp ../dscanner/makefile
	DC=$(DMD) DFLAGS="$(DFLAGS) -defaultlib=$(LIB)" make -C ../dscanner githash debug

style: publictests style_lint

style_lint: ../dscanner/dsc $(LIB)
	@echo "Check for trailing whitespace"
	grep -nr '[[:blank:]]$$' etc std ; test $$? -eq 1

	@echo "Enforce whitespace before opening parenthesis"
	grep -nrE "(for|foreach|foreach_reverse|if|while|switch|catch)\(" $$(find etc std -name '*.d') ; test $$? -eq 1

	@echo "Enforce whitespace between colon(:) for import statements (doesn't catch everything)"
	grep -nr 'import [^/,=]*:.*;' $$(find etc std -name '*.d') | grep -vE "import ([^ ]+) :\s"; test $$? -eq 1

	@echo "Check for package wide std.algorithm imports"
	grep -nr 'import std.algorithm : ' $$(find etc std -name '*.d') ; test $$? -eq 1

	@echo "Enforce Allman style"
	grep -nrE '(if|for|foreach|foreach_reverse|while|unittest|switch|else|version) .*{$$' $$(find etc std -name '*.d'); test $$? -eq 1

	@echo "Enforce do { to be in Allman style"
	grep -nr 'do *{$$' $$(find etc std -name '*.d') ; test $$? -eq 1

	@echo "Enforce no space between assert and the opening brace, i.e. assert("
	grep -nrE 'assert +\(' $$(find etc std -name '*.d') ; test $$? -eq 1

	@echo "Enforce space after cast(...)"
	grep -nrE '[^"]cast\([^)]*?\)[[:alnum:]]' $$(find etc std -name '*.d') ; test $$? -eq 1

	@echo "Enforce space between a .. b"
	grep -nrE '[[:alnum:]][.][.][[:alnum:]]|[[:alnum:]] [.][.][[:alnum:]]|[[:alnum:]][.][.] [[:alnum:]]' $$(find etc std -name '*.d' | grep -vE 'std/string.d|std/uni.d') ; test $$? -eq 1

	@echo "Enforce space between binary operators"
	grep -nrE "[[:alnum:]](==|!=|<=|<<|>>|>>>|^^)[[:alnum:]]|[[:alnum:]] (==|!=|<=|<<|>>|>>>|^^)[[:alnum:]]|[[:alnum:]](==|!=|<=|<<|>>|>>>|^^) [[:alnum:]]" $$(find etc std -name '*.d'); test $$? -eq 1

	@echo "Validate changelog files (Do _not_ use REF in the title!)"
	@for file in $$(find changelog -name '*.dd') ; do  \
		cat $$file | head -n1 | grep -nqE '\$$\((REF|LINK2|HTTP|MREF)' && \
		{ echo "$$file: The title line can't contain links - it's already a link" && exit 1; } ;\
		cat $$file | head -n2 | tail -n1 | grep -q '^$$' || \
		{ echo "$$file: After the title line an empty, separating line is expected" && exit 1; } ;\
		cat $$file | head -n3 | tail -n1 | grep -nqE '^.{1,}$$'  || \
		{ echo "$$file: The title is supposed to be followed by a long description" && exit 1; } ;\
	done

	@echo "Check that Ddoc runs without errors"
	$(DMD) $(DFLAGS) -defaultlib= -debuglib= $(LIB) -w -D -Df/dev/null -main -c -o- $$(find etc std -type f -name '*.d') 2>&1 | grep -v "Deprecation:"; test $$? -eq 1

	# at the moment libdparse has problems to parse some modules (->excludes)
	@echo "Running DScanner"
	../dscanner/dsc --config .dscanner.ini --styleCheck $$(find etc std -type f -name '*.d' | grep -vE 'std/traits.d|std/typecons.d') -I.

################################################################################
# Check for missing imports in public unittest examples.
################################################################################
publictests: $(PUBLICTESTS)

$(TEST_EXTRACTOR): $(TOOLS_DIR)/styles/tests_extractor.d $(LIB)
	DFLAGS="$(DFLAGS) $(LIB) -defaultlib= -debuglib= $(LINKDL)" $(DUB) build --force --compiler=$${PWD}/$(DMD) --root=$(TOOLS_DIR)/styles -c tests_extractor

################################################################################
# Extract public tests of a module and test them in an separate file (i.e. without its module)
# This is done to check for potentially missing imports in the examples, e.g.
# make -f posix.mak std/format.publictests
################################################################################
%.publictests: %.d $(LIB) $(TEST_EXTRACTOR) | $(PUBLICTESTS_DIR)/.directory
	@$(TEST_EXTRACTOR) --inputdir  $< --outputdir $(PUBLICTESTS_DIR)
	@$(DMD) $(DFLAGS) -defaultlib= -debuglib= $(LIB) -main -unittest -run $(PUBLICTESTS_DIR)/$(subst /,_,$<)

.PHONY : auto-tester-build
auto-tester-build: all checkwhitespace

.PHONY : auto-tester-test
auto-tester-test: unittest

.DELETE_ON_ERROR: # GNU Make directive (delete output files on error)
