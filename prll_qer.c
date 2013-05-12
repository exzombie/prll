/* 
   Copyright 2009-2010 Jure Varlec
   This program is free software: you can redistribute it and/or modify
   it under the terms of the GNU General Public License as published by
   the Free Software Foundation, either version 3 of the License, or
   (at your option) any later version.
   
   This program is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
   GNU General Public License for more details.
   
   A copy of the GNU General Public License is provided in COPYING.
   If not, see <http://www.gnu.org/licenses/>.
*/

#include "config.h"
#define _SVID_SOURCE
#include <stdio.h>
#include <sys/msg.h>
#include <stdlib.h>
#include <errno.h>
#define __STDC_FORMAT_MACROS
#include <inttypes.h>
#include <unistd.h>
#include <sys/types.h>
#include "mkrandom.h"
#include "abrterr.h"

int main(int argc, char ** argv) {
  if (argc < 2) {
    fprintf(stderr,
	    "%s: message queue tool for the prll() shell function.\n"
	    "Consult the prll source and documentation for usage.\n"
	    "Not meant to be used standalone.\n"
	    , argv[0]);
    return 1;
  }

  // Choosing operating mode
  enum {
    PRLL_CLIENT_MODE, PRLL_REMOVE_MODE,
    PRLL_GETONE_MODE, PRLL_CREATE_MODE,
    PRLL_TEST_MODE
  } mode;
  if (argv[1][0] == '\0')
    goto arg_err;
  if (argv[1][0] == 'r' && argv[1][1] == '\0')
    mode = PRLL_REMOVE_MODE;
  else if (argv[1][0] == 'c' && argv[1][1] == '\0')
    mode = PRLL_CLIENT_MODE;
  else if (argv[1][0] == 'o' && argv[1][1] == '\0')
    mode = PRLL_GETONE_MODE;
  else if (argv[1][0] == 'n' && argv[1][1] == '\0')
    mode = PRLL_CREATE_MODE;
  else if (argv[1][0] == 't' && argv[1][1] == '\0')
    mode = PRLL_TEST_MODE;
  else if (argv[1][0] == 'P' && argv[1][1] == '\0') {
    if (argc < 3) {
      fprintf(stderr, "%s: Not enough parameters.\n", argv[0]);
      return 1;
    }
    FILE* out = fopen(argv[2], "w");
    if (!out) {
      fprintf(stderr, "%s: Could not open tasks file.\n", argv[0]);
      return 1;
    }
    fprintf(out, "%lld\n", (long long)getppid());
    fclose(out);
    return 0;
  } else {
  arg_err:
    fprintf(stderr, "%s: Incorrect mode specification: %s\n", argv[0], argv[1]);
    return 1;
  }

  // Open the message queue and prepare the variable for the message
  key_t qkey;
  int qid;
  if (mode != PRLL_CREATE_MODE) {
    if (argc < 3) {
      fprintf(stderr, "%s: Not enough parameters.\n", argv[0]);
      return 1;
    }
    qkey = strtoumax(argv[2], 0, 0);
    qid = msgget(qkey, 0);
    if (qid == -1 || qkey == 0) {
      if (mode != PRLL_TEST_MODE && mode != PRLL_REMOVE_MODE) {
	fprintf(stderr, "%s: Couldn't open the message queue.\n", argv[0]);
	perror(argv[0]);
      }
      return 1;
    } else if (mode == PRLL_TEST_MODE)
      return 0;
  }
  struct { long msgtype; char jarg; } msg;
  const long msgtype = 'm'+'a'+'p'+'p'; // arbitrary

  // Do the work
  // CLIENT (SEND A SINGLE MESSAGE) MODE
  if (mode == PRLL_CLIENT_MODE) {
    if (argc < 4) {
      fprintf(stderr, "%s: Not enough parameters.\n", argv[0]);
      return 1;
    }
    msg.msgtype = msgtype;
    msg.jarg = strtol(argv[3], 0, 0);
    if (errno) abrterr();
    if (msgsnd(qid, &msg, sizeof(msg.jarg), 0)) abrterr();
  // GET A SINGLE MESSAGE MODE
  } else if (mode == PRLL_GETONE_MODE) {
    if (msgrcv(qid, &msg, sizeof(msg.jarg), msgtype, 0) != sizeof(msg.jarg)) {
      perror(argv[0]);
    }
    if (msg.jarg == 0) {
      return 0;
    } else if (msg.jarg == 1) {
      return 1;
    } else abrterr2("Unknown command.");
  // CREATE A NEW QUEUE MODE
  } else if (mode == PRLL_CREATE_MODE) {
    do {
      if (mkrandom(&qkey)) abrterr2("Error accessing /dev/(u)random.");
    } while (-1 == (qid = msgget(qkey, 0600 | IPC_CREAT | IPC_EXCL))
	     && errno == EEXIST);
    if (qid == -1) abrterr();
    printf("%#" PRIXMAX "\n", (uintmax_t)qkey);
  // REMOVE MODE
  } else if (mode == PRLL_REMOVE_MODE) {
    if (msgctl(qid, IPC_RMID, NULL)) abrterr();
  }    
  return 0;
}
