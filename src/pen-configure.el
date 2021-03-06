(require 'f)

(defvar penconfdir (f-join user-home-directory ".pen"))

(defun pen-add-key-booste ()
  (interactive)
  (let ((pen-booste-key-file-path (f-join user-home-directory ".pen" "booste_api_key")))
    (if (not (f-dir-p penconfdir))
        (f-mkdir penconfdir))
    (if (not (f-file-p pen-booste-key-file-path))
        (let ((key (read-passwd "booste key: ")))
          (if (sor key)
              (progn
                (f-touch pen-booste-key-file-path)
                (f-write-text key 'utf-8 pen-booste-key-file-path)))))))

(defun pen-add-key-openai (key)
  (interactive (list (read-passwd "OpenAI key: ")))
  (let ((pen-openai-key-file-path (f-join user-home-directory ".pen" "openai_api_key")))
    (if (not (f-dir-p penconfdir))
        (f-mkdir penconfdir))
    (if (not (f-file-p pen-openai-key-file-path))
        (if (sor key)
            (progn
              (f-touch pen-openai-key-file-path)
              (f-write-text key 'utf-8 pen-openai-key-file-path))))))

(provide 'pen-configure)