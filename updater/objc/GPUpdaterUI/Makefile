GNUSTEP_CONFIG := $(shell command -v gnustep-config 2>/dev/null)

ifeq ($(GNUSTEP_CONFIG),)
$(error gnustep-config not found. Install GNUstep GUI development tools before building GPUpdaterUI.)
endif

OBJCFLAGS := $(shell $(GNUSTEP_CONFIG) --objc-flags)
LIB_NAME := libGPUpdaterUI.a
INCLUDE_DIR := Headers
CORE_INCLUDE_DIR := ../GPUpdaterCore/Headers
SOURCES := Source/GPStandardUpdaterController.m
OBJECTS := $(SOURCES:.m=.o)

.PHONY: all clean

all: $(LIB_NAME)

$(LIB_NAME): $(OBJECTS)
	ar rcs $@ $(OBJECTS)

Source/GPStandardUpdaterController.o: Source/GPStandardUpdaterController.m Headers/GPStandardUpdaterController.h ../GPUpdaterCore/Headers/GPUpdater.h
	clang $(OBJCFLAGS) -I$(INCLUDE_DIR) -I$(CORE_INCLUDE_DIR) -c $< -o $@

clean:
	rm -f $(OBJECTS) $(LIB_NAME)
