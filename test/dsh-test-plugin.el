;;; dsh-test-plugin.el --- dsh-plugins-bridge client tests -*- lexical-binding: t; -*-

;; Package-Requires: ((emacs "28.1"))

(require 'dsh-test-support)

(defun dsh-test-plugin--parameter (wire type &optional required enum)
  "Build a bridge parameter for WIRE with schema TYPE.
REQUIRED marks it required; ENUM is an optional list of allowed values."
  (dsh-protocol-bridge-parameter--from-alist
   `((name . ,wire)
     (wire . ,wire)
     (required . ,(if required t :json-false))
     (schema . ((type . ,type)
                ,@(when enum (list (cons 'enum (vconcat enum)))))))))

(defun dsh-test-plugin--endpoint (parameters &optional requires-agent)
  "Build a unary endpoint with PARAMETERS and optional REQUIRES-AGENT."
  (make-dsh-protocol-bridge-endpoint
   :package "@scope/pkg"
   :endpoint "ns/run"
   :namespace "ns"
   :method "run"
   :kind "unary"
   :requires-agent requires-agent
   :parameters parameters))

(defun dsh-test-plugin--route-group (&rest overrides)
  "Build a route group, letting OVERRIDES replace the defaults."
  (let ((plist (list :id "dsh-session-manager"
                     :title "dsh-session-manager"
                     :package "dsh-session-manager"
                     :third-party t
                     :selected t
                     :kinds '("exact")
                     :prefixes nil
                     :route-count 1
                     :paths '("/dsh-session-manager/stats"))))
    (while overrides
      (setq plist (plist-put plist (car overrides) (cadr overrides))
            overrides (cddr overrides)))
    (apply #'make-dsh-protocol-bridge-route-group plist)))

(ert-deftest dsh-emacs-test-plugin-bridge-base-url ()
  :tags '(dsh-unit)
  (let ((dsh-emacs-base-url "http://127.0.0.1:3080/?token=ignored")
        (dsh-emacs-plugin-bridge-base-url nil))
    (should (equal (dsh-emacs-plugin--base-url)
                   "http://127.0.0.1:3080/plugins-bridge/v1")))
  (let ((dsh-emacs-plugin-bridge-base-url "http://127.0.0.1:9999/custom/"))
    (should (equal (dsh-emacs-plugin--base-url)
                   "http://127.0.0.1:9999/custom"))))

(ert-deftest dsh-emacs-test-plugin-token-resolution ()
  :tags '(dsh-unit)
  (let ((old (getenv "DSH_BRIDGE_TOKEN")))
    (unwind-protect
        (progn
          (setenv "DSH_BRIDGE_TOKEN" "env-token")
          (let ((dsh-emacs-plugin-bridge-token "custom-token"))
            (should (equal "custom-token" (dsh-emacs-plugin--token))))
          (let ((dsh-emacs-plugin-bridge-token nil))
            (should (equal "env-token" (dsh-emacs-plugin--token))))
          (setenv "DSH_BRIDGE_TOKEN" "  padded-token  ")
          (let ((dsh-emacs-plugin-bridge-token nil))
            (should (equal "padded-token" (dsh-emacs-plugin--token))))
          (setenv "DSH_BRIDGE_TOKEN" "   ")
          (let ((dsh-emacs-plugin-bridge-token nil))
            (should-error (dsh-emacs-plugin--token) :type 'user-error)))
      (setenv "DSH_BRIDGE_TOKEN" old))))

(ert-deftest dsh-emacs-test-plugin-agent-wire ()
  :tags '(dsh-unit)
  (should (equal "agentId"
                 (dsh-emacs-plugin--agent-wire
                  (dsh-test-plugin--endpoint
                   (list (dsh-test-plugin--parameter "agentId" "string"))
                   "agentId"))))
  (should (equal "agentId"
                 (dsh-emacs-plugin--agent-wire
                  (dsh-test-plugin--endpoint
                   (list (dsh-test-plugin--parameter "agentId" "string" t))))))
  (should-not (dsh-emacs-plugin--agent-wire
               (dsh-test-plugin--endpoint
                (list (dsh-test-plugin--parameter "agentId" "string")))))
  (should-not (dsh-emacs-plugin--agent-wire
               (dsh-test-plugin--endpoint
                (list (dsh-test-plugin--parameter "other" "string"))
                :json-false))))

(ert-deftest dsh-emacs-test-plugin-read-argument-types ()
  :tags '(dsh-unit)
  (let ((dsh-emacs-plugin-bridge-token "token"))
    (cl-letf (((symbol-function 'read-string)
               (lambda (_prompt &rest _) "7")))
      (should (equal 7 (dsh-emacs-plugin--read-argument
                        (dsh-test-plugin--parameter "count" "integer")))))
    (cl-letf (((symbol-function 'read-string)
               (lambda (_prompt &rest _) "4.5")))
      (should (equal 4.5 (dsh-emacs-plugin--read-argument
                          (dsh-test-plugin--parameter "ratio" "number")))))
    (cl-letf (((symbol-function 'read-string)
               (lambda (_prompt &rest _) "{\"a\":1}")))
      (should (equal '((a . 1))
                     (dsh-emacs-plugin--read-argument
                      (dsh-test-plugin--parameter "object" "object")))))
    (cl-letf (((symbol-function 'read-string)
               (lambda (_prompt &rest _) "[\"a\"]")))
      (should (equal ["a"]
                     (dsh-emacs-plugin--read-argument
                      (dsh-test-plugin--parameter "items" "array")))))
    (cl-letf (((symbol-function 'completing-read)
               (lambda (&rest _) "false")))
      (should (eq :json-false
                  (dsh-emacs-plugin--read-argument
                   (dsh-test-plugin--parameter "flag" "boolean")))))
    (cl-letf (((symbol-function 'completing-read)
               (lambda (&rest _) "red")))
      (should (equal "red"
                     (dsh-emacs-plugin--read-argument
                      (dsh-test-plugin--parameter
                       "color" "string" nil '("red" "blue"))))))
    (cl-letf (((symbol-function 'read-string)
               (lambda (_prompt &rest _) "not-a-number")))
      (should-error (dsh-emacs-plugin--read-argument
                     (dsh-test-plugin--parameter "count" "integer"))
                    :type 'user-error))))

(ert-deftest dsh-emacs-test-plugin-read-required-arguments ()
  :tags '(dsh-unit)
  (let ((endpoint
         (dsh-test-plugin--endpoint
          (list (dsh-test-plugin--parameter "name" "string" t)
                (dsh-test-plugin--parameter "note" "string"))))
        (prompts 0))
    (cl-letf (((symbol-function 'read-string)
               (lambda (_prompt &rest _)
                 (setq prompts (1+ prompts))
                 "hello")))
      (should (equal '(("name" . "hello"))
                     (dsh-emacs-plugin--read-required-arguments
                      endpoint nil)))
      (should (= 1 prompts))))
  ;; The agent wire is required even when its descriptor says optional.
  (let ((endpoint
         (dsh-test-plugin--endpoint
          (list (dsh-test-plugin--parameter "agentId" "string")
                (dsh-test-plugin--parameter "count" "integer" t))
          "agentId")))
    (cl-letf (((symbol-function 'dsh-emacs-plugin--read-agent)
               (lambda (_agents) "session-1"))
              ((symbol-function 'read-string)
               (lambda (_prompt &rest _) "3")))
      (should (equal '(("agentId" . "session-1") ("count" . 3))
                     (dsh-emacs-plugin--read-required-arguments
                      endpoint nil))))))

(ert-deftest dsh-emacs-test-plugin-read-object-and-merge ()
  :tags '(dsh-unit)
  (cl-letf (((symbol-function 'read-string)
             (lambda (&rest _) "")))
    (should-not (dsh-emacs-plugin--read-object "Args: ")))
  (cl-letf (((symbol-function 'read-string)
             (lambda (&rest _) "{\"x\":1,\"y\":[2]}")))
    (should (equal '(("x" . 1) ("y" . [2]))
                   (dsh-emacs-plugin--read-object "Args: "))))
  (cl-letf (((symbol-function 'read-string)
             (lambda (&rest _) "[")))
    (should-error (dsh-emacs-plugin--read-object "Args: ")
                  :type 'user-error))
  (should (equal '(("a" . 1) ("b" . 2))
                 (dsh-emacs-plugin--merge-arguments
                  '(("a" . 1))
                  '(("a" . 9) ("b" . 2))))))

(ert-deftest dsh-emacs-test-plugin-invoke-request-shape ()
  :tags '(dsh-unit)
  (let ((dsh-emacs-plugin-bridge-base-url "http://bridge.test/v1")
        (dsh-emacs-plugin-bridge-token "token")
        (captured nil)
        (shown nil)
        (endpoint (dsh-test-plugin--endpoint nil)))
    (cl-letf (((symbol-function 'dsh-emacs--http-json)
               (lambda (method url headers body callback)
                 (setq captured (list method url headers body))
                 (funcall callback '(:status 200 :value nil))))
              ((symbol-function 'dsh-emacs-plugin--show-result)
               (lambda (title response) (setq shown (list title response)))))
      (dsh-emacs-plugin--invoke "@scope/pkg" endpoint '(("x" . 1))))
    (ert-info ((format "%s" "invoke-request-shape"))
      (should (equal "POST" (nth 0 captured)))
      (should (equal "http://bridge.test/v1/invoke" (nth 1 captured)))
      (should (equal '(("Authorization" . "Bearer token")
                       ("Accept" . "application/json")
                       ("Content-Type" . "application/json"))
                     (nth 2 captured)))
      (should (equal '((package . "@scope/pkg")
                       (endpoint . "ns/run")
                       (args (x . 1)))
                     (dsh-protocol-read-json (nth 3 captured))))
      (should (equal "@scope/pkg#ns/run" (car shown)))))
  ;; No arguments still sends an empty JSON object, not null.
  (let ((dsh-emacs-plugin-bridge-base-url "http://bridge.test/v1")
        (dsh-emacs-plugin-bridge-token "token")
        (body nil)
        (endpoint (dsh-test-plugin--endpoint nil)))
    (cl-letf (((symbol-function 'dsh-emacs--http-json)
               (lambda (_method _url _headers request-body _callback)
                 (setq body request-body)))
              ((symbol-function 'dsh-emacs-plugin--show-result) #'ignore))
      (dsh-emacs-plugin--invoke "@scope/pkg" endpoint nil))
    (ert-info ((format "%s" "invoke-empty-args"))
      (should (string-match-p "\"args\":{}" body)))))

(ert-deftest dsh-emacs-test-plugin-show-result ()
  :tags '(dsh-unit)
  (let ((displayed nil)
        (buffers nil))
    (cl-letf (((symbol-function 'display-buffer)
               (lambda (buffer &rest _) (setq displayed buffer) buffer)))
      (unwind-protect
          (progn
            (dsh-emacs-plugin--show-result
             "pkg#ns/run"
             '(:status 200
               :value ((ok . t)
                       (package . "pkg")
                       (endpoint . "ns/run")
                       (result . ((answer . 42))))))
            (push displayed buffers)
            (with-current-buffer displayed
              (should (equal "pkg#ns/run" (substring-no-properties
                                           (car (split-string
                                                 (buffer-string) "\n")))))
              (should (string-match-p "HTTP 200" (buffer-string)))
              (should (string-match-p "\"answer\": 42" (buffer-string)))
              (should (derived-mode-p 'special-mode)))
            (dsh-emacs-plugin--show-result
             "pkg#ns/run"
             '(:status 403
               :value ((ok . :json-false)
                       (error . ((code . "package-not-exposed")
                                 (message . "not exposed"))))))
            (push displayed buffers)
            (with-current-buffer displayed
              (should (string-match-p "package-not-exposed: not exposed"
                                      (buffer-string))))
            (dsh-emacs-plugin--show-result
             "pkg#ns/run" '(:status 401 :value nil))
            (push displayed buffers)
            (with-current-buffer displayed
              (should (string-match-p "bridge token rejected"
                                      (buffer-string)))))
        (dolist (buffer buffers)
          (when (buffer-live-p buffer) (kill-buffer buffer)))))))

(ert-deftest dsh-emacs-test-plugin-command-wiring ()
  :tags '(dsh-unit)
  (let* ((endpoint (dsh-test-plugin--endpoint
                    (list (dsh-test-plugin--parameter "agentId" "string"))
                    "agentId"))
         (plugin (dsh-protocol-bridge-plugin--from-alist
                  '((package . "@scope/pkg")
                    (endpoints . [((endpoint . "ns/run"))]))))
         (called nil)
         (fetched-agents 0)
         (raw-argument nil))
    (cl-letf (((symbol-function 'dsh-emacs-plugin--fetch-plugins)
               (lambda () (list plugin)))
              ((symbol-function 'dsh-emacs-plugin--choose-plugin)
               (lambda (_plugins) plugin))
              ((symbol-function 'dsh-emacs-plugin--fetch-plugin)
               (lambda (_package) plugin))
              ((symbol-function 'dsh-emacs-plugin--choose-endpoint)
               (lambda (_plugin) endpoint))
              ((symbol-function 'dsh-emacs-plugin--fetch-agents)
               (lambda () (setq fetched-agents (1+ fetched-agents)) nil))
              ((symbol-function 'dsh-emacs-plugin--read-arguments)
               (lambda (_endpoint _agents raw)
                 (setq raw-argument raw)
                 '(("x" . 1))))
              ((symbol-function 'dsh-emacs-plugin--invoke)
               (lambda (package chosen args)
                 (setq called (list package chosen args)))))
      (dsh-emacs-plugins)
      (should (equal (list "@scope/pkg" endpoint '(("x" . 1))) called))
      (should-not raw-argument)
      (should (= 1 fetched-agents))
      (setq called nil)
      (dsh-emacs-plugins t)
      (ert-info ((format "%s" "command-raw-arguments"))
        (should (equal (list "@scope/pkg" endpoint '(("x" . 1))) called))
        (should raw-argument)
        ;; Raw mode does not need the Agent catalog.
        (should (= 1 fetched-agents))))))

;; --- HTTP route proxy ---

(ert-deftest dsh-emacs-test-plugin-route-target-path ()
  :tags '(dsh-unit)
  (let ((group (dsh-test-plugin--route-group)))
    (should (equal "/dsh-session-manager/delete"
                   (dsh-emacs-plugin--route-target-path
                    group "/dsh-session-manager/delete")))
    (should (equal "/dsh-session-manager/delete"
                   (dsh-emacs-plugin--route-target-path group "delete")))
    (should (equal "/dsh-session-manager/stats"
                   (dsh-emacs-plugin--route-target-path group "/stats")))
    (should (equal "/dsh-session-manager"
                   (dsh-emacs-plugin--route-target-path group "")))
    (should (equal "/dsh-session-manager"
                   (dsh-emacs-plugin--route-target-path group "/")))
    (let ((prefix (dsh-test-plugin--route-group
                   :id "mcp-manager-plus"
                   :selected t
                   :prefixes t
                   :paths '("/mcp-manager-plus"))))
      (should (equal "/mcp-manager-plus/servers"
                     (dsh-emacs-plugin--route-target-path prefix "servers")))
      (should (equal "/mcp-manager-plus/servers"
                     (dsh-emacs-plugin--route-target-path prefix "/servers")))
      (should (equal "/mcp-manager-plus/servers?all=1"
                     (dsh-emacs-plugin--route-target-path
                      prefix "/mcp-manager-plus/servers?all=1")))
      (should (equal "/mcp-manager-plus?all=1"
                     (dsh-emacs-plugin--route-target-path
                      prefix "/mcp-manager-plus?all=1")))
      (should (equal "/mcp-manager-plus/servers?all=1"
                     (dsh-emacs-plugin--route-target-path
                      prefix "servers?all=1"))))))

(ert-deftest dsh-emacs-test-plugin-route-require-selected ()
  :tags '(dsh-unit)
  (should-not (dsh-emacs-plugin--require-selected-route-group
               (dsh-test-plugin--route-group)))
  (should-error (dsh-emacs-plugin--require-selected-route-group
                 (dsh-test-plugin--route-group :selected nil))
                :type 'user-error))

(ert-deftest dsh-emacs-test-plugin-route-invoke-request-shape ()
  :tags '(dsh-unit)
  (let ((dsh-emacs-plugin-bridge-base-url "http://bridge.test/v1")
        (dsh-emacs-plugin-bridge-token "token")
        (group (dsh-test-plugin--route-group))
        (captured nil))
    (cl-letf (((symbol-function 'dsh-emacs--http-request)
               (lambda (method url headers body callback)
                 (setq captured (list method url headers body))
                 (funcall callback '(:status 200 :headers nil :body "{}"))))
              ((symbol-function 'dsh-emacs-plugin--show-route-result) #'ignore))
      (dsh-emacs-plugin--invoke-route
       group "POST" "/dsh-session-manager/delete"
       "{\"id\":\"s\"}" "application/json"))
    (ert-info ((format "%s" "route-invoke-request-shape"))
      (should (equal "POST" (nth 0 captured)))
      (should (equal "http://bridge.test/v1/http/dsh-session-manager/delete"
                     (nth 1 captured)))
      (should (equal '(("Authorization" . "Bearer token")
                       ("Accept" . "*/*")
                       ("Content-Type" . "application/json"))
                     (nth 2 captured)))
      (should (equal "{\"id\":\"s\"}" (nth 3 captured)))))
  ;; A bodyless method carries no Content-Type and no request data.
  (let ((dsh-emacs-plugin-bridge-base-url "http://bridge.test/v1")
        (dsh-emacs-plugin-bridge-token "token")
        (group (dsh-test-plugin--route-group))
        (captured nil))
    (cl-letf (((symbol-function 'dsh-emacs--http-request)
               (lambda (method url headers body _callback)
                 (setq captured (list method url headers body))))
              ((symbol-function 'dsh-emacs-plugin--show-route-result) #'ignore))
      (dsh-emacs-plugin--invoke-route
       group "GET" "/dsh-session-manager/stats" nil nil))
    (ert-info ((format "%s" "route-invoke-bodyless"))
      (should (equal "GET" (nth 0 captured)))
      (should (equal '(("Authorization" . "Bearer token")
                       ("Accept" . "*/*"))
                     (nth 2 captured)))
      (should-not (nth 3 captured)))))

(ert-deftest dsh-emacs-test-plugin-route-dsh-auth-forwarding ()
  :tags '(dsh-unit)
  (let ((dsh-emacs-base-url "http://bridge.test/")
        (dsh-emacs-plugin-bridge-base-url "http://bridge.test/v1")
        (dsh-emacs-plugin-bridge-token "token")
        (dsh-emacs-plugin-route-forward-dsh-auth t)
        (group (dsh-test-plugin--route-group))
        (captured nil))
    (cl-letf (((symbol-function 'dsh-emacs--server-auth-header)
               (lambda () '(("Cookie" . "dsh-auth-test=cookie"))))
              ((symbol-function 'dsh-emacs--http-request)
               (lambda (method url headers body _callback)
                 (setq captured (list method url headers body))))
              ((symbol-function 'dsh-emacs-plugin--show-route-result) #'ignore))
      (dsh-emacs-plugin--invoke-route
       group "GET" "/dsh-session-manager/stats" nil nil))
    (ert-info ((format "%s" "route-dsh-auth-same-origin"))
      (should (equal '(("Authorization" . "Bearer token")
                       ("Accept" . "*/*")
                       ("Cookie" . "dsh-auth-test=cookie"))
                     (nth 2 captured)))))

  ;; A different origin never receives the DSH cookie.
  (let ((dsh-emacs-base-url "http://other.test/")
        (dsh-emacs-plugin-bridge-base-url "http://bridge.test/v1")
        (dsh-emacs-plugin-bridge-token "token")
        (dsh-emacs-plugin-route-forward-dsh-auth t)
        (group (dsh-test-plugin--route-group))
        (captured nil))
    (cl-letf (((symbol-function 'dsh-emacs--server-auth-header)
               (lambda () '(("Cookie" . "dsh-auth-test=cookie"))))
              ((symbol-function 'dsh-emacs--http-request)
               (lambda (_method _url headers _body _callback)
                 (setq captured headers)))
              ((symbol-function 'dsh-emacs-plugin--show-route-result) #'ignore))
      (dsh-emacs-plugin--invoke-route
       group "GET" "/dsh-session-manager/stats" nil nil))
    (ert-info ((format "%s" "route-dsh-auth-other-origin"))
      (should-not (assoc "Cookie" captured))))

  ;; The option disables forwarding even on the same origin.
  (let ((dsh-emacs-base-url "http://bridge.test/")
        (dsh-emacs-plugin-bridge-base-url "http://bridge.test/v1")
        (dsh-emacs-plugin-bridge-token "token")
        (dsh-emacs-plugin-route-forward-dsh-auth nil)
        (group (dsh-test-plugin--route-group))
        (captured nil))
    (cl-letf (((symbol-function 'dsh-emacs--server-auth-header)
               (lambda () '(("Cookie" . "dsh-auth-test=cookie"))))
              ((symbol-function 'dsh-emacs--http-request)
               (lambda (_method _url headers _body _callback)
                 (setq captured headers)))
              ((symbol-function 'dsh-emacs-plugin--show-route-result) #'ignore))
      (dsh-emacs-plugin--invoke-route
       group "GET" "/dsh-session-manager/stats" nil nil))
    (ert-info ((format "%s" "route-dsh-auth-disabled"))
      (should-not (assoc "Cookie" captured))))

  ;; Origin comparison ignores paths and normalizes default ports.
  (should (dsh-emacs-plugin--same-origin-p
           "http://127.0.0.1:3080/plugins-bridge/v1"
           "http://127.0.0.1:3080/api"))
  (should (dsh-emacs-plugin--same-origin-p "http://example.test/x"
                                          "http://example.test:80/y"))
  (should-not (dsh-emacs-plugin--same-origin-p "http://example.test/x"
                                              "http://example.test:3081/y"))
  (should-not (dsh-emacs-plugin--same-origin-p "http://example.test/x"
                                              "https://example.test/y")))

(ert-deftest dsh-emacs-test-plugin-route-show-result ()
  :tags '(dsh-unit)
  (let ((displayed nil)
        (buffers nil)
        (dsh-emacs-plugin-route-max-output 50000))
    (cl-letf (((symbol-function 'display-buffer)
               (lambda (buffer &rest _) (setq displayed buffer) buffer)))
      (unwind-protect
          (progn
            (dsh-emacs-plugin--show-route-result
             "GET /json"
             '(:status 200
               :headers (("content-type" . "application/json"))
               :body "{\"ok\":true}" :error nil))
            (push displayed buffers)
            (with-current-buffer displayed
              (should (string-match-p "HTTP 200" (buffer-string)))
              (should (string-match-p "\"ok\": true" (buffer-string)))
              (should (derived-mode-p 'special-mode)))
            (dsh-emacs-plugin--show-route-result
             "GET /text"
             '(:status 200
               :headers (("content-type" . "text/plain; charset=utf-8"))
               :body "hello" :error nil))
            (push displayed buffers)
            (with-current-buffer displayed
              (should (string-match-p "hello" (buffer-string))))
            (dsh-emacs-plugin--show-route-result
             "GET /binary"
             (list :status 200
                   :headers '(("content-type" . "image/png"))
                   :body (unibyte-string 0 1 2) :error nil))
            (push displayed buffers)
            (with-current-buffer displayed
              (should (string-match-p "binary response: 3 bytes"
                                      (buffer-string)))
              (should-not (string-match-p "\0" (buffer-string))))
            (dsh-emacs-plugin--show-route-result
             "DELETE /missing"
             '(:status 403
               :headers (("content-type" . "application/json"))
               :body "{\"ok\":false,\"error\":{\"code\":\"route-not-exposed\"}}"
               :error nil))
            (push displayed buffers)
            (with-current-buffer displayed
              (should (string-match-p "route-not-exposed" (buffer-string))))
            (dsh-emacs-plugin--show-route-result
             "GET /empty"
             '(:status 204 :headers nil :body nil :error nil))
            (push displayed buffers)
            (with-current-buffer displayed
              (should (string-match-p "(no response body)" (buffer-string)))))
        (dolist (buffer buffers)
          (when (buffer-live-p buffer) (kill-buffer buffer)))))))

(ert-deftest dsh-emacs-test-plugin-route-truncate-and-binary ()
  :tags '(dsh-unit)
  (let ((dsh-emacs-plugin-route-max-output 5))
    (should (equal "abcde\n\n… truncated: showing 5 of 8 characters"
                   (dsh-emacs-plugin--route-truncate "abcdefgh"))))
  (should (dsh-emacs-plugin--route-binary-p "image/png" "abc"))
  (should (dsh-emacs-plugin--route-binary-p "application/octet-stream" "abc"))
  (should (dsh-emacs-plugin--route-binary-p nil (unibyte-string 0 1)))
  (should-not (dsh-emacs-plugin--route-binary-p "text/plain" "abc"))
  (should-not (dsh-emacs-plugin--route-binary-p "application/json" "{}")))

(ert-deftest dsh-emacs-test-plugin-route-command-wiring ()
  :tags '(dsh-unit)
  (let* ((group (dsh-test-plugin--route-group))
         (called nil)
         (checked nil))
    (cl-letf (((symbol-function 'dsh-emacs-plugin--fetch-routes)
               (lambda () (list group)))
              ((symbol-function 'dsh-emacs-plugin--choose-route-group)
               (lambda (_groups) group))
              ((symbol-function 'dsh-emacs-plugin--require-selected-route-group)
               (lambda (_group) (setq checked t)))
              ((symbol-function 'dsh-emacs-plugin--choose-route-path)
               (lambda (_group) "/dsh-session-manager/delete"))
              ((symbol-function 'dsh-emacs-plugin--choose-route-method)
               (lambda () "POST"))
              ((symbol-function 'dsh-emacs-plugin--read-route-body)
               (lambda (_method) "{\"id\":\"s\"}"))
              ((symbol-function 'dsh-emacs-plugin--read-route-content-type)
               (lambda () "application/json"))
              ((symbol-function 'dsh-emacs-plugin--invoke-route)
               (lambda (g method path body type)
                 (setq called (list g method path body type)))))
      (dsh-emacs-plugin-routes)
      (ert-info ((format "%s" "route-command-wiring"))
        (should checked)
        (should (equal (list group "POST" "/dsh-session-manager/delete"
                             "{\"id\":\"s\"}" "application/json")
                       called))))))

(ert-deftest dsh-emacs-test-plugin-route-programmatic-call ()
  :tags '(dsh-unit)
  (let ((dsh-emacs-plugin-bridge-base-url "http://bridge.test/v1")
        (dsh-emacs-plugin-bridge-token "token")
        (dsh-emacs-plugin-bridge-timeout 7)
        (dsh-emacs-plugin-route-forward-dsh-auth nil)
        (group (dsh-test-plugin--route-group))
        (captured nil))
    (cl-letf (((symbol-function 'dsh-emacs-plugin--fetch-routes)
               (lambda () (list group)))
              ((symbol-function 'dsh-emacs-plugin--choose-route-group)
               (lambda (&rest _)
                 (error "group prompt unexpectedly reached")))
              ((symbol-function 'dsh-emacs-plugin--choose-route-path)
               (lambda (&rest _)
                 (error "path prompt unexpectedly reached")))
              ((symbol-function 'dsh-emacs-plugin--choose-route-method)
               (lambda (&rest _)
                 (error "method prompt unexpectedly reached")))
              ((symbol-function 'dsh-emacs--http-json-sync)
               (lambda (method url headers &optional body timeout)
                 (setq captured (list method url headers body timeout))
                 '(:status 200 :value (("ok" . t))
                          :error nil :parse-error nil))))
      (should (equal '(("ok" . t))
                     (dsh-emacs-plugin-routes
                      "dsh-session-manager" "get" "stats"))))
    (ert-info ((format "%s" "route-programmatic-call"))
      (should (equal
               (list "GET"
                     "http://bridge.test/v1/http/dsh-session-manager/stats"
                     '(("Authorization" . "Bearer token")
                       ("Accept" . "*/*"))
                     nil
                     7)
               captured)))))

(ert-deftest dsh-emacs-test-plugin-route-programmatic-body ()
  :tags '(dsh-unit)
  (let ((dsh-emacs-plugin-bridge-base-url "http://bridge.test/v1")
        (dsh-emacs-plugin-bridge-token "token")
        (dsh-emacs-plugin-route-forward-dsh-auth nil)
        (group (dsh-test-plugin--route-group))
        (captured nil))
    (cl-letf (((symbol-function 'dsh-emacs-plugin--fetch-routes)
               (lambda () (list group)))
              ((symbol-function 'dsh-emacs-plugin--read-route-body)
               (lambda (method)
                 (should (equal "POST" method))
                 "{\"id\":\"s\"}"))
              ((symbol-function 'dsh-emacs-plugin--read-route-content-type)
               (lambda () "text/plain"))
              ((symbol-function 'dsh-emacs--http-json-sync)
               (lambda (method url headers &optional body _timeout)
                 (setq captured (list method url headers body))
                 '(:status 200 :value t :error nil :parse-error nil))))
      (should (eq t (dsh-emacs-plugin-routes
                     "dsh-session-manager" "POST"
                     "/dsh-session-manager/delete"))))
    (ert-info ((format "%s" "route-programmatic-body"))
      (should (equal "{\"id\":\"s\"}" (nth 3 captured)))
      (should (equal "text/plain"
                     (cdr (assoc "Content-Type" (nth 2 captured))))))))

(ert-deftest dsh-emacs-test-plugin-route-programmatic-supplied-body ()
  :tags '(dsh-unit)
  (let ((dsh-emacs-plugin-bridge-base-url "http://bridge.test/v1")
        (dsh-emacs-plugin-bridge-token "token")
        (dsh-emacs-plugin-route-forward-dsh-auth nil)
        (group (dsh-test-plugin--route-group))
        (captured nil))
    (cl-letf (((symbol-function 'dsh-emacs-plugin--fetch-routes)
               (lambda () (list group)))
              ((symbol-function 'dsh-emacs-plugin--read-route-body)
               (lambda (&rest _)
                 (error "body prompt unexpectedly reached")))
              ((symbol-function 'dsh-emacs-plugin--read-route-content-type)
               (lambda (&rest _)
                 (error "content-type prompt unexpectedly reached")))
              ((symbol-function 'dsh-emacs--http-json-sync)
               (lambda (method url headers &optional body _timeout)
                 (setq captured (list method url headers body))
                 '(:status 200 :value t :error nil :parse-error nil))))
      (should (eq t (dsh-emacs-plugin-routes
                     "dsh-session-manager" "POST"
                     "/dsh-session-manager/delete" "{\"id\":\"s\"}"))))
    (ert-info ((format "%s" "route-programmatic-supplied-body"))
      (should (equal "{\"id\":\"s\"}" (nth 3 captured)))
      (should (equal "application/json"
                     (cdr (assoc "Content-Type" (nth 2 captured))))))))

(ert-deftest dsh-emacs-test-plugin-route-programmatic-failure ()
  :tags '(dsh-unit)
  (let ((dsh-emacs-plugin-bridge-base-url "http://bridge.test/v1")
        (dsh-emacs-plugin-bridge-token "token")
        (dsh-emacs-plugin-route-forward-dsh-auth nil)
        (group (dsh-test-plugin--route-group)))
    (cl-letf (((symbol-function 'dsh-emacs-plugin--fetch-routes)
               (lambda () (list group))))
      (ert-info ((format "%s" "route-programmatic-http-error"))
        (cl-letf (((symbol-function 'dsh-emacs--http-json-sync)
                   (lambda (&rest _)
                     '(:status 500 :value nil :error nil
                              :parse-error nil))))
          (should-error (dsh-emacs-plugin-routes
                         "dsh-session-manager" "GET" "stats")
                        :type 'user-error)))
      (ert-info ((format "%s" "route-programmatic-non-json"))
        (cl-letf (((symbol-function 'dsh-emacs--http-json-sync)
                   (lambda (&rest _)
                     '(:status 200 :value nil :error nil
                              :parse-error (error "bad JSON")))))
          (should-error (dsh-emacs-plugin-routes
                         "dsh-session-manager" "GET" "stats")
                        :type 'user-error)))
      (ert-info ((format "%s" "route-programmatic-no-content"))
        (cl-letf (((symbol-function 'dsh-emacs--http-json-sync)
                   (lambda (&rest _)
                     '(:status 204 :value nil :error nil
                              :parse-error (error "empty body")))))
          (should-not (dsh-emacs-plugin-routes
                       "dsh-session-manager" "GET" "stats"))))
      (ert-info ((format "%s" "route-programmatic-unknown-group"))
        (should-error (dsh-emacs-plugin-routes "missing" "GET" "/x")
                      :type 'user-error)))))

(ert-deftest dsh-emacs-test-plugin-insert-route-call ()
  :tags '(dsh-unit)
  (let ((group (dsh-test-plugin--route-group))
        (buffer (generate-new-buffer " *dsh-route-insert*")))
    (unwind-protect
        (with-current-buffer buffer
          (insert "before")
          (cl-letf (((symbol-function 'dsh-emacs-plugin--select-route)
                     (lambda (&rest _)
                       (list group "POST"
                             "/dsh-session-manager/delete")))
                    ((symbol-function 'dsh-emacs-plugin--read-route-body)
                     (lambda (method)
                       (should (equal "POST" method))
                       "{\"id\":\"s\"}")))
            (dsh-emacs-plugin-insert-route-call))
          (ert-info ((format "%s" "insert-route-call-body"))
            (should (equal
                     (concat
                      "before"
                      (format "(dsh-emacs-plugin-routes %S %S %S %S)"
                              "dsh-session-manager" "POST"
                              "/dsh-session-manager/delete"
                              "{\"id\":\"s\"}"))
                     (buffer-string))))
          (erase-buffer)
          (cl-letf (((symbol-function 'dsh-emacs-plugin--select-route)
                     (lambda (&rest _)
                       (list group "GET"
                             "/dsh-session-manager/stats")))
                    ((symbol-function 'dsh-emacs-plugin--read-route-body)
                     (lambda (_method) nil)))
            (dsh-emacs-plugin-insert-route-call))
          (ert-info ((format "%s" "insert-route-call-no-body"))
            (should (equal
                     (format "(dsh-emacs-plugin-routes %S %S %S)"
                             "dsh-session-manager" "GET"
                             "/dsh-session-manager/stats")
                     (buffer-string)))))
      (kill-buffer buffer))))

(provide 'dsh-test-plugin)
;;; dsh-test-plugin.el ends here
