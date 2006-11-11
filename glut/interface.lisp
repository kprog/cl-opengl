;;; -*- Mode: Lisp; indent-tabs-mode: nil -*-
;;;
;;; interface.lisp --- CLOS interface to the GLUT API.
;;;
;;; Copyright (c) 2006, Luis Oliveira <loliveira@common-lisp.net>
;;;   All rights reserved.
;;;
;;; Redistribution and use in source and binary forms, with or without
;;; modification, are permitted provided that the following conditions
;;; are met:
;;;
;;;  o Redistributions of source code must retain the above copyright
;;;    notice, this list of conditions and the following disclaimer.
;;;  o Redistributions in binary form must reproduce the above copyright
;;;    notice, this list of conditions and the following disclaimer in the
;;;    documentation and/or other materials provided with the distribution.
;;;  o Neither the name of the author nor the names of the contributors may
;;;    be used to endorse or promote products derived from this software
;;;    without specific prior written permission.
;;;
;;; THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
;;; "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
;;; LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
;;; A PARTICULAR PURPOSE ARE DISCLAIMED.  IN NO EVENT SHALL THE COPYRIGHT
;;; OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
;;; SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
;;; LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
;;; DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
;;; THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
;;; (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
;;; OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

(in-package #:cl-glut)

;;; This an experimental interface to GLUT. The main goal of this interface
;;; is to provide an easy, flexible way to explore OpenGL. GLUT is not very
;;; helpful in achieving this goal (even though Freeglut is much better than
;;; the original GLUT in this aspect).
;;;
;;; At the moment, not all of GLUT's capabilities are accessible when
;;; using this high-level interface *exclusively*. Patches and
;;; suggestions are most welcome!

(eval-when (:compile-toplevel :load-toplevel :execute)
  ;; FIXME: find good alternative names instead of shadowing these CL symbols
  (shadow '(cl:special cl:close)))

(export '(;; events / GFs
          timer idle keyboard special reshape visibility display mouse
          motion passive-motion entry menu-state spaceball-motion
          spaceball-rotate spaceball-button button-box dials tablet-motion
          tablet-button menu-status overlay-display window-status keyboard-up
          special-up joystick mouse-wheel close wm-close menu-destroy
          enable-event disable-event display-window
          ;; classes
          base-window window sub-window
          ;; accessors
          title name id events parent pos-x pos-y width height mode
          ;; other functions and macros
          display-window find-window with-window destroy-current-window
          ;; specials
          *run-main-loop-after-display*))

(defvar *id->window* (make-array 0 :adjustable t)
  "Mapping of GLUT window IDs to instances of the BASE-WINDOW class.")

(defvar *windows-with-idle-event* '())

;;;; Events

;;; One callback is defined for each GLUT event. Enabling an event for
;;; a given window means registering the respective shared callback
;;; for its window id (using the *-func GLUT functions).
;;;
;;; There is one generic function for each event which is called by
;;; the shared callback to dispatch to the correct method based on the
;;; window (and possibly the other arguments).
;;;
;;; Ugh, some of these event are not implemented by Freeglut, which
;;; is what we care about... Better remove them?
;;;
;;; TODO: the TIMER event is not related to a GLUT window and therefore
;;;       doesn't fit this pattern. Implement it in some other way.
;;;
;;; TODO: The JOYSTICK event has parameters, meaning a way to accept
;;;       parameters eg: (:joystick n m) when enabling an event is
;;;       necessary.

(defparameter *events* '())

(defstruct event name gf cb func arg-count)

(defun find-event-or-lose (event-name)
  (or (find event-name *events* :key #'event-name)
      (error "No such event: ~A" event-name)))

(defgeneric enable-event (window event-name))
(defgeneric disable-event (window event-name))

(defmacro when-current-window-exists (&body body)
  "Evals BODY when GLUT's current window exists in *ID->WINDOW*.
Lexically binds CURRENT-WINDOW to the respective object."
  (let ((id (gensym)))
    `(let ((,id (get-window)))
       (when (> (length *id->window*) ,id)
         (let ((current-window (aref *id->window* ,id)))
           (unless (null current-window)
             ;;(format t "glut callback: ~A -> ~A~%" ,id current-window)
             ,@body))))))

(defctype ascii-to-char :unsigned-char)

(defmethod expand-from-foreign (value (type (eql 'ascii-to-char)))
  `(code-char ,value))

;;; The first element in ARGS is a dummy name for the first argument
;;; in the event's generic function, the window.
(defmacro define-glut-event (name args &body callback-body)
  (let ((arg-names (mapcar #'car (cdr args)))
        (event-cb (gl::symbolicate "%" name))
        (event-func (gl::symbolicate name '#:-func))
        (event-name (intern (symbol-name name) '#:keyword)))
    `(progn
       (defgeneric ,name (,(car args) ,@arg-names))
       (defcallback ,event-cb :void ,(cdr args)
         ,@callback-body)
       ;; When we put #'foo-func instead of 'foo-func in the
       ;; FUNC slot weird stuff happens. No idea why.
       (push (make-event :name ,event-name :gf #',name :cb ',event-cb
                         :func ',event-func :arg-count ,(length args))
             *events*))))

(defmacro define-glut-events (&body event-specs)
  `(progn
     (setq *events* '())
     ,@(loop for (name args) in event-specs collect
             `(define-glut-event ,name ,args
                (when-current-window-exists
                 (,name current-window ,@(mapcar #'car (cdr args))))))))

(define-glut-events
  ;; (idle             (window))
  (keyboard         (window (key ascii-to-char) (x :int) (y :int)))
  (special          (window (special-key special-keys) (x :int) (y :int)))
  (reshape          (window (width :int) (height :int)))
  (visibility       (window (state visibility-state)))
  (display          (window))
  (mouse            (window (button mouse-button) (state mouse-button-state)
                            (x :int) (y :int)))
  (motion           (window (x :int) (y :int)))
  (passive-motion   (window (x :int) (y :int)))
  (entry            (window (state entry-state)))
  (menu-state       (window (state menu-state)))
  (spaceball-motion (window (x :int) (y :int) (z :int)))
  (spaceball-rotate (window (x :int) (y :int) (z :int)))
  (spaceball-button (window (button :int) (state :int)))
  (button-box       (window (button :int) (state :int)))
  (dials            (window (dial :int) (value :int)))
  (tablet-motion    (window (x :int) (y :int)))
  (tablet-button    (window (button :int) (state :int) (x :int) (y :int)))
  (menu-status      (window (status menu-state) (x :int) (y :int)))
  (overlay-display  (window))
  (window-status    (window (state window-status)))
  (keyboard-up      (window (key ascii-to-char) (x :int) (y :int)))
  (special-up       (window (special-key special-keys) (x :int) (y :int)))
  ;; (joystick         (window (buttons joystick-buttons) (x :int) (y :int)
  ;;                           (z :int)))
  (mouse-wheel      (window (button mouse-button) (pressed mouse-button-state)
                            (x :int) (y :int)))
  (close            (window))
  ;; (wm-close         (window)) ; synonym for CLOSE
  (menu-destroy     (window)))

;;; These two functions should not be called directly and are called
;;; by ENABLE-EVENT and DISABLE-EVENT. See below.

(defun register-callback (event) 
  (funcall (event-func event) (get-callback (event-cb event))))

(defun unregister-callback (event) 
  (funcall (event-func event) (null-pointer)))

;;;; Windows

;;; The WINDOW (top-level windows) and SUB-WINDOW (those pseudo-windows
;;; that live inside top-level windows and have their own GL context)
;;; classes inherit BASE-WINDOW.
;;;
;;; See DISPLAY-WINDOW's documentation.

(defparameter +default-title+
  (concatenate 'string (lisp-implementation-type) " "
               (lisp-implementation-version)))

(defvar *run-main-loop-after-display* t
  "This special variable controls whether the DISPLAY-WINDOW
  method specialized on GLUT:WINDOW will call GLUT:MAIN-LOOP.")

(defclass base-window ()
  ((name :reader name :initarg :name :initform (gensym "GLUT-WINDOW"))
   (id   :reader id)
   (pos-x  :accessor pos-x  :initarg :pos-x  :initform -1)
   (pos-y  :accessor pos-y  :initarg :pos-y  :initform -1)
   (height :accessor height :initarg :height :initform 300)
   (width  :accessor width  :initarg :width  :initform 300)
   (title  :accessor title  :initarg :title  :initform +default-title+)
   ;; When this slot unbound, DISPLAY-WINDOW calls
   ;; FIND-APPLICABLE-EVENTS to populate it.
   (events :accessor events :initarg :events)))

(defgeneric display-window (window)
  (:documentation
   "Creates the underlying GLUT window structures and displays
   WINDOW. The creation takes place in :AROUND methods so the
   user can define :before methods on DISPLAY-WINDOW and do
   OpenGL stuff with it, for example."))

(defun find-window (name)
  (loop for window across *id->window*
        when (and (not (null window)) (eq (name window) name))
        do (return window)))

(defmacro with-window (window &body body)
  (let ((current-id (gensym)))
    `(let ((,current-id (get-window)))
       (unwind-protect
            (progn
              (set-window (id ,window))
              ,@body)
         (set-window ,current-id)))))

;;; We do some extra stuff to provide an IDLE event per-window since
;;; GLUT's IDLE event is global.
(define-glut-event idle (window)
  (loop for win in *windows-with-idle-event*
        do (with-window win
             (idle win))))

(defun find-applicable-events (window)
  (loop for event in *events*
        when (compute-applicable-methods
              (event-gf event)
              (cons window (loop repeat (event-arg-count event) collect t)))
        collect event))

(defmethod display-window :around ((win base-window))
  (unless (slot-boundp win 'events)
    (setf (events win) (find-applicable-events win)))
  (with-window win
    (glut:position-window (pos-x win) (pos-y win))
    (glut:reshape-window (width win) (height win))
    (glut:set-window-title (title win))
    (dolist (event (events win))
      (register-callback event)))
  (when (member :idle (events win) :key #'event-name)
    (push win *windows-with-idle-event*))
  ;; save window in the *id->window* array
  (when (<= (length *id->window*) (id win))
    (setq *id->window*
          (adjust-array *id->window* (1+ (id win)) :initial-element nil)))
  (setf (aref *id->window* (id win)) win)
  (call-next-method))

(defmethod display-window ((win base-window))
  (values))

(defmethod enable-event ((window base-window) event-name)
  (let ((event (find-event-or-lose event-name))) 
    (with-window window
      (register-callback event))
    (pushnew event (events window))
    (when (eq event-name :idle)
      (push window *windows-with-idle-event*))))

(defmethod disable-event ((window base-window) event-name)
  (if (eq event-name :display)
      (warn "GLUT would be upset if we set the DISPLAY callback to NULL. ~
             So we won't do that.")
      (let ((event (find-event-or-lose event-name))) 
        ;; We don't actually disable the CLOSE event since we need it
        ;; for bookkeeping. See the CLOSE methods below.
        (unless (or (eq event-name :idle) (eq event-name :close))
          (with-window window
            (unregister-callback event)))
        (setf (events window) (delete event (events window)))
        (when (eq event-name :idle)
          (setq *windows-with-idle-event*
                (delete window *windows-with-idle-event*))))))

(defun destroy-current-window ()
  (destroy-window (get-window)))

(defmethod close :around ((w base-window))
  (when (member :close (events w) :key #'event-name)
    (call-next-method))
  (setf (aref *id->window* (id w)) nil)
  (setq *windows-with-idle-event* (delete w *windows-with-idle-event*))
  (when (null *windows-with-idle-event*)
    (unregister-callback (find-event-or-lose :idle))))

(defmethod close ((w base-window))
  (values))

;;;; Top-level Windows

(defclass window (base-window)
  ((sub-windows :accessor sub-windows :initform nil)
   ;; Can sub-windows have a different display mode?
   (mode :initarg :mode :initform nil)))

(defmethod (setf title) :before (string (win window))
  (when (slot-boundp win 'id)
    (with-window win
      (set-window-title string))))

(defmethod display-window :around ((win window))
  (apply #'init-display-mode (slot-value win 'mode))
  (setf (slot-value win 'id) (create-window (title win)))
  (call-next-method)
  (when *run-main-loop-after-display*
    (glut:main-loop)))

;;;; Sub-windows

(defclass sub-window (base-window)
  ((parent :reader parent
           :initform (error "Must specify a PARENT window."))))

(defmethod initialize-instance :after ((win sub-window) &key parent
                                       &allow-other-keys)
  (let ((parent-window (typecase parent
                         (window parent)
                         (symbol (find-window parent)))))
    (check-type parent-window window)
    (setf (slot-value win 'parent) parent-window)
    (push win (sub-windows parent-window))))

(defmethod display-window :around ((win sub-window))
  (setf (slot-value win 'id) (create-sub-window (id (parent win)) 0 0 0 0))
  (call-next-method))

;;; For posterity:
;;;
;;; "This is quite ugly: OS X is very picky about which thread gets to handle
;;; events and only allows the main thread to do so. We need to run any event
;;; loops in the initial thread on multithreaded Lisps, or in this case,
;;; OpenMCL."

;; #-openmcl
;; (defun run-event-loop ()
;;   (glut:main-loop))

;; #+openmcl
;; (defun run-event-loop ()
;;   (flet ((start ()
;;            (ccl:%set-toplevel nil)
;;            (glut:main-loop)))
;;     (ccl:process-interrupt ccl::*initial-process*
;;                            (lambda ()
;;                              (ccl:%set-toplevel #'start)
;;                              (ccl:toplevel)))))