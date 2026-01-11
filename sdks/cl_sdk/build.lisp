;;;; build.lisp
;;;;
;;;; Build script for SW4RM Orchestrator standalone executable
;;;;
;;;; Usage:
;;;;   sbcl --load build.lisp
;;;;
;;;; This will:
;;;;   1. Load Quicklisp
;;;;   2. Load the sw4rm-orchestrator system
;;;;   3. Build a standalone executable
;;;;   4. Exit
;;;;
;;;; The resulting executable will be named 'sw4rm-orchestrator'
;;;; and can be run directly without SBCL.

(format t "~%=== SW4RM Orchestrator Build Script ===~%~%")

;; Load Quicklisp
(format t "Loading Quicklisp...~%")
#+quicklisp
(progn
  (format t "Quicklisp already loaded~%"))
#-quicklisp
(let ((quicklisp-init (merge-pathnames "quicklisp/setup.lisp"
                                       (user-homedir-pathname))))
  (if (probe-file quicklisp-init)
      (load quicklisp-init)
      (error "Quicklisp not found. Please install Quicklisp first.")))

;; Load the system
(format t "~%Loading sw4rm-orchestrator system...~%")
(ql:quickload :sw4rm-orchestrator :silent nil)

;; Build the executable
(format t "~%Building standalone executable...~%")
(in-package :sw4rm-orchestrator)

#+sbcl
(progn
  (format t "Building for SBCL...~%")
  (sb-ext:save-lisp-and-die "sw4rm-orchestrator"
                            :toplevel #'main
                            :executable t
                            :compression t
                            :save-runtime-options t
                            :purify t))

#+ccl
(progn
  (format t "Building for CCL...~%")
  (ccl:save-application "sw4rm-orchestrator"
                        :toplevel-function #'main
                        :prepend-kernel t))

#-(or sbcl ccl)
(error "Building standalone executables is only supported on SBCL and CCL")

;; If we reach here, something went wrong
(format t "~%Build failed - executable was not created~%")
(uiop:quit 1)

;;;; End of build script
