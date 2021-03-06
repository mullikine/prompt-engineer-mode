;; To work around an issue with
;; Debugger entered--Lisp error: (void-function make-closure)
;; in f-join.
;; It's happening for all f functions on pen-debian.
;; Try recompiling emacs
;; (defun f-join (&rest strings)
;;   (s-join "/" strings))

(defun url-found-p (url)
  "Return non-nil if URL is found, i.e. HTTP 200."
  (with-current-buffer (url-retrieve-synchronously url nil t 5)
    (prog1 (eq url-http-response-status 200)
      (kill-buffer))))

(defun ecurl (url)
  (with-current-buffer (url-retrieve-synchronously url t t 5)
    (goto-char (point-min))
    (re-search-forward "^$")
    (delete-region (point) (point-min))
    (kill-line)
    (let ((result (buffer2string (current-buffer))))
      (kill-buffer)
      result)))

(defun pen-messages-buffer ()
  "Return the \"*Messages*\" buffer.
If it does not exist, create it and switch it to `messages-buffer-mode'."
  (or (get-buffer "*Messages*")
      (with-current-buffer (get-buffer-create "*Messages*")
        (messages-buffer-mode)
        (current-buffer))))

(defun pen-message-no-echo (format-string &rest args)
  (let ((inhibit-read-only t))
    (with-current-buffer (pen-messages-buffer)
      (goto-char (point-max))
      (when (not (bolp))
        (insert "\n"))
      (insert (apply 'format format-string args))
      (when (not (bolp))
        (insert "\n"))))
  ;; (let ((minibuffer-message-timeout 0))
  ;;   (message format-string args))
  )

(defun pen-log (s)
  (pen-message-no-echo "%s\\n" s)
  s)

(defun pen-write-to-file (stdin file_path)
  (ignore-errors (with-temp-buffer
                   (insert stdin)
                   (delete-file file_path)
                   (write-file file_path))))

(defun pen-cartesian-product (&rest ls)
  (let* ((len (length ls))
         (result (cond
                  ((not ls) nil)
                  ((equal 1 len) ls)
                  (t
                   (-reduce 'cartesian-product-2 ls)))))
    (if (< 2 len)
        (mapcar (lambda (l) (unsnd l (- len 2)))
                result)
      result)))

(defun pp-oneline (l)
  (chomp (replace-regexp-in-string "\n +" " " (pp l))))
(defalias 'pp-ol 'pp-oneline)

(defun eval-string (string)
  "Evaluate elisp code stored in a string."
  (eval (car (read-from-string (format "(progn %s)" string)))))

(defun pcre-replace-string (pat rep s &rest body)
  "Replace pat with rep in s and return the result.
The string replace part is still a regular emacs replacement pattern, not PCRE"
  (eval `(replace-regexp-in-string (pcre-to-elisp pat ,@body) rep s)))

(defun qne (string)
  "Like q but without the end quotes"
  (pcre-replace-string "\"(.*)\"" "\\1" (e/q string)))

(defun e/cat (path)
  "Return the contents of FILENAME."
  (with-temp-buffer
    (insert-file-contents path)
    (buffer-string)))

(defmacro comment (&rest body) nil)

(defun variable-p (s)
  (and (not (eq s nil))
       (boundp s)))

;; For docker
(if (not (variable-p 'user-home-directory))
    (defvar user-home-directory nil))
(setq user-home-directory (or user-home-directory "/root"))

(defmacro upd (&rest body)
  `(let ((pen-sh-update t)) ,@body))

(defmacro noupd (&rest body)
  `(let ((pen-sh-update nil)) ,@body))

(defmacro tryelse (thing &optional otherwise)
  "Try to run a thing. Run something else if it fails."
  `(condition-case
       nil ,thing
     (error ,otherwise)))

(defmacro try (&rest list-of-alternatives)
  "Try to run a thing. Run something else if it fails."
  `(try-cascade '(,@list-of-alternatives)))

(defun try-cascade (list-of-alternatives)
  "Try to run a thing. Run something else if it fails."
  ;; (pen-list2str list-of-alternatives)

  (let* ((failed t)
         (result
          (catch 'bbb
            (dolist (p list-of-alternatives)
              ;; (message "%s" (pen-list2str p))
              (let ((result nil))
                (tryelse
                 (progn
                   (setq result (eval p))
                   (setq failed nil)
                   (throw 'bbb result))
                 result))))))
    (if failed
        (error "Nothing in try succeeded")
      result)))

(defmacro defset (symbol value &optional documentation)
  "Instead of doing a defvar and a setq, do this. [[http://ergoemacs.org/emacs/elisp_defvar_problem.html][ergoemacs.org/emacs/elisp_defvar_problem.html]]"

  `(progn (defvar ,symbol ,documentation)
          (setq ,symbol ,value)))

(defun string-empty-or-nil-p (s)
  (or (not s)
      (string-empty-p s)))

(defun string-not-empty-nor-nil-p (s)
  (not (string-empty-or-nil-p s)))

(defun -filter-not-empty-string (l)
  (-filter 'string-not-empty-nor-nil-p l))

(defun string-first-nonnil-nonempty-string (&rest ss)
  "Get the first non-nil string."
  (let ((result))
    (catch 'bbb
      (dolist (p ss)
        (if (string-not-empty-nor-nil-p p)
            (progn
              (setq result p)
              (throw 'bbb result)))))
    result))
(defalias 'sor 'string-first-nonnil-nonempty-string)

(defun cwd ()
  "Gets the current working directory"
  (interactive)
  (f-expand (substring (shut-up-c (pwd)) 10)))

(defun get-dir ()
  "Gets the directory of the current buffer's file. But this could be different from emacs' working directory.
Takes into account the current file name."
  (shut-up-c
   (let ((filedir (if buffer-file-name
                      (file-name-directory buffer-file-name)
                    (file-name-directory (cwd)))))
     (if (s-blank? filedir)
         (cwd)
       filedir))))

(defmacro shut-up-c (&rest body)
  "This works for c functions where shut-up does not."
  `(progn (let* ((inhibit-message t))
            ,@body)))

(defun pen-q (&rest strings)
  (let ((print-escape-newlines t))
    (s-join " " (mapcar 'prin1-to-string strings))))

(defun pen-str2list (s)
  "Convert a newline delimited string to list."
  (split-string s "\n"))

(defun pen-list2str (&rest l)
  "join the string representation of elements of a given list into a single string with newline delimiters"
  (if (equalp 1 (length l))
      (setq l (car l)))
  (mapconcat 'identity (mapcar 'str l) "\n"))

(defun scrape (re s &optional delim)
  "Return a list of matches of re within s.
delim is used to guarantee the function returns multiple matches per line
(etv (scrape \"\\b\\w+\\b\" (buffer-string) \" +\"))"
  (if delim
      (setq s (pen-list2str (s-split delim s))))
  (pen-list2str
   (-flatten
    (cl-loop
     for
     line
     in
     (s-split "\n" (str s))
     collect
     (if (string-match-p re line)
         (s-replace-regexp (concat "^.*\\(" re "\\).*") "\\1" line))))))

(defun chomp (str)
  "Chomp (remove tailing newline from) STR."
  (replace-regexp-in-string "\n\\'" "" str))

(defun slurp-file (filePath)
  "Return filePath's file content."
  (with-temp-buffer
    (insert-file-contents filePath)
    (buffer-string)))

(defun str (thing)
  "Converts object or string to an unformatted string."

  (if thing
      (if (stringp thing)
          (substring-no-properties thing)
        (progn
          (setq thing (format "%s" thing))
          (set-text-properties 0 (length thing) nil thing)
          thing))
    ""))

(defun sh-construct-exports (varval-tuples)
  (concat
   "export "
   (sh-construct-envs varval-tuples)))

(defun sh-construct-envs (varval-tuples)
  (s-join
   " "
   (-filter
    'identity
    (cl-loop for tp in varval-tuples
             collect
             (let ((lhs (car tp))
                   (rhs (cadr tp)))
               (if tp
                   (concat
                    lhs
                    "="
                    (if rhs
                        (if (booleanp rhs)
                            "y"
                          (pen-q rhs))
                      ""))))))))

(defun pen-sn (cmd &optional stdin dir exit_code_var detach b_no_unminimise output_buffer b_unbuffer chomp b_output-return-code)
  "Runs command in shell and return the result.
This appears to strip ansi codes.
\(sh) does not.
This also exports PEN_PROMPTS_DIR, so lm-complete knows where to find the .prompt files"
  (interactive)

  (if (not cmd)
      (setq cmd "false"))

  (if (not dir)
      (setq dir (get-dir)))

  (let ((default-directory dir))
    (if b_unbuffer
        (setq cmd (concat "unbuffer -p " cmd)))

    (if (or
         (and (variable-p 'pen-sh-update)
              (eval 'pen-sh-update))
         (>= (prefix-numeric-value current-global-prefix-arg) 16))
        (setq cmd (concat "export UPDATE=y; " cmd)))

    (setq tf (make-temp-file "elisp_bash"))
    (setq tf_exit_code (make-temp-file "elisp_bash_exit_code"))

    (let ((exps
           (sh-construct-exports
            (-filter 'identity
                     (list (list "PATH" (getenv "PATH"))
                           (list "PEN_PROMPTS_DIR" (concat pen-prompts-directory "/prompts"))
                           (if (and (variable-p 'pen-sh-update) (eval 'pen-sh-update))
                               (list "UPDATE" "y")))))))
      (setq final_cmd (concat exps "; ( cd " (pen-q dir) "; " cmd "; echo -n $? > " tf_exit_code " ) > " tf)))

    (if detach
        (setq final_cmd (concat "trap '' HUP; unbuffer bash -c " (pen-q final_cmd) " &")))

    (shut-up-c
     (if (not stdin)
         (progn
           (shell-command final_cmd output_buffer))
       (with-temp-buffer
         (insert stdin)
         (shell-command-on-region (point-min) (point-max) final_cmd output_buffer))))
    (setq output (slurp-file tf))
    (if chomp
        (setq output (chomp output)))
    (progn
      (defset b_exit_code (slurp-file tf_exit_code)))

    (if b_output-return-code
        (setq output (str b_exit_code)))
    output))

(cl-defun pen-cl-sn (cmd &key stdin &key dir &key detach &key b_no_unminimise &key output_buffer &key b_unbuffer &key chomp &key b_output-return-code)
  (interactive)
  (pen-sn cmd stdin dir nil detach b_no_unminimise output_buffer b_unbuffer chomp b_output-return-code))

(defun pen-snc (cmd &optional stdin)
  "sn chomp"
  (chomp (pen-sn cmd stdin)))

(defun slugify (input &optional joinlines length)
  "Slugify input"
  (interactive)
  (let ((slug
         (if joinlines
             (pen-sn "tr '\n' - | slugify" input)
           (pen-sn "slugify" input))))
    (if length
        (substring slug 0 (- length 1))
      slug)))

(defun fz-completion-second-of-tuple-annotation-function (s)
  (let ((item (assoc s minibuffer-completion-table)))
    (when item
      ;; (concat " # " (second item))
      (cond
       ((listp item) (concat " # " (second item)))
       ((stringp item) "")
       (t "")))))

(cl-defun cl-fz (list &key prompt &key full-frame &key initial-input &key must-match &key select-only-match &key hist-var &key add-props)
  (if (and (not hist-var)
           (sor prompt))
      (setq hist-var (intern (concat "histvar-fz-" (slugify prompt)))))

  (setq prompt (sor prompt ":"))

  (if (not (string-match " $" prompt))
      (setq prompt (concat prompt " ")))

  (if (eq (type-of list) 'symbol)
      (cond
       ((variable-p 'clojure-mode-funcs) (setq list (eval list)))
       ((fboundp 'clojure-mode-funcs) (setq list (funcall list)))))

  (if (stringp list)
      (setq list (split-string list "\n")))

  (if (and select-only-match (eq (length list) 1))
      (car list)
    (progn
      (setq prompt (or prompt ":"))
      (let ((helm-full-frame full-frame)
            (completion-extra-properties nil))

        (if add-props
            (setq completion-extra-properties
                  (append
                   completion-extra-properties
                   add-props)))

        (if (and (listp (car list)))
            (setq completion-extra-properties
                  (append
                   '(:annotation-function fz-completion-second-of-tuple-annotation-function)
                   completion-extra-properties)))

        (completing-read prompt list nil must-match initial-input hist-var)))))

(defun fz (list &optional input b_full-frame prompt must-match select-only-match add-props)
  (cl-fz
   list
   :initial-input input
   :full-frame b_full-frame
   :prompt prompt
   :must-match must-match
   :select-only-match select-only-match
   :add-props add-props))

(defun selected ()
  (or
   (use-region-p)
   (evil-visual-state-p)))
(defalias 'selected-p 'selected)

(defun glob (pattern &optional dir)
  (split-string (pen-cl-sn (concat "pen-glob " (pen-q pattern) " 2>/dev/null") :stdin nil :dir dir :chomp t) "\n"))

(defun flatten-once (list-of-lists)
  (apply #'append list-of-lists))

(defun new-buffer-from-string (&optional contents bufname mode nodisplay)
  "Create a new untitled buffer from a string."
  (interactive)
  (if (not bufname)
      (setq bufname "*untitled*"))
  (let ((buffer (generate-new-buffer bufname)))
    (set-buffer-major-mode buffer)
    (if (not nodisplay)
        (display-buffer buffer '(display-buffer-same-window . nil)))
    (with-current-buffer buffer
      (if contents (insert (str contents)))
      (beginning-of-buffer)
      (if mode (call-function mode)))
    buffer))
(defalias 'nbfs 'new-buffer-from-string)
(defun new-buffer-from-o (o)
  (new-buffer-from-string
   (if (stringp o)
       o
     (pp-to-string o))))
(defun etv (o)
  "Returns the object. This is a way to see the contents of a variable while not interrupting the flow of code.
 Example:
 (message (etv \"shane\"))"
  (new-buffer-from-o o)
  o)

(defun regex-match-string-1 (pat s)
  "Get first match from substring"
  (save-match-data
    (and (string-match pat s)
         (match-string-no-properties 0 s))))
(defalias 'regex-match-string 'regex-match-string-1)

(defun s-preserve-trailing-whitespace (s-new s-old)
  "Return s-new but with the same amount of trailing whitespace as s-old."
  (let* ((trailing_ws_pat "[ \t\n]*\\'")
         (original_whitespace (regex-match-string trailing_ws_pat s-old))
         (new_result (concat (replace-regexp-in-string trailing_ws_pat "" s-new) original_whitespace)))
    new_result))

(defun preserve-trailing-whitespace (fun s)
  "Run a string filter command, but preserve the amount of trailing whitespace. (ptw 'awk1 \"hi\")"
  (s-preserve-trailing-whitespace (apply fun (list s)) s))
(defalias 'ptw 'preserve-trailing-whitespace)

(defun filter-selected-region-through-function (fun)
  (let* ((start (if (selected) (region-beginning) (point-min)))
         (end (if (selected) (region-end) (point-max)))
         (doreverse (and (selected) (< (point) (mark))))
         (removed (delete-and-extract-region start end))
         (replacement (str (ptw fun (str removed))))
         (replacement-len (length (str replacement))))
    (if buffer-read-only (new-buffer-from-string replacement)
      (progn
        (insert replacement)
        (let ((end-point (point))
              (start-point (- (point) replacement-len)))
          (push-mark start-point)
          (goto-char end-point)
          (setq deactivate-mark nil)
          (activate-mark)
          (if doreverse
              (cua-exchange-point-and-mark nil)))))))
(defalias 'filter-selection 'filter-selected-region-through-function)

(defmacro ntimes (n &rest body)
  (cons 'progn (flatten-once
                (cl-loop for i from 1 to n collect body))))

(defun pen-selected-text ()
  "Just give me the selected text as a string. If it's empty, then nothing was selected. region-active-p does not work for evil selection."
  (interactive)
  (cond
   ((or (region-active-p)
        (eq evil-state 'visual))
    (str (buffer-substring (region-beginning) (region-end))))
   (iedit-mode
    (iedit-current-occurrence-string))
   (t (read-string "pen-selected-text: "))))

(defalias 'pps 'pp-to-string)

(defun xc (&optional s silent)
  "emacs kill-ring, xclip copy
when s is nil, return current contents of clipboard
when s is a string, set the clipboard to s"
  (interactive)
  (if (and
       s
       (not (stringp s)))
      (setq s (pps s)))
  (if (not (empty-string-p s))
      (kill-new s)
    (if (selected-p)
        (progn
          (setq s (pen-selected-text))
          (call-interactively 'kill-ring-save))))
  (if s
      (if (not silent) (message "%s" (concat "Copied: " s)))
    (progn
      (shell-command-to-string "xsel --clipboard --output"))))

(defun pen-ivy-completing-read (prompt collection
                                       &optional predicate require-match initial-input
                                       history def inherit-input-method)
  "This is like ivy-completing-read but it does not escape +"
  (let ((handler
         (and (< ivy-completing-read-ignore-handlers-depth (minibuffer-depth))
              (assq this-command ivy-completing-read-handlers-alist))))
    (if handler
        (let ((completion-in-region-function #'completion--in-region)
              (ivy-completing-read-ignore-handlers-depth (1+ (minibuffer-depth))))
          (funcall (cdr handler)
                   prompt collection
                   predicate require-match
                   initial-input history
                   def inherit-input-method))
      ;; See the doc of `completing-read'.
      (when (consp history)
        (when (numberp (cdr history))
          (setq initial-input (nth (1- (cdr history))
                                   (symbol-value (car history)))))
        (setq history (car history)))
      (when (consp def)
        (setq def (car def)))
      (let ((str (ivy-read
                  prompt collection
                  :predicate predicate
                  :require-match (when (and collection require-match)
                                   require-match)
                  :initial-input (cond ((consp initial-input)
                                        (car initial-input))
                                       (t
                                        initial-input))
                  :preselect def
                  :def def
                  :history history
                  :keymap nil
                  :dynamic-collection ivy-completing-read-dynamic-collection
                  :extra-props '(:caller ivy-completing-read)
                  :caller (if (and collection (symbolp collection))
                              collection
                            this-command))))
        (if (string= str "")
            (or def "")
          str)))))

(defmacro initvar (symbol &optional value)
  "defvar while ignoring errors"
  (let ((sym (eval symbol)))
    `(progn (ignore-errors (defvar ,sym nil))
            ;; (ignore-errors (defvar ,symbol nil))
            (if ,value (setq ,symbol ,value)))))

;; To get around an annoying error message
(defvar histvar nil)

(defun completing-read-hist (prompt &optional initial-input histvar default-value)
  "read-string but with history."
  (if (not histvar)
      (setq histvar (intern (concat "completing-read-hist-" (slugify prompt)))))

  (setq prompt (sor prompt ":"))

  (if (not (string-match " $" prompt))
      (setq prompt (concat prompt " ")))

  (if (not (variable-p histvar))
            (eval `(defvar ,histvar nil)))
  (if (and (not initial-input)
           (listp histvar))
      (setq initial-input (first histvar)))
  (eval `(progn
           (let ((inhibit-quit t))
             (or (with-local-quit
                   (let ((completion-styles
                          '(basic))
                         (s (str (pen-ivy-completing-read ,prompt ,histvar nil nil initial-input ',histvar nil))))

                     (setq ,histvar (seq-uniq ,histvar 'string-equal))
                     s))
                 "")))))
(defalias 'read-string-hist 'completing-read-hist)

(defun vector2list (v)
  (append v nil))

(defun region-or-buffer-string ()
  (interactive)
  (if (or (region-active-p) (eq evil-state 'visual))
      (str (buffer-substring (region-beginning) (region-end)))
    (str (buffer-substring (point-min) (point-max)))))

(defun current-major-mode-string ()
  "Get the current major mode as a string."
  (str major-mode))

(defun detect-language (&optional detect buffer-not-selection)
  "Returns the language of the buffer or selection."
  (interactive)
  (let ((lang
         (if (not detect)
             (s-replace-regexp "-mode$" "" (current-major-mode-string))
           (str (language-detection-string
                 (if buffer-not-selection
                     (buffer-string)
                   (region-or-buffer-string)))))))

    (if (string-equal "rustic" lang) (setq lang "rust"))
    (if (string-equal "clojurec" lang) (setq lang "clojure"))
    lang))

(defun mode-to-lang (&optional modesym)
  (if (not modesym)
      (setq modesym major-mode))
  (s-replace-regexp "-mode$" "" (symbol-name modesym)))

(defun lang-to-mode (&optional langstr)
  (if (not langstr)
      (setq langstr (detect-language)))
  (intern (concat langstr "-mode")))

(defun get-ext-for-lang (langstr)
  (get-ext-for-mode (lang-to-mode langstr)))

(defun get-ext-for-mode (&optional m)
  (interactive)
  (if (not m) (setq m major-mode))

  (cond ((eq major-mode 'json-mode) "json")
        ((eq major-mode 'python-mode) "py")
        ((eq major-mode 'fundamental-mode) "txt")
        (t (try (let ((result (chomp (s-replace-regexp "^\." "" (scrape "\\.[a-z0-9A-Z]+" (car (rassq m auto-mode-alist)))))))
                  (setq result (cond ((string-equal result "pythonrc") "py")
                                     (t result)))

                  (if (called-interactively-p)
                      (message result)
                    result))
                "txt"))))
(defalias 'get-path-ext-from-mode-alist 'get-ext-for-mode)


(defun pen-thing-at-point (&optional only-if-selected)
  (interactive)

  (if (and only-if-selected
           (not mark-active))
      nil
    (if (or mark-active
            iedit-mode)
        (pen-selected-text)
      (str
       (or (thing-at-point 'symbol)
           (thing-at-point 'sexp)
           (let ((s (str (thing-at-point 'char))))
             (if (string-equal s "\n")
                 ""
               s))
           "")))))

(defalias 'second 'cadr)

;; I would like to disable the yaml lsp server for .prompt files.
;; At least, until a schema for it is made in schemastore.
;; http://www.schemastore.org/json/
(defun maybe-lsp ()
  "Maybe run lsp."
  (interactive)
  (cond
   ((derived-mode-p 'prompt-description-mode)
    (message "Disabled lsp for prompts"))
   ((derived-mode-p 'completer-description-mode)
    (message "Disabled lsp for completers"))
   (t (call-interactively 'lsp))))

(defun pen-onelineify (s)
  (snc "sed -z 's/\\n/\\\\n/g'" s))

(defun pen-unonelineify (s)
  (snc "sed -z 's/\\\\n/\\n/g'" s))

(defun replace-region (s)
  "Apply the function to the selected region. The function must accept a string and return a string."
  (let ((rstart (if (region-active-p) (region-beginning) (point-min)))
        (rend (if (region-active-p) (region-end) (point-max)))
        (was_selected (selected-p))
        (deactivate-mark nil))

    (if buffer-read-only
        (progn
          (message "buffer is readonly. placing in temp buffer")
          (nbfs s))
      (progn
        (let ((doreverse (< (point) (mark))))
          (delete-region
           rstart
           rend)
          (insert s)

          (if doreverse
              (call-interactively 'cua-exchange-point-and-mark)))

        (if (not was_selected)
            (deactivate-mark))))))

(provide 'pen-support)