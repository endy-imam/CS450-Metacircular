;;; file: s450.scm
;;;
;;; Metacircular evaluator from chapter 4 of STRUCTURE AND
;;; INTERPRETATION OF COMPUTER PROGRAMS (2nd edition)
;;;
;;; Modified by kwn, 3/4/97
;;; Modified and commented by Carl Offner, 10/21/98 -- 10/12/04
;;;
;;; This code is the code for the metacircular evaluator as it appears
;;; in the textbook in sections 4.1.1-4.1.4, with the following
;;; changes:
;;;
;;; 1.  It uses #f and #t, not false and true, to be Scheme-conformant.
;;;
;;; 2.  Some function names were changed to avoid conflict with the
;;; underlying Scheme:
;;;
;;;       eval => xeval
;;;       apply => xapply
;;;       extend-environment => xtend-environment
;;;
;;; 3.  The driver-loop is called s450.
;;;
;;; 4.  The booleans (#t and #f) are classified as self-evaluating.
;;;
;;; 5.  These modifications make it look more like UMB Scheme:
;;;
;;;        The define special form evaluates to (i.e., "returns") the
;;;          variable being defined.
;;;        No prefix is printed before an output value.
;;;
;;; 6.  I changed "compound-procedure" to "user-defined-procedure".
;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;;	 xeval and xapply -- the kernel of the metacircular evaluator
;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define (xeval exp env)
  ; lookup action for special form checks
  (let ((action (lookup-action (type-of exp))))
    ; sift through the xeval
    (cond ((self-evaluating? exp) exp)
          ((variable? exp) (lookup-variable-value exp env))
          ; where the special-form lookups takes place
          ; if action exists, invoke it
          (action (action exp env))
          ((application? exp)
           (xapply (xeval (operator exp) env)
                   (list-of-values (operands exp) env) ))
          (else
           (error "Unknown expression type -- XEVAL " exp) ))))

(define (xapply procedure arguments)
  (cond ((primitive-procedure? procedure)
         (apply-primitive-procedure procedure arguments))
        ((user-defined-procedure? procedure)
         (eval-sequence
           (procedure-body procedure)
           (xtend-environment
             (procedure-parameters procedure)
             arguments
             (procedure-environment procedure))))
        (else
         (error
          "Unknown procedure type -- XAPPLY " procedure))))

;;; Handling procedure arguments

(define (list-of-values exps env)
  (if (no-operands? exps)
      '()
      (cons (xeval (first-operand exps) env)
            (list-of-values (rest-operands exps) env) )))

;;; These functions, called from xeval, do the work of evaluating some
;;; of the special forms:

(define (eval-if exp env)
  (if (true? (xeval (if-predicate exp) env))
      (xeval (if-consequent exp) env)
      (xeval (if-alternative exp) env) ))

(define (eval-sequence exps env)
  (cond ((last-exp? exps) (xeval (first-exp exps) env))
        (else (xeval (first-exp exps) env)
              (eval-sequence (rest-exps exps) env) )))

(define (eval-assignment exp env)
  (let ((name (assignment-variable exp)))
    (set-variable-value! name
			 (xeval (assignment-value exp) env)
			 env)
  name) )    ;; A & S return 'ok

(define (eval-definition exp env)
  (let ((name (definition-variable exp)))  
    (define-variable! name
      (xeval (definition-value exp) env)
      env)
  name) )     ;; A & S return 'ok

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;;	 Representing expressions
;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;; Numbers, strings, and booleans are all represented as themselves.
;;; (Not characters though; they don't seem to work out as well
;;; because of an interaction with read and display.)

(define (self-evaluating? exp)
  (or (number? exp)
      (string? exp)
      (boolean? exp) ))

;;; variables -- represented as symbols

(define (variable? exp) (symbol? exp))

;;; quote -- represented as (quote <text-of-quotation>)

(define (quoted? exp)
  (tagged-list? exp 'quote) )

(define (text-of-quotation exp) (cadr exp))

(define (tagged-list? exp tag)
  (if (pair? exp)
      (eq? (car exp) tag)
      #f) )

;;; assignment -- represented as (set! <var> <value>)

(define (assignment? exp) 
  (tagged-list? exp 'set!) )

(define (assignment-variable exp) (cadr exp))

(define (assignment-value exp) (caddr exp))

;;; definitions -- represented as
;;;    (define <var> <value>)
;;;  or
;;;    (define (<var> <parameter_1> <parameter_2> ... <parameter_n>) <body>)
;;;
;;; The second form is immediately turned into the equivalent lambda
;;; expression.

(define (definition? exp)
  (tagged-list? exp 'define) )

(define (definition-variable exp)
  (if (symbol? (cadr exp))
      (cadr exp)
      (caadr exp) ))

(define (definition-value exp)
  (if (symbol? (cadr exp))
      (caddr exp)
      (make-lambda (cdadr exp)
                   (cddr exp) )))

;;; lambda expressions -- represented as (lambda ...)
;;;
;;; That is, any list starting with lambda.  The list must have at
;;; least one other element, or an error will be generated.

(define (lambda? exp) (tagged-list? exp 'lambda))

(define (lambda-parameters exp) (cadr exp))
(define (lambda-body exp) (cddr exp))

(define (make-lambda parameters body)
  (cons 'lambda (cons parameters body)) )

;;; conditionals -- (if <predicate> <consequent> <alternative>?)

(define (if? exp) (tagged-list? exp 'if))

(define (if-predicate exp) (cadr exp))

(define (if-consequent exp) (caddr exp))

(define (if-alternative exp)
  (if (not (null? (cdddr exp)))
      (cadddr exp)
      #f) )

(define (make-if predicate consequent alternative)
  (list 'if predicate consequent alternative) )


;;; sequences -- (begin <list of expressions>)

(define (begin? exp) (tagged-list? exp 'begin))

(define (begin-actions exp) (cdr exp))

(define (last-exp? seq) (null? (cdr seq)))
(define (first-exp seq) (car seq))
(define (rest-exps seq) (cdr seq))

(define (sequence->exp seq)
  (cond ((null? seq) seq)
        ((last-exp? seq) (first-exp seq))
        (else (make-begin seq)) ))

(define (make-begin seq) (cons 'begin seq))


;;; procedure applications -- any compound expression that is not one
;;; of the above expression types.

(define (application? exp) (pair? exp))
(define (operator exp) (car exp))
(define (operands exp) (cdr exp))

(define (no-operands? ops) (null? ops))
(define (first-operand ops) (car ops))
(define (rest-operands ops) (cdr ops))


;;; Derived expressions -- the only one we include initially is cond,
;;; which is a special form that is syntactically transformed into a
;;; nest of if expressions.

(define (cond? exp) (tagged-list? exp 'cond))

(define (cond-clauses exp) (cdr exp))

(define (cond-else-clause? clause)
  (eq? (cond-predicate clause) 'else) )

(define (cond-predicate clause) (car clause))

(define (cond-actions clause) (cdr clause))

(define (cond->if exp)
  (expand-clauses (cond-clauses exp)) )

(define (expand-clauses clauses)
  (if (null? clauses)
      #f                          ; no else clause -- return #f
      (let ((first (car clauses))
            (rest (cdr clauses)) )
        (if (cond-else-clause? first)
            (if (null? rest)
                (sequence->exp (cond-actions first))
                (error "ELSE clause isn't last -- COND->IF "
                       clauses) )
            (make-if (cond-predicate first)
                     (sequence->exp (cond-actions first))
                     (expand-clauses rest) )))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;;	 Truth values and procedure objects
;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;; Truth values

(define (true? x)
  (not (eq? x #f)) )

(define (false? x)
  (eq? x #f) )


;;; Procedures

(define (make-procedure parameters body env)
  (list 'procedure parameters body env) )

(define (user-defined-procedure? p)
  (tagged-list? p 'procedure) )


(define (procedure-parameters p) (cadr p))
(define (procedure-body p) (caddr p))
(define (procedure-environment p) (cadddr p))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;;  File Load (from load.s450)
;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define eval-load
  (lambda (exp env)
    (define (filename exp) (cadr exp))
    (define thunk (lambda ()
        (readfile)
        ))
    (define readfile (lambda()
           (let ((item (read)))
       (if (not (eof-object? item))
           (begin
             (xeval item env)
             (readfile))))
           ))
    (with-input-from-file (filename exp) thunk)
    (filename exp)      ; return the name of the file - why not?
    ))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;;  Action Lookup Table / Callbacks
;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;; Lookup-Action

(define (lookup-action type)
  (let ((record (assoc type (cdr action-table))))
    (if record
        (cdr record)
        #f) ))

; type-of λexp: output symbol of type given expression
(define (type-of exp)
  (if (pair? exp)
      (car exp)
      #f))


;;; Callbacks for Certain Special Forms
; quote -> quote-callback
(define (quote-callback exp env)
  (text-of-quotation exp) )
; lambda -> lambda-callback
(define (lambda-callback exp env)
  (make-procedure (lambda-parameters exp) (lambda-body exp) env) )
; begin -> begin-callback
(define (begin-callback exp env)
  (eval-sequence (begin-actions exp) env) )
; cond -> cond-callback
(define (cond-callback exp env)
  (xeval (cond->if exp) env))


;;; Actual Action Table
(define action-table
  (list '*table*
        (cons 'quote  quote-callback)
        (cons 'set!   eval-assignment)
        (cons 'define eval-definition)
        (cons 'if     eval-if)
        (cons 'lambda lambda-callback)
        (cons 'begin  begin-callback)
        (cons 'cond   cond-callback) ))


;;; Install New Special Forms
(define (install-special-form name action)
  (cond ((not (symbol? name)) (error "Not a symbol: " name))
        ((not (procedure? action)) (error "Not a lambda: " action))
        ((lookup-action name) (error "Action already exists: " name))
        (else (set! action-table
                    (cons '*table*
                          (cons (cons name action)
                                (cdr action-table) )))
              name) ))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;;	 Representing environments
;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;; An environment is a list of frames.

(define (enclosing-environment env) (cdr env))

(define (first-frame env) (car env))

(define the-empty-environment '())

;;; Each frame is represented as a pair of lists:
;;;   1.  a list of the variables bound in that frame, and
;;;   2.  a list of the associated values.

(define (make-frame variables values)
  (cons variables values))

(define (frame-variables frame) (car frame))
(define (frame-values frame) (cdr frame))

(define (add-binding-to-frame! var val frame)
  (set-car! frame (cons var (car frame)))
  (set-cdr! frame (cons val (cdr frame))) )

;;; Extending an environment

(define (xtend-environment vars vals base-env)
  (if (= (length vars) (length vals))
      (cons (make-frame vars vals) base-env)
      (if (< (length vars) (length vals))
          (error "Too many arguments supplied " vars vals)
          (error "Too few arguments supplied " vars vals) )))

;;; Looking up a variable in an environment

(define (lookup-variable-value var env)
  (define (env-loop env)
    (define (scan vars vals)
      (cond ((null? vars)
             (env-loop (enclosing-environment env)) )
            ((eq? var (car vars))
             (car vals))
            (else (scan (cdr vars) (cdr vals))) ))
    (if (eq? env the-empty-environment)
        (error "Unbound variable " var)
        (let ((frame (first-frame env)))
          (scan (frame-variables frame)
                (frame-values frame) ))))
  ; check if var is special form or not to prevent crash
  (if (lookup-action var)
      (begin (display "Special Form:  ") var)
      (env-loop env) ))

;;; Setting a variable to a new value in a specified environment.
;;; Note that it is an error if the variable is not already present
;;; (i.e., previously defined) in that environment.

(define (set-variable-value! var val env)
  (define (env-loop env)
    (define (scan vars vals)
      (cond ((null? vars)
             (env-loop (enclosing-environment env)) )
            ((eq? var (car vars))
             (set-car! vals val))
            (else (scan (cdr vars) (cdr vals))) ))
    (if (eq? env the-empty-environment)
        (error "Unbound variable -- SET! " var)
        (let ((frame (first-frame env)))
          (scan (frame-variables frame)
                (frame-values frame) ))))
  ; check if var is special form or not to prevent crash
  (if (lookup-action var)
      (error "Variable is Special-Form Not Allowed -- SET! " var)
      (env-loop env) ))

;;; Defining a (possibly new) variable.  First see if the variable
;;; already exists.  If it does, just change its value to the new
;;; value.  If it does not, define the new variable in the current
;;; frame.

(define (define-variable! var val env)
  (let ((frame (first-frame env)))
    (define (scan vars vals)
      (cond ((null? vars)
             (add-binding-to-frame! var val frame) )
            ((eq? var (car vars))
             (set-car! vals val) )
            (else (scan (cdr vars) (cdr vals))) ))
    ; check if var is special form or not to prevent crash
    (if (lookup-action var)
        (error "Variable is Special-Form Not Allowed -- DEFINE " var)
        (scan (frame-variables frame)
              (frame-values frame) ))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;;	 Value Accessors
;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; defined? λsymbol: check if symbol is defined in enviornment
; -> def?-callback λexp λenv: s450 interface
(define (def?-callback exp env)
  ; sift through the var-list and environments
  (define (def-check var-list curr-var base-env)
    (cond ; if reached the-empty-environment, return false
          ((and (null? var-list) (null? base-env)) #f)
          ; if all var checked in current frame, go down one environment
          ((null? var-list)
            (def-check (car (first-frame base-env))
                       curr-var
                       (enclosing-environment base-env) ))
          ; still var in var-list, check if current entry is true, return true
          ((eq? (car var-list) curr-var) #t)
          ; not same, go down one entry in list
          (else (def-check (cdr var-list) curr-var base-env)) ))
  ; main procedure
  (if (null? (cdr exp))
      (error "No arguments exists! -- DEFINED?")
      (def-check '() (cadr exp) env) ))

; locally-defined? λsymbol: check if symbol is defined in current frame
; -> frame-def?-callback λexp λenv: s450 interface
(define (frame-def?-callback exp env)
  ; sift through the var-list and environments
  (define (def-check var-list curr-var)
    (cond ; if all var checked in current frame, return false
          ((null? var-list) #f)
          ; still var in var-list, check if current entry is true, return true
          ((eq? (car var-list) curr-var) #t)
          ; not same, go down one entry in list
          (else (def-check (cdr var-list) curr-var)) ))
  ; main procedure
  (if (null? (cdr exp))
      (error "No arguments exists! -- LOCALLY-DEFINED?")
      (def-check (car (first-frame env)) (cadr exp)) ))

; make-unbound! λsymbol: remove symbol binding from current chain of frame
; -> unb!-callback λexp λenv: s450 interface
(define (unb!-callback exp env)
  ; sift through the table and environments
  (define (unb! curr-env val)
    (cond ((null? curr-env) val)
          (else (set-car! curr-env (delete-in-frame! (car curr-env) val))
                (unb! (cdr curr-env) val) )))
  ; main procedure
  (cond ((null? (cdr exp))
          (error "No arguments exists! -- MAKE-UNBOUND!"))
        ((assoc (cadr exp) prim-table)
          (error "Forbids Primitives -- MAKE-UNBOUND!"))
        (else (unb! env (cadr exp))) ))

; locally-make-unbound! λsymbol: remove symbol binding from current frame
; -> frame-unb!-callback λexp λenv: s450 interface
(define (frame-unb!-callback exp env)
  (cond ((null? (cdr exp))
          (error "No arguments exists! -- LOCALLY-MAKE-UNBOUND!"))
        ((assoc (cadr exp) prim-table)
          (error "Forbids Primitives -- LOCALLY-MAKE-UNBOUND!"))
        (else (set-car! env (delete-in-frame! (car env) (cadr exp)))) ))


; helper procedures
(define (delete-in-frame! frame var)
  ; re-frame-iter
  (define (re-frame-iter! in-var in-val out-var out-val)
    (cond ((null? in-var) (cons out-var out-val))
          ((equal? (car in-var) var)
            (cons (append out-var (cdr in-var))
                  (append out-val (cdr in-val)) ))
          (else (re-frame-iter! (cdr in-var) (cdr in-val)
                                (append out-var (list (car in-var)))
                                (append out-val (list (car in-val))) ))))
  ; main procedure
  (re-frame-iter! (car frame) (cdr frame) '() '()) )


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;;	 The initial environment
;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;; This is initialization code that is executed once, when the the
;;; interpreter is invoked.

(define (setup-environment)
  (let ((initial-env
         (xtend-environment (prim-names)
                            (prim-obj)
                            the-empty-environment) ))
    initial-env) )

;;; Define the primitive procedures

(define (primitive-procedure? proc)
  (tagged-list? proc 'primitive) )

(define (primitive-implementation proc) (cadr proc))

; prim-table for evaluating in scheme-base level (primitive-procedures)
;   install-primitive-procedure allows expansions
(define prim-table
  (list (list 'car car)
        (list 'cdr cdr)
        (list 'cons cons)
        (list 'null? null?) ))

; prim-names (primitive-procedure-names)
(define (prim-names) (map car prim-table))
; prim-obj (primitive-procedure-objects)
(define (prim-obj) (map (lambda (proc) (list 'primitive (cadr proc)))
                        prim-table) )

;;; Here is where we rely on the underlying Scheme implementation to
;;; know how to apply a primitive procedure.

(define (apply-primitive-procedure proc args)
  (apply (primitive-implementation proc) args) )

;;; Here is where to install new primitive procedures

(define (install-primitive-procedure name action)
  (cond ; name must be a symbol
        ((not (symbol? name))
          (error "Not a symbol: " name))
        ; action must be a lambda / procedure
        ((not (procedure? action))
          (error "Not a lambda: " action))
        ; action shouldn't already exists in list
        ((assoc name prim-table)
          (error "Action already exists: " name))
        ; if everything checks out, add to the list and output name
        (else (set! prim-table (cons (list name action) prim-table))
              ; reset the global environment
              (set! the-global-environment (setup-environment))
              name) ))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;;	 The main driver loop
;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;; Note that (read) returns an internal representation of the next
;;; Scheme expression from the input stream.  It does NOT evaluate
;;; what is typed in -- it just parses it and returns an internal
;;; representation.  It is the job of the scheme evaluator to perform
;;; the evaluation.  In this case, our evaluator is called xeval.

(define input-prompt "s450==> ")

(define (s450)
  (prompt-for-input input-prompt)
  (let ((input (read)))
    (let ((output (xeval input the-global-environment)))
      (user-print output) ))
  (s450) )

(define (prompt-for-input string)
  (newline) (newline) (display string) )

;;; Note that we would not want to try to print a representation of the
;;; <procedure-env> below -- this would in general get us into an
;;; infinite loop.

(define (user-print object)
  (if (user-defined-procedure? object)
      (display (list 'user-defined-procedure
                     (procedure-parameters object)
                     (procedure-body object)
                     '<procedure-env>) )
      (display object) ))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;;	 Here we go:  define the global environment and invite the
;;;        user to run the evaluator.
;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


(define the-global-environment (setup-environment))

(display "... loaded the metacircular evaluator. (s450) runs it.")
(newline)


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;;	 Pre-Evaluation for Preprocessing
;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;; Install Special Forms
(install-special-form 'load eval-load)

;;; Install Primitive Procedures
(install-primitive-procedure '+ +)
(install-primitive-procedure '- -)
(install-primitive-procedure '* *)
(install-primitive-procedure '/ /)

(install-primitive-procedure 'newline newline)
(install-primitive-procedure 'display display)

;;; Install Local Access
(install-special-form 'defined?                    def?-callback)
(install-special-form 'locally-defined?      frame-def?-callback)
(install-special-form 'make-unbound!               unb!-callback)
(install-special-form 'locally-make-unbound! frame-unb!-callback)
