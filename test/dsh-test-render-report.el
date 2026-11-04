;;; dsh-test-render-report.el --- Render report tests -*- lexical-binding: t; -*-

;; Package-Requires: ((emacs "28.1"))

(require 'dsh-test-support)

;; Developer diagnostics count only the target, and leave no instrumentation.
(load (expand-file-name "scripts/render-report.el" dsh-emacs-test-root) nil t)

(ert-deftest dsh-emacs-test-render-report-render-report-scopes-text-and-property-writes ()
  :tags '(dsh-unit)
  (with-temp-buffer
    (insert "abcdef")
    (let* ((target (current-buffer))
           (local-before (local-variable-p 'after-change-functions))
           (hooks-before after-change-functions)
           (setter (symbol-function 'put-text-property))
           (report
            (dsh-render-report-measure
             (lambda ()
               (put-text-property 2 3 'face 'bold)
               (put-text-property 0 1 'face 'italic (copy-sequence "x"))
               (with-temp-buffer
                 (insert "scratch")
                 (put-text-property 1 2 'face 'italic)
                 (put-text-property 4 5 'face 'italic target))
               (goto-char 2)
               (insert "X")))))
      (ert-info ((format "%s" "render-report-scopes-text-and-property-writes"))
        (should (equal (plist-get report :text-edits) '((2 0 1))))
        (should (equal (plist-get report :property-calls)
                       '((put-text-property 2 3 face) (put-text-property 4 5 face))))
        (should (plist-get report :text-changed))
        (should (plist-get report :modified)))
      (ert-info ((format "%s" "render-report-restores-hook-locality-and-advice"))
        (should (eq local-before (local-variable-p 'after-change-functions)))
        (should (equal hooks-before after-change-functions))
        (should (eq setter (symbol-function 'put-text-property))))
      (let (escaped)
        (add-hook 'after-change-functions #'ignore nil t)
        (setq hooks-before after-change-functions)
        (condition-case err
            (dsh-render-report-measure (lambda () (error "report probe")))
          (error (setq escaped err)))
        (ert-info ((format "%s" "render-report-error-propagates-after-cleanup"))
          (should (equal escaped '(error "report probe")))
          (should (local-variable-p 'after-change-functions))
          (should (equal hooks-before after-change-functions))
          (should (eq setter (symbol-function 'put-text-property)))
          (should (not dsh-render-report--active)))))))

(ert-deftest dsh-emacs-test-render-report-render-report-snapshots-marker-range-case ()
  :tags '(dsh-unit)
  (dolist (setter '(put-text-property set-text-properties
                                      add-text-properties remove-text-properties))
    (with-temp-buffer
      (insert "abcdef")
      (let* ((start (copy-marker 2))
             (end (copy-marker 4))
             (report
              (dsh-render-report-measure
               (lambda ()
                 (if (eq setter 'put-text-property)
                     (funcall setter start end 'face 'bold)
                   (funcall setter start end '(face bold)))
                 (goto-char 3)
                 (insert "XYZ")
                 (set-marker start nil)
                 (set-marker end nil)))))
        (ert-info ((format "%s" (format "render-report-snapshots-marker-range-%s" setter)))
          (should (equal (plist-get report :property-calls)
                         (list (list setter 2 4
                                     (when (eq setter 'put-text-property) 'face))))))))))

(ert-deftest dsh-emacs-test-render-report-render-report-excludes-other-session-buffers ()
  :tags '(dsh-unit)
  (with-temp-buffer
    (let ((report (dsh-render-report-measure
                   (lambda ()
                     (dsh-render-report-scenario 'session-title #'funcall)))))
      (ert-info ((format "%s" "render-report-excludes-other-session-buffers"))
        (should (= (plist-get report :renders) 0))
        (should (= (plist-get report :session-rows) 0))
        (should (= (plist-get report :session-row-builds) 0))
        (should (= (plist-get report :generated-chars) 0))
        (should (null (plist-get report :text-edits)))
        (should (null (plist-get report :property-calls)))
        (should (not (plist-get report :modified)))))))

(ert-deftest dsh-emacs-test-render-report-render-report-preserves-output-case ()
  :tags '(dsh-unit)
  (dolist (scenario '(session-title fragment-title fragment-warm
                                    fragment-after-stream fragment-rewarmed))
    (let* ((dsh-emacs-session-recents-limit 15)
           report
           (instrumented
            (dsh-render-report-scenario
             scenario (lambda (run)
                        (setq report (dsh-render-report-measure run))
                        (buffer-string))))
           (ordinary (dsh-render-report-scenario
                      scenario (lambda (run) (funcall run) (buffer-string)))))
      (ert-info ((format "%s" (format "render-report-preserves-output-%s" scenario)))
        (should (dsh-test-equal-text-p instrumented ordinary)))
      (when (eq scenario 'session-title)
        (ert-info ((format "%s" "render-report-distinguishes-row-visits-from-builds"))
          (should (= (plist-get report :session-rows) 555))
          (should (= (plist-get report :session-row-builds) 1))))
      (when (memq scenario '(fragment-warm fragment-after-stream fragment-rewarmed))
        (ert-info ((format "%s" (format "render-report-unchanged-%s" scenario)))
          (should (= (plist-get report :renders)
                     (if (eq scenario 'fragment-after-stream) 1 0)))
          (should (null (plist-get report :text-edits)))
          (should (null (plist-get report :property-calls)))
          (should (not (plist-get report :modified))))))))

(provide 'dsh-test-render-report)
;;; dsh-test-render-report.el ends here
