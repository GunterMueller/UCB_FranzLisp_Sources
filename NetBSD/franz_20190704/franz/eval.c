/*-					-[Thu Aug 18 10:07:22 1983 by jkf]-
 * 	eval.c
 * evaluator
 *
 * (c) copyright 1982, Regents of the University of California
 */

#include <sys/cdefs.h>
#ifndef lint
#ifdef notdef
static char    *rcsid 
__attribute__((__unused__)) =
"Header: eval.c,v 1.6 83/09/07 17:54:42 sklower Exp";
#else
__RCSID("$Id: eval.c,v 1.10 2014/12/11 17:12:17 christos Exp $");
#endif
#endif

#include <signal.h>
#include <stdarg.h>
#include <stdlib.h>
#include "global.h"
#include "frame.h"



/*
 *	eval
 * returns the value of the pointer passed as the argument.
 *
 */

lispval
eval(lispval actarg)
{
#define argptr handy
	lispval         a = actarg;
	lispval         handy;
	struct nament  *nameptr;
	struct argent  *workp;
	struct nament  *oldbnp = bnp;
	int             dopopframe = FALSE;
	int             type, shortcircuit = TRUE;
	Savestack(4);

#if 0
	printf("Eval: ");
	printr(a, stdout);
	printf("\n");
#endif
#ifdef DEBUG
	if (rsetsw && rsetatom->a.clb != nil) {
		printf("Eval:");
	 	printr(a, stdout);
		printf("\nrset: ");
		printr(rsetatom->a.clb, stdout);
		printf(" evalhook: ");
		printr(evalhatom->a.clb, stdout);
		printf(" evalhook call flag: %d\n", evalhcallsw);
	}
#endif

	/* check if an interrupt is pending	 and handle if so */
	if (sigintcnt > 0)
		sigcall(SIGINT);

	if (rsetsw && rsetatom->a.clb != nil) {	/* if (*rset t) has been done */
		pbuf            pb;
		shortcircuit = FALSE;
		if (evalhsw != nil && evalhatom->a.clb != nil) {
			/*
			 * if (sstatus evalhook t) and evalhook non-nil
			 */
			if (!evalhcallsw) {
				/*
				 * if we got here after calling evalhook,
				 * then evalhcallsw will be TRUE, so we want
				 * to skip calling the hook function,
				 * permitting one form to be evaluated before
				 * the hook fires.
				 */
				/*
				 * setup equivalent of (funcall evalhook <arg
				 * to eval>)
				 */
				(np++)->val = a;	/* push form on
							 * namestack */
				lbot = np;	/* set up args to funcall */
				(np++)->val = evalhatom->a.clb;	/* push evalhook's clb */
				(np++)->val = a;	/* eval's arg becomes
							 * 2nd arg to funcall */
				PUSHDOWN(evalhatom, nil);	/* bind evalhook to nil */
				PUSHDOWN(funhatom, nil);	/* bind funcallhook to
								 * nil */
				funhcallsw = TRUE;	/* skip any funcall hook */
				handy = Lfuncal();	/* now call funcall */
				funhcallsw = FALSE;
				POP;
				POP;
				Restorestack();
				return (handy);
			};
		}
		errp = Pushframe(F_EVAL, a, nil);
		dopopframe = TRUE;	/* remember to pop later */
		if (retval == C_FRETURN) {
			Restorestack();
			errp = Popframe();
			return (lispretval);
		}
	};

	evalhcallsw = FALSE;	/* clear indication that evalhook called */

	switch (TYPE(a)) {
	case ATOM:
		if (rsetsw && rsetatom->a.clb != nil && bptr_atom->a.clb != nil) {

			struct nament  *bpntr, *eval1bptr;
			/* Both rsetsw and rsetatom for efficiency */
			/* bptr_atom set by second arg to eval1 */
			eval1bptr = (struct nament *) bptr_atom->a.clb->d.cdr;
			/*
			 * eval1bptr is bnp when eval1 was called; if an atom
			 * was bound after this, then its clb is valid
			 */
			for (bpntr = eval1bptr; bpntr < bnp; bpntr++)
				if (bpntr->atm == a) {
					handy = a->a.clb;
					goto gotatom;
				};	/* Value saved in first binding of a,
					 * if any, after pointer to eval1, is
					 * the valid value, else use its clb */
			for (bpntr = (struct nament *) bptr_atom->a.clb->d.car;
			     bpntr < eval1bptr; bpntr++)
				if (bpntr->atm == a) {
					handy = bpntr->val;
					goto gotatom;	/* Simply no way around
							 * goto here */
				};
		};
		handy = a->a.clb;
gotatom:
		if (handy == CNIL) {
			handy = errorh1(Vermisc, "Unbound Variable:", nil, TRUE, 0, a);
		}
		if (dopopframe)
			errp = Popframe();
		Restorestack();
		return (handy);

	case VALUE:
		if (dopopframe)
			errp = Popframe();
		Restorestack();
		return (a->l);

	case DTPR:
		(np++)->val = a;/* push form on namestack */
		lbot = np;	/* define beginning of argstack */
		/* oldbnp = bnp;		   redundant - Mitch Marcus */
		a = a->d.car;	/* function name or lambda-expr */
		for (EVER) {
			switch (TYPE(a)) {
			case ATOM:
				/* get function binding  */
				if (a->a.fnbnd == nil && a->a.clb != nil
				    && a->a.clb != CNIL)
				{
#if 0
					printf("Atom: ");
					printr(a, stdout);
					printf("\n");
					printf("%p\n", a->a.clb);
#endif
					a = a->a.clb;
					if (TYPE(a) == ATOM)
						a = a->a.fnbnd;
				} else
					a = a->a.fnbnd;
				break;
			case VALUE:
				a = a->l;	/* get value  */
				break;
			}

			vtemp = (CNIL - 1);	/* sentinel value for error
						 * test */

			/* funcal: */
			switch (TYPE(a)) {
			case BCD:	/* function */
				argptr = actarg->d.cdr;

				/*
				 * decide whether lambda, nlambda or macro
				 * and push args onto argstack accordingly.
				 */

				if (a->bcd.discipline == nlambda) {
					(np++)->val = argptr;
					TNP;
				} else if (a->bcd.discipline == macro) {
					(np++)->val = actarg;
					TNP;
				} else
					for (; argptr != nil; argptr = argptr->d.cdr) {
						/*
						 * short circuit evaluations
						 * of ATOM, INT, DOUB if not
						 * in debugging mode
						 */
						if (shortcircuit
						    && ((type = TYPE(argptr->d.car)) == ATOM)
						    && (argptr->d.car->a.clb != CNIL))
							(np++)->val = argptr->d.car->a.clb;
						else if (shortcircuit &&
							 ((type == INT) || (type == STRNG)))
							(np++)->val = argptr->d.car;
						else
							(np++)->val = eval(argptr->d.car);
						TNP;
					}
				/* go for it */

				if (TYPE(a->bcd.discipline) == STRNG)
					vtemp = Ifcall(a);
				else
					vtemp = (a->bcd.start)();
				break;

			case ARRAY:
				vtemp = Iarray(a, actarg->d.cdr, TRUE);
				break;

			case DTPR:	/* push args on argstack according to
					 * type                */
				protect(a);	/* save function definition
						 * in case function is
						 * redefined */
				lbot = np;
				argptr = a->d.car;
				if (argptr == lambda) {
					for (argptr = actarg->d.cdr;
					     argptr != nil; argptr = argptr->d.cdr) {

						(np++)->val = eval(argptr->d.car);
						TNP;
					}
				} else if (argptr == nlambda) {
					(np++)->val = actarg->d.cdr;
					TNP;
				} else if (argptr == macro) {
					(np++)->val = actarg;
					TNP;
				} else if (argptr == lexpr) {
					for (argptr = actarg->d.cdr;
					     argptr != nil; argptr = argptr->d.cdr) {

						(np++)->val = eval(argptr->d.car);
						TNP;
					}
					handy = newdot();
					handy->d.car = (lispval) lbot;
					handy->d.cdr = (lispval) np;
					PUSHDOWN(lexpr_atom, handy);
					lbot = np;
					(np++)->val = inewint(((lispval *) handy->d.cdr) - (lispval *) handy->d.car);

				} else
					break;	/* something is wrong - this
						 * isn't a proper function */

				argptr = (a->d.cdr)->d.car;
				nameptr = bnp;
				workp = lbot;
				if (bnp + (np - lbot) > bnplim)
					binderr();
				for (; argptr != (lispval) nil;
				     workp++, argptr = argptr->d.cdr) {	/* rebind formal names
									 * (shallow) */
					if (argptr->d.car == nil)
						continue;
					/*
					 * if(((nameptr)->atm =
					 * argptr->d.car)==nil)
					 * error("Attempt to lambda bind
					 * nil",FALSE);
					 */
					nameptr->atm = argptr->d.car;
					if (workp < np) {
						nameptr->val = nameptr->atm->a.clb;
						nameptr->atm->a.clb = workp->val;
					} else
						bnp = nameptr,
							error("Too few actual parameters", FALSE);
					nameptr++;
				}
				bnp = nameptr;
				if (workp < np)
					error("Too many actual parameters", FALSE);

				/* execute body, implied prog allowed */

				for (handy = a->d.cdr->d.cdr;
				     handy != nil;
				     handy = handy->d.cdr) {
					vtemp = eval(handy->d.car);
				}
			}
			if (vtemp != (CNIL - 1)) {
				/* if we get here with a believable value, */
				/* we must have executed a function. */
				popnames(oldbnp);

				/* in case some clown trashed t */

				tatom->a.clb = (lispval) tatom;
				if (a->d.car == macro) {
					if (Vdisplacemacros->a.clb && (TYPE(vtemp) == DTPR)) {
						actarg->d.car = vtemp->d.car;
						actarg->d.cdr = vtemp->d.cdr;
					}
					vtemp = eval(vtemp);
				}
				/*
				 * It is of the most wonderful coincidence
				 * that the offset for car is the same as for
				 * discipline so we get bcd macros for free
				 * here !
				 */
				if (dopopframe)
					errp = Popframe();
				Restorestack();
				return (vtemp);
			}
			popnames(oldbnp);
			a = (lispval) errorh1(Verundef, "eval: Undefined function ", nil, TRUE, 0, actarg->d.car);
		}

	}
	if (dopopframe)
		errp = Popframe();
	Restorestack();
	return (a);		/* other data types are considered constants */
}

/*
 *    popnames
 * removes from the name stack all entries above the first argument.
 * routine should usually be used to clean up the name stack as it
 * knows about the special cases.  bnp is returned pointing to the
 * same place as the argument passed.
 */
lispval
popnames(struct nament *llimit)
{
	struct nament  *rnp;

	for (rnp = bnp; --rnp >= llimit;)
		rnp->atm->a.clb = rnp->val;
	bnp = llimit;
	return nil;
}


/*
 * dumpnamestack utility routine to dump out the namestack. from bottom to 5
 * above np should be put elsewhere
 */
void 
dumpnamestack(void)
{
	struct argent  *newnp;

	printf("namestack dump:\n");
	for (newnp = orgnp; (newnp < np + 6) && (newnp < nplim); newnp++) {
		if (newnp == np)
			printf("**np:**\n");
		printf("[%td]: ", newnp - orgnp);
		printr(newnp->val, stdout);
		printf("\n");
	}
	printf("end namestack dump\n");
}



lispval
Lapply(void)
{
	lispval         a;
	lispval         handy;
	lispval         vtmp;
	struct nament  *oldbnp = bnp;
	struct argent  *oldlbot = lbot;	/* Bottom of my frame! */
	struct argent  *oldnp = np;	/* First free on stack */
	int             extrapush;	/* if must save function value */

	a = lbot->val;
	argptr = lbot[1].val;
	if (np - lbot != 2)
		errorh2(Vermisc, "Apply: Wrong number of args.", nil, FALSE,
			999, a, argptr);
	if (TYPE(argptr) != DTPR && argptr != nil)
		argptr = errorh1(Vermisc, "Apply: non-list of args", nil, TRUE,
				 998, argptr);
	(np++)->val = a;	/* push form on namestack */
	TNP;
	lbot = np;		/* bottom of current frame */
	for (EVER) {
		extrapush = 0;
		if (TYPE(a) == ATOM) {
			a = a->a.fnbnd;
			extrapush = 1;
		}
		/*
		 * get function definition (unless calling form is itself a
		 * lambda- expression)
		 */
		vtmp = CNIL;	/* sentinel value for error test */
		switch (TYPE(a)) {

		case BCD:
			/* push arguments - value of a */
			if (a->bcd.discipline == nlambda || a->bcd.discipline == macro) {
				(np++)->val = argptr;
				TNP;
			} else
				for (; argptr != nil; argptr = argptr->d.cdr) {
					(np++)->val = argptr->d.car;
					TNP;
				}

			if (TYPE(a->bcd.discipline) == STRNG)
				vtmp = Ifcall(a);	/* foreign function */
			else
				vtmp = (a->bcd.start)();	/* go for it */
			break;

		case ARRAY:
			vtmp = Iarray(a, argptr, FALSE);
			break;


		case DTPR:
			if (a->d.car == nlambda || a->d.car == macro) {
				(np++)->val = argptr;
				TNP;
			} else if (a->d.car == lambda)
				for (; argptr != nil; argptr = argptr->d.cdr) {
					(np++)->val = argptr->d.car;
					TNP;
				}
			else if (a->d.car == lexpr) {
				for (; argptr != nil; argptr = argptr->d.cdr) {

					(np++)->val = argptr->d.car;
					TNP;
				}
				handy = newdot();
				handy->d.car = (lispval) lbot;
				handy->d.cdr = (lispval) np;
				PUSHDOWN(lexpr_atom, handy);
				lbot = np;
				(np++)->val = inewint(((lispval *) handy->d.cdr) - (lispval *) handy->d.car);

			} else
				break;	/* something is wrong - this isnt a
					 * proper function */
			rebind(a->d.cdr->d.car, lbot);

			if (extrapush == 1) {
				protect(a);
				extrapush = 2;
			}
			for (handy = a->d.cdr->d.cdr;
			     handy != nil;
			     handy = handy->d.cdr) {
				vtmp = eval(handy->d.car);	/* go for it */
			}
			break;

		case VECTOR:
			/* certain vectors are valid (fclosures) */
			if (a->v.vector[VPropOff] == fclosure)
				vtmp = (lispval) Ifclosure(a, FALSE);
			break;

		};

		/* pop off extra value if we pushed it before */
		if (extrapush == 2) {
			np--;
			extrapush = 0;
		};

		if (vtmp != CNIL)
			/* if we get here with a believable value, */
			/* we must have executed a function. */
		{
			popnames(oldbnp);

			/* in case some clown trashed t */

			tatom->a.clb = (lispval) tatom;
			np = oldnp;
			lbot = oldlbot;
			return (vtmp);
		}
		popnames(oldbnp);
		a = (lispval) errorh1(Verundef, "apply: Undefined Function ",
				      nil, TRUE, 0, oldlbot->val);
	}
	/* NOT REACHED */
}


/*
 * Rebind -- rebind formal names
 */
void
rebind(
	lispval         argptr,	/* argptr points to list of atoms */
	struct argent  *workp	/* workp points to position on stack where
				 * evaluated args begin */
)
{
	struct nament  *nameptr = bnp;

	for (; argptr != (lispval) nil;
	     workp++, argptr = argptr->d.cdr) {	/* rebind formal names
						 * (shallow) */
		if (argptr->d.car == nil)
			continue;
		nameptr->atm = argptr->d.car;
		if (workp < np) {
			nameptr->val = nameptr->atm->a.clb;
			nameptr->atm->a.clb = workp->val;
		} else
			bnp = nameptr,
				error("Too few actual parameters", FALSE);
		nameptr++;
		if (nameptr > bnplim)
			binderr();
	}
	bnp = nameptr;
	if (workp < np)
		error("Too many actual parameters", FALSE);
}

/*
 * the argument to Lfuncal is now mandatory. If
 * it is given  then it is the name of the function to call and lbot points
 * to the first arg. if it is not given, then lbot points to the function to
 * call
 */
lispval
Ifuncal(lispval fcn)
{
	lispval         handy;
	struct nament  *oldbnp = bnp;	/* MUST be first local for evalframe */
	lispval         a;
	lispval         fcncalled;
	lispval         vtmp;
	int             typ, dopopframe = FALSE, extrapush;
	Savestack(3);

	if (fcn != NULL)	/* function I am evaling.    */
		a = fcncalled = fcn;
	else {
		a = fcncalled = lbot->val;
		lbot++;
	}

#ifdef DEBUG
	if (rsetsw && rsetatom->a.clb != nil) {
		printf("evalhsw: ");
		printr(evalhsw, stdout);
		printf("\nrset: ");
		printr(rsetatom->a.clb, stdout);
		printf(" funhook: ");
		printr(funhatom->a.clb, stdout);
		printf(" funhook call flag: %d\n", funhcallsw);
	}
#endif

	/* check if exception pending */
	if (sigintcnt > 0)
		sigcall(SIGINT);

	if (rsetsw && rsetatom->a.clb != nil) {	/* if (*rset t) has been done */
		pbuf            pb;
		if (evalhsw != nil && funhatom->a.clb != nil) {
			/*
			 * if (sstatus evalhook t) and evalhook non-nil
			 */
			if (!funhcallsw) {
				/*
				 * if we got here after calling funcallhook,
				 * then funhcallsw will be TRUE, so we want
				 * to skip calling the hook function,
				 * permitting one form to be evaluated before
				 * the hook fires.
				 */
				/*
				 * setup equivalent of (funcall funcallhook
				 * <args to eval>)
				 */
				protect(a);
				a = fcncalled = funhatom->a.clb;	/* new function to
									 * funcall */
				PUSHDOWN(funhatom, nil);	/* lambda-bind
								 * funcallhook to nil */
				PUSHDOWN(evalhatom, nil);
#ifdef DEBUG
				printf(" now will funcall ");
				printr(a,stdout);
				putchar('\n');
#endif
			}
		}
		errp = Pushframe(F_FUNCALL, a, nil);
		dopopframe = TRUE;	/* remember to pop later */
		if (retval == C_FRETURN) {
			popnames(oldbnp);
			errp = Popframe();
			Restorestack();
			return (lispretval);
		}
	}

	funhcallsw = FALSE;	/* so recursive calls to funcall will cause
				 * hook to fire */
	for (EVER) {
top:
		extrapush = 0;

		typ = TYPE(a);
		if (typ == ATOM) {	/* get function defn (unless calling
					 * form */
			/* is itself a lambda-expr) */
			a = a->a.fnbnd;
			typ = TYPE(a);
			extrapush = 1;	/* must protect this later */
		}
		vtmp = CNIL - 1;	/* sentinel value for error test */
		switch (typ) {
		case ARRAY:
			protect(a);	/* stack array descriptor on top */
			a = a->ar.accfun;	/* now funcall access
						 * function */
			goto top;
		case BCD:
			if (a->bcd.discipline == nlambda) {
				if (np == lbot)
					protect(nil);	/* default is nil */
				while (np - lbot != 1 || (lbot->val != nil &&
						 TYPE(lbot->val) != DTPR)) {
					lbot->val = errorh1(Vermisc,
					    "Bad funcall arg(s) to fexpr.",
					    nil, TRUE, 0, lbot->val);

					np = lbot + 1;
				}
			}
			/* go for it */

			if (TYPE(a->bcd.discipline) == STRNG)
				vtmp = Ifcall(a);
			else
				vtmp = (a->bcd.start)();
			if (a->bcd.discipline == macro)
				vtmp = eval(vtmp);
			break;


		case DTPR:
			if (a->d.car == lambda) {
				;	/* VOID */
			} else if (a->d.car == nlambda || a->d.car == macro) {
				if (np == lbot)
					protect(nil);	/* default */
				while (np - lbot != 1 || (lbot->val != nil &&
						 TYPE(lbot->val) != DTPR)) {
					lbot->val = error(
					    "Bad funcall arg(s) to fexpr.",
					    TRUE);
					np = lbot + 1;
				}
			} else if (a->d.car == lexpr) {
				handy = newdot();
				handy->d.car = (lispval) lbot;
				handy->d.cdr = (lispval) np;
				PUSHDOWN(lexpr_atom, handy);
				lbot = np;
				(np++)->val = inewint(((lispval *) handy->d.cdr) - (lispval *) handy->d.car);
			} else {
				printf("%p\n", a->d.car);
				break;	/* something is wrong - this isn't a
					 * proper function */
			}
			rebind(a->d.cdr->d.car, lbot);

			/*
			 * since the actual arguments are bound to their
			 * formal params we can pop them off the stack.
			 * However if we are doing debugging (that is if
			 * we've pushed a frame on the stack) then we must
			 * not pop off the actual args since they must be
			 * visible for evalframe to work
			 */
			if (!dopopframe)
				np = lbot;
			if (extrapush == 1) {
				protect(a);
				extrapush = 2;
			}
			for (handy = a->d.cdr->d.cdr;
			     handy != nil;
			     handy = handy->d.cdr) {
				vtmp = eval(handy->d.car);	/* go for it */
			}
			if (a->d.car == macro)
				vtmp = eval(vtmp);
			break;

		case VECTOR:
			/*
			 * A fclosure represented as a vector with the
			 * property 'fclosure'
			 */
			if (a->v.vector[VPropOff] == fclosure)
				vtmp = (lispval) Ifclosure(a, TRUE);
			break;

		}

		/* pop off extra value if we pushed it before */
		if (extrapush == 2) {
			np--;
			extrapush = 0;
		}
		if (vtmp != CNIL - 1) {
			/* if we get here with a believable value, */
			/* we must have executed a function. */
			popnames(oldbnp);

			/* in case some clown trashed t */

			tatom->a.clb = (lispval) tatom;

			if (dopopframe)
				errp = Popframe();
			Restorestack();
			return (vtmp);
		}
		popnames(oldbnp);
		a = fcncalled = (lispval) errorh1(Verundef,
		    "funcall: Bad function", nil, TRUE, 0, fcncalled);
	}
	/* NOT REACHED */
}
lispval				/* this version called from lisp */
Lfuncal(void)
{
	lispval         handy;
	Savestack(0);

	switch (np - lbot) {
	case 0:
		return argerr("funcall");
	}
	handy = lbot++->val;
	handy = Ifuncal(handy);
	Restorestack();
	return (handy);
}

/*
 * The following must be the next "function" after Lfuncal, for the sake of
 * Levalf.
 */
void 
fchack (void)
{
}


/*
 * Llexfun  :: lisp function lexpr-funcall
 * lexpr-funcall is a cross between funcall and apply.
 * the last argument is nil or a list of the rest of the arguments.
 * we push those arguments on the stack and call funcall
 *
 */
lispval
Llexfun(void)
{
	lispval         handy;

	switch (np - lbot) {
	case 0:
		return argerr("lexpr-funcall");	/* need at least one arg */
	case 1:
		return (Lfuncal());	/* no args besides function */
	}
	/* have at least one argument past the function to funcall */
	handy = np[-1].val;	/* get last value */
	np--;			/* pop it off stack */

	while ((handy != nil) && (TYPE(handy) != DTPR))
		handy = errorh1(Vermisc, "lexpr-funcall: last argument is not a list ",
				nil, TRUE, 0, handy);

	/* stack arguments */
	for (; handy != nil; handy = handy->d.cdr)
		protect(handy->d.car);

	return (Lfuncal());
}


#undef protect

lispval         protect(lispval);

/*
 * protect pushes the first argument onto namestack, thereby protecting from
 * gc
 */
lispval
protect(lispval a)
{
	(np++)->val = a;
	if (np >= nplim)
		namerr();
	return a;
}

/*
 * unprot returns the top thing on the name stack.  Underflow had better not
 * occur.
 */
lispval
unprot(void)
{
	return ((--np)->val);
}

lispval
linterp(void)
{
	return error("BYTE INTERPRETER CALLED ERRONEOUSLY", FALSE);
}

/*
 * Undeff - called from qfuncl when it detects a call to a undefined function
 * from compiled code, we print out a message and will continue only if
 * returned a symbol (ATOM in C parlance).
 */
lispval
Undeff(lispval atmn)
{
	do {
		atmn = errorh1(Verundef,
		    "Undefined function called from compiled code ",
		    nil, TRUE, 0, atmn);
	}
	while (TYPE(atmn) != ATOM);
	return (atmn);
}

/* VARARGS1 */
void
bindfix(lispval firstarg, ...)
{
	lispval         argp;
	va_list         ap;
	struct nament  *mybnp = bnp;
	va_start(ap, firstarg);
#ifdef DEBUG
	printf("bindfix\n");
#endif

	for (argp = firstarg; argp != nil; argp = va_arg(ap, lispval)) {
		mybnp->atm = argp;
		mybnp->val = mybnp->atm->a.clb;
		mybnp->atm->a.clb = va_arg(ap, lispval);
		bnp = mybnp++;
	}
	va_end(ap);
}
