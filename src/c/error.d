/*
    error.c -- Error handling.
*/
/*
    Copyright (c) 1984, Taiichi Yuasa and Masami Hagiya.
    Copyright (c) 1990, Giuseppe Attardi.
    Copyright (c) 2001, Juan Jose Garcia Ripoll.

    ECL is free software; you can redistribute it and/or
    modify it under the terms of the GNU Library General Public
    License as published by the Free Software Foundation; either
    version 2 of the License, or (at your option) any later version.

    See file '../Copyright' for full details.
*/


#include "ecl.h"
#include <signal.h>

void
cs_overflow(void)
{
#ifdef DOWN_STACK
	if (cs_limit < cs_org - cssize)
	  cs_limit -= CSGETA;
#else
	if (cs_limit > cs_org + cssize)
	  cs_limit += CSGETA;
#endif
	FEerror("Control stack overflow.", 0);
}

void
error(const char *s)
{
	printf("\nUnrecoverable error: %s\n", s);
	fflush(stdout);
#ifdef SIGIOT
	signal(SIGIOT, SIG_DFL); /* avoid getting into a loop with abort */
#endif
	abort();
}

void
internal_error(const char *s)
{
	printf("\nInternal error in %s()\n", s);
	fflush(stdout);
#ifdef SIGIOT
	signal(SIGIOT, SIG_DFL); /* avoid getting into a loop with abort */
#endif
	abort();
}

/*****************************************************************************/
/*		Support for Lisp Error Handler				     */
/*****************************************************************************/

cl_object null_string;

void
terminal_interrupt(bool correctable)
{
	funcall(2, @'si::terminal-interrupt', correctable? Ct : Cnil);
}

void
FEerror(char *s, int narg, ...)
{
	cl_va_list args;
	cl_va_start(args, narg, narg, 0);
	funcall(4, @'si::universal-error-handler',
		Cnil,                    /*  not correctable  */
		make_constant_string(s),	 /*  condition text  */
		cl_grab_rest_args(args));
}

cl_object
CEerror(char *err, int narg, ...)
{
	cl_va_list args;
	cl_va_start(args, narg, narg, 0);
	return funcall(4, @'si::universal-error-handler',
		       Ct,			/*  correctable  */
		       make_constant_string(err),	/*  continue-format-string  */
		       cl_grab_rest_args(args));
}

/***********************
 * Conditions signaler *
 ***********************/

void
FEcondition(int narg, cl_object name, ...)
{
	cl_va_list args;
	cl_va_start(args, name, narg, 1);
	funcall(4, @'si::universal-error-handler',
		Cnil,                    /*  not correctable  */
		name,                    /*  condition name  */
		cl_grab_rest_args(args));
}

void
FEprogram_error(const char *s, int narg, ...)
{
	cl_va_list args;
	gc(t_contiguous);
	cl_va_start(args, narg, narg, 0);
	funcall(4, @'si::universal-error-handler',
		Cnil,                    /*  not correctable  */
		@'si::simple-program-error', /*  condition name  */
		cl_list(4, @':format-control', make_constant_string(s),
			@':format-arguments', cl_grab_rest_args(args)));
}

void
FEcontrol_error(const char *s, int narg, ...)
{
	cl_va_list args;
	cl_va_start(args, narg, narg, 0);
	funcall(4, @'si::universal-error-handler',
		Cnil,                    /*  not correctable  */
		@'si::simple-control-error', /*  condition name  */
		cl_list(4, @':format-control', make_constant_string(s),
			@':format-arguments', cl_grab_rest_args(args)));
}

void
FEcannot_open(cl_object fn)
{
	FEcondition(3, @'file-error', @':pathname', fn);
}

void
FEend_of_file(cl_object strm)
{
	FEcondition(3, @'end-of-file', @':stream', strm);
}

void
FEwrong_type_argument(cl_object type, cl_object value)
{
	FEcondition(5, @'type-error', @':datum', value, @':expected-type', type);
}

void
FEunbound_variable(cl_object sym)
{
	FEcondition(3, @'unbound-variable', @':name', sym);
}

void
FEundefined_function(cl_object fname)
{
	FEcondition(3, @'undefined-function', @':name', fname);
}

/*************
 * Shortcuts *
 *************/

void
FEwrong_num_arguments(cl_object fun)
{
	FEprogram_error("Wrong number of arguments passed to function ~S.",
			1, fun);
}

void
FEwrong_num_arguments_anonym(void)
{
	FEprogram_error("Wrong number of arguments passed to an anonymous function", 0);
}

void
FEinvalid_macro_call(cl_object name)
{
	FEerror("Invalid macro call to ~S.", 1, name);
}

void
FEinvalid_variable(char *s, cl_object obj)
{
	FEerror(s, 1, obj);
}

void
FEassignment_to_constant(cl_object v)
{
	FEprogram_error("SETQ: Tried to assign a value to the constant ~S.", 1, v);
}

void
FEinvalid_function(cl_object obj)
{
	FEwrong_type_argument(@'function', obj);
}

/*      bootstrap version                */
static
@(defun "universal_error_handler" (c err args)
@
	error("\nLisp initialization error.\n");
@)

void
illegal_index(cl_object x, cl_object i)
{
	FEerror("~S is an illegal index to ~S.", 2, i, x);
}

void
FEtype_error_symbol(cl_object obj)
{
	FEwrong_type_argument(@'symbol', obj);
}

/************************************
 * Higher level interface to errors *
 ************************************/

@(defun error (eformat &rest args)
@
	funcall(4, @'si::universal-error-handler',
		Cnil,
		eformat,
		cl_grab_rest_args(args));
@)

@(defun cerror (cformat eformat &rest args)
@
	return(funcall(4, @'si::universal-error-handler',
		       cformat,
		       eformat,
		       cl_grab_rest_args(args)));
@)

void
init_error(void)
{
	cl_def_c_function_va(@'si::universal-error-handler', universal_error_handler);
	null_string = make_constant_string("");
	register_root(&null_string);
}
