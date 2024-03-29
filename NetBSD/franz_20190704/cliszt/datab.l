(include-if (null (get 'chead 'version)) "../chead.l")
(Liszt-file datab
   "Header: datab.l,v 1.5 83/08/28 17:14:27 layer Exp")

;;; ----	d a t a b			data base
;;;
;;;				-[Sat Aug  6 23:59:11 1983 by layer]-

;--- d-tranloc :: locate a function in the transfer table
;
; return the offset we should use for this function call
;
(defun d-tranloc (fname)
   (cond ((get fname g-tranloc))
	 (t (Push g-tran fname)
	    (let ((newval #-for-c (* 8 g-trancnt)
			  #+for-c g-trancnt))
		(putprop fname newval g-tranloc)
		(incr g-trancnt)
		newval))))


;--- d-loc :: return the location of the variable or value in IADR form 
;	- form : form whose value we are to locate
;
; if we are given a xxx as form, we check yyy;
;	xxx		yyy
;     --------	     ---------
;	nil	     Nil is always returned
;	symbol	     return the location of the symbols value, first looking
;		     in the registers, then on the stack, then the bind list.
;		     If g-ingorereg is t then we don't check the registers.
;		     We would want to do this if we were interested in storing
;		     something in the symbol's value location.
;	number	     always return the location of the number on the bind
;		     list (as a (lbind n))
;	other	     always return the location of the other on the bind
;		     list (as a (lbind n))
;
(defun d-loc (form)
   (if (null form) then 'Nil
    elseif (numberp form) then
	 (if (and (fixp form) (greaterp form -1025) (lessp form 1024))
	     then `(fixnum ,form)		; small fixnum
	     else (d-loclit form nil))
    elseif (symbolp form) 
       then (if (and (null g-ignorereg) (car (d-bestreg form nil))) thenret
		else (if (d-specialp form) then (d-loclit form t)
			 else (do ((ll g-locs (cdr ll))	; check stack
				   (n g-loccnt))
				  ((null ll)
				   (comp-warn (or form)
					      " declared special by compiler")
				   (d-makespec form)
				   (d-loclit form t))
				  (if (atom (car ll))
				      then (if (eq form (car ll))
					       then (return `(stack ,n))
					       else (setq n (1- n)))))))
       else (d-loclit form nil)))


;--- d-loclit :: locate or add litteral to bind list
;	- form : form to check for and add if not present
;	- flag : if t then if we are given a symbol, return the location of
;		 its value, else return the location of the symbol itself
;
; scheme: we share the locations of atom (symbols,numbers,string) but always
;	 create a fresh copy of anything else.
(defun d-loclit (form flag)
   (prog (loc onplist symboltype)
       (if (null form) 
	   then (return 'Nil)
	elseif (symbolp form)
	   then (setq symboltype t)
		(cond ((setq loc (get form g-bindloc))
		       (setq onplist t)))
	elseif (atom form)
	   then (do ((ll g-lits (cdr ll))	; search for atom on list
		     (n g-litcnt (1- n)))
		    ((null ll))
		    (if (eq form (car ll))
			then (setq loc n)	; found it
			     (return))))	; leave do
       (if (null loc)
	   then (Push g-lits form)
		(setq g-litcnt (1+ g-litcnt)
		      loc g-litcnt)
		(cond ((and symboltype (null onplist))
		       (putprop form loc g-bindloc))))

       (return (if (and flag symboltype) then `(bind ,loc)
		   else `(lbind ,loc)))))
			     


;--- d-locv :: find the location of a value cell, and dont return a register
;
(defun d-locv (sm)
  (let ((g-ignorereg t))
       (d-loc sm)))


;--- d-simple :: see if arg can be addressed in one instruction
;                we define simple and really simple as follows
;  <rsimple> ::= number
;		 quoted anything
;		 local symbol
;		 t
;		 nil
;  <simple>  ::= <rsimple>
;		 (cdr <rsimple>)
;		 (internal-fixnum-unbox <rsimple>)	[for-c only]
;		 global symbol
;
(defun d-simple (arg)
   (let (tmp)
       (if (d-rsimple arg) thenret
	elseif (atom arg) then (d-loc arg)
	elseif (and (memq (car arg) '(cdr car cddr cdar internal-fixnum-unbox))
		    (setq tmp (d-rsimple (cadr arg))))
	   then (if (eq 'Nil tmp) then tmp
		 elseif (atom tmp)
		    then #+for-vax
			 (if (eq 'car (car arg))
			     then `(racc 4 ,tmp)
			  elseif (eq 'cdr (car arg))
			     then `(racc 0 ,tmp)
			  elseif (eq 'cddr (car arg))
			     then `(racc * 0 ,tmp)
			  elseif (eq 'cdar (car arg))
			     then `(racc * 4 ,tmp))
			 #+for-c
			 (if (eq 'car (car arg))
			     then `(racc ,tmp -> d.car)
			  elseif (eq 'cdr (car arg))
			     then `(racc ,tmp -> d.cdr)
			  elseif (eq 'internal-fixnum-unbox (car arg))
			     then `(racc ,tmp -> i))
			 #+for-68k
			 (if (eq 'car (car arg))
			     then `(racc 4 ,tmp)
			  elseif (eq 'cdr (car arg))
			     then `(racc 0 ,tmp))
		 elseif (eq 'internal-fixnum-unbox (car arg))
		    then (d-semisimple-unbox tmp)
		 elseif (not (eq 'cdr (car arg)))
		    then nil
		 elseif (eq 'lbind (car tmp))
		    then `(bind ,(cadr tmp))
		 elseif (eq 'stack (car tmp))
		    then `(vstack ,(cadr tmp))
		 elseif (eq 'fixnum (car tmp))
		    then `(immed ,(cadr tmp))
		 elseif (atom (car tmp))
		    then #+(or for-vax for-68k)
		         `(0 ,(cadr tmp))
			 #+for-c
			 `(,(cadr tmp) -> d.cdr)
		    else (comp-err "bad arg to d-simple: " (or arg))))))

#+for-c
(defun d-semisimple-unbox (rsimple)
  ;; We do more or less what cdr does, but we add just one new IADR instead
  ;; of several (cdr converts lbind to bind and stack to vstack).  The new
  ;; IADR form just tells e-cvt to stick "->i" onto the end.
  (if (eq 'fixnum (car rsimple))
      then `(immed ,(cadr rsimple))
   elseif (memq (car rsimple) '(stack vstack bind lbind))
      then `(iunbox ,rsimple)
   elseif (atom (car rsimple))
      then (break "strange rsimple to unbox")
   else
      (break "bad rsimple to unbox")))

(defun d-rsimple (arg)
   (if (atom arg) then
       (if (null arg) then 'Nil
	elseif (eq t arg) then 'T
	elseif (or (numberp arg)
		   (memq arg g-locs)) 
	   then (d-loc arg)
	   else (car (d-bestreg arg nil)))
    elseif (eq 'quote (car arg)) then (d-loclit (cadr arg) nil)))

;--- d-specialp :: check if a variable is special
; a varible is special if it has been declared as such, or if
; the variable special is t
(defun d-specialp (vrb)
  (or special
      (eq 'special (d-findfirstprop vrb 'bindtype))   ; local special decl
      (eq 'special (get vrb g-bindtype))))

(defun d-fixnump (vrb)
   (and (symbolp vrb)
	(or (eq 'fixnum (d-findfirstprop vrb 'vartype))
	    (eq 'fixnum (get vrb g-vartype)))))

;--- d-functyp :: return the type of function
;	- name : function name
;
; If name had a macro function definition, we return `macro'.  Otherwise
; we see if name as a declared type, if so we return that.  Otherwise
; we see if name is defined and we return that if so, and finally if
; we have no idea what this function is, we return lambda.
;   This is not really satisfactory, but will handle most cases.
;
; If macrochk is nil then we don't check for the macro case.  This
; is important to prevent recursive macroexpansion.
;
(defun d-functyp (name macrochk)
   (let (func ftyp)
      (if (atom name) 
	 then
	      (setq func (getd name))
	      (setq ftyp (if (and macrochk (get name 'cmacro)) ;compiler macro
			    then 'cmacro
			  elseif (bcdp func)
			    then (let ((type (getdisc func)))
				    (if (memq type '(lambda nlambda macro))
				       then type
				     elseif (stringp type)
				       then 'lambda	; foreign function
				       else (comp-warn
					       "function "
					       name
					       " has a strange discipline "
					       type)
					    'lambda	; assume lambda
				    ))
			  elseif (dtpr func)
			    then (car func)
			  elseif (and macrochk (get name 'macro-autoload))
			    then 'macro))
	      (if (memq ftyp '(macro cmacro)) then ftyp
	       elseif (d-findfirstprop name 'functype) thenret
	       elseif (get name g-functype) thenret  ; check if declared first
	       elseif ftyp thenret
		 else 'lambda)
	 else ;/\/ can we get here? [jwd]
	      'lambda)))		; default is lambda


;[begin jwd]

;--- d-notice-definition
;
; Note that we use g-defined instead of g-functype because local functions
; don't have a g-functype property, and it was easier (safer) to add a new
; property than to change what happened for local functions.
;
(defun d-notice-definition (name type)
  ;; remember type as defined in source
  (if (get name g-defined)
      then (comp-warn name " is defined twice")
      else (putprop name type g-defined))
  ;; see if type conflicts with previous calls
  (if (memq name g-assumed-lambda)
      then (if (not (or (eq type 'lambda)
			(eq type 'lexpr)))
	       then (comp-warn name " is being defined as a " type
			 " function" N
			 " but was previously called as a lambda function."))
           ;; type no longer unknown
           (setq g-assumed-lambda (delq name g-assumed-lambda))))


;--- d-notice-call
;
; Remember the name of a function that is being called before it is defined.
; The compiler assumes it will eventually be defined as a lambda function by
; the user, and we want to notice whether that happens in this file or not.
;
(defun d-notice-call (name)
  (if (not (or (getd name)			;builtin?
	       (get name g-defined)		;defined in current source?
	       ;(get name g-stdref)		;already called?  (?safe?)
	       (memq name g-assumed-lambda)))	;already noticed?
      then (setq g-assumed-lambda (cons name g-assumed-lambda))))

;[end jwd]


;--- d-allfixnumargs :: check if all forms are fixnums
; make sure all forms are fixnums or symbols whose declared type are fixnums
;
(defun d-allfixnumargs (forms)
   (do ((xx forms (cdr xx))
	(arg))
       ((null xx) t)
       (cond ((and (fixp (setq arg (car xx))) (not (bigp arg))))
	     ((d-fixnump arg))
	     (t (return nil)))))

	      
(defun d-findfirstprop (name type)
   (do ((xx g-decls (cdr xx))
	(rcd))
       ((null xx))
       (if (and (eq name (caar xx))
		(get (setq rcd (cdar xx)) type))
	  then (return rcd))))

	      


