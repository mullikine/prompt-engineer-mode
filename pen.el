;;; pen.el --- Prompt Engineering functions

(require 'pen-support)
(require 'dash)
(require 'ht)

(defvar pen.el-map (make-sparse-keymap)
  "Keymap for `pen.el'.")
;; (makunbound 'pen.el)
(defvar-local pen.el nil)

(define-minor-mode pen
  "Mode for working with language models in your  buffers."
  :global t
  :init-value t
  :lighter " pen"
  :keymap pen.el-map)

(pen 1)

(defcustom pen-prompt-directory ""
  "Directory where .prompt files are located"
  :type 'string
  :group 'prompt-engineer
  :initialize #'custom-initialize-default)

(defset pen-prompt-functions nil)
(defset pen-prompt-functions-meta nil)

(defun pen-yaml-test (yaml key)
  (ignore-errors
    (if (and yaml
             (sor key))
        (let ((c (ht-get yaml key)))
          (and (sor c)
               (string-equal c "on"))))))

(defun pen-generate-prompt-functions ()
  "Generate prompt functions for the files in the prompts directory
Function names are prefixed with pen-pf- for easy searching"
  (interactive)
  (noupd
   (let ((paths
          (-non-nil (mapcar 'sor (glob (concat pen-prompt-directory "/*.prompt"))))))
     (cl-loop for path in paths do
              (message (concat "pen-mode: Loading .prompt file " path))

              ;; results in a hash table
              (let* ((yaml (yamlmod-read-file path))
                     (title (ht-get yaml "title"))
                     (title-slug (slugify title))
                     (doc (ht-get yaml "doc"))
                     (cache (pen-yaml-test yaml "cache"))
                     (needs-work (pen-yaml-test yaml "needs-work"))
                     (disabled (pen-yaml-test yaml "disabled"))
                     (prefer-external (pen-yaml-test yaml "prefer-external"))
                     (conversation-mode (pen-yaml-test yaml "conversation-mode"))
                     (filter (pen-yaml-test yaml "filter"))
                     ;; Don't actually use this. But I can toggle to use the prettifier with a bool
                     (prettifier (ht-get yaml "prettifier"))
                     (completion (pen-yaml-test yaml "completion"))
                     (n-collate (ht-get yaml "n-collate"))
                     (vars (vector2list (ht-get yaml "vars")))
                     (aliases (vector2list (ht-get yaml "aliases")))
                     (alias-slugs (mapcar 'str2sym (mapcar (lambda (s) (concat "pen-pf-" s)) (mapcar 'slugify aliases))))
                     (examples (vector2list (ht-get yaml "examples")))
                     (preprocessors (vector2list (ht-get yaml "pen-preprocessors")))
                     (var-slugs (mapcar 'slugify vars))
                     (var-syms
                      (let ((ss (mapcar 'str2sym var-slugs)))
                        (message (concat "_" prettifier))
                        (if (sor prettifier)
                            (setq ss (append ss '(&key prettify))))
                        ss))
                     (pen-defaults (vector2list (ht-get yaml "pen-defaults")))
                     (completion (pen-yaml-test yaml "completion"))
                     (func-name (concat "pen-pf-" title-slug))
                     (func-sym (str2sym func-name))
                     (iargs (let ((iteration 0))
                              (cl-loop for v in vars
                                       collect
                                       (let ((example (or (sor (nth iteration examples)
                                                               "")
                                                          "")))
                                         (message "%s" (concat "Example " (str iteration) ": " example))
                                         (if (equal 0 iteration)
                                             ;; The first argument may be captured through selection
                                             `(if (selectionp)
                                                  (my/selected-text)
                                                (if ,(> (length (str2lines example)) 1)
                                                    (tvipe ;; ,(concat v ": ")
                                                     ,example)
                                                  (read-string-hist ,(concat v ": ") ,example)))
                                           `(if ,(> (length (str2lines example)) 1)
                                                (tvipe ;; ,(concat v ": ")
                                                 ,example)
                                              (read-string-hist ,(concat v ": ") ,example))))
                                       do
                                       (progn
                                         (setq iteration (+ 1 iteration))
                                         (message (str iteration)))))))

                (setq n-collate (or n-collate 1))

                (add-to-list 'pen-prompt-functions-meta yaml)

                ;; var names will have to be slugged, too

                (if alias-slugs
                    (cl-loop for a in alias-slugs do
                             (progn
                               (defalias a func-sym)
                               (add-to-list 'pen-prompt-functions a))))

                (if (not needs-work)
                    (add-to-list 'pen-prompt-functions
                                 (eval
                                  `(cl-defun ,func-sym ,var-syms
                                     ,(sor doc title)
                                     (interactive ,(cons 'list iargs))
                                     (let* ((sh-update
                                             (or sh-update (>= (prefix-numeric-value current-global-prefix-arg) 4)))
                                            (shcmd (concat
                                                    ,(if (sor prettifier)
                                                         '(if prettify
                                                              "PRETTY_PRINT=y "
                                                            ""))
                                                    ,(flatten-once
                                                      (list
                                                       (list 'concat
                                                             (if cache
                                                                 "oci "
                                                               "")
                                                             "openai-complete "
                                                             (q path))
                                                       (flatten-once
                                                        (cl-loop for vs in var-slugs collect
                                                                 (list " "
                                                                       (list 'q (str2sym vs)))))))))
                                            (result
                                             (chomp
                                              (mapconcat 'identity
                                                         (cl-loop for i in (number-sequence ,n-collate)
                                                                  collect
                                                                  (progn
                                                                    ;; (ns (concat "update? " (str sh-update)))
                                                                    (message (concat ,func-name " query " (int-to-string i) "..."))
                                                                    (let ((ret (sn shcmd)))
                                                                      (message (concat ,func-name " done " (int-to-string i)))
                                                                      ret)))
                                                         ""))))
                                       (if (interactive-p)
                                           (cond
                                            ((and ,filter
                                                  (selectedp))
                                             (replace-region (concat (selection) result)))
                                            (,completion
                                             (etv result))
                                            ((or ,(not filter)
                                                 (>= (prefix-numeric-value current-prefix-arg) 4)
                                                 (not (selectedp)))
                                             (etv result))
                                            (t
                                             (replace-region result)))
                                         result))))))
                (message (concat "pen-mode: Loaded prompt function " func-name)))))))
(pen-generate-prompt-functions)


;; (define-key global-map (kbd "H-TAB") nil)
(define-key global-map (kbd "H-TAB g") 'pen-generate-prompt-functions)



(defun pen-filter-with-prompt-function ()
  (interactive)
  (let ((f (fz pen-prompt-functions nil nil "pen filter: ")))
    (if f
        (filter-selected-region-through-function (str2sym f)))))
(define-key global-map (kbd "H-TAB s") 'pen-filter-with-prompt-function)

(defun pen-run-prompt-function ()
  (interactive)
  (let* ((sh-update (or sh-update (>= (prefix-numeric-value current-global-prefix-arg) 4)))
         (f (fz pen-prompt-functions nil nil "pen run: ")))
    ;; (ns (concat "sh-update: " (str sh-update)))
    (if f
        (call-interactively (str2sym f)))))

(defalias 'camille-complete 'pen-run-prompt-function)
(define-key global-map (kbd "H-TAB r") 'pen-run-prompt-function)

;; Camille-complete (because I press SPC to replace
(define-key selected-keymap (kbd "SPC") 'pen-run-prompt-function)
(define-key selected-keymap (kbd "M-SPC") 'pen-run-prompt-function)


(defun company-pen-filetype--candidates (prefix)
  (let* ((preceding-text (pen-preceding-text))
         (response
          (->>
              preceding-text
            (pen-pf-generic-file-type-completion (detect-language))))
         (res
          (list response)))
    (mapcar (lambda (s) (concat (company-pen-filetype--prefix) s))
            res)))


(defvar my-completion-engine 'company-pen-filetype)

(require 'company)
(defun my-completion-at-point ()
  (interactive)
  (call-interactively 'completion-at-point)
  (if (>= (prefix-numeric-value current-prefix-arg) 4)
      (call-interactively 'company-pen-filetype)
    (call-interactively 'completion-at-point)))

;; (define-key global-map (kbd "M-1") #'my-completion-at-point)
(define-key global-map (kbd "M-1") #'company-pen-filetype)


(defun pen-complete-long (preceding-text &optional tv)
  (interactive (list (str (buffer-substring (point) (max 1 (- (point) 1000))))
                     t))
  (let* ((response (pen-pf-generic-file-type-completion (detect-language) preceding-text)))
    (if tv
        (tv response)
      response)))


;; This should have many options and return a list of completions
;; It should be used in company-mode
;; j_company-pen-filetype
(defun pen-company-complete-generate (preceding-text))


(defun pen-completions-line (preceding-text &optional tv)
  (interactive (list (pen-preceding-text-line)
                     t))
  (let* ((response (pen-pf-generic-file-type-completion (detect-language) preceding-text)))
    (if tv
        (tv response)
      response)))

(define-key global-map (kbd "H-P") 'pen-complete-long)

(my-load "$MYGIT/semiosis/pen.el/pen-core.el")
(require 'pen-core)

(my-load "$MYGIT/semiosis/pen.el/pen-ivy.el")
(require 'pen-ivy)

(my-load "$MYGIT/semiosis/pen.el/pen-company.el")
(require 'pen-company)

(my-load "$MYGIT/semiosis/pen.el/pen-library.el")
(require 'pen-library)

(load (concat emacsdir "/config/examplary.el"))
(require 'examplary)

(my-load "$MYGIT/semiosis/pen.el/imaginary.el")
(require 'imaginary)

(my-load "$MYGIT/semiosis/pen.el/pen-contrib.el")
(require 'pen-contrib)

(define-key org-brain-visualize-mode-map (kbd "C-c a") 'org-brain-asktutor)
(define-key org-brain-visualize-mode-map (kbd "C-c t") 'org-brain-show-topic)
(define-key org-brain-visualize-mode-map (kbd "C-c d") 'org-brain-describe-topic)

(provide 'my-openai)
(provide 'pen)