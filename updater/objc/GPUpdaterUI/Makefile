GNUSTEP_CONFIG := $(shell command -v gnustep-config 2>/dev/null)

ifeq ($(GNUSTEP_CONFIG),)
$(error gnustep-config not found. Install GNUstep GUI development tools before building GPUpdaterUI.)
endif

OBJCFLAGS := $(shell $(GNUSTEP_CONFIG) --objc-flags)
LIB_NAME := libGPUpdaterUI.a
INCLUDE_DIR := Headers
CORE_INCLUDE_DIR := ../GPUpdaterCore/Headers
SOURCES := Source/GPStandardUpdaterController.m
# Opening URLs goes through ShellExecuteW on Windows (GPUpdaterUIShell.c);
# link the app with -lshell32 there.
C_SOURCES := Source/GPUpdaterUIShell.c
OBJECTS := $(SOURCES:.m=.o) $(C_SOURCES:.c=.o)

.PHONY: all clean

all: $(LIB_NAME)

$(LIB_NAME): $(OBJECTS)
	ar rcs $@ $(OBJECTS)

Source/GPStandardUpdaterController.o: Source/GPStandardUpdaterController.m Headers/GPStandardUpdaterController.h ../GPUpdaterCore/Headers/GPUpdater.h Source/GPUpdaterUIShell.h
	clang $(OBJCFLAGS) -I$(INCLUDE_DIR) -I$(CORE_INCLUDE_DIR) -c $< -o $@

Source/GPUpdaterUIShell.o: Source/GPUpdaterUIShell.c Source/GPUpdaterUIShell.h
	clang -O2 -c $< -o $@

clean:
	rm -f $(OBJECTS) $(LIB_NAME)
