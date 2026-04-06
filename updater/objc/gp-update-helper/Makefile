GNUSTEP_CONFIG := $(shell command -v gnustep-config 2>/dev/null)

ifeq ($(GNUSTEP_CONFIG),)
$(error gnustep-config not found. Install GNUstep Base development tools before building gp-update-helper.)
endif

OBJCFLAGS := $(shell $(GNUSTEP_CONFIG) --objc-flags)
BASE_LIBS := $(shell $(GNUSTEP_CONFIG) --base-libs)
CORE_INCLUDE_DIR := ../GPUpdaterCore/Headers
TARGET := gp-update-helper
SOURCES := Source/main.m
OBJECTS := $(SOURCES:.m=.o)

.PHONY: all clean

all: $(TARGET)

$(TARGET): $(OBJECTS) ../GPUpdaterCore/libGPUpdaterCore.a
	clang $(OBJCFLAGS) -I$(CORE_INCLUDE_DIR) -o $@ $(OBJECTS) ../GPUpdaterCore/libGPUpdaterCore.a $(BASE_LIBS)

Source/main.o: Source/main.m ../GPUpdaterCore/Headers/GPUpdater.h
	clang $(OBJCFLAGS) -I$(CORE_INCLUDE_DIR) -c $< -o $@

../GPUpdaterCore/libGPUpdaterCore.a:
	$(MAKE) -C ../GPUpdaterCore

clean:
	rm -f $(OBJECTS) $(TARGET)
