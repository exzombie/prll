/* 
   Copyright 2010 Jure Varlec
   This program is free software: you can redistribute it and/or modify
   it under the terms of the GNU General Public License as published by
   the Free Software Foundation, either version 3 of the License, or
   (at your option) any later version.
   
   This program is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
   GNU General Public License for more details.
   
   A copy of the GNU General Public License is provided in COPYING.GPL-3.
   If not, see <http://www.gnu.org/licenses/>.
*/

#define _SVID_SOURCE
#include <stdio.h>
#include <sys/msg.h>
#include <stdlib.h>
#include <errno.h>

int main(int argc, char ** argv) {
  if (argc < 3) {
    fprintf(stderr,
	    "%s: jobserver for the prll() shell function.\n"
	    "Consult the prll source and documentation for usage.\n"
	    "Not meant to be used standalone.\n"
	    , argv[0]);
    return 1;
  }

  // Choosing operating mode
  enum {PRLL_CLIENT_MODE, PRLL_SERVER_MODE, PRLL_GETONE_MODE} mode;
  if (argv[1][0] == 's' && argv[1][1] == '\0')
    mode = PRLL_SERVER_MODE;
  else if (argv[1][0] == 'c' && argv[1][1] == '\0')
    mode = PRLL_CLIENT_MODE;
  else if (argv[1][0] == 'o' && argv[1][1] == '\0')
    mode = PRLL_GETONE_MODE;
  else {
    fprintf(stderr, "%s: incorrect mode specification: %s\n", argv[0], argv[1]);
    return 1;
  }

  // Open the message queue and prepare the variable for the message
  key_t qkey = strtol(argv[2], 0, 0);
  int qid = msgget(qkey, 0);
  if (qid == -1) {
    perror(argv[0]);
    return 1;
  }
  // msg.jarg will contain the job number that has completed.
  // This information is currently unused.
  struct { long msgtype; long jarg; } msg;
  const long msgtype = 'm'+'a'+'p'+'p'; // arbitrary

  // Do the work
  // CLIENT MODE
  if (mode == PRLL_CLIENT_MODE) {
    if (argc < 4) {
      fprintf(stderr, "%s: not enough parameters.\n", argv[0]);
      return 1;
    }
    msg.msgtype = msgtype;
    msg.jarg = strtol(argv[3], 0, 0);
    if (errno) {
      perror(argv[0]);
      return 1;
    }
    if (msgsnd(qid, &msg, sizeof(long), 0)) {
      perror(argv[0]);
      return 1;
    }
  // SERVER MODE
  } else if (mode == PRLL_SERVER_MODE) {
    while (1) {
      if (msgrcv(qid, &msg, sizeof(long), msgtype, 0) != sizeof(long)) {
	perror(argv[0]);
	continue;
      }
      if (msg.jarg == 0) {
	printf("\n");
	fflush(stdout);
      } else if (msg.jarg == 1) {
	return 0;
      } else {
	fprintf(stderr, "%s: unknown command.\n", argv[0]);
      }
    }
  } else if (mode == PRLL_GETONE_MODE) {
    if (msgrcv(qid, &msg, sizeof(long), msgtype, 0) != sizeof(long)) {
      perror(argv[0]);
    }
    if (msg.jarg == 0) {
      return 0;
    } else if (msg.jarg == 1) {
      return 1;
    } else {
      fprintf(stderr, "%s: unknown command.\n", argv[0]);
    }
  }
  return 0;
}
