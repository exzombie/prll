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
#include <fcntl.h>
#ifdef HAVE_MALLOPT_H
#include <malloc.h>
#endif
#include <sys/sem.h>
#include "mkrandom.h"

size_t page_size;

union semun {
  int val;
  struct semid_ds *buf;
  unsigned short  *array;
};

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
    PRLL_CREATE_MODE, PRLL_TEST_MODE,
    PRLL_WRITESERVER_MODE, PRLL_READER_MODE
  } mode;
  char delim;
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
  else if (argv[1][0] == 'w' && argv[1][1] == '\0') {
    mode = PRLL_WRITESERVER_MODE;
    delim = '\n';
  } else if (argv[1][0] == 'W' && argv[1][1] == '\0') {
    mode = PRLL_WRITESERVER_MODE;
    delim = '\0';
  } else if (argv[1][0] == 'c' && argv[1][1] == '\0')
    mode = PRLL_READER_MODE;
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
    sid = semget(skey, 0, 0);
    if (sid == -1 || skey == 0) {
      if (mode != PRLL_TEST_MODE) {
	fprintf(stderr, "%s: Couldn't open semaphore.\n", argv[0]);
	perror(argv[0]);
      }
      return 1;
    } else if (mode == PRLL_TEST_MODE)
      return 0;
  }

  // SEMAPHORE OPS

  /*
    SEQUENCE OF EVENTS:
    Buffering mode:
      A single semaphore is used as a lock.
    Reader and writer:
      Writer is a server that reads stdin. Every time it gets a delimiter
      it signals end of data. It only ever has a single client (the reader)
      which passes on the data. Every time a delimiter is found, the
      reader quits and a new one is spawned.

      These modes use semaphores 1 and 2. Here's what happens:

      Initial value of semaphores as provided by CREATE mode is 11.
      Writer starts its loop, changes semaphores to 10. It then waits
        for a reader to appear (state 00).
      Reader was waiting for state 10. It takes the lock by changing
        state to 00. It then waits for TX to start (state 01).
      Writer changes state to 01 and starts writing data.
      Reader acks the signal by changing state to 00 and starts reading data,
        all the time checking for state 01.
      By seeing state 00 writer is sure that reader started reading. When a
        delimiter is found, it changes state to 01. It waits for the reader
	to finish reading (state 11).
      When reader notices state 01 it knows there's no more data coming, so
        it quits. By virtue of UNDO, this changes state to 11.
      Writer checks to see if there is more data available on stdin. If so,
        it sets state to 10, allowing another client to connect.
   */

  // Buffering mode:
#define bfr_w4z 	0	// Wait for zero
#define bfr_take	1	// Take lock with undo
  // Reader mode
#define rdr_take	2 // 2	// Wait for 10, take lock with undo
#define rdr_recv	4	// Ack RX
  // Writeserver mode
#define wrtr_w4z	5 // 2	// Wait for 00
#define wrtr_txmt	7	// Announce TX
#define wrtr_txfin	8 // 2	// Announce end of TX
#define wrtr_rst	10 // 3	// Allow connection

#define wrtr_w4z2	6	// Wait for x0

  struct sembuf sop[] = {
    {0, 0, 0},
    {0, 1, SEM_UNDO},

    {1, -1, SEM_UNDO}, {2, 0, 0},
    {2, -1, 0},

    {1, 0, 0}, {2, 0, 0},
    {2, 1, 0},
    {2, 0, 0}, {2, 1, 0},
    {1, -1, 0}, {2, -1, 0}, {1, 1, 0}
  };

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
	return 1;
      }
    }
    written = fwrite(lst->data, 1, last_page_len, stdout);
    last_errno = errno;
    llst_free(lst);
    if (ferror(stdout) || written != last_page_len) {
      fprintf(stderr,
	      "%s: Error dumping data, exiting.\n   Error: %s\n",
	      argv[0], strerror(last_errno));
      return 1;
    }

    // Unlocking is automatic because of SEM_UNDO.

  // CREATE A NEW SEMAPHORE MODE
  } else if (mode == PRLL_CREATE_MODE) {
    do {
      if (mkrandom(&skey)) {
	fprintf(stderr, "%s: Error accessing /dev/(u)random.\n", argv[0]);
	return 1;
      }
    } while (-1 == (sid = semget(skey, 3, 0600 | IPC_CREAT | IPC_EXCL))
	     && errno == EEXIST);
    if (sid == -1) {
      fprintf(stderr, "%s: Couldn't create semaphore.\n", argv[0]);
      perror(argv[0]);
      return 1;
    }
    union semun arg;
    unsigned short vals[] = {0, 1, 1};
    arg.array = vals;
    if (-1 == semctl(sid, 0, SETALL, arg)) {
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

  // WRITESERVER MODE
  } else if (mode == PRLL_WRITESERVER_MODE) {
    char bfr[page_size];
    int chr;
    ssize_t writ, red;
    const ssize_t sze = (ssize_t)page_size;
    do {
      fprintf(stderr, "wrt, rst\n"); // debug
      if (semop(sid, sop+wrtr_rst, 3)) {
	fprintf(stderr,
		"%s wrt: Couldn't get confirmation on semaphore, exiting.\n",
		argv[0]);
	perror(argv[0]);
	return 1;
      }
      fprintf(stderr, "wrt, wait\n"); // debug
      if (semop(sid, sop+wrtr_w4z, 2)) {
	fprintf(stderr, "%s wrt: Couldn't wait on semaphore, exiting.\n",
		argv[0]);
	perror(argv[0]);
	return 1;
      }
      fprintf(stderr, "wrt, txmt\n"); // debug
      if (semop(sid, sop+wrtr_txmt, 1)) {
	fprintf(stderr, "%s wrt: Couldn't accept on semaphore, exiting.\n",
		argv[0]);
	perror(argv[0]);
	return 1;
      }

      red = 0;
      while (EOF != (chr = getc(stdin))) {
	if ((char)chr == delim) break;
	bfr[red++] = (char)chr;
	if (red == (ssize_t)page_size) {
	  writ = red = 0;
	  while (sze > (writ += write(1, bfr+writ, sze-writ))) {
	    if (errno != EWOULDBLOCK) {
	      fprintf(stderr,
		      "%s wrt: Error passing data, exiting.\n   Error: %s\n",
		      argv[0], strerror(errno));
	      exit(1);
	    }
	  }
	} 
      }
      writ = 0;
      while (red > (writ += write(1, bfr+writ, red-writ))) {
	if (errno != EWOULDBLOCK) {
	  fprintf(stderr,
		  "%s wrt: Error passing data, exiting.\n   Error: %s\n",
		  argv[0], strerror(errno));
	  exit(1);
	}
      }

      fprintf(stderr, "wrt, txfin\n"); // debug
      if (semop(sid, sop+wrtr_txfin, 2)) {
	fprintf(stderr,
		"%s wrt: Couldn't announce end on semaphore, exiting.\n",
		argv[0]);
	perror(argv[0]);
	return 1;
      }

      int tmp = getc(stdin);
      if (tmp == EOF) break;
      else ungetc(tmp, stdin);
    } while ((char)chr == delim);

  // READER MODE
  } else if (mode == PRLL_READER_MODE) {
    char bfr[page_size];
    ssize_t writ, red;
    const ssize_t sze = (ssize_t)page_size;
    int semval;
    int oldflags = fcntl (0, F_GETFL, 0);
    if (oldflags == -1) {
      fprintf(stderr, "%s rdr: Couldn't use fnctl, exiting.\n",
	      argv[0]);
      perror(argv[0]);
      return 1;
    }
    oldflags |= O_NONBLOCK;
    oldflags = fcntl (0, F_SETFL, oldflags);
    if (oldflags == -1) {
      fprintf(stderr, "%s rdr: Couldn't use fnctl, exiting.\n",
	      argv[0]);
      perror(argv[0]);
      return 1;
    }

    fprintf(stderr, "rdr, take\n"); // debug
    if (semop(sid, sop+rdr_take, 2)) {
      fprintf(stderr, "%s rdr: Couldn't take semaphore, exiting.\n",
	      argv[0]);
      perror(argv[0]);
      return 1;
    }
    fprintf(stderr, "rdr, recv\n"); // debug
    if (semop(sid, sop+rdr_recv, 1)) {
      fprintf(stderr,
	      "%s rdr: Couldn't receive start on semaphore, exiting.\n",
	      argv[0]);
      perror(argv[0]);
      return 1;
    }
    fprintf(stderr, "rdr, readloop\n"); // debug

    do {
      while (0 < (red = read(0, bfr, sze))) {
	writ = 0;
	while (red > (writ += write(1, bfr+writ, red-writ))) {
	  if (errno != EWOULDBLOCK) {
	    fprintf(stderr,
		    "%s rdr: Error passing data, exiting.\n   Error: %s\n",
		    argv[0], strerror(errno));
	    exit(1);
	  }
	}
      }
      if (errno != EWOULDBLOCK) {
	fprintf(stderr,
		"%s rdr: Error passing data, exiting.\n   Error: %s\n",
		argv[0], strerror(errno));
	exit(1);
      }
      
    fprintf(stderr, "rdr, read\n"); // debug
      semval = semctl(sid, 2, GETVAL);
      if (semval == -1) {
	fprintf(stderr, "%s rdr: Couldn't read semaphore, exiting.\n",
		argv[0]);
	perror(argv[0]);
	return 1;
      }
    } while (semval == 0);

  }

  return 0;
}
