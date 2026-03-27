#include <windows.h>

int WINAPI wWinMain(HINSTANCE instance, HINSTANCE previous, PWSTR commandLine, int showCommand)
{
    (void)instance;
    (void)previous;
    (void)commandLine;
    (void)showCommand;

    /* Stay alive long enough for backend smoke validation to observe the child process. */
    Sleep(30000);
    return 0;
}
