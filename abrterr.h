#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>

#define abrterr()							\
  do {									\
  fprintf(stderr,							\
	  "\n"								\
	  "Error in %s on line %d. Aborting.\n"				\
	  "Error message: %s\n",					\
	  "\n"								\
	  __FILE__, __LINE__, strerror(errno)); exit(1);		\
  } while (0)
#define abrterr2(msg)							\
  do {									\
  fprintf(stderr,							\
	  "\n"								\
	  "Error in %s on line %d. Aborting.\n"				\
	  "Error message: %s\n",					\
	  "\n"								\
	  __FILE__, __LINE__, msg); exit(1);				\
  } while (0)
