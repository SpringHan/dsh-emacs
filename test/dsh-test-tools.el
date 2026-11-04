;;; dsh-test-tools.el --- Tools tests -*- lexical-binding: t; -*-

;; Package-Requires: ((emacs "28.1"))

(require 'dsh-test-support)

(defun dsh-emacs-test--tool-result-event-meta (seq call-id text meta &optional is-error)
  "Build a `tool/result' event carrying TEXT and the settled result META."
  (list (cons "type" "tool/result")
        (cons "seq" seq)
        (cons "data"
              (list (cons "message"
                          (list (cons "callId" call-id)
                                (cons "content"
                                      (vector (list (cons "type" "tool-result")
                                                    (cons "isError" (if is-error t :json-false))
                                                    (cons "exitCode" (if is-error 1 0))
                                                    (cons "content"
                                                          (vector (list (cons "type" "text")
                                                                        (cons "text" text)))))))))
                    (cons "meta" meta)))))

(defun dsh-emacs-test--tool-result-event-bare (seq call-id content)
  "Build a `tool/result' event whose MESSAGE.CONTENT is CONTENT verbatim.
Lets a test drive a malformed content value through the result path."
  (list (cons "type" "tool/result")
        (cons "seq" seq)
        (cons "data"
              (list (cons "message"
                          (list (cons "callId" call-id)
                                (cons "content" content)))))))

(defun dsh-emacs-test--tool-result-event-source (seq call-id text)
  "Build a real dsh Web `tool/result' with MESSAGE.SOURCE.CALL-ID."
  (list (cons "type" "tool/result")
        (cons "seq" seq)
        (cons "data"
              (list (cons "message"
                          (list (cons "source" (list (cons "callId" call-id)))
                                (cons "content"
                                      (vector (list (cons "type" "tool-result")
                                                    (cons "isError" :json-false)
                                                    (cons "exitCode" 0)
                                                    (cons "content"
                                                          (vector (list (cons "type" "text")
                                                                        (cons "text" text)))))))))))))

(ert-deftest dsh-emacs-test-tools-tool-call-routes-plan-and-ordinary-cards ()
  :tags '(dsh-unit)
  (with-temp-buffer
    (dsh-emacs-mode)
    (setq-local dsh-emacs-show-tool-calls t)
    (let* ((args "{\"command\":\"printf protocol\"}")
           (event (dsh-emacs-test--tool-call-event 11 "ordinary" "bash" args)))
      (push '("time" . 1000) event)
      (should (= 11 (dsh-emacs-render-tool-call event)))
      (let ((state (dsh-emacs-render--tool-state "ordinary")))
        (should (eq 'pending (plist-get state :state)))
        (should (equal "bash" (plist-get state :name)))
        (should (equal args (plist-get state :args-raw)))
        (should (equal (format-time-string "%H:%M:%S" 1.0)
                       (plist-get state :call-time)))))
    (let ((text "# Decoding plan\n\nKeep the application order."))
      (should (= 12 (dsh-emacs-render-tool-call
                     (dsh-emacs-test--tool-call-event
                      12 "plan" "exit_plan_mode"
                      (json-encode `((plan . ,text)))))))
      (should (equal text (plist-get (dsh-emacs-render--tool-state "plan")
                                    :plan-text)))
      (should-not (plist-get (dsh-emacs-render--tool-state "plan") :state))
      (should (string-match-p "Plan: Decoding plan" (buffer-string))))
    ;; An absent/blank document still uses the ordinary pending tool card.
    (dolist (args '("{}" "{\"plan\":\"  \\n\"}"))
      (should (= 13 (dsh-emacs-render-tool-call
                     (dsh-emacs-test--tool-call-event
                      13 "empty-plan" "exit_plan_mode" args))))
      (let ((state (dsh-emacs-render--tool-state "empty-plan")))
        (should (eq 'pending (plist-get state :state)))
        (should (equal args (plist-get state :args-raw)))
        (should-not (plist-get state :plan-text))))))

(ert-deftest dsh-emacs-test-tools-hidden-tool-calls-still-apply-todo ()
  :tags '(dsh-unit)
  (with-temp-buffer
    (dsh-emacs-mode)
    (setq-local dsh-emacs-show-tool-calls nil)
    (setq-local dsh-emacs-todo-expand-by-default t)
    (setq-local dsh-emacs--anchor-seq 7)
    (let ((before (buffer-string)) messages)
      (cl-letf (((symbol-function 'message)
                 (lambda (format-string &rest args)
                   (push (apply #'format format-string args) messages))))
        (dolist (name '("bash" "exit_plan_mode"))
          (should-not (dsh-emacs-render-event
                       (dsh-emacs-test--tool-call-event
                        20 name name "invalid JSON")))
          (should-not (dsh-emacs-render--tool-state name)))
        (should-not messages))
      (should (equal before (buffer-string)))
      (should (= 7 dsh-emacs--anchor-seq)))
    (should (= 21 (dsh-emacs-render-event
                   (dsh-emacs-test--tool-call-event
                    21 nil "todo_write"
                    "{\"todos\":[{\"content\":\"Keep todo visible\",\"status\":\"pending\"}]}"))))
    (should (equal '(("Keep todo visible" . "pending")) dsh-emacs--todo-list))
    (should (dsh-emacs-ui-find-block dsh-emacs--todo-namespace "seq-21"))
    (should (string-match-p "Keep todo visible" (buffer-string)))
    (should (= 21 dsh-emacs--anchor-seq))
    (should-not (dsh-emacs-render--tool-state "seq-21"))))

(ert-deftest dsh-emacs-test-tools-tool-result-preserves-seq-and-display-gate ()
  :tags '(dsh-unit)
  (with-temp-buffer
    (dsh-emacs-mode)
    (setq-local dsh-emacs-show-tool-calls t)
    (setq-local dsh-emacs-tool-expand-by-default t)
    (dsh-emacs-render-tool-call
     (dsh-emacs-test--tool-call-event
      1 "ordinary" "bash" "{\"command\":\"true\"}"))
    (should (= 21 (dsh-emacs-render-tool-result
                   (dsh-emacs-test--tool-result-event
                    21 "ordinary" nil 0 "ordinary output"))))
    (should (equal "ordinary output"
                   (plist-get (dsh-emacs-render--tool-state "ordinary")
                              :result)))
    (let ((before (buffer-string)))
      (should (= 22 (dsh-emacs-render-tool-result
                     (dsh-emacs-test--tool-result-event
                      22 "unknown" nil 0 "untracked output"))))
      (should (equal before (buffer-string)))
      (should-not (dsh-emacs-render--tool-state "unknown")))
    (dsh-emacs-render-tool-call
     (dsh-emacs-test--tool-call-event
      3 "plan" "exit_plan_mode"
      (json-encode '((plan . "# Refactor plan\n\nKeep behavior.")))))
    (should (= 23 (dsh-emacs-render-tool-result
                   (dsh-emacs-test--tool-result-event
                    23 "plan" nil nil "Plan approved"))))
    (should (string-match-p
             "Approved"
             (dsh-emacs-test--tool-block-text
              (dsh-emacs-render--make-namespace) "tool-plan")))
    (let ((before (buffer-string))
          (state (copy-tree (dsh-emacs-render--tool-state "ordinary")))
          ;; This shape reaches the decoder, whose object lookup rejects it.
          (invalid '((type . "tool/result") (seq . 24)
                     (data . ((malformed . t) . invalid)))))
      (should-error (dsh-emacs-render-tool-result invalid)
                    :type 'wrong-type-argument)
      (setq-local dsh-emacs-show-tool-calls nil)
      (should-not (dsh-emacs-render-tool-result invalid))
      (should-not (dsh-emacs-render-tool-result
                   (dsh-emacs-test--tool-result-event
                    25 "ordinary" t 1 "must stay hidden")))
      (should (equal before (buffer-string)))
      (should (equal state
                     (dsh-emacs-render--tool-state "ordinary"))))))

(ert-deftest dsh-emacs-test-tools-tool-running-keeps-leading-glyph ()
  :tags '(dsh-unit)
  (with-temp-buffer
    (dsh-emacs-mode)
    (dsh-emacs-modeline-setup)
    (setq-local dsh-emacs-tool-expand-by-default t)
    ;; 1) tool call (running): keeps the leading dot + gear loading
    (dsh-emacs-render-tool-call
     (dsh-emacs-test--tool-call-event 1 "c1" "bash" "{\"description\":\"list files\",\"command\":\"ls -la\"}"))
    (let* ((ns (dsh-emacs-render--make-namespace))
           (block (dsh-emacs-test--tool-block-text ns "tool-c1")))
      (ert-info ((format "%s" "tool-running-keeps-leading-glyph"))
        (should (and block
                     (string-match-p (regexp-quote "● ") block)
                     ;; Keeps the leading glyph while running; the animated spinner moved to the
                     ;; mode-line progress bar
                     (string-match-p "Bash" block)))))
    ;; 2) successful result: bash expands into a terminal card ($ prompt line +
    ;; output, no ✓ footer on a clean exit), no longer a generic IN/OUT ioCard
    (dsh-emacs-render-tool-result
     (dsh-emacs-test--tool-result-event 2 "c1" nil 0 "total 3\ndrwxr-xr-x"))
    (let* ((ns (dsh-emacs-render--make-namespace))
           (block (dsh-emacs-test--tool-block-text ns "tool-c1")))
      (ert-info ((format "%s" "tool-bash-success-terminal-card"))
        (should (and block
                     (string-match-p (regexp-quote "● ") block)
                     (string-match-p (regexp-quote "$ ls -la") block)
                     (string-match-p "drwxr-xr-x" block)
                     (not (string-match-p (regexp-quote "✓ exit 0") block))
                     (not (string-match-p "IN" block))
                     (not (string-match-p "OUT" block))))))
    ;; 3) expanded rows are unpadded: cards draw on the transcript background
    ;; with no surface band, so each row ends at its own content.
    (let* ((ns (dsh-emacs-render--make-namespace))
           (block (dsh-emacs-test--tool-block-text ns "tool-c1")))
      (ert-info ((format "%s" "tool-bash-card-rows-are-unpadded"))
        (should (and block
                     (string-match-p "^  \\$ ls -la$" block)
                     (string-match-p "^  drwxr-xr-x$" block)))))
    ;; 3) error result: the leading marker becomes a red status dot ●
    (dsh-emacs-render-tool-call
     (dsh-emacs-test--tool-call-event 3 "c2" "edit" "{\"path\":\"/tmp/x\"}"))
    (dsh-emacs-render-tool-result
     (dsh-emacs-test--tool-result-event 4 "c2" nil 1 "segmentation fault"))
    (let* ((ns (dsh-emacs-render--make-namespace))
           (block (dsh-emacs-test--tool-block-text ns "tool-c2")))
      (ert-info ((format "%s" "tool-error-state-dot-leading"))
        (should (and block
                     (string-match-p (regexp-quote "● ") block)
                     (string-match-p "segmentation fault" block)))))))

(ert-deftest dsh-emacs-test-tools-simple-render-style-uses-dots ()
  :tags '(dsh-unit)
  (ert-info ((format "%s" "render-style-defaults-to-full"))
    (should (eq 'full dsh-emacs-render-style)))
  (let ((dsh-emacs-render-style 'full))
    (ert-info ((format "%s" "full-style-falls-back-to-dot-without-svg"))
      (should (equal "●" (substring-no-properties
                           (dsh-emacs-render--tool-icon "bash"))))
      (should (equal "✶" (substring-no-properties
                           (dsh-emacs-render--think-icon))))))
  (ert-info ((format "%s" "simple-suppresses-svg-on-graphics"))
    (cl-letf (((symbol-function 'display-graphic-p) (lambda (&rest _) t))
              ((symbol-function 'image-type-available-p) (lambda (&rest _) t))
              ((symbol-function 'create-image) (lambda (&rest _) '(:test-svg))))
      (let ((dsh-emacs-render-style 'full))
        (should (get-text-property 0 'display
                                   (dsh-emacs-render--tool-icon "bash"))))
      (let ((dsh-emacs-render-style 'simple))
        (should-not (get-text-property 0 'display
                                       (dsh-emacs-render--tool-icon "bash"))))))
  (let ((dsh-emacs-render-style 'simple))
    (let ((icon (dsh-emacs-render--tool-icon "bash")))
      (ert-info ((format "%s" "simple-tool-icon-is-one-dot"))
        (should (equal "●" (substring-no-properties icon)))
        (should (eq 'dsh-emacs-tool-icon-face
                    (get-text-property 0 'face icon)))
        (should-not (get-text-property 0 'display icon))))
    (ert-info ((format "%s" "simple-tool-leading-colors-states"))
      (dolist (entry '((pending . dsh-emacs-tool-icon-face)
                       (success . dsh-emacs-tool-success-face)
                       (error . dsh-emacs-tool-error-face)
                       (stopped . dsh-emacs-tool-stopped-face)))
        (let ((leading (dsh-emacs-render--tool-leading "ignored" (car entry))))
          (should (equal "● " (substring-no-properties leading)))
          (should (eq (cdr entry)
                      (get-text-property 0 'face leading))))))
    (ert-info ((format "%s" "simple-row-icons-are-dots"))
      (let ((think (dsh-emacs-render--think-icon))
            (todo (dsh-emacs-render--todo-icon))
            (turn (dsh-emacs-render--turn-trigger-icon))
            (goal (dsh-emacs-render--goal-trigger-icon)))
        (dolist (entry `((,think . dsh-emacs-thinking-face)
                         (,todo . dsh-emacs-tool-icon-face)
                         (,turn . dsh-emacs-meta-face)
                         (,goal . dsh-emacs-composer-goal-face)))
          (should (equal "●" (substring-no-properties (car entry))))
          (should (eq (cdr entry)
                      (get-text-property 0 'face (car entry)))))))
    (ert-info ((format "%s" "simple-row-chrome-is-neutral-and-muted"))
      (should (facep 'dsh-emacs-event-row-face))
      (should (equal '(bold dsh-emacs-event-row-face)
                     (dsh-emacs-render--row-label-face 'dsh-emacs-thinking-face)))
      (should (eq 'dsh-emacs-event-row-face
                  (dsh-emacs-render--row-chrome-face
                   'dsh-emacs-tool-success-face)))
      (let ((dsh-emacs-render-style 'full))
        (should (eq 'dsh-emacs-thinking-face
                    (dsh-emacs-render--row-label-face 'dsh-emacs-thinking-face)))
        (should (eq 'dsh-emacs-tool-success-face
                    (dsh-emacs-render--row-chrome-face
                     'dsh-emacs-tool-success-face)))))
    (with-temp-buffer
      (dsh-emacs-mode)
      (dsh-emacs-modeline-setup)
      (setq-local dsh-emacs-show-tool-calls t)
      (dsh-emacs-render-tool-call
       (dsh-emacs-test--tool-call-event
        1 "s1" "bash" "{\"command\":\"true\"}"))
      (let* ((ns (dsh-emacs-render--make-namespace))
             (found (dsh-emacs-ui-find-block ns "tool-s1"))
             (title-faces (and found (dsh-test--faces-at (+ (car found) 2))))
             (block (and found
                         (dsh-emacs-test--tool-block-text ns "tool-s1"))))
        (ert-info ((format "%s" "simple-pending-tool-row-leads-with-dot"))
          (should (and block (string-prefix-p "● Bash" block)))
          (should (memq 'dsh-emacs-event-row-face title-faces))
          (should-not (memq 'dsh-emacs-tool-title-face title-faces))
          (should-not (memq 'dsh-emacs-tool-pending-face title-faces))))
      (dsh-emacs-render-tool-result
       (dsh-emacs-test--tool-result-event 2 "s1" nil 0 "done"))
      (let* ((ns (dsh-emacs-render--make-namespace))
             (found (dsh-emacs-ui-find-block ns "tool-s1"))
             (faces (and found (dsh-test--faces-at (car found))))
             (title-faces (and found (dsh-test--faces-at (+ (car found) 2))))
             (block (and found
                         (dsh-emacs-test--tool-block-text ns "tool-s1"))))
        (ert-info ((format "%s" "simple-settled-tool-row-stays-a-success-dot"))
          (should (and block (string-prefix-p "● Bash" block)))
          (should (memq 'dsh-emacs-tool-success-face faces))
          (should (memq 'dsh-emacs-event-row-face title-faces))
          (should-not (memq 'dsh-emacs-tool-success-face title-faces)))))))

;; --- Test 29c: a file read expands into a line-numbered read card ---
(ert-deftest dsh-emacs-test-tools-tool-read-card-numbers-the-window ()
  :tags '(dsh-unit)
  (with-temp-buffer
    (dsh-emacs-mode)
    (dsh-emacs-modeline-setup)
    (setq-local dsh-emacs-tool-expand-by-default t)
    (dsh-emacs-render-tool-call
     (dsh-emacs-test--tool-call-event
      1 "r1" "read" "{\"file_path\":\"/a/b.el\",\"offset\":2,\"limit\":2}"))
    (dsh-emacs-render-tool-result
     (dsh-emacs-test--tool-result-event-meta
      2 "r1"
      "<path>/a/b.el</path>\n<type>file</type>\n<content>\n2: (b)\n3: (c)\n</content>"
      '((path . "/a/b.el") (offset . 2) (totalLines . 9) (lang . "emacs-lisp")
        (lines . [((number . 2) (text . "(b)"))
                  ((number . 3) (text . "(c)"))]))))
    (let* ((ns (dsh-emacs-render--make-namespace))
           (full (buffer-string))
           (block (dsh-emacs-test--tool-block-text ns "tool-r1"))
           (num (string-match "2  (b)" full)))
      (ert-info ((format "%s" "tool-read-card-numbers-the-window"))
        (should (string-match-p "^  2  (b)$" block))
        (should (string-match-p "3  (c)" block))
        (should (string-match-p "Showing 2 of 9 lines · emacs-lisp" block))
        (should (not (string-match-p "<content>" block)))
        (should (not (string-match-p "file_path" block))))
      (ert-info ((format "%s" "tool-read-card-gutter-keeps-its-face"))
        (should (and num
                     (memq 'dsh-emacs-tool-meta-face
                           (ensure-list (get-text-property num 'face full)))))))))

;; A read that covered the whole file prints no window footer.
(ert-deftest dsh-emacs-test-tools-tool-read-card-whole-file-has-no-window-footer ()
  :tags '(dsh-unit)
  (with-temp-buffer
    (dsh-emacs-mode)
    (dsh-emacs-modeline-setup)
    (setq-local dsh-emacs-tool-expand-by-default t)
    (dsh-emacs-render-tool-call
     (dsh-emacs-test--tool-call-event 1 "r2" "read" "{\"file_path\":\"/a/c.el\"}"))
    (dsh-emacs-render-tool-result
     (dsh-emacs-test--tool-result-event-meta
      2 "r2"
      "<path>/a/c.el</path>\n<type>file</type>\n<content>\n1: one\n2: \n</content>"
      '((path . "/a/c.el") (offset . 1) (totalLines . 2)
        (lines . [((number . 1) (text . "one"))
                  ((number . 2) (text . ""))]))))
    (let* ((ns (dsh-emacs-render--make-namespace))
           (block (dsh-emacs-test--tool-block-text ns "tool-r2")))
      (ert-info ((format "%s" "tool-read-card-whole-file-has-no-window-footer"))
        (should (string-match-p "1  one" block))
        (should (not (string-match-p "Showing" block)))
        (should (not (string-match-p "IN" block)))))))

;; --- Test 29d: write/edit rows expand into an aligned diff card ---
(ert-deftest dsh-emacs-test-tools-tool-edit-running-shows-intended-diff ()
  :tags '(dsh-unit)
  (with-temp-buffer
    (dsh-emacs-mode)
    (dsh-emacs-modeline-setup)
    (setq-local dsh-emacs-tool-expand-by-default t)
    ;; While the call runs the diff is the one the arguments intend.
    (dsh-emacs-render-tool-call
     (dsh-emacs-test--tool-call-event
      1 "d1" "edit"
      (json-encode '((file_path . "src/x.el")
                     (old_string . "(head)\n(old a)\n(old b)\n(tail)")
                     (new_string . "(head)\n(new a)\n(tail)")))))
    (let* ((ns (dsh-emacs-render--make-namespace))
           (running (dsh-emacs-test--tool-block-text ns "tool-d1")))
      (ert-info ((format "%s" "tool-edit-running-shows-intended-diff"))
        (should (string-match-p "^    (head)$" running))
        (should (string-match-p "^    (tail)$" running))
        (should (not (string-match-p "[-+] (head)" running)))
        (should (string-match-p "- (old a)" running))
        (should (string-match-p "- (old b)" running))
        (should (string-match-p "+ (new a)" running))
        (should (string-match-p (regexp-quote "└ +1 -2 · 1 file") running))
        (should (not (string-match-p "old_string" running)))))
    ;; Settled, the applied diffs from the result metadata win.
    (dsh-emacs-render-tool-result
     (dsh-emacs-test--tool-result-event-meta
      2 "d1" "The file src/x.el has been updated successfully."
      '((diffs . [((path . "src/x.el")
                   (oldText . "one\ntwo")
                   (newText . "ONE\ntwo\nthree"))]))))
    (let* ((ns (dsh-emacs-render--make-namespace))
           (full (buffer-string))
           (settled (dsh-emacs-test--tool-block-text ns "tool-d1"))
           (del (string-match "- one" full))
           (add (string-match "+ ONE" full))
           (context (string-match "    two" full)))
      (ert-info ((format "%s" "tool-edit-settled-shows-applied-diff"))
        (should (string-match-p "^    two$" settled))
        (should (not (string-match-p "[-+] two" settled)))
        (should (string-match-p "+ three" settled))
        (should (string-match-p (regexp-quote "└ +2 -1 · 1 file") settled))
        (should (not (string-match-p "(old a)" settled))))
      (ert-info ((format "%s" "tool-diff-lines-carry-state-faces"))
        (should (and del add
                     (memq 'dsh-emacs-tool-diff-del-face
                           (ensure-list (get-text-property del 'face full)))
                     (memq 'dsh-emacs-tool-diff-add-face
                           (ensure-list (get-text-property add 'face full))))))
      (ert-info ((format "%s" "tool-diff-context-has-no-change-face"))
        (should (and context
                     (not (cl-intersection
                           '(dsh-emacs-tool-diff-add-face dsh-emacs-tool-diff-del-face
                                                          dsh-emacs-tool-success-face)
                           (ensure-list (get-text-property (+ context 4) 'face full)))))))
      ;; Expanded card rows are drawn on the transcript background and are not
      ;; padded to the box width, so each row ends at its own content.
      (ert-info ((format "%s" "tool-diff-card-rows-are-unpadded"))
        (should (string-match-p "^  - one$" settled))
        (should (string-match-p "^  \\+ three$" settled))
        (should (string-match-p "^  src/x\\.el$" settled))))))

;; Alignment keeps unchanged source lines intact, including literal signs,
;; repeated lines and blank context between separate changes.
(ert-deftest dsh-emacs-test-tools-tool-diff-align ()
  :tags '(dsh-unit)
  (dolist (case '(("empty" "" "" nil)
                  ("creation" nil "a\n\nb\n"
                   ((add . "a") (add . "") (add . "b")))
                  ("deletion" "a\n" "" ((del . "a")))
                  ("identical" "+ literal\n- literal\n"
                   "+ literal\n- literal\n"
                   ((context . "+ literal") (context . "- literal")))
                  ("insert-middle" "head\ntail" "head\nnew\ntail"
                   ((context . "head") (add . "new") (context . "tail")))
                  ("delete-middle" "head\nold\ntail" "head\ntail"
                   ((context . "head") (del . "old") (context . "tail")))
                  ("separate-edits" "old\nshared\n旧" "new\nshared\n新"
                   ((del . "old") (add . "new") (context . "shared")
                    (del . "旧") (add . "新")))
                  ("repeated-lines" "a\nb\na" "b\na\nb"
                   ((del . "a") (context . "b") (context . "a") (add . "b")))
                  ("blank-context" "old\n\ntail" "new\n\ntail"
                   ((del . "old") (add . "new") (context . "")
                    (context . "tail")))))
    (pcase-let ((`(,name ,old ,new ,expected) case))
      (ert-info ((format "%s" (concat "tool-diff-align-" name)))
        (should (equal expected (dsh-emacs-render--diff-align old new)))))))

;; Huge changed middles stay bounded, but identical edges still align and
;; the card explicitly identifies the unaligned replacement.
(ert-deftest dsh-emacs-test-tools-tool-diff-large-replacement-keeps-edges-and-totals ()
  :tags '(dsh-unit)
  (let* ((old (concat "head\n" (apply #'concat (make-list 513 "old\n")) "tail"))
         (new (concat "head\n" (apply #'concat (make-list 513 "new\n")) "tail"))
         (diff (dsh-emacs-render--diff-rows (list (list "large.txt" old new))))
         (rows (car diff)))
    (ert-info ((format "%s" "tool-diff-large-replacement-keeps-edges-and-totals"))
      (should (equal '(513 513 1) (cdr diff)))
      (should (equal "    head" (nth 1 rows)))
      (should (equal "  ⋯ Large replacement: middle shown without alignment" (nth 2 rows)))
      (should (equal "  - old" (nth 3 rows)))
      (should (equal "  + new" (nth 516 rows)))
      (should (equal "    tail" (car (last rows)))))))

;; A write keeps its argument-derived whole-file diff when the result records
;; none, and repeated paths get a gap row instead of a second path row.
(ert-deftest dsh-emacs-test-tools-tool-write-keeps-whole-file-diff ()
  :tags '(dsh-unit)
  (with-temp-buffer
    (dsh-emacs-mode)
    (dsh-emacs-modeline-setup)
    (setq-local dsh-emacs-tool-expand-by-default t)
    (dsh-emacs-render-tool-call
     (dsh-emacs-test--tool-call-event
      1 "w1" "write" "{\"file_path\":\"new.txt\",\"content\":\"alpha\\nbeta\"}"))
    (dsh-emacs-render-tool-result
     (dsh-emacs-test--tool-result-event-meta 2 "w1" "created" nil))
    (let* ((ns (dsh-emacs-render--make-namespace))
           (block (dsh-emacs-test--tool-block-text ns "tool-w1")))
      (ert-info ((format "%s" "tool-write-keeps-whole-file-diff"))
        (should (string-match-p "+ alpha" block))
        (should (string-match-p "+ beta" block))
        (should (string-match-p (regexp-quote "└ +2 -0 · 1 file") block))
        (should (not (string-match-p "\"content\"" block)))))
    (dsh-emacs-render-tool-call
     (dsh-emacs-test--tool-call-event
      3 "w2" "write" "{\"file_path\":\"a.txt\",\"content\":\"x\"}"))
    (dsh-emacs-render-tool-result
     (dsh-emacs-test--tool-result-event-meta
      4 "w2" "ok"
      '((diffs . [((path . "a.txt") (oldText . "x") (newText . "y"))
                  ((path . "a.txt") (oldText . nil) (newText . "z"))
                  ((path . "b.txt") (oldText . nil) (newText . "q"))]))))
    (let* ((ns (dsh-emacs-render--make-namespace))
           (block (dsh-emacs-test--tool-block-text ns "tool-w2")))
      (ert-info ((format "%s" "tool-diff-multi-hunk-gap-and-file-count"))
        (should (string-match-p "  ⋯" block))
        (should (string-match-p "b.txt" block))
        (should (string-match-p (regexp-quote "└ +3 -1 · 2 files") block))))))

;; The diff card declines what dsh web's models decline: an edit that records
;; no diff, a failed call, and inconsistent read metadata all keep the ioCard.
(ert-deftest dsh-emacs-test-tools-tool-edit-without-diffs-keeps-iocard ()
  :tags '(dsh-unit)
  (with-temp-buffer
    (dsh-emacs-mode)
    (dsh-emacs-modeline-setup)
    (setq-local dsh-emacs-tool-expand-by-default t)
    (dsh-emacs-render-tool-call
     (dsh-emacs-test--tool-call-event
      1 "e1" "edit" "{\"file_path\":\"src/y.el\",\"old_string\":\"a\",\"new_string\":\"b\"}"))
    (dsh-emacs-render-tool-result
     (dsh-emacs-test--tool-result-event-meta 2 "e1" "no match found" nil))
    (let* ((ns (dsh-emacs-render--make-namespace))
           (block (dsh-emacs-test--tool-block-text ns "tool-e1")))
      (ert-info ((format "%s" "tool-edit-without-diffs-keeps-iocard"))
        (should (string-match-p "no match found" block))
        (should (string-match-p "old_string" block))))
    (dsh-emacs-render-tool-call
     (dsh-emacs-test--tool-call-event
      3 "e2" "edit" "{\"file_path\":\"src/z.el\",\"old_string\":\"a\",\"new_string\":\"b\"}"))
    (dsh-emacs-render-tool-result
     (dsh-emacs-test--tool-result-event-meta
      4 "e2" "the file changed on disk" nil t))
    (let* ((ns (dsh-emacs-render--make-namespace))
           (block (dsh-emacs-test--tool-block-text ns "tool-e2")))
      (ert-info ((format "%s" "tool-failed-edit-keeps-iocard"))
        (should (string-match-p "the file changed on disk" block))
        (should (not (string-match-p "└ +" block)))))
    (dsh-emacs-render-tool-call
     (dsh-emacs-test--tool-call-event 5 "r3" "read" "{\"file_path\":\"/a/d.el\"}"))
    (dsh-emacs-render-tool-result
     (dsh-emacs-test--tool-result-event-meta
      6 "r3"
      "<path>/a/d.el</path>\n<type>file</type>\n<content>\n1: a\n2: b\n</content>"
      '((path . "/a/d.el") (offset . 1) (totalLines . 2)
        (lines . [((number . 2) (text . "a"))
                  ((number . 2) (text . "b"))]))))
    (let* ((ns (dsh-emacs-render--make-namespace))
           (block (dsh-emacs-test--tool-block-text ns "tool-r3")))
      (ert-info ((format "%s" "tool-read-inconsistent-meta-keeps-iocard"))
        (should (string-match-p "<content>" block))
        (should (not (string-match-p "Showing" block)))))))

;; A failed or interrupted file call keeps its diagnostic output: a
;; specialized card may replace the result text only for a successful call.
;; The Host marks a failure with `isError' and, for an abort, an `interrupted'
;; failure code.
(ert-deftest dsh-emacs-test-tools-tool-case-case-keeps-diagnostics ()
  :tags '(dsh-unit)
  (dolist (case '((error nil) (stopped "interrupted")))
    (dolist (name '("read" "edit" "write"))
      (with-temp-buffer
        (dsh-emacs-mode)
        (setq-local dsh-emacs-tool-expand-by-default t)
        (let* ((state (car case))
               (code (cadr case))
               (meta (if (equal name "read")
                         '((path . "/a") (offset . 1) (totalLines . 1)
                           (lines . [((number . 1) (text . "preview"))]))
                       '((diffs . [((path . "/a") (oldText . "old")
                                    (newText . "preview"))]))))
               (text (if (equal name "read")
                         (concat "<path>/a</path>\n<type>file</type>\n"
                                 "<content>\n1: diagnostic output\n</content>")
                       "diagnostic output"))
               (event (dsh-emacs-test--tool-result-event-meta
                       2 "failed-file" text meta t)))
          (when code
            (setf (alist-get "error" (alist-get "data" event nil nil #'equal)
                             nil nil #'equal)
                  (list (cons "name" "ToolError") (cons "code" code))))
          (dsh-emacs-render-tool-call
           (dsh-emacs-test--tool-call-event
            1 "failed-file" name
            (concat "{\"file_path\":\"/a\",\"old_string\":\"old\","
                    "\"new_string\":\"preview\",\"content\":\"preview\"}")))
          (dsh-emacs-render-tool-result event)
          (let* ((body (dsh-emacs-test--tool-block-text
                        (dsh-emacs-render--make-namespace) "tool-failed-file"))
                 (tracked (plist-get
                           (dsh-emacs-render--tool-state "failed-file") :state)))
            (ert-info ((format "%s" (format "tool-%s-%s-keeps-diagnostics" name state)))
              (should (eq state tracked))
              (should (string-match-p "diagnostic output" body))
              (should (string-match-p "file_path" body))
              (should (not (string-match-p (regexp-quote "└ +") body)))
              (should (not (string-match-p "1  preview" body))))))))))

;; dsh's shell renderer writes the exit status into the result text
;; (`[exit code: N]' / `[killed by signal: X]'), not the wire block: a failed
;; command must settle the row as failed, print its footer, and lose the
;; marker from the output instead of duplicating it.
(ert-deftest dsh-emacs-test-tools-tool-bash-exit-marker-settles-error ()
  :tags '(dsh-unit)
  (with-temp-buffer
    (dsh-emacs-mode)
    (setq-local dsh-emacs-tool-expand-by-default t)
    (dsh-emacs-render-tool-call
     (dsh-emacs-test--tool-call-event
      1 "b1" "bash" "{\"command\":\"make\",\"description\":\"build\"}"))
    (dsh-emacs-render-tool-result
     (dsh-emacs-test--tool-result-event
      2 "b1" nil nil "make: *** No rule\n[exit code: 2]"))
    (let ((body (dsh-emacs-test--tool-block-text
                 (dsh-emacs-render--make-namespace) "tool-b1")))
      (ert-info ((format "%s" "tool-bash-exit-marker-settles-error"))
        (should (eq 'error (plist-get (dsh-emacs-render--tool-state "b1") :state)))
        (should (string-match-p (regexp-quote "✗ exit 2") body))
        (should (not (string-match-p (regexp-quote "[exit code: 2]") body)))))))

(ert-deftest dsh-emacs-test-tools-tool-bash-signal-marker-settles-error ()
  :tags '(dsh-unit)
  (with-temp-buffer
    (dsh-emacs-mode)
    (setq-local dsh-emacs-tool-expand-by-default t)
    (dsh-emacs-render-tool-call
     (dsh-emacs-test--tool-call-event
      1 "b2" "bash" "{\"command\":\"sleep 60\",\"description\":\"wait\"}"))
    (dsh-emacs-render-tool-result
     (dsh-emacs-test--tool-result-event
      2 "b2" nil nil "waiting\n[killed by signal: SIGTERM]"))
    (let ((body (dsh-emacs-test--tool-block-text
                 (dsh-emacs-render--make-namespace) "tool-b2")))
      (ert-info ((format "%s" "tool-bash-signal-marker-settles-error"))
        (should (eq 'error (plist-get (dsh-emacs-render--tool-state "b2") :state)))
        (should (string-match-p (regexp-quote "✗ signal SIGTERM") body))
        (should (not (string-match-p
                      (regexp-quote "[killed by signal: SIGTERM]") body)))))))

;; Background-job cards: the Host's trailing `[status: ...]' line becomes a
;; state-colored footer, `job_list' and `job_kill' render their result as
;; rows, and the argument JSON is never repeated (the row header already
;; carries the job id).
(ert-deftest dsh-emacs-test-tools-tool-job-output-card ()
  :tags '(dsh-unit)
  (with-temp-buffer
    (dsh-emacs-mode)
    (setq-local dsh-emacs-tool-expand-by-default t)
    (dsh-emacs-render-tool-call
     (dsh-emacs-test--tool-call-event
      1 "j1" "job_output" "{\"job_id\":\"bash-7\",\"wait\":true}"))
    (dsh-emacs-render-tool-result
     (dsh-emacs-test--tool-result-event
      2 "j1" nil nil "step one\nstep two\n[status: running]"))
    (let ((body (dsh-emacs-test--tool-block-text
                 (dsh-emacs-render--make-namespace) "tool-j1")))
      (ert-info ((format "%s" "tool-job-output-card"))
        (should (eq 'success (plist-get (dsh-emacs-render--tool-state "j1") :state)))
        (should (string-match-p "step one" body))
        (should (string-match-p (regexp-quote "[status: running]") body))
        (should (not (string-match-p "job_id" body)))
        (should (not (string-match-p "^OUT$" body)))))))

;; The Host calls an exited background command completed even when its exit
;; code is nonzero.  The footer must distinguish that failure from exit 0.
(ert-deftest dsh-emacs-test-tools-tool-job-output-footer-case ()
  :tags '(dsh-unit)
  (dolist (case '(("completed, exit code: 0" dsh-emacs-tool-success-face)
                  ("completed, exit code: 2" dsh-emacs-tool-error-face)
                  ("completed, exit code: -1" dsh-emacs-tool-error-face)
                  ("completed" dsh-emacs-tool-success-face)))
    (with-temp-buffer
      (dsh-emacs-mode)
      (setq-local dsh-emacs-tool-expand-by-default t)
      (dsh-emacs-render-tool-call
       (dsh-emacs-test--tool-call-event
        1 "job-exit" "job_output" "{\"job_id\":\"bash-7\"}"))
      (let ((footer (format "[status: %s]" (car case))))
        (dsh-emacs-render-tool-result
         (dsh-emacs-test--tool-result-event
          2 "job-exit" nil nil (concat "command output\n" footer)))
        (let* ((text (buffer-string))
               (pos (string-match (regexp-quote footer) text)))
          (ert-info ((format "%s" (format "tool-job-output-footer-%s" (car case))))
            (should (and pos
                         (memq (cadr case)
                               (ensure-list (get-text-property pos 'face text)))))))))))

(ert-deftest dsh-emacs-test-tools-tool-job-list-card ()
  :tags '(dsh-unit)
  (with-temp-buffer
    (dsh-emacs-mode)
    (setq-local dsh-emacs-tool-expand-by-default t)
    (dsh-emacs-render-tool-call
     (dsh-emacs-test--tool-call-event 1 "j2" "job_list" "{}"))
    (dsh-emacs-render-tool-result
     (dsh-emacs-test--tool-result-event
      2 "j2" nil nil
      (concat "bash-7 [bash] running — make build\n"
              "bash-2 [bash] completed — cat > x.sh <<'PY'\necho hi")))
    (let ((body (dsh-emacs-test--tool-block-text
                 (dsh-emacs-render--make-namespace) "tool-j2")))
      (ert-info ((format "%s" "tool-job-list-card"))
        (should (string-match-p "bash-7 \\[bash\\] running — make build" body))
        (should (string-match-p "bash-2 \\[bash\\] completed — cat > x.sh" body))
        (should (string-match-p "^    echo hi$" body))
        (should (not (string-match-p "^OUT$" body)))))))

(ert-deftest dsh-emacs-test-tools-tool-job-kill-pending-summary-prefers-id ()
  :tags '(dsh-unit)
  (with-temp-buffer
    (dsh-emacs-mode)
    (setq-local dsh-emacs-tool-expand-by-default t)
    (dsh-emacs-render-tool-call
     (dsh-emacs-test--tool-call-event
      1 "j3" "job_kill" "{\"reason\":\"stale\",\"job_id\":\"bash-7\"}"))
    (ert-info ((format "%s" "tool-job-kill-pending-summary-prefers-id"))
      (should (equal "bash-7" (plist-get (dsh-emacs-render--tool-state "j3") :summary))))
    (dsh-emacs-render-tool-result
     (dsh-emacs-test--tool-result-event
      2 "j3" nil nil "requested cancellation of job bash-7"))
    (let ((body (dsh-emacs-test--tool-block-text
                 (dsh-emacs-render--make-namespace) "tool-j3")))
      (ert-info ((format "%s" "tool-job-kill-card"))
        (should (string-match-p "requested cancellation of job bash-7" body))
        (should (string-match-p "bash-7" (dsh-emacs-render--first-line body)))
        (should (not (string-match-p "reason" body)))
        (should (not (string-match-p "^OUT$" body)))))))

;; A `job_output' failure carries no status line; the generic card keeps the
;; diagnostic text and the argument JSON that names the job.
(ert-deftest dsh-emacs-test-tools-tool-job-output-without-status-keeps-iocard ()
  :tags '(dsh-unit)
  (with-temp-buffer
    (dsh-emacs-mode)
    (setq-local dsh-emacs-tool-expand-by-default t)
    (dsh-emacs-render-tool-call
     (dsh-emacs-test--tool-call-event
      1 "j4" "job_output" "{\"job_id\":\"nope\"}"))
    (dsh-emacs-render-tool-result
     (dsh-emacs-test--tool-result-event 2 "j4" t 1 "unknown job id nope"))
    (let ((body (dsh-emacs-test--tool-block-text
                 (dsh-emacs-render--make-namespace) "tool-j4")))
      (ert-info ((format "%s" "tool-job-output-without-status-keeps-iocard"))
        (should (eq 'error (plist-get (dsh-emacs-render--tool-state "j4") :state)))
        (should (string-match-p "unknown job id nope" body))
        (should (string-match-p "job_id" body))
        (should (string-match-p "^  OUT unknown job id nope$" body))))))

;; A `present' row names the files it declared in the header (web PresentRow)
;; and shows the result text as its body; the argument JSON is never repeated.
(ert-deftest dsh-emacs-test-tools-tool-present-summary-names-paths ()
  :tags '(dsh-unit)
  (with-temp-buffer
    (dsh-emacs-mode)
    (setq-local dsh-emacs-tool-expand-by-default t)
    (dsh-emacs-render-tool-call
     (dsh-emacs-test--tool-call-event
      1 "p1" "present"
      (concat "{\"files\":[{\"path\":\"report.md\","
              "\"description\":\"Final report\"},{\"path\":\"notes.txt\"}]}")))
    (ert-info ((format "%s" "tool-present-summary-names-paths"))
      (should (equal "report.md, notes.txt"
                     (plist-get (dsh-emacs-render--tool-state "p1") :summary))))
    (dsh-emacs-render-tool-result
     (dsh-emacs-test--tool-result-event
      2 "p1" nil nil "Presented report.md\nPresented notes.txt"))
    (let ((body (dsh-emacs-test--tool-block-text
                 (dsh-emacs-render--make-namespace) "tool-p1")))
      (ert-info ((format "%s" "tool-present-card"))
        (should (string-match-p "Present files" body))
        (should (string-match-p "report.md, notes.txt" body))
        (should (string-match-p "Presented report.md" body))
        (should (string-match-p "Presented notes.txt" body))
        (should (not (string-match-p "\"files\"" body)))
        (should (not (string-match-p "^OUT$" body)))))))

;; A failed `present' keeps the Host's message and the declared-path summary.
(ert-deftest dsh-emacs-test-tools-tool-present-failure-keeps-diagnostic ()
  :tags '(dsh-unit)
  (with-temp-buffer
    (dsh-emacs-mode)
    (setq-local dsh-emacs-tool-expand-by-default t)
    (dsh-emacs-render-tool-call
     (dsh-emacs-test--tool-call-event
      1 "p2" "present" "{\"files\":[{\"path\":\"missing.txt\"}]}"))
    (dsh-emacs-render-tool-result
     (dsh-emacs-test--tool-result-event
      2 "p2" t 1 "Cannot present missing.txt: not a regular file"))
    (let ((body (dsh-emacs-test--tool-block-text
                 (dsh-emacs-render--make-namespace) "tool-p2")))
      (ert-info ((format "%s" "tool-present-failure-keeps-diagnostic"))
        (should (eq 'error (plist-get (dsh-emacs-render--tool-state "p2") :state)))
        (should (string-match-p "Cannot present missing.txt" body))
        (should (string-match-p "missing.txt" (dsh-emacs-render--first-line body)))
        (should (not (string-match-p "\"files\"" body)))
        (should (not (string-match-p "^OUT$" body)))))))

;; Metadata line numbers before the declared offset invalidate the window.
;; The raw output must survive rather than being replaced by unrelated lines.
(ert-deftest dsh-emacs-test-tools-tool-read-before-offset-keeps-raw-output ()
  :tags '(dsh-unit)
  (with-temp-buffer
    (dsh-emacs-mode)
    (setq-local dsh-emacs-tool-expand-by-default t)
    (dsh-emacs-render-tool-call
     (dsh-emacs-test--tool-call-event
      1 "bad-window" "read" "{\"file_path\":\"/a\",\"offset\":10}"))
    (dsh-emacs-render-tool-result
     (dsh-emacs-test--tool-result-event-meta
      2 "bad-window"
      "<path>/a</path>\n<type>file</type>\n<content>\n10: actual window\n</content>"
      '((path . "/a") (offset . 10) (totalLines . 20)
        (lines . [((number . 1) (text . "wrong window"))]))))
    (let ((body (dsh-emacs-test--tool-block-text
                 (dsh-emacs-render--make-namespace) "tool-bad-window")))
      (ert-info ((format "%s" "tool-read-before-offset-keeps-raw-output"))
        (should (string-match-p "10: actual window" body))
        (should (string-match-p "file_path" body))
        (should (not (string-match-p "wrong window" body)))))))

;; A host with a raised read byte cap can return a large, valid envelope.
;; Rendering must complete without consuming regexp stack per character.
(ert-deftest dsh-emacs-test-tools-tool-large-read-completes-numbered-card ()
  :tags '(dsh-unit)
  (with-temp-buffer
    (dsh-emacs-mode)
    (setq-local dsh-emacs-tool-expand-by-default t)
    (let* ((line (make-string 1000 ?x))
           (lines (vconcat
                   (cl-loop for n from 1 to 150
                            collect (list (cons 'number n) (cons 'text line)))))
           (text (concat
                  "<path>/large.txt</path>\n<type>file</type>\n<content>\n"
                  (mapconcat (lambda (cell)
                               (format "%d: %s" (alist-get 'number cell)
                                       (alist-get 'text cell)))
                             lines "\n")
                  "\n\n(End of file - total 150 lines)\n</content>"))
           (meta `((path . "/large.txt") (offset . 1) (totalLines . 150)
                   (lines . ,lines))))
      (dsh-emacs-render-tool-call
       (dsh-emacs-test--tool-call-event
        1 "large-read" "read" "{\"file_path\":\"/large.txt\"}"))
      (progn
        (dsh-emacs-render-tool-result
         (dsh-emacs-test--tool-result-event-meta 2 "large-read" text meta))
        (let ((body (dsh-emacs-test--tool-block-text
                     (dsh-emacs-render--make-namespace) "tool-large-read")))
          (ert-info ((format "%s" "tool-large-read-completes-numbered-card"))
            (should (eq 'success (plist-get
                                  (dsh-emacs-render--tool-state "large-read") :state)))
            (should (string-match-p (concat "  150  " line) body))
            (should (not (string-match-p "<content>" body)))))))))

;; Checking the envelope ends separately still rejects non-file results,
;; truncated envelopes, trailing output, and overlapping opening/closing tags.
;; Cases carry a short label: interpolating the multi-line result itself would
;; break the one-line-per-assertion output.
(ert-deftest dsh-emacs-test-tools-tool-read-rejects-envelope-case ()
  :tags '(dsh-unit)
  (dolist (case '(("directory-type" . "<path>/a</path>\n<type>directory</type>\n<content>\nx\n</content>")
                  ("no-path-tag" . "<type>file</type>\n<content>\nx\n</content>")
                  ("truncated" . "<path>/a</path>\n<type>file</type>\n<content>\nx")
                  ("trailing-output" . "<path>/a</path>\n<type>file</type>\n<content>\nx\n</content>extra")
                  ("overlapping-tags" . "<path>/a</path>\n<type>file</type>\n<content>\n</content>")))
    (ert-info ((format "%s" (format "tool-read-rejects-envelope-%s" (car case))))
      (should (null (dsh-emacs-render--read-card-body
                     "read" "{\"file_path\":\"/a\"}"
                     '((path . "/a") (offset . 1) (totalLines . 1)
                       (lines . [((number . 1) (text . "x"))]))
                     (cdr case)))))))

;; A malformed result body must not signal out of the renderer either: a
;; non-array `content', or an array whose members are not objects, settles the
;; call with no usable result text instead of raising `sequencep'.
(ert-deftest dsh-emacs-test-tools-tool-read-malformed-output ()
  :tags '(dsh-unit)
  (dolist (content '(42 "invalid" [42] [[]] t))
    (with-temp-buffer
      (dsh-emacs-mode)
      (setq-local dsh-emacs-tool-expand-by-default t)
      (dsh-emacs-render-tool-call
       (dsh-emacs-test--tool-call-event
        1 "bad-content" "bash" "{\"command\":\"ls\"}"))
      (let ((label (format "tool-malformed-content-%S" content)))
        (progn
          (dsh-emacs-render-tool-result
           (dsh-emacs-test--tool-result-event-bare 2 "bad-content" content))
          ;; The event carries no usable tool-result block, so the call still
          ;; settles, with no result text to show.
          (ert-info ((format "%s" label))
            (should (let ((state (dsh-emacs-render--tool-state "bad-content")))
                      (and (eq 'success (plist-get state :state))
                           (equal "" (or (plist-get state :result) "")))))))))))

;; Malformed metadata must not leave a completed tool pending.  Exercise
;; non-object metadata and non-object array members through the result path.
(ert-deftest dsh-emacs-test-tools-tool-read-source-validation ()
  :tags '(dsh-unit)
  (dolist (name '("read" "edit" "write"))
    (dolist (bad '(42 t :json-false "invalid" [42]))
      (dolist (nested '(nil t))
        (with-temp-buffer
          (dsh-emacs-mode)
          (setq-local dsh-emacs-tool-expand-by-default t)
          (let* ((read-p (equal name "read"))
                 (meta (if (not nested) bad
                         (if read-p
                             `((path . "/a.txt") (offset . 1) (totalLines . 1)
                               (lines . ,(vector bad)))
                           `((diffs . ,(vector bad))))))
                 (text (if read-p
                           (concat "<path>/a.txt</path>\n<type>file</type>\n"
                                   "<content>\n1: actual\n</content>")
                         "completed mutation"))
                 (label (format "tool-%s-malformed-meta-%S-nested-%S"
                                name bad nested)))
            (dsh-emacs-render-tool-call
             (dsh-emacs-test--tool-call-event
              1 "bad-meta" name
              (concat "{\"file_path\":\"/a.txt\",\"old_string\":\"old\","
                      "\"new_string\":\"new\",\"content\":\"written\"}")))
            (progn
              (dsh-emacs-render-tool-result
               (dsh-emacs-test--tool-result-event-meta 2 "bad-meta" text meta))
              (let ((body (dsh-emacs-test--tool-block-text
                           (dsh-emacs-render--make-namespace) "tool-bad-meta")))
                (ert-info ((format "%s" label))
                  (should (eq 'success (plist-get
                                        (dsh-emacs-render--tool-state "bad-meta") :state)))
                  (should (if (equal name "write")
                              (string-match-p (regexp-quote "+ written") body)
                            (and (string-match-p
                                  (if read-p "1: actual" "completed mutation") body)
                                 (string-match-p "file_path" body)))))))))))))

;; A hunk's line split matches dsh web's `wo': one trailing newline is markup,
;; a further empty line is a real line.
(ert-deftest dsh-emacs-test-tools-diff-lines-drop-one-trailing-newline ()
  :tags '(dsh-unit)
  (ert-info ((format "%s" "diff-lines-drop-one-trailing-newline"))
    (should (null (dsh-emacs-render--diff-lines "")))
    (should (equal '("a") (dsh-emacs-render--diff-lines "a\n")))
    (should (equal '("a" "") (dsh-emacs-render--diff-lines "a\n\n")))
    (should (equal '("a" "" "b") (dsh-emacs-render--diff-lines "a\n\nb")))))

;; --- Test 30: blank tool results hide the OUT section ---
(ert-deftest dsh-emacs-test-tools-tool-no-output-hides-out-section ()
  :tags '(dsh-unit)
  (with-temp-buffer
    (dsh-emacs-mode)
    (dsh-emacs-modeline-setup)
    (setq-local dsh-emacs-tool-expand-by-default t)
    (dsh-emacs-render-tool-call
     (dsh-emacs-test--tool-call-event 1 "c3" "read" "{\"path\":\"/a/b.txt\"}"))
    (dsh-emacs-render-tool-result
     (dsh-emacs-test--tool-result-event 2 "c3" nil 0 ""))
    (let* ((ns (dsh-emacs-render--make-namespace))
           (block (dsh-emacs-test--tool-block-text ns "tool-c3")))
      (ert-info ((format "%s" "tool-no-output-hides-OUT-section"))
        (should (and block
                     (string-match-p "IN" block)
                     (not (string-match-p "OUT" block))))))))

;; --- Test 31: collapsed tool lines are compact (no ellipsis/blank) + expanding
;; restores the bash terminal card ---
(ert-deftest dsh-emacs-test-tools-tool-collapsed-single-line ()
  :tags '(dsh-unit)
  (with-temp-buffer
    (dsh-emacs-mode)
    (dsh-emacs-modeline-setup)
    ;; Keeps the default collapsed state (expand-by-default is unbound)
    (dsh-emacs-render-tool-call
     (dsh-emacs-test--tool-call-event 1 "x1" "bash" "{\"description\":\"list\",\"command\":\"ls\"}"))
    (dsh-emacs-render-tool-result
     (dsh-emacs-test--tool-result-event 2 "x1" nil 0 "file-a"))
    (let* ((ns (dsh-emacs-render--make-namespace))
           (block (dsh-emacs-test--tool-block-text ns "tool-x1")))
      (ert-info ((format "%s" "tool-collapsed-single-line"))
        (should (and block
                     ;; When collapsed it is a single line: it has the header, no ellipsis
                     ;; placeholder,
                     ;; no card body
                     (string-match-p "Bash" block)
                     (not (string-match-p (regexp-quote "$ ls") block))
                     (not (string-match-p "IN" block))
                     (not (string-match-p "OUT" block))
                     (string-match-p "list" block))))
      ;; Expanding should restore the terminal card body ($ prompt line + output; no
      ;; ✓ footer on a clean exit), and collapsing again returns to a single line
      (dsh-emacs-ui-toggle-fragment)
      (let* ((expanded (dsh-emacs-test--tool-block-text ns "tool-x1")))
        (ert-info ((format "%s" "tool-bash-expand-restores-terminal-card"))
          (should (and expanded
                       (string-match-p (regexp-quote "$ ls") expanded)
                       (string-match-p "file-a" expanded)
                       (not (string-match-p (regexp-quote "✓ exit 0") expanded))
                       (not (string-match-p "IN" expanded)))))
        (dsh-emacs-ui-toggle-fragment)
        (let ((recollapsed (dsh-emacs-test--tool-block-text ns "tool-x1")))
          (ert-info ((format "%s" "tool-recollapse-single-line"))
            (should (and recollapsed
                         (not (string-match-p (regexp-quote "$ ls") recollapsed))
                         (string-match-p "Bash" recollapsed)))))))))

;; --- Test 31b: the generic ioCard is one aligned block — both labels share a
;; column, the IN value is flattened to a single row, OUT keeps its lines
;; hanging at the text column under a content-sized divider, and a clean
;; success prints no status line ---
(ert-deftest dsh-emacs-test-tools-tool-io-in-is-one-row ()
  :tags '(dsh-unit)
  (with-temp-buffer
    (dsh-emacs-mode)
    (dsh-emacs-modeline-setup)
    (setq-local dsh-emacs-tool-expand-by-default t)
    (dsh-emacs-render-tool-call
     (dsh-emacs-test--tool-call-event 1 "g1" "my_tool" "{\"x\":\"1\"}"))
    (dsh-emacs-render-tool-result
     (dsh-emacs-test--tool-result-event 2 "g1" nil nil "ok\nsecond line"))
    (let ((block (dsh-emacs-test--tool-block-text
                  (dsh-emacs-render--make-namespace) "tool-g1")))
      (ert-info ((format "%s" "tool-io-in-is-one-row"))
        (should (string-match-p "^  IN  { \"x\": \"1\" }$" block)))
      (ert-info ((format "%s" "tool-io-out-hangs-under-its-column"))
        (should (string-match-p "^  OUT ok$" block))
        (should (string-match-p "^      second line$" block)))
      (ert-info ((format "%s" "tool-io-divider-and-success-has-no-status-line"))
        (should (string-match-p "^  ─\\{4,\\}$" block))
        (should (not (string-match-p (regexp-quote "✓ exit 0") block)))))))

;; --- Test 31c: a zero-argument generic call drops the empty IN section and
;; keeps its input out of the header entirely ---
(ert-deftest dsh-emacs-test-tools-tool-io-empty-args-hide-in ()
  :tags '(dsh-unit)
  (with-temp-buffer
    (dsh-emacs-mode)
    (dsh-emacs-modeline-setup)
    (setq-local dsh-emacs-tool-expand-by-default t)
    (dsh-emacs-render-tool-call
     (dsh-emacs-test--tool-call-event 1 "g2" "dev_injected_list" "{}"))
    (dsh-emacs-render-tool-result
     (dsh-emacs-test--tool-result-event 2 "g2" nil nil "（无注入记录）"))
    (let* ((block (dsh-emacs-test--tool-block-text
                   (dsh-emacs-render--make-namespace) "tool-g2"))
           (header (dsh-emacs-render--first-line block)))
      (ert-info ((format "%s" "tool-io-empty-args-hide-IN"))
        (should (not (string-match-p "^  IN" block))))
      (ert-info ((format "%s" "tool-generic-header-hides-empty-input"))
        (should (string-match-p "● Tool Call · dev_injected_list$" header))
        (should (not (string-match-p "{}" header)))
        (should (string-match-p "^  OUT （无注入记录）$" block))))))

;; --- Test 31e: a known-variant row whose arguments yield no summary still
;; falls back to the result preview in the header ---
(ert-deftest dsh-emacs-test-tools-tool-known-variant-result-preview-summary ()
  :tags '(dsh-unit)
  (with-temp-buffer
    (dsh-emacs-mode)
    (dsh-emacs-modeline-setup)
    (dsh-emacs-render-tool-call
     (dsh-emacs-test--tool-call-event 1 "g4" "glob" "{}"))
    (dsh-emacs-render-tool-result
     (dsh-emacs-test--tool-result-event 2 "g4" nil nil "alpha.md\nbeta.md"))
    (let ((block (dsh-emacs-test--tool-block-text
                  (dsh-emacs-render--make-namespace) "tool-g4")))
      (ert-info ((format "%s" "tool-known-variant-result-preview-summary"))
        (should (string-match-p "● Glob · alpha.md …" block))))))

;; --- Test 31d: a failed generic call keeps its status line above the block ---
(ert-deftest dsh-emacs-test-tools-tool-io-failure-keeps-status-line ()
  :tags '(dsh-unit)
  (with-temp-buffer
    (dsh-emacs-mode)
    (dsh-emacs-modeline-setup)
    (setq-local dsh-emacs-tool-expand-by-default t)
    (dsh-emacs-render-tool-call
     (dsh-emacs-test--tool-call-event 1 "g3" "dev_plugin_status" "{}"))
    (dsh-emacs-render-tool-result
     (dsh-emacs-test--tool-result-event 2 "g3" t 1 "boom"))
    (let ((block (dsh-emacs-test--tool-block-text
                  (dsh-emacs-render--make-namespace) "tool-g3")))
      (ert-info ((format "%s" "tool-io-failure-keeps-status-line"))
        (should (string-match-p (regexp-quote "✗ exit 1") block))
        (should (string-match-p "^  OUT boom$" block))))))

;; --- Test 32: tool name decoupled from icon — same icon, different name ---
(ert-deftest dsh-emacs-test-tools-tool-grep-title-distinct-from-search ()
  :tags '(dsh-unit)
  (with-temp-buffer
    (dsh-emacs-mode)
    (dsh-emacs-modeline-setup)
    (dsh-emacs-render-tool-call
     (dsh-emacs-test--tool-call-event 1 "g1" "grep" "{\"pattern\":\"foo\"}"))
    (let* ((ns (dsh-emacs-render--make-namespace))
           (block (dsh-emacs-test--tool-block-text ns "tool-g1")))
      (ert-info ((format "%s" "tool-grep-title-distinct-from-search"))
        (should (and block
                     (string-match-p "● Grep" block)       ; leading dot + real tool name
                     (not (string-match-p "Search" block)) ; must no longer render as Search
                     (not (string-match-p "· Search" block))))))))

(ert-deftest dsh-emacs-test-tools-tool-web-search-title-stays-distinct ()
  :tags '(dsh-unit)
  (with-temp-buffer
    (dsh-emacs-mode)
    (dsh-emacs-modeline-setup)
    (dsh-emacs-render-tool-call
     (dsh-emacs-test--tool-call-event 1 "w1" "web_search" "{\"query\":\"cats\"}"))
    (let* ((ns (dsh-emacs-render--make-namespace))
           (block (dsh-emacs-test--tool-block-text ns "tool-w1")))
      (ert-info ((format "%s" "tool-web-search-title-stays-distinct"))
        (should (and block
                     (string-match-p "● Web Search" block)
                     (not (string-match-p "● Search · cats" block))))))))

;; web_search's SVG icon is overridden to a globe (harness WebRow: globe for web
;; search, magnifier family for grep/glob), and it differs from the search
;; variant's magnifier
(ert-deftest dsh-emacs-test-tools-tool-web-search-globe-svg-override ()
  :tags '(dsh-unit)
  (ert-info ((format "%s" "tool-web-search-globe-svg-override"))
    (should (and (string= (cdr (assoc "web_search" dsh-emacs--tool-name-icon-keys)) "web")
                 (string-match-p "fill-rule=\"evenodd\""
                                 (dsh-emacs-render--tool-icon-svg "search" "#a78bfa" "web_search"))
                 (not (string-equal
                       (dsh-emacs-render--tool-icon-svg "search" "#a78bfa" "web_search")
                       (dsh-emacs-render--tool-icon-svg "search" "#a78bfa")))))))

(ert-deftest dsh-emacs-test-tools-tool-generic-header-is-tool-call-name ()
  :tags '(dsh-unit)
  (with-temp-buffer
    (dsh-emacs-mode)
    (dsh-emacs-modeline-setup)
    (setq-local dsh-emacs-tool-expand-by-default t)
    (dsh-emacs-render-tool-call
     (dsh-emacs-test--tool-call-event 1 "u1" "my_tool" "{\"x\":\"1\"}"))
    (dsh-emacs-render-tool-result
     (dsh-emacs-test--tool-result-event 2 "u1" nil nil "ok"))
    (let* ((ns (dsh-emacs-render--make-namespace))
           (block (dsh-emacs-test--tool-block-text ns "tool-u1"))
           (header (dsh-emacs-render--first-line block)))
      (ert-info ((format "%s" "tool-generic-header-is-tool-call-name"))
        (should (string-match-p "● Tool Call · my_tool$" header))
        (should (not (string-match-p "{\"x\"" header))))
      (ert-info ((format "%s" "tool-generic-input-only-when-expanded"))
        (should (string-match-p "^  IN  { \"x\": \"1\" }$" block))))))

;; A curated title still owns the row (present / job rows keep their documented
;; headers and summaries) and is not rewritten to the generic format.
(ert-deftest dsh-emacs-test-tools-tool-title-defcustom-override ()
  :tags '(dsh-unit)
  (with-temp-buffer
    (dsh-emacs-mode)
    (dsh-emacs-modeline-setup)
    (let ((dsh-emacs-tool-titles '(("my_tool" . "Curated")))) ; defcustom override
      (dsh-emacs-render-tool-call
       (dsh-emacs-test--tool-call-event 1 "u2" "my_tool" "{\"x\":\"1\"}")))
    (let* ((ns (dsh-emacs-render--make-namespace))
           (block (dsh-emacs-test--tool-block-text ns "tool-u2")))
      (ert-info ((format "%s" "tool-title-defcustom-override"))
        (should (string-match-p "● Curated" block))
        (should (not (string-match-p "Tool Call" block)))))))

;; --- Test 33: adjacent tool lines stack compactly (no extra blank lines) ---
(defun dsh-emacs-test--t32-call (seq id name args)
  (list (cons "type" "tool/call") (cons "seq" seq)
        (cons "data" (list (cons "callId" id) (cons "name" name)
                           (cons "arguments" args)))))

(defun dsh-emacs-test--t32-result (seq id text)
  (list (cons "type" "tool/result") (cons "seq" seq)
        (cons "data" (list (cons "message"
                                 (list (cons "callId" id)
                                       (cons "content"
                                             (vector (list (cons "type" "tool-result")
                                                           (cons "isError" :json-false)
                                                           (cons "exitCode" 0)
                                                           (cons "content"
                                                                 (vector (list (cons "type" "text")
                                                                               (cons "text" text)))))))))))))

(ert-deftest dsh-emacs-test-tools-tool-adjacent-stack-tight ()
  :tags '(dsh-unit)
  (with-temp-buffer
    (dsh-emacs-mode)
    (dsh-emacs-modeline-setup)
    (dsh-emacs-render-tool-call
     (dsh-emacs-test--t32-call 1 "y1" "search" "{\"query\":\"*.md\"}"))
    (dsh-emacs-render-tool-result (dsh-emacs-test--t32-result 2 "y1" "a"))
    (dsh-emacs-render-tool-call
     (dsh-emacs-test--t32-call 3 "y2" "read" "{\"path\":\"/tmp/x\"}"))
    (dsh-emacs-render-tool-result (dsh-emacs-test--t32-result 4 "y2" "b"))
    (when-let* ((line-search (save-excursion
                               (goto-char (point-min))
                               (when (search-forward "Search" nil t)
                                 (line-number-at-pos (match-beginning 0)))))
                (line-read (save-excursion
                             (goto-char (point-min))
                             (when (search-forward "Read" nil t)
                               (line-number-at-pos (match-beginning 0))))))
      ;; Two collapsed tools should occupy two adjacent lines (no blank line or ellipsis
      ;; placeholder in between)
      (ert-info ((format "%s" "tool-adjacent-stack-tight"))
        (should (= line-read (1+ line-search)))))))

;; --- Test 34: running tools have no spinner animation (leading icon) + the line
;; does not vanish on completion ---
(ert-deftest dsh-emacs-test-tools-running-tool-no-spinner ()
  :tags '(dsh-unit)
  (with-temp-buffer
    (dsh-emacs-mode)
    (setq-local dsh-emacs-tool-expand-by-default t)
    (dsh-emacs-render-tool-call
     (dsh-emacs-test--tool-call-event 1 "c1" "bash" "{\"command\":\"ls -la\"}"))
    (let* ((st (dsh-emacs-render--tool-state "c1"))
           (ns (plist-get st :ns))
           (block-id (dsh-emacs-render--tool-call-block-id "c1")))
      ;; Initial render: the line starts with the leading dot (no spinner gear), no
      ;; trailing …
      (when-let* ((b (dsh-emacs-ui-find-block ns block-id)))
        (let ((txt (buffer-substring-no-properties (car b) (cdr b))))
          (ert-info ((format "%s" "running-tool-no-spinner"))
            (should (and (string-match-p (regexp-quote "● ") txt)
                         (not (string-match-p "⚙" txt))
                         (not (string-match-p "…" txt)))))))
      ;; After the tool completes the line still renders into the same block
      ;; (does not disappear): bash card contains the $ prompt + output
      (dsh-emacs-render-tool-result
       (dsh-emacs-test--tool-result-event 2 "c1" nil 0 "total 3\ndrwxrwxr-x"))
      (when-let* ((b (dsh-emacs-ui-find-block ns block-id)))
        (let ((txt (buffer-substring-no-properties (car b) (cdr b))))
          (ert-info ((format "%s" "tool-row-not-lost-after-result"))
            (should (and (string-match-p (regexp-quote "● ") txt)
                         (string-match-p (regexp-quote "$ ls -la") txt)
                         (string-match-p "drwxrwxr-x" txt)))))))))

;; --- Test 34c: terminal card for bash nonzero exit / multi-line command ---
(ert-deftest dsh-emacs-test-tools-tool-bash-error-terminal-card ()
  :tags '(dsh-unit)
  (with-temp-buffer
    (dsh-emacs-mode)
    (setq-local dsh-emacs-tool-expand-by-default t)
    (dsh-emacs-render-tool-call
     (dsh-emacs-test--tool-call-event 1 "x1" "bash"
                                      "{\"description\":\"build+test\",\"command\":\"make build\\nmake test\"}"))
    (dsh-emacs-render-tool-result
     (dsh-emacs-test--tool-result-event 2 "x1" nil 1 "make: *** No rule.  Stop."))
    (let* ((ns (dsh-emacs-render--make-namespace))
           (block (dsh-emacs-test--tool-block-text ns "tool-x1")))
      (ert-info ((format "%s" "tool-bash-error-terminal-card"))
        (should (and block
                     ;; The command area is a single line (a multi-line command is flattened to
                     ;; one
                     ;; line with only one $ prompt); the error footer carries an exit code
                     (string-match-p (regexp-quote "$ make build") block)
                     (not (string-match-p (regexp-quote "$ make test") block))
                     (string-match-p "make test" block)
                     (string-match-p "make: \\*\\*\\* No rule" block)
                     (string-match-p (regexp-quote "✗ exit 1") block)))))))

;; --- Test 34d: bash command area single-line and elided when overlong ---
(ert-deftest dsh-emacs-test-tools-tool-bash-command-single-line-ellipsis ()
  :tags '(dsh-unit)
  (let ((long-cmd (mapconcat #'identity
                             (make-list 8 "step --flag=very-long-option-name")
                             "\\n")))
    (with-temp-buffer
      (dsh-emacs-mode)
      (setq-local dsh-emacs-tool-expand-by-default t)
      (dsh-emacs-render-tool-call
       (dsh-emacs-test--tool-call-event 1 "d1" "bash"
                                        (concat "{\"description\":\"many steps\",\"command\":\"" long-cmd "\"}")))
      (dsh-emacs-render-tool-result
       (dsh-emacs-test--tool-result-event 2 "d1" nil 0 "ok"))
      (let* ((ns (dsh-emacs-render--make-namespace))
             (block (dsh-emacs-test--tool-block-text ns "tool-d1"))
             (occ (let ((n 0) (pos 0))
                    (while (string-match (regexp-quote "$ ") block pos)
                      (setq n (1+ n) pos (match-end 0)))
                    n)))
        (ert-info ((format "%s" "tool-bash-command-single-line-ellipsis"))
          (should (and block
                       (= occ 1)
                       (string-match-p "…" block))))))))

;; --- Test 34b: tool line right after a user message: keep one blank line ---
(ert-deftest dsh-emacs-test-tools-tool-after-user-keeps-one-blank ()
  :tags '(dsh-unit)
  (let ((buf (generate-new-buffer " *t34b-layout*")))
    (unwind-protect
        (with-current-buffer buf
          (dsh-emacs-mode)
          (dsh-emacs-modeline-setup)
          (setq-local dsh-emacs-tool-expand-by-default t)
          (dsh-emacs-render-event
           (json-read-from-string
            "{\"type\":\"user/message\",\"seq\":1,\"data\":{\"content\":[{\"type\":\"text\",\"text\":\"u2\"}]}}"))
          (dsh-emacs-render-tool-call
           (dsh-emacs-test--tool-call-event 2 "t1" "bash" "{\"command\":\"ls\"}"))
          (let* ((user-line
                  (save-excursion
                    (goto-char (point-min))
                    (when (search-forward "u2" nil t)
                      (line-number-at-pos (line-beginning-position)))))
                 (tool-line
                  (save-excursion
                    (goto-char (point-min))
                    (when (search-forward "● " nil t)
                      (line-number-at-pos (line-beginning-position))))))
            (ert-info ((format "%s" "tool-after-user-keeps-one-blank"))
              (should (and user-line tool-line (= tool-line (+ user-line 2)))))))
      (kill-buffer buf))))

;; --- Test 35: real historical tool/result uses message.source.callId ---
(ert-deftest dsh-emacs-test-tools-history-tool-result-no-spinner ()
  :tags '(dsh-unit)
  (with-temp-buffer
    (dsh-emacs-mode)
    (dsh-emacs-modeline-setup)
    (let ((call (dsh-emacs-test--tool-call-event
                 10 "history-call" "bash" "{\"command\":\"pwd\"}"))
          (result (dsh-emacs-test--tool-result-event-source
                   11 "history-call" "/tmp/project")))
      (dsh-emacs-render-history-events
       (list (list (cons "event" call))
             (list (cons "event" result)))
       nil)
      (let ((state (dsh-emacs-render--tool-state "history-call")))
        (ert-info ((format "%s" "history-tool-result-no-spinner"))
          (should (eq (plist-get state :state) 'success)))))))

;; --- Test 56b: tool card state coloring covers only the header line;
;; the expanded body (IN/OUT) must not inherit it (generic ioCard such
;; as Edit/Read; regression: the old whole-block face tinted the body
;; green/red bold too) ---
(ert-deftest dsh-emacs-test-tools-tool-case-header-tinted ()
  :tags '(dsh-unit)
  (dolist (case '(("read" "{\"path\":\"foo.el\"}" nil 0 "line one\nline two")
                  ("edit" "{\"path\":\"bar.el\"}" t 1 "no match found")))
    (let ((buf (generate-new-buffer " *dsh-tool-face*")))
      (unwind-protect
          (with-current-buffer buf
            (dsh-emacs-mode)
            (dsh-emacs-modeline-setup)
            ;; The card must be expanded, otherwise the body range is empty and
            ;; the "body not tinted" assertion passes vacuously.
            (setq-local dsh-emacs-tool-expand-by-default t)
            (let* ((name (nth 0 case))
                   (args (nth 1 case))
                   (is-error (nth 2 case))
                   (exit-code (nth 3 case))
                   (out (nth 4 case))
                   (state-face (if is-error
                                   'dsh-emacs-tool-error-face
                                 'dsh-emacs-tool-success-face)))
              (dsh-emacs-render-tool-call
               (dsh-emacs-test--tool-call-event 1 "c1" name args))
              (dsh-emacs-render-tool-result
               (dsh-emacs-test--tool-result-event 2 "c1" is-error exit-code out))
              (let* ((ns (dsh-emacs-render--make-namespace))
                     (block (dsh-emacs-ui-find-block ns "tool-c1"))
                     (header-end (and block
                                      (save-excursion
                                        (goto-char (car block))
                                        (line-end-position))))
                     (body-start (and block
                                      (save-excursion
                                        (goto-char (car block))
                                        (forward-line 1)
                                        (point)))))
                (ert-info ((format "%s" (format "tool-%s-header-tinted" name)))
                  (should (and block header-end
                               (seq-every-p
                                (lambda (pos)
                                  (memq state-face (dsh-test--faces-at pos)))
                                (number-sequence (car block) header-end)))))
                ;; The body must really be expanded and contain the result text;
                ;; an empty range makes the assertion vacuous
                (ert-info ((format "%s" (format "tool-%s-body-not-tinted" name)))
                  (should (and block body-start (< body-start (cdr block))
                               (string-match-p (regexp-quote (car (split-string out "\n")))
                                               (buffer-substring-no-properties
                                                body-start (cdr block)))
                               (seq-every-p
                                (lambda (pos)
                                  (not (memq state-face (dsh-test--faces-at pos))))
                                (number-sequence body-start (1- (cdr block))))))))))
        (kill-buffer buf)))))

;; --- Test 56c: a settled tool error shows `error.reason' (dsh 0.1.6) ---
;; The host keeps the raw user-facing reason OUTSIDE the model-facing
;; `message', so the card is the only place a refusal explains itself:
;; without it the ioCard/bash footer says just "✗ failed"/"✗ exit N".
(ert-deftest dsh-emacs-test-tools-tool-case-error-reason ()
  :tags '(dsh-unit)
  (dolist (case '(("grep" "{\"pattern\":\"x\"}" nil "✗ failed — Auto review denied this call")
                  ("bash" "{\"command\":\"rm -rf /\"}" 1 "✗ exit 1 — Auto review denied this call")))
    (let ((buf (generate-new-buffer " *dsh-tool-error-reason*")))
      (unwind-protect
          (with-current-buffer buf
            (dsh-emacs-mode)
            (dsh-emacs-modeline-setup)
            ;; The status line lives in the body, so expand it: a collapsed
            ;; card would make the assertion vacuous.
            (setq-local dsh-emacs-tool-expand-by-default t)
            (dsh-emacs-render-tool-call
             (dsh-emacs-test--tool-call-event 1 "r1" (nth 0 case) (nth 1 case)))
            (dsh-emacs-render-tool-result
             (dsh-emacs-test--tool-result-event
              2 "r1" t (nth 2 case) "refused"
              '((name . "AutoReview") (code . "denied")
                (reason . "Auto review denied this call"))))
            (let* ((ns (dsh-emacs-render--make-namespace))
                   (block (dsh-emacs-test--tool-block-text ns "tool-r1")))
              (ert-info ((format "%s" (format "tool-%s-error-reason" (nth 0 case))))
                (should (and block
                             (string-match-p (regexp-quote (nth 3 case)) block))))))
        (kill-buffer buf)))))

;; --- Test 56d: a reason-less (or whitespace-only) reason keeps the old
;; status text: the 0.1.6 field is optional, and an absent `reason' must
;; not turn "✗ failed" into "✗ failed — " ---
(ert-deftest dsh-emacs-test-tools-tool-status-no-reason-case ()
  :tags '(dsh-unit)
  (let ((i 0))
    (dolist (error '(nil ((name . "X") (code . "y"))
                         ((name . "X") (code . "y") (reason . "   "))))
      (ert-info ((format "%s" (format "tool-status-no-reason-%d" i)))
        (should (equal "✗ failed"
                       (dsh-emacs-render--tool-status-text
                        'error nil nil (cdr (assq 'reason error))))))
      (setq i (1+ i)))))

(ert-deftest dsh-emacs-test-tools-tool-status-reason-newlines-collapse ()
  :tags '(dsh-unit)
  (ert-info ((format "%s" "tool-status-reason-newlines-collapse"))
    (should (equal "✗ failed — line one line two"
                   (dsh-emacs-render--tool-status-text 'error nil nil "line one\nline two")))))

(ert-deftest dsh-emacs-test-tools-tool-status-reason-ignored-when-not-error ()
  :tags '(dsh-unit)
  (ert-info ((format "%s" "tool-status-reason-ignored-when-not-error"))
    (should (equal "✓ exit 0"
                   (dsh-emacs-render--tool-status-text 'success 0 nil "not a failure")))))

(ert-deftest dsh-emacs-test-tools-collapsed-bodies-format-on-demand ()
  :tags '(dsh-unit)
  (dolist (case '(("bash" "{\"command\":\"printf lazy\"}"
                  dsh-emacs-render--bash-card-body)
                 ("read" "{\"file_path\":\"file.txt\"}"
                  dsh-emacs-render--read-card-body)
                 ("edit" "{\"file_path\":\"file.txt\",\"old_string\":\"a\",\"new_string\":\"b\"}"
                  dsh-emacs-render--diff-card-body)
                 ("custom" "{}" dsh-emacs-render--tool-body-io)))
    (pcase-let ((`(,name ,args ,formatter) case))
      (with-temp-buffer
        (dsh-emacs-mode)
        (let ((dsh-emacs-tool-expand-by-default nil)
              (calls 0))
          (cl-letf (((symbol-function formatter)
                     (lambda (&rest _) (format "formatted-%d" (cl-incf calls)))))
            (dsh-emacs-render-tool-call
             (dsh-emacs-test--tool-call-event 1 "lazy" name args))
            (dsh-emacs-render-tool-result
             (dsh-emacs-test--tool-result-event-meta 2 "lazy" "first result" nil))
            (should (= calls 0))
            (let ((block (dsh-emacs-ui-find-block
                          (dsh-emacs-render--make-namespace)
                          (dsh-emacs-render--tool-call-block-id "lazy"))))
              (should block)
              (goto-char (car block)))
            (dsh-emacs-ui-toggle-fragment)
            (should (= calls 1))
            (should (string-match-p "formatted-1" (buffer-string)))
            (dsh-emacs-ui-toggle-fragment)
            (dsh-emacs-ui-toggle-fragment)
            (should (= calls 1))
            (dsh-emacs-render-tool-result
             (dsh-emacs-test--tool-result-event-meta 3 "lazy" "second result" nil))
            (should (= calls 2))
            (should (string-match-p "formatted-2" (buffer-string)))
            (should-not (string-match-p "formatted-1" (buffer-string)))
            (dsh-emacs-ui-toggle-fragment)
            (dsh-emacs-render-tool-result
             (dsh-emacs-test--tool-result-event-meta 4 "lazy" "third result" nil))
            (should (= calls 2))
            (dsh-emacs-ui-toggle-fragment)
            (should (= calls 3))
            (let ((kill-ring nil)
                  (interprogram-cut-function nil))
              (dsh-emacs-copy-transcript)
              (should (string-match-p "formatted-3" (car kill-ring))))))))))

(ert-deftest dsh-emacs-test-tools-pending-body-expands-before-result ()
  :tags '(dsh-unit)
  (dolist (case '(("bash" dsh-emacs-render--bash-card-body)
                 ("edit" dsh-emacs-render--diff-card-body)))
    (pcase-let ((`(,name ,formatter) case))
      (with-temp-buffer
        (dsh-emacs-mode)
        (let ((dsh-emacs-tool-expand-by-default nil)
              (calls 0))
          (cl-letf (((symbol-function formatter)
                     (lambda (&rest _) (format "details-%d" (cl-incf calls)))))
            (dsh-emacs-render-tool-call
             (dsh-emacs-test--tool-call-event 1 "pending" name "{}"))
            (should (= calls 0))
            (goto-char (car (dsh-emacs-ui-find-block
                             (dsh-emacs-render--make-namespace) "tool-pending")))
            (dsh-emacs-ui-toggle-fragment)
            (should (= calls 1))
            (should (string-match-p "details-1" (buffer-string)))
            (dsh-emacs-render-tool-result
             (dsh-emacs-test--tool-result-event-meta 2 "pending" "result" nil))
            (should (= calls 2))
            (should (string-match-p "details-2" (buffer-string)))
            (should-not (string-match-p "details-1" (buffer-string)))))))))

(provide 'dsh-test-tools)
;;; dsh-test-tools.el ends here
