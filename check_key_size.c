#define _SVID_SOURCE
#include <stdio.h>
#include <sys/msg.h>
#include <assert.h>

int main() {
  printf("Sanity check: ");
  if (sizeof(long) >= sizeof(key_t)) {
    printf("OK.\n");
  } else {
    printf("FAILED!\n");
    return 1;
  }
  return 0;
}
