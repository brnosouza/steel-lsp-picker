(require-builtin helix/components)
(require "helix/misc.scm")
(require (prefix-in helix. "helix/commands.scm"))

(provide
  ;; Configurable log path
  *lsp-picker-log-path*
  lsp-picker-set-log-path!
  ;; Configurable grep provider
  *lsp-picker-grep-cmd*
  lsp-picker-set-grep-cmd!
  ;; LspEntry struct
  LspEntry LspEntry? LspEntry-name LspEntry-initialized
  ;; LspPickerState struct + accessors
  LspPickerState
  LspPickerState-clients
  LspPickerState-selected
  LspPickerState-slots
  ;; Constructors / operations
  lsp-picker-state-new
  lsp-fetch-clients
  lsp-selected-entry
  lsp-selected-name
  lsp-state-next!
  lsp-state-prev!
  lsp-state-refresh!
  lsp-state-set-slots!
  ;; Open log in a scratch buffer
  open-lsp-log-in-buffer!)

;; ─────────────────────────────────────────────
;; Configurable log path
;; ─────────────────────────────────────────────

;;@doc
;; Path to the Helix log file. Override in init.scm:
;;   (lsp-picker-set-log-path! "/custom/path/helix.log")
;; Defaults to ~/.cache/helix/helix.log
(define *lsp-picker-log-path* (box #f))

(define (lsp-picker-set-log-path! path)
  (set-box! *lsp-picker-log-path* path))

;;@doc
;; Grep command for log filtering.
;; Accepts a string (binary name) or a function (lsp-name log-path tmp-path) -> pipeline-string.
;;
;; String examples — standard "-i pattern file > tmp" args are added automatically:
;;   (lsp-picker-set-grep-cmd! "grep")   ; default
;;   (lsp-picker-set-grep-cmd! "rg")     ; ripgrep
;;   (lsp-picker-set-grep-cmd! "ag")     ; the silver searcher
;;
;; Function example — full control over the pipeline:
;;   (lsp-picker-set-grep-cmd!
;;     (lambda (name log-path tmp-path)
;;       (string-append "rg --case-sensitive " (sh-quote name)
;;                      " " (sh-quote log-path)
;;                      " > " (sh-quote tmp-path))))
(define *lsp-picker-grep-cmd* (box "grep"))

(define (lsp-picker-set-grep-cmd! cmd)
  (set-box! *lsp-picker-grep-cmd* cmd))

;; Build the shell pipeline string for log filtering.
;; When cmd is a string, use: cmd -i <name> <logpath> > <tmppath>
;; When cmd is a function, call it directly.
(define (lsp-build-pipeline lsp-name log-path tmp-path)
  (let ([cmd (unbox *lsp-picker-grep-cmd*)])
    (if (procedure? cmd)
        (cmd lsp-name log-path tmp-path)
        (string-append cmd " -i "
                       (sh-quote lsp-name) " "
                       (sh-quote log-path)
                       " > " (sh-quote tmp-path)))))

(define (lsp-resolve-log-path)
  (or (unbox *lsp-picker-log-path*)
      (string-append (get-home-dir) "/.cache/helix/helix.log")))

;; ─────────────────────────────────────────────
;; LspEntry  – wraps a raw lsp-client handle
;; ─────────────────────────────────────────────
(struct LspEntry (name initialized raw))

;; ─────────────────────────────────────────────
;; LspPickerState  – full component state
;; ─────────────────────────────────────────────
(struct LspPickerState
  (clients   ;; box: (listof LspEntry?)
   selected  ;; box: int?
   slots     ;; box: int?  – visible rows
   ))

(define (lsp-picker-state-new)
  (let ([state (LspPickerState (box '()) (box 0) (box 10))])
    (lsp-state-refresh! state)
    state))

;; ─────────────────────────────────────────────
;; Fetching LSP clients from Helix
;; ─────────────────────────────────────────────

(define (lsp-fetch-clients)
  (map (lambda (c)
         (LspEntry (lsp-client-name c)
                   (lsp-client-initialized? c)
                   c))
       (get-active-lsp-clients)))

;; ─────────────────────────────────────────────
;; State mutation helpers
;; ─────────────────────────────────────────────

(define (lsp-state-set-slots! state n)
  (set-box! (LspPickerState-slots state) n))

(define (lsp-state-refresh! state)
  (let ([all (lsp-fetch-clients)])
    (set-box! (LspPickerState-clients state) all)
    (set-box! (LspPickerState-selected state) 0)))

(define (lsp-state-next! state)
  (let ([cur (unbox (LspPickerState-selected state))]
        [total (length (unbox (LspPickerState-clients state)))])
    (when (< (+ cur 1) total)
      (set-box! (LspPickerState-selected state) (+ cur 1)))))

(define (lsp-state-prev! state)
  (let ([cur (unbox (LspPickerState-selected state))])
    (when (> cur 0)
      (set-box! (LspPickerState-selected state) (- cur 1)))))

(define (lsp-selected-entry state)
  (let ([clients (unbox (LspPickerState-clients state))]
        [idx (unbox (LspPickerState-selected state))])
    (if (and (> (length clients) 0) (< idx (length clients)))
        (list-ref clients idx)
        #f)))

(define (lsp-selected-name state)
  (let ([entry (lsp-selected-entry state)])
    (if entry (LspEntry-name entry) #f)))

;; ─────────────────────────────────────────────
;; Open log in a tmp file, then open in Helix
;; ─────────────────────────────────────────────

;;@doc
;; Filter the Helix log for `lsp-name`, write all matching lines to a tmp
;; file, then open that file in the editor.
;;
;; Steps:
;;   1. Copy (filter) the log into /tmp/lsp-log-<name>.log via
;;      `sh -c "<grep> -i <name> <logpath> > <tmpfile>"`
;;   2. Wait for the shell to finish (read its stdout, which is empty).
;;   3. Open the tmp file with `:open`.
;;
;; All lines are included — no cap. The tmp file persists until the OS
;; cleans /tmp, so re-opening the same LSP log is effectively free.
(define (open-lsp-log-in-buffer! lsp-name)
  (when lsp-name
    (log::info! (to-string "[lsp-picker] opening log for lsp=" lsp-name))
    (let* ([log-path  (lsp-resolve-log-path)]
           [tmp-path  (string-append "/tmp/lsp-log-" (sanitize-name lsp-name) ".log")]
           [pipeline  (lsp-build-pipeline lsp-name log-path tmp-path)])
      (with-handler
        (lambda (err)
          (log::warn! (to-string "[lsp-picker] failed to filter log: " err))
          (set-status! "Failed to open LSP log"))
        ;; Run the pipeline; reading stdout (empty) blocks until sh exits.
        (let* ([cmd  (with-stdout-piped (command "sh" (list "-c" pipeline)))]
               [proc (spawn-process cmd)])
          (when (Ok? proc)
            (read-port-to-string (child-stdout (Ok->value proc))))
          (helix.open tmp-path))))))

;; ─────────────────────────────────────────────
;; Helpers
;; ─────────────────────────────────────────────

;; Replace characters unsafe in file names with underscores.
(define (sanitize-name s)
  (list->string
    (map (lambda (c)
           (let ([code (char->integer c)])
             (if (or (and (>= code 65) (<= code 90))   ; A-Z
                     (and (>= code 97) (<= code 122))  ; a-z
                     (and (>= code 48) (<= code 57))   ; 0-9
                     (= code 45)                        ; -
                     (= code 46))                       ; .
                 c #\_)))
         (string->list s))))

(define (sh-quote s)
  (string-append "'" (sh-join (split-many s "'") "'\\''" ) "'"))

(define (sh-join parts sep)
  (cond
    [(null? parts) ""]
    [(null? (cdr parts)) (car parts)]
    [else (string-append (car parts) sep (sh-join (cdr parts) sep))]))

(define (get-home-dir)
  (let ([result (maybe-get-env-var "HOME")])
    (if (Ok? result) (Ok->value result) "/root")))
