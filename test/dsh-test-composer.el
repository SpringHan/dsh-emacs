;;; dsh-test-composer.el --- Composer tests -*- lexical-binding: t; -*-

;; Package-Requires: ((emacs "28.1"))

(require 'dsh-test-support)

;; --- Test 31g: the goal tools render dsh web's structured goal card ---
;; `create_goal' / `get_goal' / `update_goal' answer with the GoalView plus
;; its process-local activation; the card shows the objective as the row
;; summary and, expanded, State / Rounds and the blocker message — never the
;; raw JSON envelope or a cleared tombstone (postmortem/100).
(ert-deftest dsh-emacs-test-composer-goal-card-create-settled ()
  :tags '(dsh-unit)
  (with-temp-buffer
    (dsh-emacs-mode)
    (dsh-emacs-modeline-setup)
    (setq-local dsh-emacs-tool-expand-by-default t)
    (dsh-emacs-render-tool-call
     (dsh-emacs-test--tool-call-event 1 "gc" "create_goal"
                                      "{\"objective\":\"ship the release\"}"))
    (dsh-emacs-render-tool-result
     (dsh-emacs-test--tool-result-event
      2 "gc" nil 0
      "{\"goal\":{\"id\":\"g1\",\"revision\":2,\"objective\":\"ship the release\",\"phase\":\"active\",\"roundsStarted\":3,\"maxGoalRounds\":8},\"activation\":\"armed\"}"))
    (let* ((ns (dsh-emacs-render--make-namespace))
           (block (dsh-emacs-test--tool-block-text ns "tool-gc")))
      (ert-info ((format "%s" "goal-card-create-settled"))
        (should (and block
                     (string-match-p (regexp-quote "Create goal · ship the release") block)
                     (string-match-p "^  ship the release$" block)
                     (string-match-p "^  Status  Active$" block)
                     (string-match-p "^  Rounds  3 / 8$" block)
                     (not (string-match-p "maxGoalRounds" block))
                     (not (string-match-p "^  IN " block))))))
    ;; A phase-only update names its verb while the call runs, then the
    ;; settled card states the objective and the new state.
    (dsh-emacs-render-tool-call
     (dsh-emacs-test--tool-call-event
      3 "gu" "update_goal"
      "{\"goal_id\":\"g1\",\"revision\":2,\"action\":\"pause\"}"))
    (let* ((ns (dsh-emacs-render--make-namespace))
           (block (dsh-emacs-test--tool-block-text ns "tool-gu")))
      (ert-info ((format "%s" "goal-card-update-pending-names-action"))
        (should (and block (string-match-p (regexp-quote "Update goal · Pause") block)))))
    (dsh-emacs-render-tool-result
     (dsh-emacs-test--tool-result-event
      4 "gu" nil 0
      "{\"goal\":{\"id\":\"g1\",\"revision\":3,\"objective\":\"ship the release\",\"phase\":\"paused\",\"roundsStarted\":3,\"maxGoalRounds\":8},\"activation\":\"armed\"}"))
    (let* ((ns (dsh-emacs-render--make-namespace))
           (block (dsh-emacs-test--tool-block-text ns "tool-gu")))
      (ert-info ((format "%s" "goal-card-update-settled"))
        (should (and block
                     (string-match-p (regexp-quote "Update goal · ship the release") block)
                     (string-match-p "^  Status  Paused$" block)))))))

;; A blocked goal's wire `{code, message}' record reaches the card as its
;; human message only; a disarmed active goal reads "Awaiting continuation".
(ert-deftest dsh-emacs-test-composer-goal-card-blocked-shows-the-message ()
  :tags '(dsh-unit)
  (with-temp-buffer
    (dsh-emacs-mode)
    (dsh-emacs-modeline-setup)
    (setq-local dsh-emacs-tool-expand-by-default t)
    (dsh-emacs-render-tool-call
     (dsh-emacs-test--tool-call-event
      1 "gb" "update_goal"
      "{\"goal_id\":\"g1\",\"revision\":9,\"action\":\"blocked\",\"blocked_reason\":\"waiting on review\"}"))
    (dsh-emacs-render-tool-result
     (dsh-emacs-test--tool-result-event
      2 "gb" nil 0
      "{\"goal\":{\"id\":\"g1\",\"revision\":10,\"objective\":\"ship the release\",\"phase\":\"blocked\",\"roundsStarted\":4,\"maxGoalRounds\":8,\"blockedReason\":{\"code\":\"model-reported\",\"message\":\"waiting on review\"}},\"activation\":\"armed\"}"))
    (let* ((ns (dsh-emacs-render--make-namespace))
           (block (dsh-emacs-test--tool-block-text ns "tool-gb")))
      (ert-info ((format "%s" "goal-card-blocked-shows-the-message"))
        (should (and block
                     (string-match-p "^  Status  Blocked$" block)
                     (string-match-p "^  Blocker waiting on review$" block)
                     (not (string-match-p "model-reported" block))))))
    (dsh-emacs-render-tool-call
     (dsh-emacs-test--tool-call-event 3 "gd" "get_goal" "{}"))
    (dsh-emacs-render-tool-result
     (dsh-emacs-test--tool-result-event
      4 "gd" nil 0
      "{\"goal\":{\"id\":\"g2\",\"revision\":1,\"objective\":\"survive the fork\",\"phase\":\"active\",\"roundsStarted\":0,\"maxGoalRounds\":5},\"activation\":\"disarmed\"}"))
    (let* ((ns (dsh-emacs-render--make-namespace))
           (block (dsh-emacs-test--tool-block-text ns "tool-gd")))
      (ert-info ((format "%s" "goal-card-disarmed-state"))
        (should (and block (string-match-p "^  Status  Awaiting continuation$" block)))))))

;; A cleared goal is the card's empty state, not a raw tombstone; a failed
;; call keeps the generic ioCard with its status line.
(ert-deftest dsh-emacs-test-composer-goal-card-cleared-has-no-fields ()
  :tags '(dsh-unit)
  (with-temp-buffer
    (dsh-emacs-mode)
    (dsh-emacs-modeline-setup)
    (setq-local dsh-emacs-tool-expand-by-default t)
    (dsh-emacs-render-tool-call
     (dsh-emacs-test--tool-call-event 1 "gg" "get_goal" "{}"))
    (dsh-emacs-render-tool-result
     (dsh-emacs-test--tool-result-event 2 "gg" nil 0 "{\"goal\":null}"))
    (let* ((ns (dsh-emacs-render--make-namespace))
           (block (dsh-emacs-test--tool-block-text ns "tool-gg")))
      (ert-info ((format "%s" "goal-card-cleared-has-no-fields"))
        (should (and block
                     (string-match-p (regexp-quote "View goal · No goal") block)
                     (not (string-match-p "Status" block))
                     (not (string-match-p "null" block))))))
    (dsh-emacs-render-tool-call
     (dsh-emacs-test--tool-call-event
      3 "ge" "update_goal"
      "{\"goal_id\":\"g1\",\"revision\":1,\"action\":\"blocked\",\"blocked_reason\":\"nope\"}"))
    (dsh-emacs-render-tool-result
     (dsh-emacs-test--tool-result-event
      4 "ge" t 1 "blocked requires at least 3 consecutive goal rounds"))
    (let* ((ns (dsh-emacs-render--make-namespace))
           (block (dsh-emacs-test--tool-block-text ns "tool-ge")))
      (ert-info ((format "%s" "goal-card-failed-call-keeps-the-ioCard"))
        (should (and block
                     (string-match-p "Update goal" block)
                     (string-match-p "^  IN " block)))))))

;; A goal round continuation is host-injected like the skill evidence, but it
;; opens a turn the user should see: the transcript paints dsh web's trigger
;; notice (`TurnTriggerNodeView') instead of hiding it (postmortem/099).
(ert-deftest dsh-emacs-test-composer-goal-trigger-renders-collapsed-notice ()
  :tags '(dsh-unit)
  (let ((buf (generate-new-buffer " *dsh-goal-trigger*")))
    (unwind-protect
        (with-current-buffer buf
          (dsh-emacs-mode)
          (dsh-emacs-modeline-setup)
          (setq-local dsh-emacs--buffer-session "sess-goal-trigger")
          (dsh-emacs-render-event
           '((type . "user/message") (seq . 1) (time . 1700000000000)
             (data . ((content . [((type . "text")
                                   (text . "<goal_round>\nObjective: \"ship it\"\nRound: 3/8\n</goal_round>"))])
                      (source . ((kind . "goal") (goalId . "g1")
                                 (revision . 2) (round . 3)))))))
          (ert-info ((format "%s" "goal-trigger-renders-collapsed-notice"))
            (should (string-match-p "Continuing goal"
                                    (buffer-substring-no-properties
                                     (point-min) dsh-emacs--input-marker)))
            (should (null (string-match-p "goal_round" (buffer-string)))))
          ;; RET / mouse on the notice's labels shows the injected round prompt,
          ;; matching web's expandable trigger body.
          (goto-char (point-min))
          (search-forward "Continuing goal")
          (dsh-emacs-ui-toggle-fragment)
          (ert-info ((format "%s" "goal-trigger-expands-the-round-prompt"))
            (should (string-match-p "Objective: \"ship it\"" (buffer-string)))
            (should (string-match-p "Round: 3/8" (buffer-string))))
          ;; Opening the goal trigger does not open the other host injections.
          (dsh-emacs-render-event
           '((type . "user/message") (seq . 2)
             (data . ((content . [((type . "text") (text . "plugin notice body"))])
                      (source . ((kind . "plugin")))))))
          (ert-info ((format "%s" "goal-trigger-keeps-other-injections-hidden"))
            (should (null (string-match-p "plugin notice body" (buffer-string))))))
      (kill-buffer buf))))

;; Folding a goal notice must leave the following live reply's markers on
;; its own text, even when the final snapshot corrects the streamed content.
(ert-deftest dsh-emacs-test-composer-goal-trigger-fold-preserves-stream-boundary-case ()
  :tags '(dsh-unit)
  (dolist (initially-expanded '(nil t))
    (with-temp-buffer
      (dsh-emacs-mode)
      (dsh-emacs-render-event
       '((type . "user/message") (seq . 1)
         (data . ((content . [((type . "text") (text . "round prompt"))])
                  (source . ((kind . "goal")))))))
      (when initially-expanded
        (goto-char (point-min))
        (search-forward "Continuing goal")
        (dsh-emacs-ui-toggle-fragment))
      (dsh-emacs-render-event
       '((type . "assistant/chunk") (seq . 2)
         (data . ((turn . 1) (step . 1)
                  (chunk . ((type . "text-delta") (index . 0)
                            (text . "Hello")))))))
      (goto-char (point-min))
      (search-forward "Continuing goal")
      (dsh-emacs-ui-toggle-fragment)
      (ert-info ((format "%s" (format "goal-trigger-fold-preserves-stream-boundary-%s" initially-expanded)))
        (should (equal (buffer-substring-no-properties
                        (plist-get dsh-emacs--streaming-assistant :start)
                        (plist-get dsh-emacs--streaming-assistant :end))
                       "Hello")))
      (dsh-emacs-render-event
       '((type . "assistant/message") (seq . 3)
         (data . ((turn . 1) (step . 1)
                  (message . ((content . [((type . "text")
                                           (text . "Hello world"))])))))))
      (let ((text (buffer-substring-no-properties (point-min) (point-max))))
        (ert-info ((format "%s" (format "goal-trigger-fold-survives-reply-repair-%s" initially-expanded)))
          (should (string-match-p "Continuing goal" text))
          (should (string-match-p "Hello world" text))
          (should (if initially-expanded
                      (not (string-match-p "round prompt" text))
                    (string-match-p "round prompt" text))))))))

;; --- composer file reference: stays editable, but with link style and jumping
(ert-deftest dsh-emacs-test-composer-composer-file-chip-styled ()
  :tags '(dsh-unit)
  (with-temp-buffer
    (insert "@src/a.ts")
    (let ((e (point)))
      (dsh-emacs-reference--composer-file-chip (- e 9) e "src/a.ts")
      (ert-info ((format "%s" "composer-file-chip-styled"))
        (should (equal (get-text-property (- e 9) 'dsh-emacs-reference-ref)
                       '(file . "src/a.ts"))))
      (ert-info ((format "%s" "composer-file-chip-is-atomic"))
        (should (get-text-property (- e 9) 'dsh-emacs-reference-chip))))))

;; --- Composer Goal Row: parse the goal projection ---
(ert-deftest dsh-emacs-test-composer-goal-projection-parses ()
  :tags '(dsh-unit)
  (let* ((proj (list (cons 'goal
                           (list (cons 'id "g1")
                                 (cons 'revision 3)
                                 (cons 'objective "Improve model picker")
                                 (cons 'phase "active")
                                 (cons 'blockedReason nil)
                                 (cons 'maxGoalRounds 10)))))
         (goal (dsh-protocol-goal-projection--from-alist proj)))
    (ert-info ((format "%s" "composer-goal-projection-parses"))
      (should (dsh-protocol-goal-p goal))
      (should (equal (dsh-protocol-goal-objective goal) "Improve model picker"))
      (should (equal (dsh-protocol-goal-phase goal) "active"))
      (should (equal (dsh-protocol-goal-revision goal) 3))
      (should (equal (dsh-protocol-goal-id goal) "g1")))
    (ert-info ((format "%s" "composer-goal-nil-projection-is-nil"))
      (should (null (dsh-protocol-goal-projection--from-alist nil)))
      (should (null (dsh-protocol-goal-projection--from-alist '((nope . 1))))))))

;; A blocked goal's wire record is `{code, message}': the protocol carries the
;; human message (the code has no client consumer), and a goal-tool result
;; adds the progress counter and the process-local activation beside it.
(ert-deftest dsh-emacs-test-composer-protocol-goal-blocked-reason-is-its-message ()
  :tags '(dsh-unit)
  (let* ((blocked (dsh-protocol-goal--from-alist
                   '((id . "g1") (revision . 4) (objective . "Ship it")
                     (phase . "blocked") (maxGoalRounds . 8)
                     (blockedReason . ((code . "model-reported")
                                       (message . "waiting on review"))))))
         (view (dsh-protocol-goal-tool--from-alist
                '((goal . ((id . "g1") (revision . 4) (objective . "Ship it")
                           (phase . "active") (roundsStarted . 3)
                           (maxGoalRounds . 8)))
                  (activation . "disarmed")))))
    (ert-info ((format "%s" "protocol-goal-blocked-reason-is-its-message"))
      (should (equal (dsh-protocol-goal-blocked-reason blocked) "waiting on review")))
    (ert-info ((format "%s" "protocol-goal-tool-parses-view"))
      (should (equal (dsh-protocol-goal-objective view) "Ship it"))
      (should (equal (dsh-protocol-goal-rounds-started view) 3))
      (should (equal (dsh-protocol-goal-activation view) "disarmed")))
    (ert-info ((format "%s" "protocol-goal-tool-rejects-cleared-and-malformed"))
      (should (null (dsh-protocol-goal-tool--from-alist '((goal . nil)))))
      (should (null (dsh-protocol-goal-tool--from-alist '((goal . "nope")))))
      (should (null (dsh-protocol-goal-tool--from-alist nil))))))

;; --- Composer Goal Row: render read-only chrome above the input ---
(ert-deftest dsh-emacs-test-composer-composer-goal-row-rendered-above-input ()
  :tags '(dsh-unit)
  (with-temp-buffer
    (dsh-emacs-mode)
    (dsh-emacs-modeline-setup)
    (dsh-emacs-composer-set-goal
     (dsh-protocol-goal-projection--from-alist
      (list (cons 'goal (list (cons 'objective "Ship the refactor")
                              (cons 'phase "active"))))))
    (let ((txt (buffer-substring-no-properties (point-min) (point-max))))
      (ert-info ((format "%s" "composer-goal-row-rendered-above-input"))
        (should (string-match-p "Ship the refactor" txt))
        (should (string-match-p "Ongoing Goal" txt))
        (should (markerp dsh-emacs--composer-top-marker))
        (should (let ((g (string-match "Ship the refactor" txt))
                      (p (string-match "❯" txt)))
                  (and g p (< g p))))))))

;; --- Composer Goal Row: leading dartboard SVG display image ---
(ert-deftest dsh-emacs-test-composer-goal-row-is-read-only ()
  :tags '(dsh-unit)
  (with-temp-buffer
    (dsh-emacs-mode)
    (dsh-emacs-composer-set-goal
     (dsh-protocol-goal-projection--from-alist
      '((goal . ((objective . "Icon lead") (phase . "active"))))))
    (let ((beg (marker-position dsh-emacs--composer-top-marker)))
      (should (get-text-property beg 'dsh-emacs-composer-goal-row))
      (should (get-text-property beg 'read-only)))))

(ert-deftest dsh-emacs-test-composer-composer-goal-row-leads-with-svg-icon ()
  :tags '(dsh-unit)
  (skip-unless (image-type-available-p 'svg))
  (cl-letf (((symbol-function 'display-graphic-p) (lambda (&rest _) t)))
    (with-temp-buffer
      (dsh-emacs-mode)
      (dsh-emacs-composer-set-goal
       (dsh-protocol-goal-projection--from-alist
        '((goal . ((objective . "Icon lead") (phase . "active"))))))
      (let ((beg (marker-position dsh-emacs--composer-top-marker)))
        (should (eq 'image (car-safe (get-text-property beg 'display))))))))

;; --- Composer Goal Row: ellipsize long objectives to one line ---
(ert-deftest dsh-emacs-test-composer-composer-goal-fit-objective-ellipsizes ()
  :tags '(dsh-unit)
  (let* ((long "this objective is far longer than any chat window could ever hope to fit on a single physical line without wrapping so it must be ellipsized")
         (goal (dsh-protocol-goal-projection--from-alist
                (list (cons 'goal (list (cons 'objective long)
                                        (cons 'phase "active")))))))
    (ert-info ((format "%s" "composer-goal-fit-objective-ellipsizes"))
      (should (let ((row (dsh-emacs-composer--render-row goal))
                    (txt (dsh-emacs-composer--objective-text goal)))
                (and (string-match-p "…" row)
                     ;; The truncated row excludes the original tail and cannot wrap.
                     (not (string-match-p (substring txt (- (length txt) 20)) row))))))
    ;; Preserve short objectives unchanged.
    (let ((goal2 (dsh-protocol-goal-projection--from-alist
                  (list (cons 'goal (list (cons 'objective "short")
                                          (cons 'phase "active")))))))
      (ert-info ((format "%s" "composer-goal-fit-objective-keeps-short"))
        (should (string-match-p "short" (dsh-emacs-composer--render-row goal2)))
        (should (null (string-match-p "…" (dsh-emacs-composer--render-row goal2))))))))

;; A goal objective is a projection of the message that named the goal, so a
;; canonical session mention must display as its readable `@label' chip ---
;; never the opaque `dsh-session:' id (the transcript message already collapses
;; it).  The chip stays clickable inside the one-line dock.
(ert-deftest dsh-emacs-test-composer-composer-goal-row-collapses-session-mention ()
  :tags '(dsh-unit)
  (let* ((sid "session-alpha-1")
         (goal (dsh-protocol-goal-projection--from-alist
                `((goal . ((objective . ,(concat "review @[Alpha session]("
                                                 (dsh-test-reference--session-uri sid)
                                                 ") done"))
                           (phase . "active")))))))
    (let* ((row (dsh-emacs-composer--render-row goal))
           (text (substring-no-properties row))
           (ref (cl-find-if
                 (lambda (i) (get-text-property i 'dsh-emacs-reference-ref row))
                 (number-sequence 0 (1- (length row))))))
      (ert-info ((format "%s" "composer-goal-row-collapses-session-mention"))
        (should (string-match-p "@Alpha session" text))
        (should (null (string-match-p "dsh-session:" text)))
        (should (and ref
                     (equal (cons 'session sid)
                            (get-text-property ref 'dsh-emacs-reference-ref row))))
        (should (and ref
                     (memq 'dsh-emacs-reference-face
                           (ensure-list (get-text-property ref 'face row)))))
        (should (and ref
                     (equal "RET/mouse-1: open this session"
                            (get-text-property ref 'help-echo row))))
        (should (string-match-p "C-c C-g ?"
                                (or (get-text-property (string-match-p "review" text)
                                                       'help-echo row)
                                    "")))
        (should (cl-find-if (lambda (i)
                              (memq 'dsh-emacs-composer-goal-body-face
                                    (ensure-list (get-text-property i 'face row))))
                            (number-sequence 0 (1- (length row)))))))))

;; The goal tool card shows the same objective projection, so it collapses the
;; mention too and keeps the chip clickable.
(ert-deftest dsh-emacs-test-composer-goal-card-body-collapses-session-mention ()
  :tags '(dsh-unit)
  (let* ((sid "session-beta-1")
         (goal (dsh-protocol-goal-projection--from-alist
                `((goal . ((objective . ,(concat "keep @[Beta session]("
                                                 (dsh-test-reference--session-uri sid)
                                                 ") green"))
                           (phase . "active")
                           (roundsStarted . 1)
                           (maxGoalRounds . 4)))))))
    (let* ((body (dsh-emacs-render--goal-card-body goal))
           (text (substring-no-properties body))
           (ref (cl-find-if
                 (lambda (i) (get-text-property i 'dsh-emacs-reference-ref body))
                 (number-sequence 0 (1- (length body))))))
      (ert-info ((format "%s" "goal-card-body-collapses-session-mention"))
        (should (string-match-p "@Beta session" text))
        (should (null (string-match-p "dsh-session:" text)))
        (should (and ref
                     (equal (cons 'session sid)
                            (get-text-property ref 'dsh-emacs-reference-ref body))))))))

;; External clients may create multiline objectives; chrome remains one line
;; and clearing it must not leave later objective lines in the transcript.
(ert-deftest dsh-emacs-test-composer-composer-goal-multiline-objective-folds-to-one-row ()
  :tags '(dsh-unit)
  (with-temp-buffer
    (dsh-emacs-mode)
    (dsh-emacs-modeline-setup)
    (dsh-emacs-composer-set-goal
     (dsh-protocol-goal-projection--from-alist
      (list (cons 'goal (list (cons 'objective "line one\r\nline two\nline three")
                              (cons 'phase "active"))))))
    (let* ((region (dsh-emacs-composer--region))
           (row (buffer-substring-no-properties (car region) (cdr region))))
      (ert-info ((format "%s" "composer-goal-multiline-objective-folds-to-one-row"))
        (should (string-match-p "line one line two line three" row))
        (should (= (cl-count ?\n row) 1))
        (should (null (string-match-p "\r" row)))))
    (dsh-emacs-composer-set-goal nil)
    (ert-info ((format "%s" "composer-goal-multiline-clear-leaves-no-orphan"))
      (should (null (string-match-p "line one\\|line two\\|line three"
                                    (buffer-substring-no-properties
                                     (point-min) (point-max))))))))

;; Fallback glyphs must fit even when the window is narrower than fixed chrome.
(ert-deftest dsh-emacs-test-composer-composer-goal-narrow-fallback-fits-width ()
  :tags '(dsh-unit)
  (let ((goal (dsh-protocol-goal-projection--from-alist
               (list (cons 'goal (list (cons 'objective "narrow objective")
                                       (cons 'phase "active")))))))
    (cl-letf (((symbol-function 'dsh-emacs-composer--row-width) (lambda () 8))
              ((symbol-function 'dsh-emacs-composer--goal-icon) (lambda () nil))
              ((symbol-function 'dsh-emacs-composer--action-image)
               (lambda (&rest _args) nil)))
      (ert-info ((format "%s" "composer-goal-narrow-fallback-fits-width"))
        (should (<= (string-width (dsh-emacs-composer--render-row goal)) 8))))))

;; Use the narrowest width when several windows display the same buffer.
(ert-deftest dsh-emacs-test-composer-composer-goal-width-uses-narrowest-window ()
  :tags '(dsh-unit)
  (cl-letf (((symbol-function 'get-buffer-window-list)
             (lambda (&rest _) '(wide narrow)))
            ((symbol-function 'window-text-width)
             (lambda (window) (if (eq window 'wide) 90 23))))
    (ert-info ((format "%s" "composer-goal-width-uses-narrowest-window"))
      (should (= (dsh-emacs-composer--row-width) 23)))))

;; --- Composer Goal Row: read-only chrome without the prompt face ---
(ert-deftest dsh-emacs-test-composer-composer-goal-row-is-readonly-chrome ()
  :tags '(dsh-unit)
  (with-temp-buffer
    (dsh-emacs-mode)
    (dsh-emacs-modeline-setup)
    (dsh-emacs-composer-set-goal
     (dsh-protocol-goal-projection--from-alist
      (list (cons 'goal (list (cons 'objective "Readonly row")
                              (cons 'phase "paused"))))))
    (let* ((pos (save-excursion
                  (goto-char (point-min))
                  (and (search-forward "Readonly row" nil t)
                       (1- (point))))))
      (ert-info ((format "%s" "composer-goal-row-is-readonly-chrome"))
        (should (and pos
                     (get-text-property pos 'read-only)
                     (get-text-property pos 'dsh-emacs-composer-goal-row)
                     ;; The objective uses the body face and never inherits the prompt face.
                     (memq 'dsh-emacs-composer-goal-body-face
                           (if (listp (get-text-property pos 'face))
                               (get-text-property pos 'face)
                             (list (get-text-property pos 'face))))
                     (null (memq 'dsh-emacs-input-prompt-face
                                 (if (listp (get-text-property pos 'face))
                                     (get-text-property pos 'face)
                                   (list (get-text-property pos 'face)))))))))))

;; --- Composer Goal Row: transcript inserts above the row ---
(ert-deftest dsh-emacs-test-composer-composer-insert-point-lands-at-goal-row ()
  :tags '(dsh-unit)
  (with-temp-buffer
    (dsh-emacs-mode)
    (dsh-emacs-modeline-setup)
    (dsh-emacs-composer-set-goal
     (dsh-protocol-goal-projection--from-alist
      (list (cons 'goal (list (cons 'objective "Seam check")
                              (cons 'phase "active"))))))
    ;; With a composer marker, the insertion seam resolves to the row start.
    (let ((insert-pt (dsh-emacs-render--input-insert-point)))
      (ert-info ((format "%s" "composer-insert-point-lands-at-goal-row"))
        (should (and insert-pt
                     (= insert-pt (marker-position dsh-emacs--composer-top-marker))))))
    ;; Messages stack above the Goal Row and retain their order.
    (dsh-emacs-render-event
     (list (cons 'type "assistant/message") (cons 'seq 1)
           (cons 'data (list (cons 'message
                                   (list (cons 'content
                                               (vector (list (cons 'type "text")
                                                             (cons 'text "msg-one"))))))))))
    (dsh-emacs-render-event
     (list (cons 'type "assistant/message") (cons 'seq 2)
           (cons 'data (list (cons 'message
                                   (list (cons 'content
                                               (vector (list (cons 'type "text")
                                                             (cons 'text "msg-two"))))))))))
    (let ((txt (buffer-substring-no-properties (point-min) (point-max)))
          (goal-sig "Seam check"))
      (ert-info ((format "%s" "composer-messages-stay-above-goal-row"))
        (should (let ((g1 (string-match "msg-one" txt))
                      (g2 (string-match "msg-two" txt))
                      (g (string-match goal-sig txt)))
                  (and g1 g2 g (< g1 g2) (< g2 g))))
        (should (let ((g (string-match goal-sig txt))
                      (p (string-match "❯" txt)))
                  (and g p (< g p))))))))

;; --- Composer Goal Row: a nil projection removes chrome, not transcript ---
(ert-deftest dsh-emacs-test-composer-composer-goal-clear-removes-row-keeps-transcript ()
  :tags '(dsh-unit)
  (with-temp-buffer
    (dsh-emacs-mode)
    (dsh-emacs-modeline-setup)
    (dsh-emacs-composer-set-goal
     (dsh-protocol-goal-projection--from-alist
      (list (cons 'goal (list (cons 'objective "To clear")
                              (cons 'phase "active"))))))
    (dsh-emacs-render-event
     (list (cons 'type "assistant/message") (cons 'seq 1)
           (cons 'data (list (cons 'message
                                   (list (cons 'content
                                               (vector (list (cons 'type "text")
                                                             (cons 'text "keep-me"))))))))))
    (dsh-emacs-composer-set-goal nil)
    (let ((txt (buffer-substring-no-properties (point-min) (point-max))))
      (ert-info ((format "%s" "composer-goal-clear-removes-row-keeps-transcript"))
        (should (null (markerp dsh-emacs--composer-top-marker)))
        (should (null (string-match-p "To clear" txt)))
        (should (string-match-p "keep-me" txt))))))

;; --- Composer Goal Row: idempotent text and in-place projection updates ---
(ert-deftest dsh-emacs-test-composer-composer-goal-idempotent-same-text ()
  :tags '(dsh-unit)
  (with-temp-buffer
    (dsh-emacs-mode)
    (dsh-emacs-modeline-setup)
    (dsh-emacs-composer-set-goal
     (dsh-protocol-goal-projection--from-alist
      (list (cons 'goal (list (cons 'objective "v1") (cons 'phase "active"))))))
    (let ((first-marker (copy-marker (marker-position dsh-emacs--composer-top-marker))))
      ;; Reapplying identical text is idempotent and does not move the marker.
      (dsh-emacs-composer-set-goal
       (dsh-protocol-goal-projection--from-alist
        (list (cons 'goal (list (cons 'objective "v1") (cons 'phase "active"))))))
      (ert-info ((format "%s" "composer-goal-idempotent-same-text"))
        (should (= (marker-position first-marker)
                   (marker-position dsh-emacs--composer-top-marker))))
      ;; Replacing the objective updates the same single row.
      (dsh-emacs-composer-set-goal
       (dsh-protocol-goal-projection--from-alist
        (list (cons 'goal (list (cons 'objective "v2 now") (cons 'phase "paused"))))))
      (let ((txt (buffer-substring-no-properties (point-min) (point-max))))
        (ert-info ((format "%s" "composer-goal-update-replaces-row"))
          (should (null (string-match-p "v1" txt)))
          (should (string-match-p "v2 now" txt))
          (should (string-match-p "Paused Goal" txt))
          (should (markerp dsh-emacs--composer-top-marker)))))))

;; --- Composer Goal Row: route event projections to the live chat buffer ---
(ert-deftest dsh-emacs-test-composer-composer-projection-routes-to-chat ()
  :tags '(dsh-unit)
  (let* ((session-id "sess-composer-1")
         (goal (dsh-protocol-goal-projection--from-alist
                '((goal . ((objective . "route me") (phase . "active"))))))
         (chat (generate-new-buffer " *t-composer-chat*")))
    (unwind-protect
        (progn
          (puthash session-id chat dsh-emacs--chat-buffers)
          (with-current-buffer chat
            (dsh-emacs-mode)
            (dsh-emacs-modeline-setup))
          (dsh-emacs-events--apply-goal-projection session-id goal)
          (with-current-buffer chat
            (ert-info ((format "%s" "composer-projection-routes-to-chat"))
              (should (string-match-p "route me"
                                      (buffer-substring-no-properties
                                       (point-min) (point-max))))
              (should (markerp dsh-emacs--composer-top-marker))))
          ;; A null projection clears that session's Goal Row.
          (dsh-emacs-events--apply-goal-projection session-id nil)
          (with-current-buffer chat
            (ert-info ((format "%s" "composer-projection-null-clears"))
              (should (null (string-match-p "route me"
                                            (buffer-substring-no-properties
                                             (point-min) (point-max))))))))
      (remhash session-id dsh-emacs--chat-buffers)
      (when (buffer-live-p chat) (kill-buffer chat)))))

;; --- Composer Goal Row: nil in a control baseline is a clear tombstone ---
(ert-deftest dsh-emacs-test-composer-composer-control-baseline-nil-clears ()
  :tags '(dsh-unit)
  (let* ((session-id "sess-composer-baseline-nil")
         (chat (generate-new-buffer " *t-composer-baseline-nil*")))
    (unwind-protect
        (progn
          (puthash session-id chat dsh-emacs--chat-buffers)
          (with-current-buffer chat
            (dsh-emacs-mode)
            (dsh-emacs-modeline-setup)
            (dsh-emacs-composer-set-goal
             (dsh-protocol-goal-projection--from-alist
              (list (cons 'goal (list (cons 'objective "stale baseline goal")
                                      (cons 'phase "active")))))))
          (dsh-emacs-events--host-control-baseline
           nil
           (list (cons 'projections
                       (list (cons session-id
                                   (list (cons 'values
                                               (list (cons 'goal nil)))))))))
          (with-current-buffer chat
            (ert-info ((format "%s" "composer-control-baseline-nil-clears"))
              (should (null dsh-emacs--composer-goal))
              (should (null (string-match-p
                             "stale baseline goal"
                             (buffer-substring-no-properties (point-min) (point-max))))))))
      (remhash session-id dsh-emacs--chat-buffers)
      (when (buffer-live-p chat) (kill-buffer chat)))))

;; --- session/control baseline seeds the queue mirror through the `inbox'
;; --- projection cell (the dedicated `queues' record is gone since 0.1.7) ---
(ert-deftest dsh-emacs-test-composer-control-baseline-seeds-inbox-mirror ()
  :tags '(dsh-unit)
  (let* ((session-id "sess-baseline-inbox")
         (chat (generate-new-buffer " *t-baseline-inbox*"))
         (inbox (list (cons 'next-turn
                            (vector (dsh-emacs-test--inbox-message "bn1" "seeded")))
                      (cons 'next-step
                            (vector (dsh-emacs-test--inbox-message
                                     "bs1" "steer me")))))
         (baseline (list (cons 'projections
                               (list (cons session-id
                                           (list (cons 'asOfSeq 7)
                                                 (cons 'values
                                                       (list (cons 'inbox inbox)))))))))
         (announced nil))
    (unwind-protect
        (progn
          (puthash session-id chat dsh-emacs--chat-buffers)
          (with-current-buffer chat
            (dsh-emacs-mode)
            (setq-local dsh-emacs--buffer-session session-id))
          (cl-letf (((symbol-function 'dsh-emacs-queue--announce)
                     (lambda (_events) (setq announced t))))
            ;; Exercise the real JSON boundary: record keys decode as symbols,
            ;; whereas chat buffers are indexed by string session ids.
            (dsh-emacs-events--host-dispatch
             'proc-baseline
             (json-encode
              `((type . "item") (streamId . "control")
                (value . ((type . "baseline") (value . ,baseline))))))
            (with-current-buffer chat
              (ert-info ((format "%s" "control-baseline-seeds-inbox-mirror"))
                (should (equal '("bn1" "bs1")
                               (mapcar #'dsh-protocol-queue-item-id dsh-emacs--queue-items)))
                (should (equal '(queued steering)
                               (mapcar #'dsh-protocol-queue-item-placement
                                       dsh-emacs--queue-items)))
                (should (eq 'proc-baseline dsh-emacs--queue-process)))
              ;; The baseline IS the connect-time snapshot: it seeds silently.
              (ert-info ((format "%s" "control-baseline-inbox-seed-is-silent"))
                (should (null announced))))))
      (remhash session-id dsh-emacs--chat-buffers)
      (when (buffer-live-p chat) (kill-buffer chat)))))

;; --- session/control baseline replaces a stale mirror on reconnect ---
;; A reconnect's baseline arrives on a NEW process.  The empty `inbox' cell of
;; a session with nothing pending must replace the previous connection's items
;; (silently — it is the connect-time snapshot), not leave them behind: that is
;; what "a reconnect restores the pending queue from the baseline" means in the
;; common case where the queue is empty.
(ert-deftest dsh-emacs-test-composer-control-baseline-replaces-stale-inbox-mirror ()
  :tags '(dsh-unit)
  (let* ((old-chats dsh-emacs--chat-buffers)
         (session-id "sess-baseline-empty")
         (chat (generate-new-buffer " *t-baseline-empty*"))
         (baseline (list (cons 'projections
                               (list (cons session-id
                                           (list (cons 'values
                                                       (list (cons 'inbox
                                                                   (list (cons 'next-turn [])
                                                                         (cons 'next-step [])))))))))))
         (announced nil))
    (unwind-protect
        (progn
          (setq dsh-emacs--chat-buffers
                (let ((h (make-hash-table :test 'equal)))
                  (puthash session-id chat h)
                  h))
          (with-current-buffer chat
            (dsh-emacs-mode)
            (setq-local dsh-emacs--buffer-session session-id)
            ;; Items left by the previous connection's process.
            (dsh-emacs-queue-apply chat 'proc-old
                                   (list (dsh-emacs-test--queue-item
                                          "stale" "queued" "stale"))))
          (cl-letf (((symbol-function 'dsh-emacs-queue--announce)
                     (lambda (_events) (setq announced t))))
            (dsh-emacs-events--host-dispatch
             'proc-new
             (json-encode
              `((type . "item") (streamId . "control")
                (value . ((type . "baseline") (value . ,baseline))))))
            (with-current-buffer chat
              (ert-info ((format "%s" "control-baseline-replaces-stale-inbox-mirror"))
                (should (null dsh-emacs--queue-items))
                (should (eq 'proc-new dsh-emacs--queue-process))
                (should (null announced))))))
      (remhash session-id dsh-emacs--chat-buffers)
      (when (buffer-live-p chat) (kill-buffer chat)))))

;; --- Composer Goal Row: hide complete goals, matching dsh web ---
(ert-deftest dsh-emacs-test-composer-composer-goal-active-shown ()
  :tags '(dsh-unit)
  (with-temp-buffer
    (dsh-emacs-mode)
    (dsh-emacs-modeline-setup)
    (dsh-emacs-composer-set-goal
     (dsh-protocol-goal-projection--from-alist
      (list (cons 'goal (list (cons 'objective "Shown active")
                              (cons 'phase "active"))))))
    ;; Active goals are visible.
    (ert-info ((format "%s" "composer-goal-active-shown"))
      (should (string-match-p "Shown active"
                              (buffer-substring-no-properties (point-min) (point-max))))
      (should (markerp dsh-emacs--composer-top-marker)))
    ;; A complete projection hides the row.
    (dsh-emacs-composer-set-goal
     (dsh-protocol-goal-projection--from-alist
      (list (cons 'goal (list (cons 'objective "Shown active")
                              (cons 'phase "complete"))))))
    (ert-info ((format "%s" "composer-goal-complete-hidden"))
      (should (null (markerp dsh-emacs--composer-top-marker)))
      (should (null (string-match-p "Shown active"
                                    (buffer-substring-no-properties (point-min) (point-max))))))))

;; --- Composer Goal Row: a goal already complete is never shown ---
(ert-deftest dsh-emacs-test-composer-composer-goal-complete-never-shown ()
  :tags '(dsh-unit)
  (with-temp-buffer
    (dsh-emacs-mode)
    (dsh-emacs-modeline-setup)
    (dsh-emacs-composer-set-goal
     (dsh-protocol-goal-projection--from-alist
      (list (cons 'goal (list (cons 'objective "Never shown")
                              (cons 'phase "complete"))))))
    (ert-info ((format "%s" "composer-goal-complete-never-shown"))
      (should (null (markerp dsh-emacs--composer-top-marker)))
      (should (null (string-match-p "Never shown"
                                    (buffer-substring-no-properties (point-min) (point-max))))))))

;; --- Composer Goal Row: reflow the same goal after a width change ---
(ert-deftest dsh-emacs-test-composer-composer-goal-reflows-after-window-change ()
  :tags '(dsh-unit)
  (with-temp-buffer
    (dsh-emacs-mode)
    (dsh-emacs-modeline-setup)
    (let ((row-width 80))
      (cl-letf (((symbol-function 'dsh-emacs-composer--row-width)
                 (lambda () row-width)))
        (dsh-emacs-composer-set-goal
         (dsh-protocol-goal-projection--from-alist
          (list (cons 'goal
                      (list (cons 'objective
                                  "A long objective whose rendered width must change")
                            (cons 'phase "active"))))))
        (let ((wide (buffer-substring-no-properties (point-min) (point-max))))
          (setq row-width 40)
          (dsh-emacs-composer--window-configuration-change)
          (let ((narrow (buffer-substring-no-properties (point-min) (point-max))))
            (ert-info ((format "%s" "composer-goal-reflows-after-window-change"))
              (should (not (equal wide narrow)))
              (should (string-match-p "…" narrow)))))))))

;; --- Composer Goal Row: paused and blocked goals remain visible ---
(ert-deftest dsh-emacs-test-composer-composer-goal-paused-shown ()
  :tags '(dsh-unit)
  (with-temp-buffer
    (dsh-emacs-mode)
    (dsh-emacs-modeline-setup)
    (dsh-emacs-composer-set-goal
     (dsh-protocol-goal-projection--from-alist
      (list (cons 'goal (list (cons 'objective "Paused goal")
                              (cons 'phase "paused"))))))
    (ert-info ((format "%s" "composer-goal-paused-shown"))
      (should (markerp dsh-emacs--composer-top-marker))
      (should (string-match-p "Paused goal"
                              (buffer-substring-no-properties (point-min) (point-max)))))))

;; --- Goal actions: pause wire payload and CAS ref ---
(ert-deftest dsh-emacs-test-composer-goal-pause-payload-ref-cas ()
  :tags '(dsh-unit)
  (let ((sent nil))
    (with-temp-buffer
      (dsh-emacs-mode)
      (dsh-emacs-modeline-setup)
      (setq-local dsh-emacs--buffer-session "sess-gact")
      (dsh-emacs-composer-set-goal
       (dsh-protocol-goal-projection--from-alist
        (list (cons 'goal (list (cons 'id "goal-1")
                                (cons 'revision 7)
                                (cons 'objective "Active goal")
                                (cons 'phase "active"))))))
      (cl-letf (((symbol-function 'dsh-emacs--rpc-async)
                 (lambda (method params cb)
                   (push (list method params) sent)
                   (funcall cb t
                            (list (cons 'id "goal-1")
                                  (cons 'revision 8)
                                  (cons 'objective "Active goal")
                                  (cons 'phase "paused"))))))
        (dsh-emacs-goal-pause))
      (let ((call (car sent)))
        (ert-info ((format "%s" "goal-pause-payload-ref-cas"))
          (should (equal (nth 0 call) "goals/pause"))
          (should (equal (nth 1 call)
                         '((agentId . "sess-gact")
                           (ref . ((id . "goal-1") (revision . 7))))))))
      ;; A successful callback optimistically updates the row to paused.
      (ert-info ((format "%s" "goal-pause-optimistic-view"))
        (should (string-match-p "Paused Goal"
                                (buffer-substring-no-properties (point-min) (point-max))))))))

;; --- Goal actions: pause is gated to the active phase ---
(ert-deftest dsh-emacs-test-composer-goal-pause-gated-on-active ()
  :tags '(dsh-unit)
  (let ((sent nil))
    (with-temp-buffer
      (dsh-emacs-mode)
      (dsh-emacs-modeline-setup)
      (setq-local dsh-emacs--buffer-session "sess-gpaused")
      (dsh-emacs-composer-set-goal
       (dsh-protocol-goal-projection--from-alist
        (list (cons 'goal (list (cons 'id "g-paused")
                                (cons 'revision 2)
                                (cons 'objective "Paused g")
                                (cons 'phase "paused"))))))
      (cl-letf (((symbol-function 'dsh-emacs--rpc-async)
                 (lambda (_m _p _cb) (push t sent))))
        (dsh-emacs-goal-pause))
      (ert-info ((format "%s" "goal-pause-gated-on-active"))
        (should (null sent))))))

;; --- Goal actions: an active goal cannot resume ---
(ert-deftest dsh-emacs-test-composer-goal-resume-gated-on-paused ()
  :tags '(dsh-unit)
  (let ((sent nil))
    (with-temp-buffer
      (dsh-emacs-mode)
      (dsh-emacs-modeline-setup)
      (setq-local dsh-emacs--buffer-session "sess-gactive")
      (dsh-emacs-composer-set-goal
       (dsh-protocol-goal-projection--from-alist
        (list (cons 'goal (list (cons 'id "g-active")
                                (cons 'revision 4)
                                (cons 'objective "Active g")
                                (cons 'phase "active"))))))
      (cl-letf (((symbol-function 'dsh-emacs--rpc-async)
                 (lambda (_m _p _cb) (push t sent))))
        (dsh-emacs-goal-resume))
      (ert-info ((format "%s" "goal-resume-gated-on-paused"))
        (should (null sent))))))

;; --- Goal actions: resume moves paused to active ---
(ert-deftest dsh-emacs-test-composer-goal-resume-payload ()
  :tags '(dsh-unit)
  (let ((sent nil))
    (with-temp-buffer
      (dsh-emacs-mode)
      (dsh-emacs-modeline-setup)
      (setq-local dsh-emacs--buffer-session "sess-gresume")
      (dsh-emacs-composer-set-goal
       (dsh-protocol-goal-projection--from-alist
        (list (cons 'goal (list (cons 'id "g2") (cons 'revision 3)
                                (cons 'objective "Paused goal")
                                (cons 'phase "paused"))))))
      (cl-letf (((symbol-function 'dsh-emacs--rpc-async)
                 (lambda (method params cb)
                   (push (list method params) sent)
                   (funcall cb t
                            (list (cons 'id "g2")
                                  (cons 'revision 4)
                                  (cons 'objective "Paused goal")
                                  (cons 'phase "active"))))))
        (dsh-emacs-goal-resume))
      (ert-info ((format "%s" "goal-resume-payload"))
        (should (equal (car sent)
                       '("goals/resume"
                         ((agentId . "sess-gresume")
                          (ref . ((id . "g2") (revision . 3)))))))
        (should (string-match-p "Ongoing Goal"
                                (buffer-substring-no-properties (point-min) (point-max))))))))

;; --- Goal actions: edit reads and sends request.objective ---
(ert-deftest dsh-emacs-test-composer-goal-edit-request-objective ()
  :tags '(dsh-unit)
  (let ((sent nil)
        (edit-result nil))
    (with-temp-buffer
      (dsh-emacs-mode)
      (dsh-emacs-modeline-setup)
      (setq-local dsh-emacs--buffer-session "sess-gedit")
      (dsh-emacs-composer-set-goal
       (dsh-protocol-goal-projection--from-alist
        (list (cons 'goal (list (cons 'id "g3") (cons 'revision 5)
                                (cons 'objective "old objective")
                                (cons 'phase "active"))))))
      (cl-letf (((symbol-function 'dsh-emacs--rpc-async)
                 (lambda (method params cb)
                   (push (list method params) sent)
                   (funcall cb t
                            (list (cons 'id "g3")
                                  (cons 'revision 6)
                                  (cons 'objective "new objective")
                                  (cons 'phase "active"))))))
        ;; Stub `read-string' because batch mode has no minibuffer input.
        (cl-letf (((symbol-function 'read-string)
                   (lambda (&rest _) "new objective")))
          (setq edit-result (dsh-emacs-goal-edit))))
      (let ((call (car sent)))
        (ert-info ((format "%s" "goal-edit-request-objective"))
          (should (equal (nth 0 call) "goals/edit"))
          (should (equal (nth 1 call)
                         '((agentId . "sess-gedit")
                           (ref . ((id . "g3") (revision . 5)))
                           (request . ((objective . "new objective"))))))))
      (ert-info ((format "%s" "goal-edit-optimistic-view"))
        (should (string-match-p "new objective"
                                (buffer-substring-no-properties (point-min) (point-max))))))))

;; --- Goal actions: clear sends a tombstone and removes the row ---
(ert-deftest dsh-emacs-test-composer-goal-clear-payload ()
  :tags '(dsh-unit)
  (let ((sent nil))
    (with-temp-buffer
      (dsh-emacs-mode)
      (dsh-emacs-modeline-setup)
      (setq-local dsh-emacs--buffer-session "sess-gclear")
      (dsh-emacs-composer-set-goal
       (dsh-protocol-goal-projection--from-alist
        (list (cons 'goal (list (cons 'id "g4") (cons 'revision 9)
                                (cons 'objective "Clear me")
                                (cons 'phase "active"))))))
      (cl-letf (((symbol-function 'dsh-emacs--rpc-async)
                 (lambda (method params cb)
                   (push (list method params) sent)
                   (funcall cb t (list (cons 'id "g4") (cons 'revision 10)))))
                ((symbol-function 'y-or-n-p) (lambda (&rest _) t)))
        (dsh-emacs-goal-clear))
      (let ((call (car sent)))
        (ert-info ((format "%s" "goal-clear-payload"))
          (should (equal (nth 0 call) "goals/clear"))
          (should (equal (nth 1 call)
                         '((agentId . "sess-gclear")
                           (ref . ((id . "g4") (revision . 9))))))))
      (ert-info ((format "%s" "goal-clear-removes-row"))
        (should (null (markerp dsh-emacs--composer-top-marker)))
        (should (null (string-match-p "Clear me"
                                      (buffer-substring-no-properties (point-min) (point-max)))))))))

;; --- Goal actions: RPC failure reports an error and preserves the row ---
(ert-deftest dsh-emacs-test-composer-goal-action-error-keeps-row ()
  :tags '(dsh-unit)
  (let ((sent nil))
    (with-temp-buffer
      (dsh-emacs-mode)
      (dsh-emacs-modeline-setup)
      (setq-local dsh-emacs--buffer-session "sess-gerr")
      (dsh-emacs-composer-set-goal
       (dsh-protocol-goal-projection--from-alist
        (list (cons 'goal (list (cons 'id "g-error")
                                (cons 'revision 4)
                                (cons 'objective "Keep me")
                                (cons 'phase "active"))))))
      (cl-letf (((symbol-function 'dsh-emacs--rpc-async)
                 (lambda (_m _p cb)
                   (push t sent)
                   (funcall cb nil '((message . "stale revision"))))))
        (dsh-emacs-goal-pause))
      (ert-info ((format "%s" "goal-action-error-keeps-row"))
        (should (markerp dsh-emacs--composer-top-marker))
        (should (string-match-p "Keep me"
                                (buffer-substring-no-properties (point-min) (point-max))))))))

;; --- Goal actions: the pending guard prevents a second CAS ---
(ert-deftest dsh-emacs-test-composer-goal-action-pending-guard ()
  :tags '(dsh-unit)
  (let ((sent 0))
    (with-temp-buffer
      (dsh-emacs-mode)
      (dsh-emacs-modeline-setup)
      (setq-local dsh-emacs--buffer-session "sess-gpend")
      (dsh-emacs-composer-set-goal
       (dsh-protocol-goal-projection--from-alist
        (list (cons 'goal (list (cons 'id "g-pending")
                                (cons 'revision 1)
                                (cons 'objective "Once")
                                (cons 'phase "active"))))))
      (setq dsh-emacs--composer-goal-pending t)
      (cl-letf (((symbol-function 'dsh-emacs--rpc-async)
                 (lambda (_m _p _cb) (cl-incf sent))))
        (dsh-emacs-goal-pause)
        (dsh-emacs-goal-resume))
      (ert-info ((format "%s" "goal-action-pending-guard"))
        (should (zerop sent))))))

;; --- Goal actions: an older HTTP response cannot regress a newer projection ---
(ert-deftest dsh-emacs-test-composer-goal-action-stale-response-keeps-newer-projection ()
  :tags '(dsh-unit)
  (let (callback)
    (with-temp-buffer
      (dsh-emacs-mode)
      (dsh-emacs-modeline-setup)
      (setq-local dsh-emacs--buffer-session "sess-grace")
      (dsh-emacs-composer-set-goal
       (dsh-protocol-goal-projection--from-alist
        (list (cons 'goal (list (cons 'id "g-race")
                                (cons 'revision 7)
                                (cons 'objective "Before")
                                (cons 'phase "active"))))))
      (cl-letf (((symbol-function 'dsh-emacs--rpc-async)
                 (lambda (_method _params cb) (setq callback cb))))
        (dsh-emacs-goal-pause))
      ;; The authoritative stream advances twice before the rev-8 HTTP response.
      (dsh-emacs-composer-set-goal
       (dsh-protocol-goal-projection--from-alist
        (list (cons 'goal (list (cons 'id "g-race")
                                (cons 'revision 9)
                                (cons 'objective "Newer projection")
                                (cons 'phase "active"))))))
      (funcall callback t
               (list (cons 'id "g-race")
                     (cons 'revision 8)
                     (cons 'objective "Older response")
                     (cons 'phase "paused")))
      (ert-info ((format "%s" "goal-action-stale-response-keeps-newer-projection"))
        (should (equal (dsh-protocol-goal-revision dsh-emacs--composer-goal) 9))
        (should (equal (dsh-protocol-goal-objective dsh-emacs--composer-goal)
                       "Newer projection"))
        (should (null dsh-emacs--composer-goal-pending))))))

;; A callback from before a reset must not clear a newer request's guard.
(ert-deftest dsh-emacs-test-composer-goal-action-late-callback-keeps-newer-pending-guard ()
  :tags '(dsh-unit)
  (let (callback)
    (with-temp-buffer
      (dsh-emacs-mode)
      (dsh-emacs-modeline-setup)
      (setq-local dsh-emacs--buffer-session "sess-glate")
      (dsh-emacs-composer-set-goal
       (dsh-protocol-goal-projection--from-alist
        (list (cons 'goal (list (cons 'id "g-late")
                                (cons 'revision 2)
                                (cons 'objective "Still current")
                                (cons 'phase "active"))))))
      (cl-letf (((symbol-function 'dsh-emacs--rpc-async)
                 (lambda (_method _params cb) (setq callback cb))))
        (dsh-emacs-goal-pause))
      (let ((newer-token (list "pause")))
        ;; The same verb still needs a distinct request identity after reset.
        (should (equal dsh-emacs--composer-goal-pending newer-token))
        (should-not (eq dsh-emacs--composer-goal-pending newer-token))
        (setq dsh-emacs--composer-goal-pending newer-token)
        (funcall callback t
                 (list (cons 'id "g-late")
                       (cons 'revision 3)
                       (cons 'objective "Late response")
                       (cons 'phase "paused")))
        (ert-info ((format "%s" "goal-action-late-callback-keeps-newer-pending-guard"))
          (should (eq dsh-emacs--composer-goal-pending newer-token))
          (should (equal (dsh-protocol-goal-objective dsh-emacs--composer-goal)
                         "Still current")))))))

;; --- Goal actions: the strip exposes the phase-appropriate toggle ---
;; Assert keymap properties rather than glyph text because SVG cells use images.
(defun dsh-test-goal-strip-binds (strip cmd)
  "Return non-nil when some char in STRIP binds CMD on its mouse-1 keymap."
  (let ((i 0) (ok nil))
    (while (and (not ok) (< i (length strip)))
      (let* ((map (get-text-property i 'keymap strip))
             (bound (and map (lookup-key map [mouse-1]))))
        (when (eq bound cmd) (setq ok t)))
      (setq i (1+ i)))
    ok))

(ert-deftest dsh-emacs-test-composer-goal-strip-active-offers-pause ()
  :tags '(dsh-unit)
  (ert-info ((format "%s" "goal-strip-active-offers-pause"))
    (should (let* ((goal (dsh-protocol-goal-projection--from-alist
                          (list (cons 'goal (list (cons 'objective "A")
                                                  (cons 'phase "active"))))))
                   (strip (car (dsh-emacs-composer--goal-action-strip goal))))
              (and strip
                   (dsh-test-goal-strip-binds strip 'dsh-emacs-goal-pause)
                   (not (dsh-test-goal-strip-binds strip 'dsh-emacs-goal-resume)))))))

(ert-deftest dsh-emacs-test-composer-goal-strip-paused-offers-resume ()
  :tags '(dsh-unit)
  (ert-info ((format "%s" "goal-strip-paused-offers-resume"))
    (should (let* ((goal (dsh-protocol-goal-projection--from-alist
                          (list (cons 'goal (list (cons 'objective "A")
                                                  (cons 'phase "paused"))))))
                   (strip (car (dsh-emacs-composer--goal-action-strip goal))))
              (and strip
                   (dsh-test-goal-strip-binds strip 'dsh-emacs-goal-resume)
                   (not (dsh-test-goal-strip-binds strip 'dsh-emacs-goal-pause)))))))

;; Blocked/complete goals have no toggle but retain edit and clear.
(ert-deftest dsh-emacs-test-composer-goal-strip-nontoggle-still-edit-clear ()
  :tags '(dsh-unit)
  (dolist (phase '("blocked" "complete"))
    (let ((goal (dsh-protocol-goal-projection--from-alist
                 (list (cons 'goal (list (cons 'objective "A")
                                         (cons 'phase phase)))))))
      (let ((strip (car (dsh-emacs-composer--goal-action-strip goal))))
        (ert-info ((format "%s" "goal-strip-nontoggle-still-edit-clear"))
          (should (and strip
                       (not (dsh-test-goal-strip-binds strip 'dsh-emacs-goal-pause))
                       (not (dsh-test-goal-strip-binds strip 'dsh-emacs-goal-resume))
                       (dsh-test-goal-strip-binds strip 'dsh-emacs-goal-edit)
                       (dsh-test-goal-strip-binds strip 'dsh-emacs-goal-clear))))))))

;; --- Goal actions: C-c C-g prefix bindings ---
(ert-deftest dsh-emacs-test-composer-goal-keymap-binds-verbs ()
  :tags '(dsh-unit)
  (ert-info ((format "%s" "goal-keymap-binds-verbs"))
    (should (eq (lookup-key dsh-emacs-goal-map (kbd "p")) #'dsh-emacs-goal-pause))
    (should (eq (lookup-key dsh-emacs-goal-map (kbd "r")) #'dsh-emacs-goal-resume))
    (should (eq (lookup-key dsh-emacs-goal-map (kbd "e")) #'dsh-emacs-goal-edit))
    (should (eq (lookup-key dsh-emacs-goal-map (kbd "d")) #'dsh-emacs-goal-clear))
    (should (eq (lookup-key dsh-emacs-goal-map (kbd "a")) #'dsh-emacs-goal-actions-toggle))))

;; --- Goal actions: row keymaps point to the correct commands ---
;; Find the edit-bound cell by keymap because SVG cells have no fallback text.
(defun dsh-test-goal-row-edit-cell ()
  "Return the buffer position whose cell binds `dsh-emacs-goal-edit', or nil."
  (let ((i (point-min)) (found nil))
    (while (and (not found) (< i (point-max)))
      (let ((map (get-text-property i 'keymap)))
        (when (and map (eq (lookup-key map [mouse-1]) 'dsh-emacs-goal-edit))
          (setq found i)))
      (setq i (1+ i)))
    found))

(ert-deftest dsh-emacs-test-composer-goal-row-action-click-region ()
  :tags '(dsh-unit)
  (with-temp-buffer
    (dsh-emacs-mode)
    (dsh-emacs-modeline-setup)
    (dsh-emacs-composer-set-goal
     (dsh-protocol-goal-projection--from-alist
      (list (cons 'goal (list (cons 'objective "clickable")
                              (cons 'phase "active"))))))
    (let ((edit-pos (dsh-test-goal-row-edit-cell)))
      (ert-info ((format "%s" "goal-row-action-click-region"))
        (should (and edit-pos
                     (eq (lookup-key (get-text-property edit-pos 'keymap) [mouse-1])
                         'dsh-emacs-goal-edit)
                     (eq (lookup-key (get-text-property edit-pos 'keymap) (kbd "RET"))
                         'dsh-emacs-goal-edit)
                     (get-text-property edit-pos 'mouse-face)
                     ;; SVG uses a display image; fallback text retains the same keymap.
                     (if (and (display-graphic-p)
                              (image-type-available-p 'svg))
                         (get-text-property edit-pos 'display)
                       t)))))))

;; --- Goal actions: disabling inline actions yields an empty strip ---
(ert-deftest dsh-emacs-test-composer-goal-actions-option-off-hides-strip ()
  :tags '(dsh-unit)
  (let ((goal (dsh-protocol-goal-projection--from-alist
               (list (cons 'goal (list (cons 'objective "A")
                                       (cons 'phase "active")))))))
    (let ((dsh-emacs-composer-goal-actions nil))
      (ert-info ((format "%s" "goal-actions-option-off-hides-strip"))
        (should (null (dsh-emacs-composer--goal-action-strip goal)))))
    (let ((dsh-emacs-composer-goal-actions t))
      (ert-info ((format "%s" "goal-actions-option-on-shows-strip"))
        (should (dsh-emacs-composer--goal-action-strip goal))))))

;; --- Goal actions: the option and toggle repaint inline actions ---
(ert-deftest dsh-emacs-test-composer-goal-toggle-renders-actions-on ()
  :tags '(dsh-unit)
  (let ((buf (generate-new-buffer " *t-goal-toggle*"))
        (default-before (default-value 'dsh-emacs-composer-goal-actions)))
    (unwind-protect
        (with-current-buffer buf
          (dsh-emacs-mode)
          (dsh-emacs-modeline-setup)
          (dsh-emacs-composer-set-goal
           (dsh-protocol-goal-projection--from-alist
            (list (cons 'goal (list (cons 'objective "toggle me")
                                    (cons 'phase "active"))))))
          (ert-info ((format "%s" "goal-toggle-renders-actions-on"))
            (should (not (null (dsh-test-goal-row-edit-cell)))))
          ;; Disable and repaint: no action cells remain.
          (setq-local dsh-emacs-composer-goal-actions nil)
          (dsh-emacs-composer-refresh)
          (ert-info ((format "%s" "goal-toggle-refresh-hides-actions"))
            (should (null (dsh-test-goal-row-edit-cell))))
          ;; The interactive command toggles and repaints.
          (dsh-emacs-goal-actions-toggle)
          (ert-info ((format "%s" "goal-actions-toggle-turns-back-on"))
            (should dsh-emacs-composer-goal-actions)
            (should (local-variable-p 'dsh-emacs-composer-goal-actions))
            (should (eq (default-value 'dsh-emacs-composer-goal-actions) default-before))
            (should (not (null (dsh-test-goal-row-edit-cell))))))
      (when (buffer-live-p buf) (kill-buffer buf)))))

(ert-deftest dsh-emacs-test-composer-goal-action-fallbacks-avoid-emoji ()
  :tags '(dsh-unit)
  (ert-info ((format "%s" "goal-action-fallbacks-avoid-emoji"))
    (should (equal "||" (car (dsh-emacs-composer--goal-action-spec 'pause))))
    (should (equal "▶" (car (dsh-emacs-composer--goal-action-spec 'resume))))
    (should (equal "✎" (car (dsh-emacs-composer--goal-action-spec 'edit))))
    (should (equal "✕" (car (dsh-emacs-composer--goal-action-spec 'clear)))))
  (ert-info ((format "%s" "queue-delete-fallback-is-x"))
    (cl-letf (((symbol-function 'image-type-available-p) (lambda (_type) nil)))
      (let ((cell (dsh-emacs-composer--next-cell
                   (dsh-emacs-test--queue-item "q1" "queued" "Alpha")
                   'delete)))
        (should cell)
        (should (string-prefix-p "✕" (substring-no-properties cell)))))))

;; --- Goal actions: toggling outside chat creates no local override ---
(ert-deftest dsh-emacs-test-composer-goal-actions-toggle-outside-chat-errors-cleanly ()
  :tags '(dsh-unit)
  (with-temp-buffer
    (let ((errored nil))
      (condition-case nil
          (dsh-emacs-goal-actions-toggle)
        (user-error (setq errored t)))
      (ert-info ((format "%s" "goal-actions-toggle-outside-chat-errors-cleanly"))
        (should errored)
        (should (not (local-variable-p 'dsh-emacs-composer-goal-actions)))))))

;; Editing must preserve the source objective, including embedded newlines.
(ert-deftest dsh-emacs-test-composer-goal-edit-preserves-source-objective ()
  :tags '(dsh-unit)
  (with-temp-buffer
    (dsh-emacs-mode)
    (setq-local dsh-emacs--buffer-session "goal-edit-source")
    (dsh-emacs-composer-set-goal
     (dsh-protocol-goal-projection--from-alist
      '((goal . ((id . "g") (revision . 1) (phase . "active")
                 (objective . "first\nsecond"))))))
    (let (initial sent)
      (cl-letf (((symbol-function 'read-string)
                 (lambda (_prompt value &rest _args)
                   (setq initial value) value))
                ((symbol-function 'dsh-emacs--rpc-async)
                 (lambda (_method params _callback) (setq sent params))))
        (dsh-emacs-goal-edit))
      (ert-info ((format "%s" "goal-edit-preserves-source-objective"))
        (should (equal initial "first\nsecond"))
        (should (equal (cdr (assq 'objective (cdr (assq 'request sent))))
                       "first\nsecond"))))))

;; Pending state must be visible immediately and disappear on failure.
(ert-deftest dsh-emacs-test-composer-goal-pending-visible-without-actions ()
  :tags '(dsh-unit)
  (with-temp-buffer
    (dsh-emacs-mode)
    (setq-local dsh-emacs--buffer-session "goal-pending-feedback")
    (dsh-emacs-composer-set-goal
     (dsh-protocol-goal-projection--from-alist
      '((goal . ((id . "g") (revision . 1) (phase . "active")
                 (objective . "Work"))))))
    (let (callback)
      (cl-letf (((symbol-function 'dsh-emacs--rpc-async)
                 (lambda (_method _params cb) (setq callback cb))))
        (dsh-emacs-goal-pause))
      (ert-info ((format "%s" "goal-pending-visible-without-actions"))
        (should (string-match-p "Pausing" (buffer-string)))
        (should (null (dsh-test-goal-row-edit-cell))))
      (funcall callback nil "offline")
      (ert-info ((format "%s" "goal-pending-failure-restores-controls"))
        (should (not (string-match-p "Pausing" (buffer-string))))
        (should (dsh-test-goal-row-edit-cell))))))

;; Full details remain reachable even when the compact row is truncated.
(ert-deftest dsh-emacs-test-composer-goal-details-preserve-objective-and-explain-block ()
  :tags '(dsh-unit)
  (with-temp-buffer
    (dsh-emacs-mode)
    (dsh-emacs-composer-set-goal
     (dsh-protocol-goal-projection--from-alist
      '((goal . ((id . "details") (revision . 2) (phase . "blocked")
                 (objective . "First line\nSecond line")
                 (blockedReason . "Needs approval"))))))
    (save-window-excursion
      (dsh-emacs-goal-describe)
      (with-current-buffer "*dsh goal*"
        (ert-info ((format "%s" "goal-details-preserve-objective-and-explain-block"))
          (should (string-match-p "First line\nSecond line" (buffer-string)))
          (should (string-match-p "Phase: blocked" (buffer-string)))
          (should (string-match-p "Blocked: Needs approval" (buffer-string)))
          (should buffer-read-only))))
    (dsh-emacs-composer-set-goal
     (dsh-protocol-goal-projection--from-alist
      '((goal . ((id . "details") (revision . 3) (phase . "blocked")
                 (objective . "First line\nSecond line")
                 (blockedReason . "Needs credentials"))))))
    (ert-info ((format "%s" "goal-reason-only-change-refreshes-tooltip"))
      (should (cl-loop for pos from (point-min) below (point-max)
                       thereis (let ((help (get-text-property pos 'help-echo)))
                                 (and (stringp help)
                                      (string-match-p "Needs credentials" help))))))
    ;; The full-details buffer collapses a canonical session mention like every
    ;; other objective surface, and a goal without an objective still opens.
    (dsh-emacs-composer-set-goal
     (dsh-protocol-goal-projection--from-alist
      '((goal . ((id . "mention") (revision . 1) (phase . "active")
                 (objective . "named @[Gamma session](dsh-session:Gamma-7) here"))))))
    (save-window-excursion
      (dsh-emacs-goal-describe)
      (with-current-buffer "*dsh goal*"
        (ert-info ((format "%s" "goal-details-collapse-session-mention"))
          (should (string-match-p "@Gamma session" (buffer-string)))
          (should (null (string-match-p "dsh-session:" (buffer-string))))
          (should (cl-find-if (lambda (i)
                                (get-text-property i 'dsh-emacs-reference-ref
                                                   (buffer-string)))
                              (number-sequence 0 (1- (length (buffer-string)))))))))
    (dsh-emacs-composer-set-goal
     (dsh-protocol-goal-projection--from-alist
      '((goal . ((id . "no-objective") (revision . 1) (phase . "active"))))))
    (save-window-excursion
      (dsh-emacs-goal-describe)
      (with-current-buffer "*dsh goal*"
        (ert-info ((format "%s" "goal-details-fall-back-without-objective"))
          (should (string-match-p "Untitled goal" (buffer-string))))))
    (ert-info ((format "%s" "goal-details-key"))
      (should (eq (lookup-key dsh-emacs-goal-map (kbd "?"))
                  #'dsh-emacs-goal-describe)))))

(ert-deftest dsh-emacs-test-composer-goal-compact-row-prioritizes-status ()
  :tags '(dsh-unit)
  (let ((goal (dsh-protocol-goal-projection--from-alist
               '((goal . ((objective . "A long objective")
                          (phase . "blocked")))))))
    (cl-letf (((symbol-function 'dsh-emacs-composer--row-width) (lambda () 24)))
      (let ((row (dsh-emacs-composer--render-row goal)))
        (ert-info ((format "%s" "goal-compact-row-prioritizes-status"))
          (should (string-match-p "Blocked Goal" row))
          (should (<= (string-width row) 24))
          (should (not (dsh-test-goal-strip-binds row 'dsh-emacs-goal-edit))))))))

;; Both SVGs must fit their backing text even in a frame with tiny cells.
(ert-deftest dsh-emacs-test-composer-goal-svg-fits-reserved-columns ()
  :tags '(dsh-unit)
  (cl-letf (((symbol-function 'display-graphic-p) (lambda (&rest _) t))
            ((symbol-function 'image-type-available-p) (lambda (_type) t))
            ((symbol-function 'get-buffer-window-list) (lambda (&rest _args) nil))
            ((symbol-function 'frame-char-width) (lambda (&optional _frame) 5))
            ((symbol-function 'create-image)
             (lambda (_data _type _data-p &rest props) (cons 'image props))))
    (let* ((icon (dsh-emacs-composer--goal-icon))
           (action (dsh-emacs-composer--action-cell
                    "||" dsh-emacs-composer--pause-svg
                    'dsh-emacs-composer-goal-action-face
                    "Pause goal · C-c C-g p" #'dsh-emacs-goal-pause)))
      (ert-info ((format "%s" "goal-svg-fits-reserved-columns"))
        (should (= (plist-get (cdr (get-text-property 0 'display icon)) :width) 10))
        (should (= (plist-get (cdr (get-text-property 0 'display action)) :width) 10))
        (should (= (string-width icon) 2))
        (should (= (string-width action) 2))))))

;; Composer owns both rows; queue state must never become prompt text.
(ert-deftest dsh-emacs-test-composer-composer-next-has-own-row-and-preserves-draft-point ()
  :tags '(dsh-unit)
  (with-temp-buffer
    (dsh-emacs-mode)
    (dsh-emacs--replace-input "draft\nsecond line")
    (goto-char (+ dsh-emacs--input-marker 3))
    (setq dsh-emacs--queue-items
          (list (dsh-emacs-test--queue-item "next" "queued" "Queued work")))
    (dsh-emacs-composer-set-goal
     (dsh-protocol-goal-projection--from-alist
      '((goal . ((objective . "Current goal") (phase . "active"))))))
    (dsh-emacs-queue--paint-after-burst)
    (ert-info ((format "%s" "composer-next-has-own-row-and-preserves-draft-point"))
      (should (dsh-test-composer-next-row))
      (should (equal (dsh-emacs--get-input) "draft\nsecond line"))
      (should (= (- (point) dsh-emacs--input-marker) 3))
      (should (equal (buffer-substring-no-properties
                      (dsh-emacs-render--input-anchor-pos) dsh-emacs--input-marker)
                     "❯ "))
      (should (string-match-p "Queued work.*\n.*Current goal.*\n❯ draft"
                              (buffer-string))))
    ;; Use the actual transcript insertion seam while both chrome rows exist.
    (save-excursion
      (goto-char (dsh-emacs-render--input-insert-point))
      (let ((inhibit-read-only t)) (insert "STREAMED\n")))
    (dsh-emacs-composer-set-goal nil)
    (ert-info ((format "%s" "composer-goal-clear-keeps-next-and-transcript"))
      (should (markerp dsh-emacs--composer-top-marker))
      (should (dsh-test-composer-next-row))
      (should (string-match-p "STREAMED\n.*Queued work.*\n❯ draft" (buffer-string)))
      (should (not (string-match-p "Current goal" (buffer-string))))
      (should (equal (dsh-emacs--get-input) "draft\nsecond line")))
    (setq dsh-emacs--queue-items nil)
    (dsh-emacs-queue--paint-after-burst)
    (ert-info ((format "%s" "composer-last-row-removal-clears-only-chrome"))
      (should (null dsh-emacs--composer-top-marker))
      (should (null (dsh-test-composer-next-row)))
      (should (string-match-p "STREAMED\n❯ draft" (buffer-string)))
      (should (equal (dsh-emacs--get-input) "draft\nsecond line")))))

(ert-deftest dsh-emacs-test-composer-composer-next-reflows-without-goal ()
  :tags '(dsh-unit)
  (with-temp-buffer
    (dsh-emacs-mode)
    (setq dsh-emacs--queue-items
          (list (dsh-emacs-test--queue-item
                 "wide" "queued"
                 "First line\nSecond line with a long continuation 中文中文中文")))
    (let ((width 60))
      (cl-letf (((symbol-function 'dsh-emacs-composer--row-width)
                 (lambda () width)))
        (dsh-emacs-queue--paint-after-burst)
        (let ((wide (dsh-test-composer-next-row)))
          (setq width 18)
          (dsh-emacs-composer--window-configuration-change)
          (let ((narrow (dsh-test-composer-next-row)))
            (ert-info ((format "%s" "composer-next-reflows-without-goal"))
              (should (and wide narrow
                           (> (string-width (string-trim-right wide))
                              (string-width (string-trim-right narrow)))
                           (<= (string-width (string-trim-right narrow)) 18)
                           (= (cl-count ?\n narrow) 1)
                           (get-text-property 0 'read-only narrow))))))))))

;; Removing Next Message must leave the goal intact.  Rebuilding the input
;; invalidates geometry but not the mirrored data or the ability to repaint.
(ert-deftest dsh-emacs-test-composer-composer-unchanged-rows-do-not-rewrite-buffer ()
  :tags '(dsh-unit)
  (with-temp-buffer
    (dsh-emacs-mode)
    (dsh-emacs-modeline-setup)
    (setq dsh-emacs--queue-items
          (list (dsh-emacs-test--queue-item "row" "queued" "Pending work")))
    (dsh-emacs-composer-set-goal
     (dsh-protocol-goal-projection--from-alist
      '((goal . ((objective . "Keep goal") (phase . "active"))))))
    (let ((top dsh-emacs--composer-top-marker)
          (end dsh-emacs--composer-end-marker)
          (tick (buffer-chars-modified-tick)))
      (dsh-emacs-composer-render)
      (ert-info ((format "%s" "composer-unchanged-rows-do-not-rewrite-buffer"))
        (should (eq top dsh-emacs--composer-top-marker))
        (should (eq end dsh-emacs--composer-end-marker))
        (should (= tick (buffer-chars-modified-tick)))))
    (dsh-emacs-render-event
     '((type . "assistant/message") (seq . 1)
       (data . ((message . ((content . [((type . "text")
                                         (text . "Rendered transcript"))])))))))
    (setq dsh-emacs--queue-items nil)
    (dsh-emacs-queue--paint-after-burst)
    (ert-info ((format "%s" "composer-next-clear-keeps-goal-and-rendered-transcript"))
      (should (null (dsh-test-composer-next-row)))
      (should (string-match-p "Keep goal.*\n❯ " (buffer-string)))
      (should (string-match-p "Rendered transcript" (buffer-string)))
      (should (dsh-emacs-composer--region)))
    (dsh-emacs--setup-input-area)
    (dsh-emacs-composer-render)
    (ert-info ((format "%s" "composer-rebuild-replaces-collapsed-markers"))
      (should (dsh-emacs-composer--region))
      (should (string-match-p "DeepSeek Harness" (buffer-string)))
      (should (string-match-p "Keep goal.*\n❯ " (buffer-string))))
    (dsh-emacs-composer-set-goal nil)
    (ert-info ((format "%s" "composer-all-markers-release-when-empty"))
      (should (null dsh-emacs--composer-top-marker))
      (should (null dsh-emacs--composer-end-marker)))))

(provide 'dsh-test-composer)
;;; dsh-test-composer.el ends here
