GNUSTEP_CONFIG := $(shell command -v gnustep-config 2>/dev/null)

ifeq ($(GNUSTEP_CONFIG),)
$(error gnustep-config not found. Install GNUstep Base development tools before building GPUpdaterCore.)
endif

OBJCFLAGS := $(shell $(GNUSTEP_CONFIG) --objc-flags)
BASE_LIBS := $(shell $(GNUSTEP_CONFIG) --base-libs)
LIB_NAME := libGPUpdaterCore.a
INCLUDE_DIR := Headers
SOURCES := Source/GPUpdater.m Source/GPUpdaterDownload.m
C_SOURCES := Source/GPUpdaterWinHTTP.c
OBJECTS := $(SOURCES:.m=.o) $(C_SOURCES:.c=.o)

.PHONY: all clean

all: $(LIB_NAME)

$(LIB_NAME): $(OBJECTS)
	ar rcs $@ $(OBJECTS)

Source/GPUpdater.o: Source/GPUpdater.m Headers/GPUpdater.h Headers/GPUpdaterDownload.h
	clang $(OBJCFLAGS) -I$(INCLUDE_DIR) -c $< -o $@

Source/GPUpdaterDownload.o: Source/GPUpdaterDownload.m Headers/GPUpdaterDownload.h Source/GPUpdaterWinHTTP.h
	clang $(OBJCFLAGS) -I$(INCLUDE_DIR) -c $< -o $@

Source/GPUpdaterWinHTTP.o: Source/GPUpdaterWinHTTP.c Source/GPUpdaterWinHTTP.h
	clang -O2 -c $< -o $@

clean:
	rm -f $(OBJECTS) $(LIB_NAME)
