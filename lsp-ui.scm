(require-builtin helix/components)
(require "helix/misc.scm")
(require "lsp-state.scm")

(provide render-lsp-picker)

;; ─────────────────────────────────────────────────────────────────
;; Layout calculations
;; ─────────────────────────────────────────────────────────────────

(define (calc-picker-area rect)
  (let* ([sw (area-width rect)]
         [sh (area-height rect)]
         [pw (inexact->exact (round (* sw 0.50)))]
         [ph (inexact->exact (round (* sh 0.70)))]
         [px (quotient (- sw pw) 2)]
         [py (quotient (- sh ph) 2)])
    (area px py pw ph)))

(define (calc-list-area outer)
  (area (+ (area-x outer) 1)
        (+ (area-y outer) 1)
        (- (area-width outer) 2)
        (- (area-height outer) 3)))

(define (calc-help-area outer)
  (area (+ (area-x outer) 1)
        (+ (area-y outer) (- (area-height outer) 2))
        (- (area-width outer) 2)
        1))

;; ─────────────────────────────────────────────────────────────────
;; Main render entry point
;; ─────────────────────────────────────────────────────────────────

(define (render-lsp-picker state rect frame)
  (define picker-area (calc-picker-area rect))
  (define border-style (theme-scope *helix.cx* "ui.background"))
  (define title-style (style-with-bold (theme-scope *helix.cx* "ui.text")))
  (define blk-style (style-with-bold (theme-scope *helix.cx* "ui.background")))
  (define blk (make-block blk-style border-style "all" "rounded"))

  (buffer/clear frame picker-area)
  (block/render frame picker-area blk)
  (frame-set-string! frame
                     (+ (area-x picker-area) 2)
                     (area-y picker-area)
                     " LSP Manager "
                     title-style)
  (render-lsp-list  frame (calc-list-area picker-area) state)
  (render-help-line frame (calc-help-area picker-area))

  (lsp-state-set-slots! state (area-height (calc-list-area picker-area))))

;; ─────────────────────────────────────────────────────────────────
;; LSP list
;; ─────────────────────────────────────────────────────────────────

(define (render-lsp-list frame area state)
  (define clients (unbox (LspPickerState-clients state)))
  (define selected (unbox (LspPickerState-selected state)))
  (define slots (area-height area))
  (define page-start (let ([s (unbox (LspPickerState-slots state))])
                       (* (quotient selected (max 1 s)) (max 1 s))))
  (define visible (slice-list clients page-start slots))

  (for-each-indexed
    (lambda (idx entry)
      (let* ([row        (+ (area-y area) idx)]
             [is-sel?    (= (+ page-start idx) selected)]
             [init?      (LspEntry-initialized entry)]
             [name       (LspEntry-name entry)]
             [icon       (if init? "● " "◌ ")]
             [icon-style (if init?
                             (style-fg (style) Color/Green)
                             (style-fg (style) Color/Yellow))]
             [name-style (if is-sel?
                             (style-with-bold (theme-scope *helix.cx* "ui.text.focus"))
                             (theme-scope *helix.cx* "ui.text"))]
             [status     (if init? "[ready]" "[init…]")]
             [status-x   (- (+ (area-x area) (area-width area)) (string-length status) 1)]
             [status-sty (if init?
                             (style-fg (style) Color/Green)
                             (style-fg (style) Color/Yellow))])
        (frame-set-string! frame (area-x area) row
                           (if is-sel? " > " "  ")
                           (theme-scope *helix.cx* "ui.text"))
        (frame-set-string! frame (+ (area-x area) 3) row icon icon-style)
        (frame-set-string! frame (+ (area-x area) 5) row name name-style)
        (frame-set-string! frame status-x row status status-sty)))
    visible)

  (when (null? clients)
    (frame-set-string! frame (+ (area-x area) 2) (area-y area)
                       "No LSP servers active for this buffer"
                       (style-with-dim (theme-scope *helix.cx* "ui.text")))))

;; ─────────────────────────────────────────────────────────────────
;; Help line
;; ─────────────────────────────────────────────────────────────────

(define (render-help-line frame area)
  (frame-set-string! frame (area-x area) (area-y area)
                     (truncate-string " r:restart  s:stop  l:open-log  ↑↓:nav  esc:close"
                                      (area-width area))
                     (style-with-dim (theme-scope *helix.cx* "ui.text"))))

;; ─────────────────────────────────────────────────────────────────
;; Utility
;; ─────────────────────────────────────────────────────────────────

(define (slice-list lst offset n)
  (let loop ([l lst] [pos 0] [acc '()])
    (cond
      ((null? l) (reverse acc))
      ((>= pos (+ offset n)) (reverse acc))
      ((>= pos offset) (loop (cdr l) (+ pos 1) (cons (car l) acc)))
      (else (loop (cdr l) (+ pos 1) acc)))))

(define (for-each-indexed proc lst)
  (define idx (box 0))
  (for-each (lambda (item)
              (proc (unbox idx) item)
              (set-box! idx (+ (unbox idx) 1)))
            lst))

(define (truncate-string s max-len)
  (if (<= (string-length s) max-len)
      s
      (string-append (substring s 0 (max 0 (- max-len 1))) "…")))
