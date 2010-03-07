#include "mkrandom.h"

int mkrandom(key_t * qkey) {
  FILE * urnd = fopen("/dev/urandom", "r");
  if (urnd == NULL)
    urnd = fopen("/dev/random", "r");
  if (urnd == NULL)
    return 1;
  if (fread(qkey, sizeof(key_t), 1, urnd) != 1) {
    return 1;
  }
  int status = fclose(urnd);
  if (status != 0) {
    if (errno == EINTR)
      status = fclose(urnd);
    if (status != 0)
      return 1;
  }
  // Bits read from /dev/urandom don't seem to make a
  // reliable key by themselves, so we use them as a seed.
  // random() is what ipcmk uses to make a key, so it should be fine.
  srandom(*qkey);
  *qkey = random();
  return 0;
}
