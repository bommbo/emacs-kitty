;;; kitty-image.el --- Markdown image display via terminal-query + kitty-graphics.el

(require 'kitty-graphics)
(require 'terminal-query)

(defcustom kitty-image-extensions
  '("png" "jpg" "jpeg" "gif" "bmp" "webp" "tiff" "tif" "svg")
  "File extensions recognized as images."
  :type '(repeat string)
  :group 'kitty-graphics)

(defun kitty-image--display-link (beg end file)
  "Display image FILE at BEG..END in the current buffer.
Uses terminal-query to get the exact terminal position at BEG for the
initial placement.  The overlay is added to kitty-gfx--overlays so
kitty-graphics-mode handles scroll tracking automatically."
  (let* ((abs (expand-file-name file))
         ;; kitty-gfx-display-image uploads image data, creates the overlay,
         ;; and schedules an initial refresh via posn-at-point.
         ;; We then override with terminal-query coords for accuracy.
         (ov (progn
               (kitty-gfx-display-image abs beg end)
               ;; The freshly created overlay is at the head of the list.
               (car kitty-gfx--overlays))))
    ;; Override the initial placement with the exact terminal coordinates.
    (when ov
      (let ((rc (save-excursion
                  (goto-char beg)
                  (redisplay t)
                  (sit-for 0.01)
                  (terminal-query-cursor-position))))
        (when rc
          ;; Clear cached position to force re-placement.
          (overlay-put ov 'kitty-gfx-last-row nil)
          (overlay-put ov 'kitty-gfx-last-col nil)
          (kitty-gfx--place-image
           (overlay-get ov 'kitty-gfx-id)
           (overlay-get ov 'kitty-gfx-pid)
           (overlay-get ov 'kitty-gfx-cols)
           (overlay-get ov 'kitty-gfx-rows)
           (car rc) (cdr rc))
          (overlay-put ov 'kitty-gfx-last-row (car rc))
          (overlay-put ov 'kitty-gfx-last-col (cdr rc)))))))

(defun kitty-image--scan-and-display ()
  "Scan the current buffer for Markdown image links and display each one."
  (save-excursion
    (goto-char (point-min))
    (while (re-search-forward "!\\[[^]]*\\](\\([^)\n]+\\))" nil t)
      (let* ((beg  (match-beginning 0))
             (end  (match-end 0))
             (file (string-trim (match-string 1))))
        (when (and (not (string-match-p "\\`https?://" file))
                   (let ((ext (file-name-extension file)))
                     (and ext (member (downcase ext) kitty-image-extensions)))
                   (file-exists-p (expand-file-name file))
                   ;; Skip positions that already have an overlay.
                   (not (cl-some (lambda (ov) (overlay-get ov 'kitty-gfx))
                                 (overlays-in beg end))))
          (condition-case err
              (kitty-image--display-link beg end file)
            (error
             (message "kitty-image: %s: %s"
                      (file-name-nondirectory file)
                      (error-message-string err)))))))))

;;;###autoload
(define-minor-mode kitty-image-mode
  "Display images in Markdown buffers using Kitty graphics.
Initial placement uses terminal-query for accurate positioning.
Scroll tracking is handled automatically by kitty-graphics-mode."
  :lighter " KImg"
  (if kitty-image-mode
      (progn
        (unless kitty-graphics-mode
          (kitty-graphics-mode 1))
        (kitty-image--scan-and-display))
    (kitty-gfx-remove-images)))

(provide 'kitty-image)
;;; kitty-image.el ends here
