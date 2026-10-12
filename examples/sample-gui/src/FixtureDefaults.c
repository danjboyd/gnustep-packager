#include <windows.h>

int WINAPI wWinMain(HINSTANCE instance, HINSTANCE previous, PWSTR commandLine, int showCommand)
{
    (void)instance;
    (void)previous;
    (void)commandLine;
    (void)showCommand;

    /* Stand-in for GNUstep defaults.exe when the build host has none: every
       read and write succeeds, so the launcher's packaged-defaults seeding passes. */
    return 0;
}
