;;; ob-scala-cli.el --- org-babel for scala evaluation in Scala-Cli.

;; Author: Andrea <andrea-dev@hotmail.com>
;; URL: https://github.com/ag91/scala-cli-repl
;; Package-Requires: ((s "1.12.0") (scala-cli-term-repl "0.0") (xterm-color "1.7"))
;; Version: 0.0
;; Keywords: tools, scala-cli, org-mode, scala, org-babel

;;; License:

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 3, or (at your option)
;; any later version.
;;
;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to the
;; Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
;; Boston, MA 02110-1301, USA.


;;; Commentary:
;; org-babel for scala evaluation in `scala-cli-repl'.

;; Note: if you use :scala-version as a block param, remember to set
;; it only on the initial block otherwise it causes a reload of the
;; REPL (losing any previous state)

;;; Code:
(require 'ob)
(require 'ob-comint)
(require 'scala-cli-repl)
(require 's)
(require 'xterm-color)

(add-to-list 'org-babel-tangle-lang-exts '("scala" . "scala"))
(add-to-list 'org-src-lang-modes '("scala" . scala))

(defcustom ob-scala-cli-prompt-str "scala>"
  "Regex for scala-cli prompt."
  :type 'string
  :group 'org-babel)

(defvar ob-scala-cli-debug-p nil
  "The variable to control the debug message.")

(defvar ob-scala-cli-eval-result ""
  "The result of the evaluation.")

(defvar ob-scala-cli-eval-needle ";;;;;;;;;"
  "The mark to tell whether the evaluation is done.")

(defvar ob-scala-cli-supported-params '(:scala-version :dep)
  "The ob blocks headers supported by this ob-scala-cli.")

(defun ob-scala-cli-expand-body (body)
  "Expand the BODY to evaluate."
  (format "{\n %s\n%s\n}" body ob-scala-cli-eval-needle))

(defun ob-scala-cli--trim-result (str)
  "Trim the result string.
Argument STR the result evaluated."
  (with-temp-buffer
    (insert (s-trim
             (s-chop-suffix
              ob-scala-cli-prompt-str
              (s-chop-prefix
               "}"
               (s-trim
                (s-join "" (cdr (s-split ob-scala-cli-eval-needle str))))))))
    (delete-trailing-whitespace)
    (buffer-string)))

(defun ob-scala-cli-params (params)
  "Extract scala-cli command line parameters from PARAMS.

>> (ob-scala-cli-params '((:tangle . no) (:scala-version . 3.0.0)))
=> (\"--scala-version\" \"3.0.0\")"
  (flatten-list
   (mapcar
    (lambda (param)
      (when-let ((value (alist-get
                         param
                         params))
                 (p (s-replace ":" "--" (symbol-name param)) ; NOTE: this means we want `ob-scala-cli-params' to match scala-cli command line params
                    ))
        (if (listp value)
            (mapcar (lambda (d) (list p d)) value)
          (list
           p
           (symbol-name value)))))
    ob-scala-cli-supported-params)))

(defun org-babel-execute:scala (body params)
  "Execute the scala code in BODY using PARAMS in org-babel.
This function is called by `org-babel-execute-src-block'
Argument BODY the body to evaluate.
Argument PARAMS the header arguments."
  (let ((scala-cli-params (ob-scala-cli-params params)))
    (unless (or (comint-check-proc scala-cli-repl-buffer-name) (not scala-cli-params))
      (ignore-errors
        (kill-buffer scala-cli-repl-buffer-name))
      (save-window-excursion
        (let ((scala-cli-repl-program-args scala-cli-params))
          (scala-cli-repl)))
      (while (not (and (get-buffer scala-cli-repl-buffer-name)
                       (with-current-buffer scala-cli-repl-buffer-name
                         (save-excursion
                           (goto-char (point-min))
                           (search-forward ob-scala-cli-prompt-str nil t)))))
        (message "Waiting for scala-cli to start...")
        (sit-for 0.5))))

  (setq ob-scala-cli-eval-result "")

  (set-process-filter
   (get-buffer-process scala-cli-repl-buffer-name)
   (lambda (process str)
     (term-emulate-terminal process str)
     (let ((str (s-replace "" "" (substring-no-properties (xterm-color-filter str)))))
       (when ob-scala-cli-debug-p (print str))
       (setq ob-scala-cli-eval-result (concat ob-scala-cli-eval-result str)))))

  (let ((full-body (ob-scala-cli-expand-body body)))
    (comint-send-string scala-cli-repl-buffer-name full-body)
    (comint-send-string scala-cli-repl-buffer-name "\n"))

  (while (not (s-ends-with? ob-scala-cli-prompt-str (s-trim-right ob-scala-cli-eval-result)))
    (sit-for 0.5))
  (sit-for 0.2)

  (when ob-scala-cli-debug-p (print (concat "#### " ob-scala-cli-eval-result)))
  (ob-scala-cli--trim-result ob-scala-cli-eval-result))

(provide 'ob-scala-cli)

;;; ob-scala-cli.el ends here