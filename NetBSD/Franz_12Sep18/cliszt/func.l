(include-if (null (get 'chead 'version)) "../chead.l")
(Liszt-file func
   "Header: func.l,v 1.12 83/08/28 17:12:47 layer Exp")

;;; ----	f u n c				function compilation
;;;
;;;			-[Wed Aug 24 10:51:11 1983 by layer]-

; cm-ncons :: macro out an ncons expression
;
(defun cm-ncons nil
  `(cons ,(cadr v-form) nil))

; cc-not :: compile a "not" or "null" expression
;
(defun cc-not nil
  (makecomment '(beginning not))
  (if (null g-loc)
      then (let ((g-cc (cons (cdr g-cc) (car g-cc)))
		 (g-ret nil))
		(d-exp (cadr v-form)))
      else (let ((finlab (d-genlab))
		 (finlab2 (d-genlab))
		 (g-ret nil))
		; eval arg and jump to finlab if nil
		(let ((g-cc (cons finlab nil))
		      g-loc)
		     (d-exp (cadr v-form)))
		; didn't jump, answer must be t
		(d-move 'T g-loc)
		(if (car g-cc)
		    then (e-goto (car g-cc))
		    else (e-goto finlab2))
		(e-label finlab)
		; answer is nil
		(d-move 'Nil g-loc)
		(if (cdr g-cc) then (e-goto (cdr g-cc)))
		(e-label finlab2))))

;--- cc-numberp :: check for numberness
;
(defun cc-numberp nil
  (d-typecmplx (cadr v-form) 
	       '#.(immed-const (plus 1_2 1_4 1_9))))

;--- cc-or :: compile an "or" expression
;
(defun cc-or nil
  (let ((finlab (d-genlab))
	(finlab2)
	(exps (if (cdr v-form) thenret else '(nil)))) ; (or) => nil
       (if (null (car g-cc))
	   then (d-exp (do ((g-cc (cons finlab nil))
			    (g-loc (if g-loc then 'reg))
			    (g-ret nil)
			    (ll exps (cdr ll)))
			   ((null (cdr ll)) (car ll))
			   (d-exp (car ll))))
		(if g-loc
		    then (setq finlab2 (d-genlab))
			 (e-goto finlab2)
			 (e-label finlab)
			 (d-move 'reg g-loc)
			 (e-label finlab2)
		    else (e-label finlab))
	   else (if (null g-loc) then (setq finlab (car g-cc)))
		(d-exp (do ((g-cc (cons finlab nil))
			    (g-loc (if g-loc then 'reg))
			    (g-ret nil)
			    (ll exps (cdr ll)))
			   ((null (cdr ll)) (car ll))
			   (d-exp (car ll))))
		(if g-loc
		    then (setq finlab2 (d-genlab))
			 (e-goto finlab2)
			 (e-label finlab)
			 (d-move 'reg g-loc)
			 (e-goto (car g-cc))	; result is t
			 (e-label finlab2)))
       (d-clearreg)))  ;we are not sure of the state due to possible branches.
			       
;--- c-prog :: compile a "prog" expression
;
; for interlisp compatibility, we allow the formal variable list to
; contain objects of this form (vrbl init) which gives the initial value
; for that variable (instead of nil)
;
(defun c-prog nil
   (let ((g-decls g-decls))
      (let (g-loc g-cc seeninit initf
	    (p-rettrue g-ret) (g-ret nil)
	    ((spcs locs initsv . initsn) (d-classify (cadr v-form))))

	 (e-pushnil (length locs))	; locals initially nil
	 (d-bindprg spcs locs)		; bind locs and specs

	 (cond (initsv (d-pushargs initsv)
		       (mapc '(lambda (x)
				 (d-move 'unstack (d-loc x))
				 (decr g-loccnt)
				 (unpush g-locs))
			     (nreverse initsn))))

	 ; determine all possible labels
	 (do ((ll (cddr v-form) (cdr ll))
	      (labs nil))
	     ((null ll) (setq g-labs `((,(d-genlab) ,@labs)
				       ,@g-labs)))
	     (if (and (car ll) (symbolp (car ll)))
		then (if (assq (car ll) labs)
			then (comp-err "label is mulitiply defined " (car ll))
			else (setq labs (cons (cons (car ll) (d-genlab))
					      labs)))))

	 ; compile each form which is not a label
	 (d-clearreg)		; unknown state after binding
	 (do ((ll (cddr v-form) (cdr ll)))
	     ((null ll))
	     (if (or (null (car ll)) (not (symbolp (car ll))))
		then (d-exp (car ll))
		else (e-label (cdr (assq (car ll) (cdar g-labs))))
		     (d-clearreg))))		; dont know state after label

      ; result is nil if fall out and care about value
      (if (or g-cc g-loc) then (d-move 'Nil 'reg))

      (e-label (caar g-labs))		; return to label
      (setq g-labs (cdr g-labs))
      (d-unbind)))			; unbind our frame

;--- d-bindprg :: do binding for a prog expression
;	- spcs : list of special variables
;	- locs : list of local variables
;	- specinit : init values for specs (or nil if all are nil)
;
(defun d-bindprg (spcs locs)
   ; place the local vrbls and prog frame entry on the stack
   (setq g-loccnt (+ g-loccnt (length locs))
	 g-locs (nconc locs `((prog . ,(length spcs)) ,@g-locs)))

   ; now bind the specials, if any, to nil
   (if spcs then (e-setupbind)
       (mapc '(lambda (vrb)
		  (e-shallowbind vrb 'Nil))
	     spcs)
       (e-unsetupbind)))

;--- d-unbind :: remove one frame from g-locs
;
(defun d-unbind nil
   (do ((count 0 (1+ count)))
       ((dtpr (car g-locs))
	(if (not (zerop (cdar g-locs)))
	    then (e-unshallowbind (cdar g-locs)))
	(cond ((not (zerop count))
	       (e-dropnp count)

	       (setq g-loccnt (- g-loccnt count))))
	(setq g-locs (cdr g-locs)))
       (setq g-locs (cdr g-locs))))
	
;--- d-classify :: seperate variable list into special and non-special
;	- lst : list of variables
; returns ( xxx yyy zzz . aaa) 
;		where xxx is the list of special variables and
;		yyy is the list of local variables
;		zzz are the non nil initial values for prog variables
;		aaa are the names corresponding to the values in zzz
;
(defun d-classify (lst)
   (do ((ll lst (cdr ll))
	(locs) (spcs) (init) (initsv) (initsn)
	(name))
       ((null ll) (cons spcs (cons locs (cons initsv initsn))))
       (if (atom (car ll))
	   then (setq name (car ll))
	   else (setq name (caar ll))
		(push name initsn)
		(push (cadar ll) initsv))
       (if (d-specialp name)
	   then (push name spcs)
	   else (push name locs))))

; cm-progn :: compile a "progn" expression
;
(defun cm-progn nil
  `((lambda nil ,@(cdr v-form))))

; cm-prog1 :: compile a "prog1" expression
;
(defun cm-prog1 nil
  (let ((gl (d-genlab)))
       `((lambda (,gl) 
		 ,@(cddr v-form)
		 ,gl)
	 ,(cadr v-form))))

; cm-prog2 :: compile a "prog2" expression
;
(defun cm-prog2 nil
   (let ((gl (d-genlab)))
       `((lambda (,gl)
	     ,(cadr v-form)
	     (setq ,gl ,(caddr v-form))
	     ,@(cdddr v-form)
	     ,gl)
	 nil)))

;--- cm-progv :: compile a progv form
;  a progv form looks like (progv 'l-vars 'l-inits 'g-exp1 ... 'g-expn)
; l-vars should be a list of variables, l-inits a list of initial forms
; We cannot permit returns and go-s through this form.
;
; we stack a (progv . 0) form on g-locs so that return and go will know
; not to try to go through this form.
;
(defun c-progv nil
   (let ((gl (d-genlab))
	 (g-labs (cons nil g-labs))
	 (g-locs (cons '(progv . 0) g-locs)))
       (d-exp `((lambda (,gl)
		    (prog1 (progn ,@(cdddr v-form))
			   (internal-unbind-vars ,gl)))
		(internal-bind-vars ,(cadr v-form) ,(caddr v-form))))))

(defun c-internal-bind-vars nil
   (let ((g-locs g-locs)
	 (g-loccnt g-loccnt))
       (d-pushargs (cdr v-form))
       (d-calldirect #-for-c '_Ibindvars
		     #+for-c 'Ibindvars
		     (length (cdr v-form)))))

(defun c-internal-unbind-vars nil
   (let ((g-locs g-locs)
	 (g-loccnt g-loccnt))
       (d-pushargs (cdr v-form))
       (d-calldirect #-for-c '_Iunbindvars
		     #+for-c 'Iunbindvars
		     (length (cdr v-form)))))

;--- cc-quote : compile a "quote" expression
; 
; if we are just looking to set the ; cc, we just make sure 
; we set the cc depending on whether the expression quoted is
; nil or not.
(defun cc-quote nil
   (let ((arg (cadr v-form))
	 argloc)
       (if (null g-loc) 
	   then (if (and (null arg) (cdr g-cc))
		    then (e-goto (cdr g-cc))
		 elseif (and arg (car g-cc))
		    then (e-goto (car g-cc))
		 elseif (null g-cc)
		    then (comp-warn "losing the value of this expression "
				    (or v-form)))
	   else (d-move (d-loclit arg nil) g-loc)
		;; When compiling to C, we can't rely on the "move" setting
	        ;; the condition codes.  We have to do something explicitly.
	        #+for-c
		(if (and (null arg) (cdr g-cc))
		    then (e-goto (cdr g-cc))
		 elseif (and arg (car g-cc))
		    then (e-goto (car g-cc)))
		#-for-c
		(d-handlecc))))

;--- c-setarg :: set a lexpr's arg
; form is (setarg index value)
;
(defun c-setarg nil
  (prog ()				;/\/ allow hack to escape w/ return
   (if (not (eq 'lexpr g-ftype))
       then (comp-err "setarg only allowed in lexprs"))
   (if (and fl-inter (eq (length (cdr v-form)) 3))	; interlisp setarg
       then (if (not (eq (cadr v-form) (car g-args)))
		then (comp-err "setarg: can only compile local setargs "
			       v-form)
		else (setq v-form (cdr v-form))))

   ; compile index into fixnum-reg, was (d-pushargs (list (cadr v-form)))
   ; /\/ and it was better so, because now fixnum-reg can be clobbered
   ; /\/ by the calculation of arg2 -- suppose it's (+ 3 (g)).  So we
   ; /\/ insert this little hack ...
   ;
   (let ((val-loc (d-simple (caddr v-form))))
        (if (null val-loc)
	    then (comp-warn "Simplifying " (or nil v-form))
	         (let ((g-cc nil)
		       (g-ret nil)
		       (g-loc 'reg)
		       (indsym (gensym 'X))
		       (valsym (gensym 'X)))
		      (return
		       (d-exp `(let ((,indsym ,(cadr v-form))
				     (,valsym ,(caddr v-form)))
				 (setarg ,indsym ,valsym)))))))
   ; /\/ end hack

   (let ((g-cc) (g-ret)
	 (g-loc '#.fixnum-reg))
       (d-exp #-for-c (cadr v-form)
	      #+for-c `(internal-fixnum-unbox ,(cadr v-form))))
   (let ((g-loc 'reg)
	 (g-cc nil)
	 (g-ret nil))
       (d-exp (caddr v-form)))
   #+for-vax
   (progn
       (e-sub3 `(* -4 #.olbot-reg) '(0 #.fixnum-reg) '#.fixnum-reg)
       (e-move 'r0 '(-8 #.olbot-reg #.fixnum-reg)))
   #+for-68k
   (progn
       (e-sub `(-4 #.olbot-reg) '#.fixnum-reg)
       (e-write3 'lea '(% -8 #.olbot-reg #.fixnum-reg) 'a5)
       (e-move 'd0 '(0 a5)))
   #+for-c
   (progn
       (e-move (e-cvt 'reg) '((#.largp-var + #.fixnum-reg) -> val)))))

;--- cc-stringp :: check for string ness
;
(defun cc-stringp nil
  (d-typesimp (cadr v-form) #.(immed-const 0)))

;--- cc-symbolp :: check for symbolness
;
(defun cc-symbolp nil
  (d-typesimp (cadr v-form) #.(immed-const 1)))

;--- c-return :: compile a "return" statement
;
(defun c-return nil
   ; value is always put in reg
   (let ((g-loc 'reg)
	 g-cc
	 g-ret)
       (d-exp (cadr v-form)))

   ; if we are doing a non local return, compute number of specials to unbind
   ; and locals to pop
   (if (car g-labs)
       then (e-goto (caar g-labs))
       else (do ((loccnt 0)		;; locals
		 (speccnt 0)		;; special
		 (catcherrset 0)	;; catch/errset frames
		 (ll g-labs (cdr ll))
		 (locs g-locs))
		((null ll) (comp-err "return used not within a prog or do"))
		(if (car ll)
		    then  (comp-note g-fname ": non local return used ")
			 ; unbind down to but not including
			 ; this frame.
			 (if (greaterp loccnt 0)
			     then (e-pop loccnt))
			 (if (greaterp speccnt 0)
			     then (e-unshallowbind speccnt))
			 (if (greaterp catcherrset 0)
			     then (comp-note
				      g-fname
				      ": return through a catch or errset"
				      v-form)
				  (do ((i 0 (1+ i)))
				      ((=& catcherrset i))
				      (d-popframe)))
			 (e-goto (caar ll))
			 (return)
		    else ; determine number of locals and special on
			 ; stack for this frame, add to running
			 ; totals
			 (do ()
			     ((dtpr (car locs))
			      (if (eq 'catcherrset (caar locs)) ; catchframe
				  then (incr catcherrset)
			       elseif (eq 'progv (caar locs))
				  then (comp-err "Attempt to 'return' through a progv"))
			      (setq speccnt (+ speccnt (cdar locs))
				    locs (cdr locs)))
			     (incr loccnt)
			     (setq locs (cdr locs)))))))
	 
; c-rplaca :: compile a "rplaca" expression
;
#+for-vax
(defun c-rplaca nil
  (let ((ssimp (d-simple (caddr v-form)))
	(g-ret nil))
       (let ((g-loc (if ssimp then 'reg else 'stack))
	     (g-cc nil))
	    (d-exp (cadr v-form)))
       (if (null ssimp)
	   then (push nil g-locs)
		(incr g-loccnt)
		(let ((g-loc 'r1)
		      (g-cc nil))
		    (d-exp (caddr v-form)))
		(d-move 'unstack 'reg)
		(unpush g-locs)
		(decr g-loccnt)
		(e-move 'r1 '(4 r0))
	   else (e-move (e-cvt ssimp)  '(4 r0)))
       (d-clearreg)))		; cant tell what we are clobbering

#+for-68k
(defun c-rplaca nil
   (let ((ssimp (d-simple (caddr v-form)))
	 (g-ret nil))
       (makecomment `(c-rplaca starting :: v-form = ,v-form))
       (let ((g-loc (if ssimp then 'areg else 'stack))
	     (g-cc nil))
	   (d-exp (cadr v-form)))
       (if (null ssimp)
	   then (push nil g-locs)
		(incr g-loccnt)
		(let ((g-loc 'd1)
		      (g-cc nil))
		    (d-exp (caddr v-form)))
		(d-move 'unstack 'areg)
		(unpush g-locs)
		(decr g-loccnt)
		(e-move 'd1 '(4 a0))
	   else (e-move (e-cvt ssimp)  '(4 a0)))
       (e-move 'a0 'd0)
       (d-clearreg)
       (makecomment `(c-rplaca done))))

; Note that PNX version uses u1 directly
;
#+for-c
(defun c-rplaca nil
   (let ((ssimp (d-simple (caddr v-form)))
	 (g-ret nil))
       (makecomment `(c-rplaca starting :: v-form = ,v-form))
       ; if arg2 is simple, put arg1 in reg else on stack
       (let ((g-loc (if ssimp then 'reg else 'stack))
	     (g-cc nil))
	   (d-exp (cadr v-form)))
       ; now compute arg2 -- we will return the altered arg1
       (if (null ssimp)
	   then (push nil g-locs)
		(incr g-loccnt)
		(let ((g-loc 'u1)
		      (g-cc nil))
		    (d-exp (caddr v-form)))
		(d-move 'unstack 'reg)
		(unpush g-locs)
		(decr g-loccnt)
		(e-move 'u1 `(,(e-cvt 'reg) -> d.car))
	   else (e-move (e-cvt ssimp) `(,(e-cvt 'reg) -> d.car)))
       (d-clearreg)
       (makecomment `(c-rplaca done))))

; c-rplacd :: compile a "rplacd" expression
;
#+for-vax
(defun c-rplacd nil
  (let ((ssimp (d-simple (caddr v-form)))
	(g-ret nil))
       (let ((g-loc (if ssimp then 'reg else 'stack))
	     (g-cc nil))
	    (d-exp (cadr v-form)))
       (if (null ssimp)
	   then (push nil g-locs)
		(incr g-loccnt)
		(let ((g-loc 'r1)
		      (g-cc nil))
		    (d-exp (caddr v-form)))
		(d-move 'unstack 'reg)
		(unpush g-locs)
		(decr g-loccnt)
		(e-move 'r1 '(0 r0))
	   else (e-move (e-cvt ssimp)  '(0 r0)))
       (d-clearreg)))

#+for-68k
(defun c-rplacd nil
   (let ((ssimp (d-simple (caddr v-form)))
	 (g-ret nil))
       (makecomment `(c-rplacd starting :: v-form = ,v-form))
       (let ((g-loc (if ssimp then 'areg else 'stack))
	     (g-cc nil))
	   (d-exp (cadr v-form)))
       (if (null ssimp)
	   then (push nil g-locs)
		(incr g-loccnt)
		(let ((g-loc 'd1)
		      (g-cc nil))
		    (d-exp (caddr v-form)))
		(d-move 'unstack 'areg)
		(unpush g-locs)
		(decr g-loccnt)
		(e-move 'd1 '(0 a0))
	   else (e-move (e-cvt ssimp) '(0 a0)))
       (e-move 'a0 'd0)
       (d-clearreg)
       (makecomment `(d-rplacd done))))

#+for-c
(defun c-rplacd nil
   (let ((ssimp (d-simple (caddr v-form)))
	 (g-ret nil))
       (makecomment `(c-rplacd starting :: v-form = ,v-form))
       (let ((g-loc (if ssimp then 'reg else 'stack))
	     (g-cc nil))
	   (d-exp (cadr v-form)))
       (if (null ssimp)
	   then (push nil g-locs)
		(incr g-loccnt)
		(let ((g-loc 'u1)
		      (g-cc nil))
		    (d-exp (caddr v-form)))
		(d-move 'unstack 'reg)
		(unpush g-locs)
		(decr g-loccnt)
		(e-move 'u1 `(,(e-cvt 'reg) -> d.cdr))
	   else (e-move (e-cvt ssimp) `(,(e-cvt 'reg) -> d.cdr)))
       (d-clearreg)
       (makecomment `(d-rplacd done))))

;--- cc-setq :: compile a "setq" expression
;
(defun cc-setq nil
  (let (tmp tmp2)
       (if (oddp (length (cdr v-form)))
	   then (comp-err "wrong number of args to setq "
			  (or v-form))
	elseif (cdddr v-form)		; if multiple setq's
	   then (do ((ll (cdr v-form) (cddr ll))
		     (g-loc)
		     (g-cc nil))
		    ((null (cddr ll)) (setq tmp ll))
		    (setq g-loc (d-locv (car ll)))
		    (d-exp (cadr ll))
		    (d-clearuse (car ll)))
	else (setq tmp (cdr v-form)))

       ; do final setq
       (let ((g-loc (d-locv (car tmp)))
	     (g-cc (if g-loc then nil else g-cc))
	     (g-ret nil))
	    (d-exp (cadr tmp))
	    (d-clearuse (car tmp)))
       (if g-loc
	   then (d-move (setq tmp2 (d-locv (car tmp))) g-loc)
		(if g-cc
		    then #+(or for-68k for-c) (d-cmpnil tmp2)
			 (d-handlecc)))))

; cc-typep :: compile a "typep" expression
; 
; this returns the type of the expression, it is always non nil
; /\/ Nonsense: it returns nil for all hunks because the table is wrong.
;
#+for-vax
(defun cc-typep nil
  (let ((argloc (d-simple (cadr v-form)))
	(g-ret))
       (if (null argloc)
	   then (let ((g-loc 'reg) g-cc)
		    (d-exp (cadr v-form)))
		(setq argloc 'reg))
       (if g-loc
	   then (e-write4 'ashl '($ -9) (e-cvt argloc) 'r0)
		(e-write3 'cvtbl "_typetable+1[r0]" 'r0)
		(e-move "_tynames+4[r0]" 'r0)
		(e-move '(0 r0) (e-cvt g-loc)))
       (if (car g-cc) then (e-goto (car g-cc)))))

#+for-c
(defun cc-typep nil
  (let ((argloc (d-simple (cadr v-form)))
	(g-ret))
       (if (null argloc)
	   then (let ((g-loc 'reg) g-cc)
		    (d-exp (cadr v-form)))
		(setq argloc 'reg))
       (if g-loc
	   then (e-statement (e-cvt g-loc) '=
			     "*(tynames+1)[ TYPE(" (e-cvt argloc) ")]"))
       (if (car g-cc) then (e-goto (car g-cc)))))

#+for-68k
(defun cc-typep nil
  (let ((argloc (d-simple (cadr v-form)))
	(g-ret))
       (if (null argloc) 
	   then (let ((g-loc 'reg) g-cc)
		    (d-exp (cadr v-form)))
		(setq argloc 'reg))
       (if g-loc
	   then (e-move (e-cvt argloc) 'd0)
		(e-sub '#.nil-reg 'd0)
		(e-write3 'moveq '($ 9) 'd1)
		(e-write3 'asrl 'd1 'd0)
		(e-write3 'lea '"_typetable+1" 'a5)
		(e-add 'd0 'a5)
		(e-write3 'movb '(0 a5) 'd0)
		(e-write2 'extw 'd0)
		(e-write2 'extl 'd0)
		(e-write3 'asll '($ 2) 'd0)
		(e-write3 'lea "_tynames+4" 'a5)
		(e-add 'd0 'a5)
		(e-move '(0 a5) 'a5)
		(e-move '(0 a5) (e-cvt g-loc)))
       (if (car g-cc) then (e-goto (car g-cc)))))

; cm-symeval :: compile a symeval expression.
; the symbol cell in franz lisp is just the cdr.
;
(defun cm-symeval nil
  `(cdr ,(cadr v-form)))

; c-*throw :: compile a "*throw" expression
;
; the form of *throw is (*throw 'tag 'val) .
; we calculate and stack the value of tag, then calculate val 
; we call Idothrow to do the actual work, and only return if the
; throw failed.
;
(defun c-*throw nil
  (let ((arg2loc (d-simple (caddr v-form)))
	g-cc
	g-ret
	arg1loc
	#+for-c
	C-args)
       ; put on the C runtime stack value to throw, and
       ; tag to throw to.
       (if arg2loc
	   then (if (setq arg1loc (d-simple (cadr v-form)))
		    then (C-pusharg (e-cvt arg2loc))
			 (C-pusharg (e-cvt arg1loc))
		    else (let ((g-loc 'reg))
			     (d-exp (cadr v-form))	; calc tag
			     (C-pusharg (e-cvt arg2loc))
			     (C-pusharg (e-cvt 'reg))))
	   else (let ((g-loc 'stack))
		    (d-exp (cadr v-form))	; calc tag to stack
		    (push nil g-locs)
		    (incr g-loccnt)
		    (setq g-loc 'reg)
		    (d-exp (caddr v-form))	; calc value into reg
		    (C-pusharg (e-cvt 'reg))
		    (C-pusharg (e-cvt 'unstack))
		    (unpush g-locs)
		    (decr g-loccnt)))
       ; now push the type of non local go we are doing, in this case
       ; it is a C_THROW
       (C-pusharg (e-cvt '(immed #.C_THROW)))
       #+for-vax
       (e-write3 'calls '$3 '_Inonlocalgo)
       #+for-c
       (progn
	 (e-C-call "Inonlocalgo" C-args)
	 (e-line "/* NOTREACHED */")
	 (setq g-skipcode t))
       #+for-68k
       (e-quick-call '_Inonlocalgo)))

;--- cm-zerop ::  convert zerop to a quick test
; zerop is only allowed on fixnum and flonum arguments.  In both cases,
; if the value of the first 32 bits is zero, then we have a zero.
; thus we can define it as a macro:
#+for-vax
(defun cm-zerop nil
  (cond ((atom (cadr v-form))
	 `(and (null (cdr ,(cadr v-form))) (not (bigp ,(cadr v-form)))))
	(t (let ((gnsy (gensym)))
		`((lambda (,gnsy)
			  (and (null (cdr ,gnsy)) 
				(not (bigp ,gnsy))))
		  ,(cadr v-form))))))

#+for-68k
(defun cm-zerop nil
   (cond ((atom (cadr v-form))
	  `(and (=& 0 ,(cadr v-form))	;was (cdr ,(cadr v-form))
		(not (bigp ,(cadr v-form)))))
	 (t (let ((gnsy (gensym)))
		`((lambda (,gnsy)
		      (and (=& 0 ,gnsy)		;was (cdr ,gnsy)
			   (not (bigp ,gnsy))))
		  ,(cadr v-form))))))

; We want a more principled test when compiling to C.  Converting to call
; equal should work fairly well in the fixnum case because it is converted
; to =& if all args are known to be fixnums.
;
#+for-c
(defun cm-zerop ()
  `(equal 0 ,(cadr v-form)))
