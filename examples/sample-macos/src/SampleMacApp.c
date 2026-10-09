/* Reference payload for the DMG backend fixture. It is a faceless program
 * inside a normal .app bundle so packaging and smoke tests never open a window:
 * it prints a line, then waits until the smoke harness terminates it.
 * `--exit` makes it exit immediately with status 0. */
#include <signal.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

static volatile sig_atomic_t running = 1;

static void stop(int sig) {
  (void)sig;
  running = 0;
}

int main(int argc, char **argv) {
  signal(SIGTERM, stop);
  signal(SIGINT, stop);
  printf("SampleMacApp started\n");
  fflush(stdout);
  if (argc > 1 && strcmp(argv[1], "--exit") == 0) {
    return 0;
  }
  while (running) {
    sleep(1);
  }
  return 0;
}
