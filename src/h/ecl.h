/*
    ecl.h -- Main headers for development of ECL
*/
/*
    Copyright (c) 1984, Taiichi Yuasa and Masami Hagiya.
    Copyright (c) 1990, Giuseppe Attardi.

    ECoLisp is free software; you can redistribute it and/or
    modify it under the terms of the GNU Library General Public
    License as published by the Free Software Foundation; either
    version 2 of the License, or (at your option) any later version.

    See file '../Copyright' for full details.
*/

#include <sys/param.h>		/* includes <sys/signal.h> and <sys/types.h> */
#include <sys/types.h>		/* for EMX */
#include <stddef.h>
#include <stdio.h>
#include <stdarg.h>
#include <setjmp.h>
#include "config.h"
#ifndef cygwin
#include <inttypes.h>
#endif
#include <gmp.h>
#include <object.h>
#include <stacks.h>
#ifdef ECL_THREADS
# include <pthread.h>
# define start_critical_section()
# define end_critical_section()
#else
# define start_critical_section()
# define end_critical_section()
#endif
#ifndef _ARGS
# define _ARGS(x) x
#endif
#include <external.h>
/*#include "ecl-inl.h"*/
#include <eval.h>
#include <number.h>
#ifdef LOCATIVE
#include <unify.h>
#endif
