GNUSTEP_CONFIG := $(shell command -v gnustep-config 2>/dev/null)

ifeq ($(GNUSTEP_CONFIG),)
$(error gnustep-config not found. Install GNUstep Base development tools before building gp-update-helper.)
endif

OBJCFLAGS := $(shell $(GNUSTEP_CONFIG) --objc-flags)
BASE_LIBS := $(shell $(GNUSTEP_CONFIG) --base-libs)
# Downloads go through WinHTTP on Windows (GPUpdaterDownload.m).
UNAME_S := $(shell uname -s 2>/dev/null)
ifneq ($(filter Windows_NT,$(OS))$(findstring MINGW,$(UNAME_S))$(findstring MSYS,$(UNAME_S)),)
BASE_LIBS += -lwinhttp
endif
CORE_INCLUDE_DIR := ../GPUpdaterCore/Headers
TARGET := gp-update-helper
SOURCES := Source/main.m
C_SOURCES := Source/monocypher/monocypher.c Source/monocypher/monocypher-ed25519.c
OBJECTS := $(SOURCES:.m=.o) $(C_SOURCES:.c=.o)

.PHONY: all clean

all: $(TARGET)

$(TARGET): $(OBJECTS) ../GPUpdaterCore/libGPUpdaterCore.a
	clang $(OBJCFLAGS) -I$(CORE_INCLUDE_DIR) -o $@ $(OBJECTS) ../GPUpdaterCore/libGPUpdaterCore.a $(BASE_LIBS)

Source/main.o: Source/main.m ../GPUpdaterCore/Headers/GPUpdater.h ../GPUpdaterCore/Headers/GPUpdaterDownload.h
	clang $(OBJCFLAGS) -I$(CORE_INCLUDE_DIR) -c $< -o $@

Source/monocypher/%.o: Source/monocypher/%.c Source/monocypher/monocypher.h Source/monocypher/monocypher-ed25519.h
	clang -O2 -c $< -o $@

../GPUpdaterCore/libGPUpdaterCore.a:
	$(MAKE) -C ../GPUpdaterCore

clean:
	rm -f $(OBJECTS) $(TARGET)
