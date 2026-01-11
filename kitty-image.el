;;; kitty-image.el --- Display images below Markdown links in Kitty terminal (row/col based)

(require 'terminal-query)

(defvar kitty-image--images nil)
(defvar kitty-image--next-id 1)
(defvar kitty-image--scroll-timer nil)
(defvar kitty-image--edit-timer nil
  "Timer used to debounce image redraw after buffer edits.")

;; ────────────────────────────────
;; Write to TTY

(defun kitty-image--write-tty (data)
  (let ((coding-system-for-write 'binary))
    (write-region data nil "/dev/tty" t 0)))

;; ────────────────────────────────
;; Get row/col of buffer position

(defun kitty-image--get-row-col (pos)
  "Return (row . col) of buffer POS in terminal."
  (save-excursion
    (goto-char pos)
    (redisplay t)
    (sit-for 0.01)
    (let ((cursor-pos (terminal-query-cursor-position)))
      (when cursor-pos
        (cons (car cursor-pos) (cdr cursor-pos))))))

;; ────────────────────────────────
;; Find markdown links

(defun kitty-image--find-markdown-links ()
  (let (results)
    (save-excursion
      (goto-char (point-min))
      (while (re-search-forward "!\\[\\([^]]*\\)\\](\\([^)]+\\))" nil t)
        (let* ((link-start (match-beginning 0))
               (file (match-string 2))
               (clean (string-trim (replace-regexp-in-string "[\"'].*" "" file))))
          (when (and clean (file-exists-p clean))
            (push (list (match-end 0) clean link-start) results)))))
    (nreverse results)))

;; ────────────────────────────────
;; Check if position has enough space below

(defun kitty-image--has-space-below-p (link-start)
  "Check if link has enough space below for image (avoid bottom edge)."
  (let* ((win-height (window-body-height))
         (link-line (count-screen-lines (window-start) link-start))
         (required-space 5))
    (< (+ link-line required-space) win-height)))

;; ────────────────────────────────
;; Display image at next line

(defun kitty-image--display-at-pos (pos file link-start)
  (when (and (pos-visible-in-window-p link-start)
             (kitty-image--has-space-below-p link-start)
             (file-exists-p file))
    (let ((row-col (kitty-image--get-row-col link-start)))
      (when row-col
        (let* ((row (car row-col))
               (col (cdr row-col))
               (next-row (1+ row))
               (target-col col)
               (move-cmd (format "\x1b[%d;%dH" next-row target-col))
               (data (with-temp-buffer
                       (set-buffer-multibyte nil)
                       (insert-file-contents-literally (expand-file-name file))
                       (buffer-string)))
               (b64 (base64-encode-string data t))
               (image-id kitty-image--next-id))

          (kitty-image--write-tty move-cmd)
          (kitty-image--write-tty (format "\x1b_Ga=T,f=100,i=%d,t=d;%s\x1b\\" image-id b64))

          (push (list pos image-id file) kitty-image--images)
          (setq kitty-image--next-id (1+ kitty-image--next-id)))))))

;; ────────────────────────────────
;; Clear all

(defun kitty-image--clear-all ()
  (kitty-image--write-tty "\x1b_Ga=d,d=A\x1b\\")
  (setq kitty-image--images nil))

;; ────────────────────────────────
;; Main display

(defun kitty-image-display-all ()
  (interactive)
  (kitty-image--clear-all)
  (let ((links (kitty-image--find-markdown-links)))
    (dolist (link links)
      (let ((pos (nth 0 link))
            (file (nth 1 link))
            (link-start (nth 2 link)))
        (when (pos-visible-in-window-p link-start)
          (kitty-image--display-at-pos pos file link-start))))))

;; ────────────────────────────────
;; Scroll handler

(defun kitty-image--on-scroll (win start-pos)
  "Called when window is scrolled."
  (when (and kitty-image-mode
             (eq win (selected-window)))
    (when kitty-image--scroll-timer
      (cancel-timer kitty-image--scroll-timer))
    (setq kitty-image--scroll-timer
          (run-with-idle-timer 0.1 nil #'kitty-image-display-all))))

;; ────────────────────────────────
;; Edit handler

(defun kitty-image--on-edit (beg end _len)
  "Called after buffer changes. Debounce and refresh images."
  (when (and kitty-image-mode
             (eq (current-buffer) (window-buffer (selected-window))))
    (when kitty-image--edit-timer
      (cancel-timer kitty-image--edit-timer))
    (setq kitty-image--edit-timer
          (run-with-idle-timer 0.15 nil #'kitty-image-display-all))))

;; ────────────────────────────────
;; Minor mode

(define-minor-mode kitty-image-mode
  "Display Markdown images below links using terminal row/col."
  :lighter " KImg"
  (if kitty-image-mode
      (progn
        (setq-local truncate-lines t)
        (add-hook 'window-scroll-functions #'kitty-image--on-scroll nil t)
        (add-hook 'after-change-functions #'kitty-image--on-edit nil t)
        (kitty-image-display-all))
    (remove-hook 'window-scroll-functions #'kitty-image--on-scroll t)
    (remove-hook 'after-change-functions #'kitty-image--on-edit t)
    (kitty-image--clear-all)
    (when kitty-image--scroll-timer
      (cancel-timer kitty-image--scroll-timer)
      (setq kitty-image--scroll-timer nil))
    (when kitty-image--edit-timer
      (cancel-timer kitty-image--edit-timer)
      (setq kitty-image--edit-timer nil))))

(provide 'kitty-image)
