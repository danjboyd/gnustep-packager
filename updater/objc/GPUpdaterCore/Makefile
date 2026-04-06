GNUSTEP_CONFIG := $(shell command -v gnustep-config 2>/dev/null)

ifeq ($(GNUSTEP_CONFIG),)
$(error gnustep-config not found. Install GNUstep Base development tools before building GPUpdaterCore.)
endif

OBJCFLAGS := $(shell $(GNUSTEP_CONFIG) --objc-flags)
BASE_LIBS := $(shell $(GNUSTEP_CONFIG) --base-libs)
LIB_NAME := libGPUpdaterCore.a
INCLUDE_DIR := Headers
SOURCES := Source/GPUpdater.m
OBJECTS := $(SOURCES:.m=.o)

.PHONY: all clean

all: $(LIB_NAME)

$(LIB_NAME): $(OBJECTS)
	ar rcs $@ $(OBJECTS)

Source/GPUpdater.o: Source/GPUpdater.m Headers/GPUpdater.h
	clang $(OBJCFLAGS) -I$(INCLUDE_DIR) -c $< -o $@

clean:
	rm -f $(OBJECTS) $(LIB_NAME)
