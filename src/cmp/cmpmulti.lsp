;;;;  Copyright (c) 1984, Taiichi Yuasa and Masami Hagiya.
;;;;  Copyright (c) 1990, Giuseppe Attardi.
;;;;
;;;;    This program is free software; you can redistribute it and/or
;;;;    modify it under the terms of the GNU Library General Public
;;;;    License as published by the Free Software Foundation; either
;;;;    version 2 of the License, or (at your option) any later version.
;;;;
;;;;    See file '../Copyright' for full details.

;;;; CMPMULT  Multiple-value-call and Multiple-value-prog1.

(in-package "COMPILER")

(defun c1multiple-value-call (args &aux forms)
  (check-args-number 'MULTIPLE-VALUE-CALL args 1)
  (cond
   ;; (M-V-C #'FUNCTION) => (FUNCALL #'FUNCTION)
   ((endp (rest args)) (c1funcall args))
   ;; (M-V-C #'FUNCTION (VALUES A ... Z)) => (FUNCALL #'FUNCTION A ... Z)
   ((and (= (length args) 2)
	 (consp (setq forms (second args)))
	 (eq 'VALUES (first forms)))
    (c1funcall (list* (first args) (rest forms))))
   ;; More complicated case.
   (t (let ((funob (c1expr (first args))))
	(make-c1form 'MULTIPLE-VALUE-CALL funob funob (c1args* (rest args)))))))

(defun c2multiple-value-call (funob forms)
  (let* ((tot (make-lcl-var :rep-type :cl-index))
	 (*temp* *temp*)
	 (loc (maybe-save-value funob forms)))
    (wt-nl "{ cl_index " tot "=0;")
    (let ((*unwind-exit* `((STACK ,tot) ,@*unwind-exit*)))
      (let ((*destination* 'VALUES))
	(dolist (form forms)
	  (c2expr* form)
	  (wt-nl tot "+=cl_stack_push_values();")))
      (c2funcall funob 'ARGS-PUSHED loc tot))
    (wt "}"))
  )

(defun c1multiple-value-prog1 (args)
  (check-args-number 'MULTIPLE-VALUE-PROG1 args 1)
  (make-c1form* 'MULTIPLE-VALUE-PROG1 :args (c1expr (first args))
		(c1args* (rest args))))

(defun c2multiple-value-prog1 (form forms)
  (if (eq 'TRASH *destination*)
      ;; dont bother saving values
      (c2progn (cons form forms))
      (let ((nr (make-lcl-var :type :cl-index)))
	(let ((*destination* 'VALUES)) (c2expr* form))
	(wt-nl "{ cl_index " nr "=cl_stack_push_values();")
	(let ((*destination* 'TRASH)
	      (*unwind-exit* `((STACK ,nr) ,@*unwind-exit*)))
	  (dolist (form forms)
	    (c2expr* form)))
	(wt-nl "cl_stack_pop_values(" nr ");}")
	(unwind-exit 'VALUES))))

;;; Beppe:
;;; this is the WRONG way to handle 1 value problem.
;;; should be done in c2values, so that (values (truncate a b)) can
;;; be used to restrict to one value, so we would not have to warn
;;; if this occurred in a proclaimed fun.

(defun c1values (args)
  (make-c1form* 'VALUES :args (c1args* args)))

(defun c2values (forms)
  (when (and (eq *destination* 'RETURN-OBJECT)
             (rest forms)
             (consp *current-form*)
             (eq 'DEFUN (first *current-form*)))
    (cmpwarn "Trying to return multiple values. ~
              ~%;But ~a was proclaimed to have single value.~
              ~%;Only first one will be assured."
             (second *current-form*)))
  (cond
   ;; When the values are not going to be used, then just
   ;; process each form separately.
   ((eq *destination* 'TRASH)
    (mapc #'c2expr forms))
   ;; For (VALUES) we can replace the output with either NIL (if the value
   ;; is actually used) and set only NVALUES when the value is the output
   ;; of a function.
   ((endp forms)
    (cond ((eq *destination* 'RETURN)
	   (wt-nl "value0=Cnil; NVALUES=0;")
	   (unwind-exit 'RETURN))
	  ((eq *destination* 'VALUES)
	   (wt-nl "VALUES(0)=Cnil; NVALUES=0;")
	   (unwind-exit 'VALUES))
	  (t
	   (unwind-exit 'NIL))))
   ;; For a single form, we must simply ensure that we only take a single
   ;; value of those that the function may output.
   ((endp (rest forms))
    (let ((*destination* 'VALUE0))
      (c2expr* (first forms)))
    (unwind-exit 'VALUE0))
   ;; In all other cases, we store the values in the VALUES vector,
   ;; and force the compiler to retrieve anything out of it.
   (t
    (let* ((nv (length forms))
	   (*inline-blocks* 0)
	   (forms (nreverse (coerce-locs (inline-args forms)))))
      ;; By inlining arguments we make sure that VL has no call to funct.
      ;; Reverse args to avoid clobbering VALUES(0)
      (wt-nl "NVALUES=" nv ";")
      (do ((vl forms (rest vl))
	   (i (1- (length forms)) (1- i)))
	  ((null vl))
	(declare (fixnum i))
	(wt-nl "VALUES(" i ")=" (first vl) ";"))
      (unwind-exit 'VALUES)
      (close-inline-blocks)))))

(defun c1multiple-value-setq (args &aux (info (make-info)) (vrefs nil)
			      (vars nil) (temp-vars nil) (late-bindings nil))
  (check-args-number 'MULTIPLE-VALUE-SETQ args 2 2)
  (dolist (var (reverse (first args)))
          (cmpck (not (symbolp var)) "The variable ~s is not a symbol." var)
	  (setq var (chk-symbol-macrolet var))
	  (cond ((symbolp var)
		 (cmpck (constantp var)
			"The constant ~s is being assigned a value." var)
		 (push var vars))
		(t (let ((new-var (gensym)))
		     (push new-var vars)
		     (push new-var temp-vars)
		     (push `(setf ,var ,new-var) late-bindings)))))
  (if temp-vars
    (c1expr `(let* (,@temp-vars)
	      (multiple-value-setq ,vars ,@(second args))
	      ,@late-bindings))
    (let ((value (c1expr (second args))))
      (dolist (var vars
	       (make-c1form 'MULTIPLE-VALUE-SETQ info (nreverse vrefs) value))
	(setq var (c1vref var))
	(push var vrefs)
	#+nil
	(unless (subtypep 'T (var-type var))
	  (cmpwarn "Variable ~s appeared in a MULTIPLE-VALUE-SETQ and declared to have type ~S."
		   (var-name var)
		   (var-type var)))
	(push var (info-changed-vars info))))))

(defun c1form-values-number (form)
  (let ((type (c1form-type form)))
    (cond ((eq type 'T)
	   (values 0 MULTIPLE-VALUES-LIMIT))
	  ((or (atom type) (not (eq (first type) 'VALUES)))
	   (values 1 1))
	  ((or (member '&rest type) (member 'optional type))
	   (values 0 MULTIPLE-VALUES-LIMIT))
	  (t
	   (let ((l (1- (length type))))
	     (values l l))))))

(defun do-m-v-setq-fixed (nvalues vars form use-bind)
  (if (= nvalues 1)
      (let ((*destination* (first vars)))
	(c2expr* form))
      (let ((*destination* 'VALUES))
	(c2expr* form)
	(dotimes (i nvalues)
	  (set-var (list 'VALUE i) (pop vars)))))
  (dolist (v vars)
    (if use-bind
	(bind (c1form-arg 0 (default-init v)) v)
	(set-var '(C-INLINE :object "Cnil" () t nil) v))))

(defun do-m-v-setq-any (min-values max-values vars use-bind)
  (let* ((*lcl* *lcl*)
         (nr (make-lcl-var :type :int))
	 (output (first vars))
	 (labels '()))
    ;; We know that at least MIN-VALUES variables will get a value
    (dotimes (i min-values)
      (when vars
	(let ((v (pop vars))
	      (loc (values-loc i)))
	  (if use-bind (bind loc v) (set-var loc v)))))
    ;; If there are more variables, we have to check whether there
    ;; are enough values left in the stack.
    (when vars
      (wt-nl "{int " nr "=NVALUES-" min-values ";")
      ;;
      ;; Loop for assigning values to variables
      ;;
      (do ((vs vars (rest vs))
	   (i min-values (1+ i)))
	  ((or (endp vs) (= i max-values)))
	(declare (fixnum i))
	(let ((loc (values-loc i))
	      (v (first vs))
	      (label (next-label)))
	  (wt-nl "if (" nr "--<=0) ") (wt-go label)
	  (push label labels)
	  (if use-bind (bind loc v) (set-var loc v))))
      ;;
      ;; Loop for setting default values when there are less output than vars.
      ;;
      (let ((label (next-label)))
	(wt-nl) (wt-go label) (wt "}")
	(push label labels)
	(setq labels (nreverse labels))
	(dolist (v vars)
	  (when labels (wt-label (pop labels)))
	  (if use-bind
	      (bind '(C-INLINE :object "Cnil" () t nil) v)
	      (set-var '(C-INLINE :object "Cnil" () t nil) v)))
	(when labels (wt-label label))))
    output))

(defun c2multiple-value-setq (vars form)
  (multiple-value-bind (min-values max-values)
      (c1form-values-number form)
    (if (= min-values max-values)
	(do-m-v-setq-fixed min-values vars form nil)
	(progn
	  (let ((*destination* 'VALUES)) (c2expr* form))
	  (unwind-exit (do-m-v-setq-any min-values max-values vars nil))))))

(defun c1multiple-value-bind (args &aux (vars nil) (vnames nil) init-form
                                   ss is ts body other-decls
                                   (*vars* *vars*))
  (check-args-number 'MULTIPLE-VALUE-BIND args 2)

  (multiple-value-setq (body ss ts is other-decls) (c1body (cddr args) nil))

  (c1add-globals ss)

  (dolist (s (first args))
    (push s vnames)
    (push (c1make-var s ss is ts) vars))
  (setq init-form (c1expr (second args)))
  (dolist (v (setq vars (nreverse vars)))
    (push-vars v))
  (check-vdecl vnames ts is)
  (setq body (c1decl-body other-decls body))
  (dolist (var vars) (check-vref var))
  (make-c1form* 'MULTIPLE-VALUE-BIND :type (c1form-type body)
		:local-vars vars
		:args vars init-form body)
  )

(defun c2multiple-value-bind (vars init-form body)
  ;; 0) Compile the form which is going to give us the values
  (let ((*destination* 'VALUES)) (c2expr* init-form))

  (let* ((*unwind-exit* *unwind-exit*)
	 (*env-lvl* *env-lvl*)
	 (*env* *env*)
	 (*lcl* *lcl*)
	 (labels nil)
	 (env-grows nil)
	 (nr (make-lcl-var :type :int))
	 min-values max-values)
    ;; 1) Retrieve the number of output values
    (wt-nl "{")
    (multiple-value-setq (min-values max-values)
      (c1form-values-number init-form))

    ;; 2) For all variables which are not special and do not belong to
    ;;    a closure, make a local C variable.
    (dolist (var vars)
      (declare (type var var))
      (let ((kind (local var)))
	(if kind
	  (progn
	    (bind (next-lcl) var)
	    (wt-nl *volatile* (rep-type-name kind) " " var ";")
	    (wt-comment (var-name var)))
	  (unless env-grows (setq env-grows (var-ref-ccb var))))))

    ;; 3) If there are closure variables, set up an environment.
    (when (setq env-grows (env-grows env-grows))
      (let ((env-lvl *env-lvl*))
	(wt-nl "volatile cl_object env" (incf *env-lvl*)
	       " = env" env-lvl ";")))

    ;; 4) Assign the values to the variables
    (do-m-v-setq-any min-values max-values vars t)

    ;; 5) Compile the body. If there are bindings of special variables,
    ;;    these bindings are undone here.
    (c2expr body)

    ;; 6) Close the C expression.
    (wt "}"))
  )

;;; ----------------------------------------------------------------------

(put-sysprop 'multiple-value-call 'c1special #'c1multiple-value-call)
(put-sysprop 'multiple-value-call 'c2 #'c2multiple-value-call)
(put-sysprop 'multiple-value-prog1 'c1special #'c1multiple-value-prog1)
(put-sysprop 'multiple-value-prog1 'c2 #'c2multiple-value-prog1)
(put-sysprop 'values 'c1 #'c1values)
(put-sysprop 'values 'c2 #'c2values)
(put-sysprop 'multiple-value-setq 'c1 #'c1multiple-value-setq)
(put-sysprop 'multiple-value-setq 'c2 #'c2multiple-value-setq)
(put-sysprop 'multiple-value-bind 'c1 #'c1multiple-value-bind)
(put-sysprop 'multiple-value-bind 'c2 #'c2multiple-value-bind)
