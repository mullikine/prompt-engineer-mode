(require 'memoize)

;; These changes are required to allow persistent caching on disk

(defset pen-ht-cache-dir (concat user-emacs-directory "/ht-cache"))

(f-mkdir pen-ht-cache-dir)

(defun pen-ht-cache-slug-fp (name)
  (concat pen-ht-cache-dir "/" "persistent-hash-" (slugify name) ".elht"))

(defun pen-ht-cache (name &optional ht)
  (let* ((n (pen-ht-cache-slug-fp name))
         (nswap (concat n ".swap")))
    (if ht
        (progn (shut-up (pen-write-to-file (prin1-to-string ht) nswap))
               (rename-file nswap n t))
      (if (f-exists-p n)
          (let ((r (find-file-noselect n)))
            (if r
                (let ((ret (read r)))
                  (kill-buffer r)
                  ret)))))))

(defun my-ht-cache-delete (name)
  (f-delete (pen-ht-cache-slug-fp name) t))

(defun make-or-load-hash-table (name args)
  (progn
    (or (pen-ht-cache name)
        (apply 'make-hash-table args))))

(defun memoize--wrap (func timeout)
  "Return the memoized version of FUNC.
TIMEOUT specifies how long the values last from last access. A
nil timeout will cause the values to never expire, which will
cause a memory leak as memoize is use, so use the nil value with
care."
  (let* (;;This also works for lambdas
         (funcpps (pps func))
         (funcslugdata (if (< 150 (length funcpps))
                           (md5 funcpps)
                         funcpps))
         (funcslug (slugify (s-join "-" (pen-str2list funcslugdata))))
         (tablename (concat "table-" funcslug))
         (timeoutsname (concat "timeouts-" funcslug))
         (table (make-or-load-hash-table tablename '(:test equal)))
         (timeouts (make-or-load-hash-table timeoutsname '(:test equal))))
    (eval
     `(lambda (&rest args)
        (let ((value (gethash args ,table)))
          (unwind-protect
              ;; (or value (puthash args (apply ,func args) ,table))
              (let ((ret (or (and
                              (not (>= (prefix-numeric-value current-global-prefix-arg) 4))
                              value)
                             ;; Add to the hash table and save the hash table
                             (let ((newret (puthash args
                                                    (or (apply ,func args)
                                                        'MEMOIZE_NIL)
                                                    ,table)))
                               (if (featurep 'hashtable-print-readable)
                                   (pen-ht-cache ,tablename ,table))
                               newret))))
                (if (equal ret 'MEMOIZE_NIL)
                    (setq ret nil))
                ret)
            (let ((existing-timer (gethash args ,timeouts))
                  (timeout-to-use (or
                                   ;; timeout comes from the calling 'memoize' function
                                   (and (variable-p 'timeout)
                                        timeout)
                                   memoize-default-timeout)))
              (when existing-timer
                (cancel-timer existing-timer))
              (when timeout-to-use
                (puthash args
                         (run-at-time timeout-to-use nil
                                      (lambda ()
                                        ;; It would probably be better to alert and ignore
                                        (try (remhash args ,table)
                                             (message ,(concat "timer for memoized " funcslug " failed"))))) ,timeouts)))))))))

(defun ignore-errors-around-advice (proc &rest args)
  (ignore-errors
    (let ((res (apply proc args)))
      res)))

;; This would break emacs
;; (memoize-restore 'ignore-errors-around-advice)
;; (memoize 'ignore-errors-around-advice)

(provide 'pen-memoize)