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
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <unistd.h>
#include <limits.h>
#include <assert.h>
#ifdef HAVE_MALLOPT_H
#include <malloc.h>
#endif
#include <sys/sem.h>
#include "mkrandom.h"

size_t page_size;

struct llst {
  char * data;
  struct llst * next;
};

struct llst * llst_alloc() {
  struct llst * lst;
  if ( !(lst = malloc(sizeof(struct llst))) ) {
    perror(0);
    exit(1);
  }
  if ( !(lst->data = malloc(page_size)) ) {
    perror(0);
    exit(1);
  }
  lst->next = NULL;
  return lst;
}

struct llst * llst_free(struct llst * lst) {
  struct llst * tmp = lst->next;
  free(lst->data);
  free(lst);
  return tmp;
}

int main(int argc, char ** argv) {
  if (argc < 2) {
    fprintf(stderr,
	    "%s: buffering tool for the prll() shell function.\n"
	    "Consult the prll source and documentation for usage.\n"
	    "Not meant to be used standalone.\n"
	    , argv[0]);
    return 1;
  }

  // Choosing operating mode
  enum {
    PRLL_BUFFER_MODE, PRLL_REMOVE_MODE,
    PRLL_CREATE_MODE, PRLL_TEST_MODE
  } mode;
  if (argv[1][0] == '\0')
    goto arg_err;
  if (argv[1][0] == 'r' && argv[1][1] == '\0')
    mode = PRLL_REMOVE_MODE;
  else if (argv[1][0] == 'b' && argv[1][1] == '\0')
    mode = PRLL_BUFFER_MODE;
  else if (argv[1][0] == 'n' && argv[1][1] == '\0')
    mode = PRLL_CREATE_MODE;
  else if (argv[1][0] == 't' && argv[1][1] == '\0')
    mode = PRLL_TEST_MODE;
  else {
  arg_err:
    fprintf(stderr, "%s: Incorrect mode specification: %s\n", argv[0], argv[1]);
    return 1;
  }

  // Get 16 pages per malloc and let free release memory back to the OS.
  page_size = 16 * (size_t)sysconf(_SC_PAGESIZE);

#ifdef HAVE_MALLOPT_H
  mallopt(M_TRIM_THRESHOLD, page_size-1);
  mallopt(M_MMAP_THRESHOLD, page_size-1);
#endif

  key_t skey;
  int sid;
  if (mode != PRLL_CREATE_MODE) {
    if (argc < 3) {
      fprintf(stderr, "%s: Not enough parameters.\n", argv[0]);
      return 1;
    }
    skey = strtol(argv[2], 0, 0);
    sid = semget(skey, 1, 0);
    if (sid == -1) {
      if (mode != PRLL_TEST_MODE) {
	fprintf(stderr, "%s: Couldn't open semaphore.\n", argv[0]);
	perror(argv[0]);
      }
      return 1;
    } else if (mode == PRLL_TEST_MODE)
      return 0;
  }

  // Ops: 0: wait for zero; 1: take lock with undo on abort; 2: release lock.
  struct sembuf sop[2];
  sop[0].sem_num = 0;
  sop[1].sem_num = 0;
  sop[0].sem_flg = 0;
  sop[1].sem_flg = SEM_UNDO;
  sop[0].sem_op = 0;
  sop[1].sem_op = 1;

  // BUFFERING MODE
  if (mode == PRLL_BUFFER_MODE) {
    struct llst * head = llst_alloc();
    struct llst * lst = head;
    unsigned long num_pages = 0;
    size_t last_page_len;
    int last_errno;

    // Read
    while (! feof(stdin) && ! ferror(stdin)) {
      last_page_len = fread(lst->data, 1, page_size, stdin);
      last_errno = errno;
      if (last_page_len == page_size) {
	num_pages++;
	lst->next = llst_alloc();
	lst = lst->next;
      } else {
	assert(feof(stdin) || ferror(stdin));
      }
    }

    if (ferror(stdin)) {
      fprintf(stderr,
	      "%s: Error reading data, dumping what I have.\n   Error: %s\n",
	      argv[0], strerror(last_errno));
    }

    // Lock
    if (semop(sid, sop, 2)) {
      fprintf(stderr, "%s: Couldn't take semaphore, not writing data.\n",
	      argv[0]);
      perror(argv[0]);
      return 1;
    }

    // Write
    size_t written;
    lst = head;
    for (unsigned long int page = 0; page < num_pages; page++) {
      written = fwrite(lst->data, 1, page_size, stdout);
      last_errno = errno;
      lst = llst_free(lst);
      if (ferror(stdout) || written != page_size) {
	fprintf(stderr,
		"%s: Error dumping data, exiting.\n   Error: %s\n",
		argv[0], strerror(last_errno));
	exit(1);
      }
    }
    written = fwrite(lst->data, 1, last_page_len, stdout);
    last_errno = errno;
    llst_free(lst);
    if (ferror(stdout) || written != last_page_len) {
      fprintf(stderr,
	      "%s: Error dumping data, exiting.\n   Error: %s\n",
	      argv[0], strerror(last_errno));
      exit(1);
    }

    // Unlocking is automatic because of SEM_UNDO.

  // CREATE A NEW SEMAPHORE MODE
  } else if (mode == PRLL_CREATE_MODE) {
    do {
      if (mkrandom(&skey)) {
	fprintf(stderr, "%s: Error accessing /dev/(u)random.\n", argv[0]);
	return 1;
      }
    } while (-1 == (sid = semget(skey, 1, 0644 | IPC_CREAT | IPC_EXCL))
	     && errno == EEXIST);
    if (sid == -1) {
      fprintf(stderr, "%s: Couldn't create semaphore.\n", argv[0]);
      perror(argv[0]);
      return 1;
    }
    union semun {
      int val;
      struct semid_ds *buf;
      unsigned short  *array;
    } arg;
    arg.val = 0;
    if (-1 == semctl(sid, 0, SETVAL, arg)) {
      fprintf(stderr, "%s: Couldn't initialize semaphore.\n", argv[0]);
      perror(argv[0]);
      return 1;
    }
    printf("%#X\n", skey);
  // REMOVE MODE
  } else if (mode == PRLL_REMOVE_MODE) {
    if (semctl(sid, 0, IPC_RMID)) {
      fprintf(stderr, "%s: Couldn't remove semaphore.\n", argv[0]);
      perror(argv[0]);
      return 1;
    }
  }

  return 0;
}
