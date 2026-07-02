(require-builtin helix/components)
(require "helix/misc.scm")
(require (prefix-in helix. "helix/commands.scm"))
(require "lsp-state.scm")
(require "lsp-ui.scm")

(provide lsp-picker
         lsp-picker-set-log-path!
         lsp-picker-set-grep-cmd!)

(define COMPONENT-NAME "lsp-picker")

;; ─────────────────────────────────────────────────────────────────
;; Restart / stop helpers
;; ─────────────────────────────────────────────────────────────────

(define (restart-lsp! state)
  (let ([name (lsp-selected-name state)])
    (if name
        (begin
          (log::info! (to-string "[lsp-picker] restarting LSP: " name))
          (helix.lsp-restart name)
          (set-status! (string-append "Restarted LSP: " name))
          (lsp-state-refresh! state))
        (set-status! "No LSP selected"))))

(define (stop-lsp! state)
  (let ([name (lsp-selected-name state)])
    (if name
        (begin
          (log::info! (to-string "[lsp-picker] stopping LSP: " name))
          (helix.lsp-stop name)
          (set-status! (string-append "Stopped LSP: " name))
          (lsp-state-refresh! state))
        (set-status! "No LSP selected"))))

;; ─────────────────────────────────────────────────────────────────
;; Main event handler
;; ─────────────────────────────────────────────────────────────────

(define (handle-event state event)
  (cond
    ((key-event-up? event)
     (lsp-state-prev! state)
     event-result/consume)

    ((key-event-down? event)
     (lsp-state-next! state)
     event-result/consume)

    ((key-event-escape? event)
     event-result/close)

    ;; 'r': restart selected LSP
    ((and (key-event-char event)
          (char=? (key-event-char event) #\r))
     (restart-lsp! state)
     event-result/close)

    ;; 's': stop selected LSP
    ((and (key-event-char event)
          (char=? (key-event-char event) #\s))
     (stop-lsp! state)
     event-result/close)

    ;; 'l': open selected LSP log in a scratch buffer
    ((and (key-event-char event)
          (char=? (key-event-char event) #\l))
     (open-lsp-log-in-buffer! (lsp-selected-name state))
     event-result/close)

    (else event-result/consume)))

;; ─────────────────────────────────────────────────────────────────
;; Public command: open the picker
;; ─────────────────────────────────────────────────────────────────

;;@doc
;; Open the LSP Manager picker.
;; Shows all LSP servers attached to the current buffer.
;; Keys:
;;   ↑/↓  Navigate list
;;   r    Restart selected LSP and close
;;   s    Stop selected LSP and close
;;   l    Open selected LSP's log in a new scratch buffer and close
;;   Esc  Close
(define (lsp-picker)
  (let ([state (lsp-picker-state-new)])
    (log::info! "[lsp-picker] picker opened")
    (push-component!
      (new-component! COMPONENT-NAME
                      state
                      render-lsp-picker
                      (hash "handle_event" handle-event)))))
