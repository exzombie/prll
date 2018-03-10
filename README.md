# prll
version 0.9999

`prll` (pronounced "parallel") is a utility for use with POSIX and
(mostly) compatible shells, such as `bash`, `zsh` and `dash`. It provides a
convenient interface for parallelizing the execution of a single task
over multiple data files, or actually any kind of data that you can
pass as a shell function argument. It is meant to make it simple to
fully utilize a multicore/multiprocessor machine.

Homepage: https://github.com/exzombie/prll


Contents of this file:

  1. Description
  2. Requirements
  3. Installation
  4. Licensing information


# 1 DESCRIPTION

`prll` is designed to be used not just in shell scripts, but especially
in interactive shells. To make the latter convenient, it is
implemented as a shell function. This means that it inherits the whole
environment of your current shell. Shells are not much good at
automatic job management; see
[further discussion](http://prll.sourceforge.net/shell_parallel.html).
Therefore, `prll` uses helper programs, written in C. To prevent race
conditions, System V Message Queues and Semaphores are used to signal
job completion. It also features full output buffering to prevent
mangling of data because of concurrent output.

The idea behind implementing `prll` as a shell function is that it
should have access to the current working environment: it should be
able to read variables and run shell functions. Many shell users like
having customized environments with lots of utility functions. For
such a user, `prll` will come in very handy.

A simple example is running a program on many files in parallel, like flipping
a bunch of images using all CPU cores:
```
prll -s 'mogrify -flip $1' *.jpg
```
Such functionality is offered by many other utilities; even standard commands
`find` and `xargs` can do this. `prll`, however, is not limited to running
commands given in strings and external programs. The above example could be
written as
```
OPERATION='-flip'
myfn() { mogrify $OPERATION $1 ; }
prll myfn *.jpg
```
`prll` is part of the shell and picks up both variables and functions. Think
about this: if you are writing a script, either a batch program or a set of
utility functions for interactive use, there is no need to put code into
external programs or build long strings of commands fraught with quoting
issues. `prll` also provides tools for argument splitting and basic resource
locking. See examples in `prll.txt` or, if `prll` is installed already, in the
man page.


# 2 REQUIREMENTS

- `sh`-like shell, such as `bash`, `zsh` or `dash`
- C compiler, such as `gcc`
- GNU `make`
- OS support for System V Message Queues and Semaphores
- device files `/dev/urandom` or `/dev/random`
- the `cat` utility
- optional tests require utilites `tr`, `grep`, `sort`, `split`, `diff` and `uname`
- optional rebuilding of the man page requires [txt2man](http://mvertes.free.fr/)

Systems tested: GNU/Linux, FreeBSD, OpenBSD, MacOS X

These requirements should be satisfied by your system by default,
excepting perhaps the compiler and its toolchain, which are not
installed by default on systems such as Ubuntu Linux. Refer to your
system's documentation on how to install missing programs. If you can
find prebuilt packages for your system (some are listed on `prll`
homepage) you need neither `make` nor the compiler.

`prll` also looks for the `/proc/cpuinfo` file. It uses it to
automatically determine the number of processors. Non-Linux systems
may lack this file or have a different syntax. Setting the number of
parallel processes manually renders the cpuinfo file unnecessary (see
usage instructions below).

Linux systems that were tested had much larger Message Queue size than
non-Linux systems. Queue size dictates the maximum number of jobs that
can be run in parallel. A rule of thumb: a BSD system can run about 20
jobs, depending on the number of existing queues, while a Linux system
can run over 500 jobs; at that point, the shell's job table becomes
saturated.


# 3 INSTALLATION

Compile the helper programs. You can use the included `Makefile`. If you
have `gcc`, you can simply run
```
make
```

On non-GNU systems, replace that with 'gmake'.
If you have `gcc` and want different compiler options, do
```
CFLAGS=whatever make
```

If you have a different compiler, you may want to completely override
compiler options, like so
```
make CFLAGS=whatever
```

You may wish to run `make test` at this point. It will do some simple
tests to verify that `prll` produces correct results. The test suite is
not comprehensive, however, and is itself not well tested, so you
should try `prll` on real-world data before coming to any
conclusions. Failure is not necessarily meaningful, either. For
example, if there are already several message queues being used on
your system, you may be running out of IPC memory. That would cause
some tests to fail or hang (in fact, some are disabled on non-Linux
systems for this reason), while it wouldn't interfere with normal
operation as long as you don't run too many parallel jobs. Also, be
aware that full testing requires several hundred megabytes of disk
space.

When `prll` is built, it is time to install it. Running
```
make install
```
will install in the default prefix, which is `/usr/local`. If you wish
to install it somewhere else, e.g. your home directory, you can do
```
make PREFIX=/home/username/software/prll ENV_PATH=/home/username/software/prll install
```
While `PREFIX` specifies the path to `prll`'s support files and
documentation, `ENV_PATH` specifies the path to the `prll.sh` file
itself and defaults to `/etc/profile.d`. This default is a common
convention on linux systems and means that `prll` is available by
default in login shells. There is no such convention on other systems,
so `prll.sh` should be put in an accessible location and users should
source it from their profile scripts themselves. In short:

  - on most linux systems, with the default ENV_PATH, prll will be
    available in login shells automatically;
  - for use in shell scripts, the script should source `prll.sh`
    explicitly;
  - on non-linux systems, interactive shells need to source
    `prll.sh` as well, e.g. in `~/.bashrc` or similar.

If you are making a distribution package, using `DESTDIR` installs
into a staging directory, as usual.


# 4 LICENSING INFORMATION

The `prll` package is provided under the GNU General Public
License, version 3 or later. See COPYING for more information.

Copyright 2009-2018 Jure Varlec
