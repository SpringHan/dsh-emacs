;;; dsh-emacs-plugin.el --- Operate dsh plugins through dsh-plugins-bridge -*- lexical-binding: t; -*-

;; Copyright (C) 2026 vritser

;; Author: vritser
;; Version: 0.7.0
;; License: GPL-3.0-or-later
;; Package-Requires: ((emacs "28.1"))

;;; Commentary:

;; dsh-plugins-bridge is a dsh Web plugin that projects the live plugin
;; catalog and its custom HTTP routes onto a loopback API.  This module adds
;; two Emacs commands.
;;
;; `dsh-emacs-plugins' operates a generated Typert Remote endpoint:
;;
;;   1. reads `GET /plugins-bridge/v1/plugins' (the exposed plugin rows);
;;   2. reads that plugin's full endpoint descriptors
;;      (`GET /plugins-bridge/v1/plugin?package=...');
;;   3. asks for the endpoint's declared arguments, offering live Agent ids
;;      for an agent-scoped wire argument
;;        (`GET /plugins-bridge/v1/agents');
;;   4. invokes the endpoint asynchronously (`POST /plugins-bridge/v1/invoke')
;;      and shows the JSON result in a read-only buffer.
;;
;; `dsh-emacs-plugin-routes' operates a plugin HTTP route:
;;
;;   1. reads `GET /plugins-bridge/v1/routes' (discovered route groups);
;;   2. asks for a selected group, target path, method and optional body;
;;   3. forwards through `/plugins-bridge/v1/http/<target-path>' and shows
;;      the raw response (JSON pretty-printed, text as-is, binary summarized).
;;      When the bridge and dsh base URLs share an origin, the request also
;;      carries the current signed DSH session Cookie, so target routes that
;;      call `connection.requestRejection' see the session Emacs already uses.
;;
;; The bridge has its own bearer token and its own `/plugins-bridge/v1'
;; prefix; it is not a dsh RPC namespace.  The default base URL is derived
;; from `dsh-emacs-base-url'; the token comes from
;; `dsh-emacs-plugin-bridge-token' or the `DSH_BRIDGE_TOKEN' environment
;; variable.  Catalog, detail and route-list reads are bounded synchronous
;; GETs because the commands need them before prompting.  Calls are
;; asynchronous; a Remote call may take up to the bridge's two-minute limit,
;; and an HTTP route completes when its handler returns.
;;
;; The bridge's agent-tool surface remains unexposed.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'url-parse)
(require 'url-util)
(require 'dsh-emacs-protocol)
(require 'dsh-emacs-server)

(declare-function dsh-emacs--active-session-id "dsh-emacs.el" ())

(defgroup dsh-emacs-plugin nil
  "Operate dsh plugins through dsh-plugins-bridge."
  :group 'dsh-emacs)

(defcustom dsh-emacs-plugin-bridge-base-url nil
  "Base URL of the dsh-plugins-bridge external API.
nil derives `<dsh-emacs-base-url>/plugins-bridge/v1'.  Set it only when
the bridge is reached through a different loopback address or a proxy."
  :type '(choice (const :tag "Derive from `dsh-emacs-base-url'" nil)
                 string)
  :group 'dsh-emacs-plugin)

(defcustom dsh-emacs-plugin-bridge-token nil
  "Bearer token for the dsh-plugins-bridge external API.
Read it from dsh **Settings → Plugins Bridge**.  When nil,
`DSH_BRIDGE_TOKEN' is consulted at request time.  This token is separate
from the dsh server launch token (`dsh-emacs-server-auth-token')."
  :type '(choice (const :tag "Use DSH_BRIDGE_TOKEN" nil) string)
  :group 'dsh-emacs-plugin)

(defcustom dsh-emacs-plugin-bridge-timeout 10
  "Seconds to wait for bridge catalog, detail and synchronous route reads.
Asynchronous invocation uses the bridge's own timeout."
  :type 'number
  :group 'dsh-emacs-plugin)

(defcustom dsh-emacs-plugin-route-max-output 50000
  "Maximum characters of an HTTP route response shown in its buffer.
A longer text or JSON body is truncated with a notice; binary bodies are
never inserted.  nil shows the complete body."
  :type '(choice (const :tag "No limit" nil) integer)
  :group 'dsh-emacs-plugin)

(defcustom dsh-emacs-plugin-route-forward-dsh-auth t
  "Whether route calls forward the same-origin DSH browser session.
When non-nil and the bridge base URL and `dsh-emacs-base-url' share an
origin, `M-x dsh-emacs-plugin-routes' sends the current signed DSH session
Cookie along with the bridge bearer token.  This lets target routes that
call `connection.requestRejection' see the session Emacs already uses;
their own checks still run.  Set nil to send only the bridge token."
  :type 'boolean
  :group 'dsh-emacs-plugin)

(defun dsh-emacs-plugin--token ()
  "Return the configured bridge token, or signal a `user-error'."
  (let ((token (or dsh-emacs-plugin-bridge-token
                   (getenv "DSH_BRIDGE_TOKEN"))))
    (setq token (and token (string-trim token)))
    (unless (and token (not (string-empty-p token)))
      (user-error "Set `dsh-emacs-plugin-bridge-token' (or DSH_BRIDGE_TOKEN) to the token from dsh Settings → Plugins Bridge"))
    token))

(defun dsh-emacs-plugin--base-url ()
  "Return the bridge external API base URL without a trailing slash."
  (let ((url (or dsh-emacs-plugin-bridge-base-url
                 (concat (dsh-emacs--server-base-url)
                         "/plugins-bridge/v1"))))
    (string-trim-right url "/")))

(defun dsh-emacs-plugin--headers (&optional accept)
  "Return the request headers common to every bridge call.
ACCEPT defaults to `application/json'; the route proxy uses `*/*'."
  (list (cons "Authorization" (concat "Bearer " (dsh-emacs-plugin--token)))
        (cons "Accept" (or accept "application/json"))))

(defun dsh-emacs-plugin--get (path)
  "Read PATH from the bridge synchronously and return the response plist."
  (dsh-emacs--http-json-sync
   "GET"
   (concat (dsh-emacs-plugin--base-url) path)
   (dsh-emacs-plugin--headers)
   nil
   dsh-emacs-plugin-bridge-timeout))

(defun dsh-emacs-plugin--failure-string (response &optional error)
  "Describe a bridge RESPONSE failure, preferring decoded ERROR.
RESPONSE is the plist from `dsh-emacs--http-json' or
`dsh-emacs--http-json-sync'.  ERROR is a decoded
`dsh-protocol-bridge-error' or nil."
  (let ((status (plist-get response :status))
        (parse-error (plist-get response :parse-error))
        (transport-error (plist-get response :error)))
    (or
     (and error
          (let ((code (dsh-protocol-bridge-error-code error))
                (message (dsh-protocol-bridge-error-message error))
                (field (dsh-protocol-bridge-error-field error)))
            (when (or code message)
              (concat (or code "error")
                      (if message (concat ": " message) "")
                      (if field (format " (field %s)" field) "")))))
     (and (equal status 401)
          "bridge token rejected; check `dsh-emacs-plugin-bridge-token' or DSH_BRIDGE_TOKEN")
     (and (equal status 503)
          "plugins-bridge is disabled or unavailable; enable it in dsh Settings → Plugins Bridge")
     (and status (>= status 200) (< status 300)
          "plugins-bridge returned an unsuccessful response")
     (and status (format "plugins-bridge returned HTTP %s" status))
     (and parse-error
          (format "unreadable plugins-bridge response: %s"
                  (error-message-string parse-error)))
     (and transport-error
          (format "plugins-bridge request failed: %s"
                  (error-message-string transport-error)))
     "plugins-bridge returned no response")))

(defun dsh-emacs-plugin--fail (response &optional error)
  "Signal a `user-error' describing RESPONSE, preferring decoded ERROR."
  (user-error "%s" (dsh-emacs-plugin--failure-string response error)))

(defun dsh-emacs-plugin--decode-plugin-list (response)
  "Decode the plugin list in RESPONSE, or return nil."
  (let ((value (plist-get response :value)))
    (and (consp value)
         (dsh-protocol-bridge-plugin-list--from-alist value))))

(defun dsh-emacs-plugin--decode-plugin (response)
  "Decode the plugin detail in RESPONSE, or return nil."
  (let ((value (plist-get response :value)))
    (and (consp value)
         (dsh-protocol-bridge-plugin-response--from-alist value))))

(defun dsh-emacs-plugin--decode-agent-list (response)
  "Decode the live Agent list in RESPONSE, or return nil."
  (let ((value (plist-get response :value)))
    (and (consp value)
         (dsh-protocol-bridge-agent-list--from-alist value))))

(defun dsh-emacs-plugin--fetch-plugins ()
  "Read and return the exposed plugin rows, or signal a `user-error'."
  (let* ((response (dsh-emacs-plugin--get "/plugins"))
         (decoded (dsh-emacs-plugin--decode-plugin-list response)))
    (unless (and decoded (dsh-protocol-bridge-plugin-list-ok decoded))
      (dsh-emacs-plugin--fail
       response
       (and decoded (dsh-protocol-bridge-plugin-list-error decoded))))
    (dsh-protocol-bridge-plugin-list-plugins decoded)))

(defun dsh-emacs-plugin--fetch-plugin (package)
  "Read PACKAGE's full detail and return its plugin view."
  (let* ((response (dsh-emacs-plugin--get
                    (concat "/plugin?package="
                            (url-hexify-string package))))
         (decoded (dsh-emacs-plugin--decode-plugin response)))
    (unless (and decoded (dsh-protocol-bridge-plugin-response-ok decoded))
      (dsh-emacs-plugin--fail
       response
       (and decoded (dsh-protocol-bridge-plugin-response-error decoded))))
    (dsh-protocol-bridge-plugin-response-plugin decoded)))

(defun dsh-emacs-plugin--fetch-agents ()
  "Read and return the live Agent rows, or signal a `user-error'."
  (let* ((response (dsh-emacs-plugin--get "/agents"))
         (decoded (dsh-emacs-plugin--decode-agent-list response)))
    (unless (and decoded (dsh-protocol-bridge-agent-list-ok decoded))
      (dsh-emacs-plugin--fail
       response
       (and decoded (dsh-protocol-bridge-agent-list-error decoded))))
    (dsh-protocol-bridge-agent-list-agents decoded)))

(defun dsh-emacs-plugin--plugin-label (plugin)
  "Return PLUGIN's display label for completion."
  (let* ((package (dsh-protocol-bridge-plugin-package plugin))
         (title (dsh-protocol-bridge-plugin-title plugin))
         (shown (if (and title (not (equal title package))) title package))
         (count (dsh-protocol-bridge-plugin-endpoint-count plugin)))
    (if (and count (> count 0))
        (format "%s — %d endpoint%s" shown count (if (= count 1) "" "s"))
      shown)))

(defun dsh-emacs-plugin--choose-plugin (plugins)
  "Read one exposed plugin from PLUGINS."
  (unless plugins
    (user-error "No exposed plugins; select packages in dsh Settings → Plugins Bridge"))
  (let* ((candidates
          (mapcar (lambda (plugin)
                    (cons (propertize
                           (dsh-protocol-bridge-plugin-package plugin)
                           'display (dsh-emacs-plugin--plugin-label plugin))
                          plugin))
                  plugins))
         (picked (completing-read "Plugin: " candidates nil t)))
    (cdr (assoc picked candidates))))

(defun dsh-emacs-plugin--endpoint-label (endpoint)
  "Return ENDPOINT's display label for completion."
  (let ((name (or (dsh-protocol-bridge-endpoint-endpoint endpoint) ""))
        (description (dsh-protocol-bridge-endpoint-description endpoint))
        (kind (dsh-protocol-bridge-endpoint-kind endpoint)))
    (concat name
            (if description (concat " — " description) "")
            (if (and kind (not (equal kind "unary")))
                (format " [%s]" kind)
              ""))))

(defun dsh-emacs-plugin--choose-endpoint (plugin)
  "Read one endpoint descriptor from PLUGIN."
  (let ((endpoints (dsh-protocol-bridge-plugin-endpoints plugin)))
    (unless endpoints
      (user-error "Plugin %s exposes no callable endpoint"
                  (dsh-protocol-bridge-plugin-package plugin)))
    (let* ((candidates
            (mapcar (lambda (endpoint)
                      (cons (propertize
                             (dsh-protocol-bridge-endpoint-endpoint endpoint)
                             'display (dsh-emacs-plugin--endpoint-label endpoint))
                            endpoint))
                    endpoints))
           (picked (completing-read "Endpoint: " candidates nil t)))
      (cdr (assoc picked candidates)))))

(defun dsh-emacs-plugin--parameter-wire (parameter)
  "Return PARAMETER's JSON property name."
  (or (dsh-protocol-bridge-parameter-wire parameter)
      (dsh-protocol-bridge-parameter-name parameter)))

(defun dsh-emacs-plugin--parameter-type (parameter)
  "Return PARAMETER's JSON Schema type, or nil."
  (let ((schema (dsh-protocol-bridge-parameter-schema parameter)))
    (and (listp schema) (alist-get 'type schema))))

(defun dsh-emacs-plugin--agent-wire (endpoint)
  "Return ENDPOINT's agent-scoped wire argument, or nil.
The descriptor's `requiresAgent' is authoritative; a required agentId
parameter is also honored for older descriptors that omit the flag.  An
OPTIONAL agentId parameter is deliberately not enough: it stays an
ordinary optional argument."
  (let ((requires (dsh-protocol-bridge-endpoint-requires-agent endpoint)))
    (or (cond ((and (stringp requires)
                    (not (string-empty-p requires)))
               requires)
              ((and requires (not (eq requires :json-false)))
               "agentId"))
        (let ((parameter
               (cl-find-if
                (lambda (parameter)
                  (and (dsh-protocol-bridge-parameter-required parameter)
                       (member (dsh-emacs-plugin--parameter-wire parameter)
                               '("agentId" "agent"))))
                (dsh-protocol-bridge-endpoint-parameters endpoint))))
          (and parameter (dsh-emacs-plugin--parameter-wire parameter))))))

(defun dsh-emacs-plugin--read-agent (agents)
  "Read one live agent id from AGENTS."
  (unless agents
    (user-error "The bridge reports no live agents; start a session first"))
  (let* ((current (dsh-emacs--active-session-id))
         (candidates
          (mapcar (lambda (agent)
                    (let ((id (dsh-protocol-bridge-agent-id agent)))
                      (cons (propertize
                             id 'display
                             (concat id
                                     (if (dsh-protocol-bridge-agent-status agent)
                                         (concat " — "
                                                 (dsh-protocol-bridge-agent-status
                                                  agent))
                                       "")
                                     (if (dsh-protocol-bridge-agent-cwd agent)
                                         (concat " — "
                                                 (dsh-protocol-bridge-agent-cwd
                                                  agent))
                                       "")))
                            id)))
                  agents))
         (default (and current (assoc current candidates))))
    (completing-read "Agent: " candidates nil t nil nil
                     (and default current))))

(defun dsh-emacs-plugin--read-argument (parameter)
  "Read one value for PARAMETER as its JSON Schema type."
  (let* ((wire (dsh-emacs-plugin--parameter-wire parameter))
         (description (dsh-protocol-bridge-parameter-description parameter))
         (schema (dsh-protocol-bridge-parameter-schema parameter))
         (type (dsh-emacs-plugin--parameter-type parameter))
         (enum (and (listp schema) (alist-get 'enum schema)))
         (prompt (concat wire
                         (if description (concat " — " description) "")
                         ": ")))
    (cond
     ((and (vectorp enum) (> (length enum) 0))
      (let* ((choices (mapcar (lambda (value) (cons (format "%s" value) value))
                              (append enum nil)))
             (picked (completing-read prompt choices nil t)))
        (cdr (assoc picked choices))))
     ((member type '("boolean" "bool"))
      (if (equal "true" (completing-read prompt '("true" "false") nil t))
          t
        :json-false))
     ((member type '("integer" "number"))
      (let ((text (read-string prompt)))
        (unless (string-match-p
                 (if (equal type "integer")
                     "\\`-?[0-9]+\\'"
                   "\\`-?[0-9]+\\(?:\\.[0-9]+\\)?\\'")
                 text)
          (user-error "%s must be a %s" wire type))
        (string-to-number text)))
     ((member type '("object" "array"))
      (let ((text (read-string (concat prompt "(JSON) "))))
        (let ((value (condition-case err
                         (dsh-protocol-read-json text)
                       (error
                        (user-error "Invalid JSON for %s: %s" wire
                                    (error-message-string err))))))
          (if (equal type "array")
              (unless (vectorp value)
                (user-error "%s must be a JSON array" wire))
            (unless (or (null value) (consp value))
              (user-error "%s must be a JSON object" wire)))
          value)))
     (t
      (read-string prompt)))))

(defun dsh-emacs-plugin--read-required-arguments (endpoint agents)
  "Read ENDPOINT's required arguments, using AGENTS for its agent wire."
  (let ((agent-wire (dsh-emacs-plugin--agent-wire endpoint))
        (args nil))
    (dolist (parameter (dsh-protocol-bridge-endpoint-parameters endpoint))
      (let ((wire (dsh-emacs-plugin--parameter-wire parameter)))
        (when (or (dsh-protocol-bridge-parameter-required parameter)
                  (and agent-wire (equal agent-wire wire)))
          (let ((value (if (and agent-wire (equal agent-wire wire))
                           (dsh-emacs-plugin--read-agent agents)
                         (dsh-emacs-plugin--read-argument parameter))))
            (when (and (stringp value) (string-empty-p value))
              (user-error "%s is required" wire))
            (setq args (cons (cons wire value) args))))))
    (when (and agent-wire (not (assoc agent-wire args)))
      (setq args (cons (cons agent-wire
                             (dsh-emacs-plugin--read-agent agents))
                       args)))
    (nreverse args)))

(defun dsh-emacs-plugin--normalize-arguments (arguments)
  "Return ARGUMENTS with JSON object keys as strings."
  (mapcar (lambda (pair)
            (cons (if (symbolp (car pair))
                      (symbol-name (car pair))
                    (car pair))
                  (cdr pair)))
          arguments))

(defun dsh-emacs-plugin--read-object (prompt)
  "Read one JSON object at PROMPT and return it as an alist, or nil."
  (let ((text (read-string prompt "{}")))
    (if (string-empty-p (string-trim text))
        nil
      (let ((value (condition-case err
                       (dsh-protocol-read-json text)
                     (error
                      (user-error "Invalid JSON arguments: %s"
                                  (error-message-string err))))))
        (unless (or (null value) (consp value))
          (user-error "Arguments must be a JSON object"))
        (dsh-emacs-plugin--normalize-arguments value)))))

(defun dsh-emacs-plugin--read-optional-arguments (endpoint)
  "Read ENDPOINT's optional arguments as one JSON object, or nil."
  (let* ((agent-wire (dsh-emacs-plugin--agent-wire endpoint))
         (optional
          (cl-remove-if
           (lambda (parameter)
             (or (dsh-protocol-bridge-parameter-required parameter)
                 (and agent-wire
                      (equal agent-wire
                             (dsh-emacs-plugin--parameter-wire parameter)))))
           (dsh-protocol-bridge-endpoint-parameters endpoint))))
    (when optional
      (dsh-emacs-plugin--read-object
       (format "Optional arguments (JSON object; keys: %s; RET skips): "
               (mapconcat (lambda (parameter)
                            (or (dsh-emacs-plugin--parameter-wire parameter)
                                "?"))
                          optional ", "))))))

(defun dsh-emacs-plugin--merge-arguments (required optional)
  "Return REQUIRED followed by OPTIONAL pairs not named by REQUIRED."
  (append required
          (cl-remove-if (lambda (pair) (assoc (car pair) required))
                        optional)))

(defun dsh-emacs-plugin--read-arguments (endpoint agents raw)
  "Read ENDPOINT's arguments, or one raw JSON object when RAW is non-nil."
  (if raw
      (dsh-emacs-plugin--read-object "Arguments (JSON object): ")
    (dsh-emacs-plugin--merge-arguments
     (dsh-emacs-plugin--read-required-arguments endpoint agents)
     (dsh-emacs-plugin--read-optional-arguments endpoint))))

(defun dsh-emacs-plugin--show-result (title response)
  "Display TITLE's invoke RESPONSE in a read-only buffer."
  (let* ((value (plist-get response :value))
         (decoded (and (consp value)
                       (dsh-protocol-bridge-result--from-alist value)))
         (buffer (get-buffer-create (format "*dsh-plugin: %s*" title))))
    (with-current-buffer buffer
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert (propertize title 'face 'bold) "\n")
        (insert (format "HTTP %s\n\n"
                        (or (plist-get response :status) "no response")))
        (cond
         ((and decoded (dsh-protocol-bridge-result-ok decoded))
          (insert (dsh-protocol-write-json
                   (dsh-protocol-bridge-result-result decoded) t)))
         (decoded
          (insert (dsh-emacs-plugin--failure-string
                   response (dsh-protocol-bridge-result-error decoded))))
         (t
          (insert (dsh-emacs-plugin--failure-string response nil))))
        (insert "\n")
        (goto-char (point-min))
        (special-mode)))
    (display-buffer buffer)))

(defun dsh-emacs-plugin--invoke (package endpoint arguments)
  "Invoke PACKAGE's ENDPOINT with ARGUMENTS and display the result."
  (let ((name (dsh-protocol-bridge-endpoint-endpoint endpoint))
        (title (format "%s#%s" package
                       (dsh-protocol-bridge-endpoint-endpoint endpoint))))
    (message "Invoking %s ..." title)
    (dsh-emacs--http-json
     "POST"
     (concat (dsh-emacs-plugin--base-url) "/invoke")
     (append (dsh-emacs-plugin--headers)
             (list (cons "Content-Type" "application/json")))
     (encode-coding-string
      (dsh-protocol-write-json
       (dsh-protocol-bridge-invoke-request package name arguments))
      'utf-8)
     (lambda (response)
       (dsh-emacs-plugin--show-result title response)))))

;;;###autoload
(defun dsh-emacs-plugins (&optional raw-arguments)
  "Operate an exposed dsh plugin through dsh-plugins-bridge.
Reads the bridge's live plugin catalog, then asks for a plugin, one of
its Remote endpoints and that endpoint's arguments.  Agent-scoped
endpoints complete live agent ids from `/v1/agents'.  The call runs
asynchronously and its JSON result opens in a read-only
`*dsh-plugin: ...*' buffer; `q' closes it.

With a prefix argument, read all arguments as one JSON object instead of
prompting for each required parameter.

Requires `dsh-emacs-plugin-bridge-token' (or `DSH_BRIDGE_TOKEN'); the
bridge itself is configured in dsh Settings → Plugins Bridge."
  (interactive "P")
  (let* ((plugin (dsh-emacs-plugin--choose-plugin
                  (dsh-emacs-plugin--fetch-plugins)))
         (package (dsh-protocol-bridge-plugin-package plugin))
         (detail (dsh-emacs-plugin--fetch-plugin package))
         (endpoint (dsh-emacs-plugin--choose-endpoint detail))
         (agent-wire (dsh-emacs-plugin--agent-wire endpoint))
         (agents (and agent-wire (not raw-arguments)
                      (dsh-emacs-plugin--fetch-agents)))
         (arguments (dsh-emacs-plugin--read-arguments
                     endpoint agents raw-arguments)))
    (dsh-emacs-plugin--invoke package endpoint arguments)))

;;; ---------------------------------------------------------------------------
;;; Plugin HTTP route proxy
;;; ---------------------------------------------------------------------------
;; The bridge's `/v1/routes' lists route groups registered directly on the
;; dsh web server.  The command below picks one group and one absolute target
;; path, then forwards the request through `/v1/http/<target-path>'.  Responses
;; are not necessarily JSON, so this path uses the raw HTTP primitive.

(defconst dsh-emacs-plugin--route-methods
  '("GET" "POST" "PUT" "PATCH" "DELETE" "HEAD" "OPTIONS")
  "HTTP methods offered by `dsh-emacs-plugin-routes'.")

(defun dsh-emacs-plugin--decode-route-list (response)
  "Decode the route list in RESPONSE, or return nil."
  (let ((value (plist-get response :value)))
    (and (consp value)
         (dsh-protocol-bridge-route-list--from-alist value))))

(defun dsh-emacs-plugin--fetch-routes ()
  "Read and return the discovered route groups, or signal a `user-error'."
  (let* ((response (dsh-emacs-plugin--get "/routes"))
         (decoded (dsh-emacs-plugin--decode-route-list response)))
    (unless (and decoded (dsh-protocol-bridge-route-list-ok decoded))
      (dsh-emacs-plugin--fail
       response
       (and decoded (dsh-protocol-bridge-route-list-error decoded))))
    (dsh-protocol-bridge-route-list-routes decoded)))

(defun dsh-emacs-plugin--route-group-label (group)
  "Return GROUP's display label for completion."
  (let* ((id (dsh-protocol-bridge-route-group-id group))
         (title (dsh-protocol-bridge-route-group-title group))
         (shown (if (and title (not (equal title id))) title id))
         (count (dsh-protocol-bridge-route-group-route-count group)))
    (concat shown
            (if (and count (> count 0))
                (format " — %d route%s" count (if (= count 1) "" "s"))
              "")
            (unless (dsh-protocol-bridge-route-group-selected group)
              " [not exposed]"))))

(defun dsh-emacs-plugin--choose-route-group (groups)
  "Read one HTTP route group from GROUPS."
  (unless groups
    (user-error "No HTTP route groups; expose a plugin route in dsh Settings → Plugins Bridge"))
  (let* ((candidates
          (mapcar (lambda (group)
                    (cons (propertize
                           (dsh-protocol-bridge-route-group-id group)
                           'display (dsh-emacs-plugin--route-group-label group))
                          group))
                  groups))
         (picked (completing-read "Route group: " candidates nil t)))
    (cdr (assoc picked candidates))))

(defun dsh-emacs-plugin--route-group-by-id (groups id)
  "Return the route group in GROUPS whose id is ID.
Signal a `user-error' when the bridge did not report ID."
  (or (cl-find id groups
               :key #'dsh-protocol-bridge-route-group-id
               :test #'equal)
      (user-error "Route group %s was not found in /v1/routes" id)))

(defun dsh-emacs-plugin--require-selected-route-group (group)
  "Signal a `user-error' unless GROUP is exposed."
  (unless (dsh-protocol-bridge-route-group-selected group)
    (user-error "Route group %s is not exposed; enable it under Plugin HTTP routes in dsh Settings → Plugins Bridge"
                (dsh-protocol-bridge-route-group-id group))))

(defun dsh-emacs-plugin--route-group-prefix (group)
  "Return GROUP's absolute route prefix."
  (concat "/" (dsh-protocol-bridge-route-group-id group)))

(defun dsh-emacs-plugin--route-target-path (group path)
  "Return PATH as an absolute target path under GROUP.
A path already starting with GROUP's prefix is kept; a relative path or
one addressed below the group is prefixed with `/<group-id>'.  A query or
fragment suffix is preserved."
  (let* ((trimmed (string-trim (or path "")))
         (split (and (string-match "[?#]" trimmed) (match-beginning 0)))
         (pathname (if split (substring trimmed 0 split) trimmed))
         (suffix (if split (substring trimmed split) ""))
         (absolute (if (string-prefix-p "/" pathname)
                       pathname
                     (concat "/" pathname)))
         (prefix (dsh-emacs-plugin--route-group-prefix group))
         (target
          (cond
           ((string-empty-p absolute) prefix)
           ((equal absolute "/") prefix)
           ((or (equal absolute prefix)
                (string-prefix-p (concat prefix "/") absolute))
            absolute)
           (t (concat prefix absolute)))))
    (concat target suffix)))

(defun dsh-emacs-plugin--choose-route-path (group)
  "Read one absolute target path for GROUP."
  (let* ((id (dsh-protocol-bridge-route-group-id group))
         (paths (dsh-protocol-bridge-route-group-paths group))
         (prefix (dsh-emacs-plugin--route-group-prefix group))
         (default (or (car paths) prefix))
         (path
          (cond
           ((dsh-protocol-bridge-route-group-prefixes group)
            (read-string (format "Target path below %s: " prefix) default))
           (paths
            (completing-read "Target path: " paths nil t nil nil default))
           (t
            (read-string (format "Target path (group %s): " id) default)))))
    (dsh-emacs-plugin--route-target-path group path)))

(defun dsh-emacs-plugin--choose-route-method ()
  "Read one HTTP method for a route call."
  (completing-read "Method: " dsh-emacs-plugin--route-methods
                   nil t nil nil "GET"))

(defun dsh-emacs-plugin--select-route (&optional group method path)
  "Select one bridge route and return (GROUP METHOD PATH).
GROUP is a route group id, METHOD an HTTP method and PATH a target path.
Each non-nil argument replaces its completion or read prompt.  The
returned GROUP is the decoded route-group struct, METHOD is upper-case
and PATH is absolute and normalized below GROUP.  The chosen group must
be exposed under **Plugin HTTP routes**."
  (let* ((groups (dsh-emacs-plugin--fetch-routes))
         (group (if group
                    (dsh-emacs-plugin--route-group-by-id groups group)
                  (dsh-emacs-plugin--choose-route-group groups))))
    (dsh-emacs-plugin--require-selected-route-group group)
    (let* ((path (dsh-emacs-plugin--route-target-path
                  group
                  (or path (dsh-emacs-plugin--choose-route-path group))))
           (method (if method
                       (string-trim (upcase method))
                     (dsh-emacs-plugin--choose-route-method))))
      (list group method path))))

(defun dsh-emacs-plugin--route-body-method-p (method)
  "Non-nil when METHOD normally accepts a request body."
  (member method '("POST" "PUT" "PATCH" "DELETE")))

(defun dsh-emacs-plugin--read-route-body (method)
  "Read an optional request body for METHOD; nil when empty."
  (when (dsh-emacs-plugin--route-body-method-p method)
    (let ((body (read-string "Request body (RET for empty): ")))
      (unless (string-empty-p body) body))))

(defun dsh-emacs-plugin--read-route-content-type ()
  "Read the Content-Type for a route request body."
  (let ((type (read-string "Content-Type: " "application/json")))
    (if (string-empty-p type) "application/json" type)))

(defun dsh-emacs-plugin--route-header (headers name)
  "Return NAME's value in response HEADERS, a lower-case alist."
  (cdr (assoc name headers)))

(defun dsh-emacs-plugin--route-binary-p (content-type body)
  "Non-nil when CONTENT-TYPE or BODY indicates a binary response."
  (let ((type (and content-type
                   (downcase (car (split-string content-type ";"))))))
    (or (and body (string-match-p "\0" body))
        (and type (string-match-p "\\`\\(?:image\\|audio\\|video\\|font\\)/"
                                  type))
        (and type
             (string-match-p
              "\\`application/\\(?:octet-stream\\|pdf\\|zip\\|gzip\\|x-tar\\)\\'"
              type)))))

(defun dsh-emacs-plugin--route-decode-body (body content-type)
  "Decode BODY for display using CONTENT-TYPE's charset when present."
  (when body
    (if (multibyte-string-p body)
        body
      (let* ((charset (and content-type
                           (string-match "charset=\\([^;[:space:]]+\\)"
                                         content-type)
                           (match-string 1 content-type)))
             (coding (and charset
                          (coding-system-p (intern charset))
                          (intern charset))))
        (condition-case nil
            (decode-coding-string body (or coding 'utf-8))
          (error (decode-coding-string body 'utf-8)))))))

(defun dsh-emacs-plugin--route-body-text (body content-type)
  "Format BODY for display, pretty-printing plausible JSON."
  (let ((text (dsh-emacs-plugin--route-decode-body body content-type)))
    (if (and text
             (or (and content-type
                      (string-match-p
                       "\\(?:application/json\\|+json\\)"
                       (downcase content-type)))
                 (string-match-p "\\`[[:space:]]*[{\\[]" text)))
        (condition-case nil
            (let ((parsed (dsh-protocol-read-json text)))
              (cond
               ((and (null parsed)
                     (string-match-p "\\`[[:space:]]*{[[:space:]]*}\\'" text))
                "{}")
               ((and (null parsed)
                     (string-match-p "\\`[[:space:]]*null[[:space:]]*\\'" text))
                "null")
               (t (dsh-protocol-write-json parsed t))))
          (error text))
      text)))

(defun dsh-emacs-plugin--route-truncate (text)
  "Truncate TEXT to `dsh-emacs-plugin-route-max-output'."
  (let ((limit dsh-emacs-plugin-route-max-output))
    (if (and limit (> (length text) limit))
        (concat (substring text 0 limit)
                (format "\n\n… truncated: showing %d of %d characters"
                        limit (length text)))
      text)))

(defun dsh-emacs-plugin--show-route-result (title response)
  "Display TITLE's HTTP route RESPONSE in a read-only buffer."
  (let* ((status (plist-get response :status))
         (headers (plist-get response :headers))
         (content-type (dsh-emacs-plugin--route-header headers "content-type"))
         (content-length
          (dsh-emacs-plugin--route-header headers "content-length"))
         (body (plist-get response :body))
         (empty (or (null body) (string-empty-p body)))
         (buffer (get-buffer-create
                  (format "*dsh-plugin-route: %s*" title))))
    (with-current-buffer buffer
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert (propertize title 'face 'bold) "\n")
        (insert (format "HTTP %s\n" (or status "no response")))
        (when content-type
          (insert (format "Content-Type: %s\n" content-type)))
        (when content-length
          (insert (format "Content-Length: %s\n" content-length)))
        (insert "\n")
        (cond
         ((and empty (null status))
          (insert (dsh-emacs-plugin--failure-string response nil)))
         (empty
          (insert "(no response body)")
          (when (equal status 401)
            (insert (concat "\nThe target route requires a DSH browser session"
                            " that Emacs could not provide; authenticate with"
                            " `dsh-emacs-server-auth-token' or the dsh web URL."))))
         ((dsh-emacs-plugin--route-binary-p content-type body)
          (insert (format "[binary response: %d bytes, %s]"
                          (string-bytes body)
                          (or content-type "unknown content type"))))
         (t
          (insert (dsh-emacs-plugin--route-truncate
                   (dsh-emacs-plugin--route-body-text body content-type)))))
        (insert "\n")
        (goto-char (point-min))
        (special-mode)))
    (display-buffer buffer)))

(defun dsh-emacs-plugin--url-origin (url)
  "Return URL's (SCHEME HOST PORT) origin tuple, or nil."
  (let ((parsed (url-generic-parse-url (or url ""))))
    (when-let* ((host (url-host parsed)))
      (list (downcase (or (url-type parsed) ""))
            (downcase host)
            (url-port parsed)))))

(defun dsh-emacs-plugin--same-origin-p (left right)
  "Non-nil when LEFT and RIGHT have the same URL origin."
  (let ((left-origin (dsh-emacs-plugin--url-origin left))
        (right-origin (dsh-emacs-plugin--url-origin right)))
    (and left-origin right-origin
         (equal left-origin right-origin))))

(defun dsh-emacs-plugin--route-dsh-auth-headers ()
  "Return DSH session headers for a same-origin route request, or nil."
  (when (and dsh-emacs-plugin-route-forward-dsh-auth
             (dsh-emacs-plugin--same-origin-p
              (dsh-emacs-plugin--base-url)
              (dsh-emacs--server-base-url)))
    (dsh-emacs--server-auth-header)))

(defun dsh-emacs-plugin--route-request (group method path body content-type)
  "Return GROUP's route request as (URL HEADERS TITLE)."
  (let* ((target (dsh-emacs-plugin--route-target-path group path))
         (url (concat (dsh-emacs-plugin--base-url) "/http" target))
         (headers (append (dsh-emacs-plugin--headers "*/*")
                          (dsh-emacs-plugin--route-dsh-auth-headers)
                          (and body
                               (list (cons "Content-Type"
                                           (or content-type
                                               "application/json")))))))
    (list url headers (format "%s %s" method target))))

(defun dsh-emacs-plugin--invoke-route (group method path body content-type)
  "Call GROUP's route at PATH with METHOD, BODY and CONTENT-TYPE."
  (pcase-let ((`(,url ,headers ,title)
               (dsh-emacs-plugin--route-request
                group method path body content-type)))
    (message "Calling %s ..." title)
    (dsh-emacs--http-request
     method url headers
     (and body (encode-coding-string body 'utf-8))
     (lambda (response)
       (dsh-emacs-plugin--show-route-result title response)))))

(defun dsh-emacs-plugin--invoke-route-sync (group method path body content-type)
  "Call GROUP's route at PATH with METHOD, BODY and CONTENT-TYPE.
Return the decoded JSON response body.  Signal a `user-error' for a
transport failure, a non-2xx status or a body that is not JSON."
  (pcase-let ((`(,url ,headers ,_title)
               (dsh-emacs-plugin--route-request
                group method path body content-type)))
    (let ((response
           (dsh-emacs--http-json-sync
            method url headers
            (and body (encode-coding-string body 'utf-8))
            dsh-emacs-plugin-bridge-timeout)))
      (let ((status (plist-get response :status))
            (parse-error (plist-get response :parse-error)))
        (cond
         ((not (and (integerp status) (<= 200 status) (< status 300)))
          (dsh-emacs-plugin--fail response))
         ((memq status '(204 205))
          nil)
         (parse-error
          (user-error "Route response is not valid JSON: %s"
                      (error-message-string parse-error)))
         (t
          (plist-get response :value)))))))

;;;###autoload
(defun dsh-emacs-plugin-routes (&optional group method path body)
  "Call an HTTP route exposed by dsh-plugins-bridge.
Interactively, select one discovered route group, one target path and an
HTTP method, then forward the request through `/v1/http'.  For `POST',
`PUT', `PATCH' and `DELETE' Emacs also reads an optional body and its
Content-Type.  The response opens in a read-only
`*dsh-plugin-route: ...*' buffer; `q' closes it.  JSON responses are
pretty-printed; text is inserted as-is and binary bodies are summarized.

GROUP is a route group id, METHOD an HTTP method, PATH a target path and
BODY an optional request body.  Each non-nil argument replaces its prompt.
When both GROUP and METHOD are non-nil, neither is read through
completion, the request runs synchronously and the decoded JSON response
is returned instead of opening a result buffer.  A supplied BODY is sent
with Content-Type application/json; without BODY, a body-bearing METHOD
still reads an optional body and Content-Type.

Requires a route group exposed under **Plugin HTTP routes** in dsh
Settings → Plugins Bridge."
  (interactive)
  (let ((programmatic (and group method)))
    (pcase-let ((`(,group ,method ,path)
                 (dsh-emacs-plugin--select-route group method path)))
      (let* ((supplied-body body)
             (body (or body (dsh-emacs-plugin--read-route-body method)))
             (content-type
              (and body
                   (if supplied-body
                       "application/json"
                     (dsh-emacs-plugin--read-route-content-type)))))
        (if programmatic
            (dsh-emacs-plugin--invoke-route-sync
             group method path body content-type)
          (dsh-emacs-plugin--invoke-route
           group method path body content-type))))))

;;;###autoload
(defun dsh-emacs-plugin-insert-route-call ()
  "Insert a `dsh-emacs-plugin-routes' call for a bridge route.
Select one route group, target path and HTTP method exactly as
`dsh-emacs-plugin-routes' does, then insert the generated call at point.
The call passes GROUP, METHOD and PATH plus, for a body-bearing method,
the nonempty BODY read here.  A supplied BODY uses Content-Type
application/json when the call runs."
  (interactive)
  (pcase-let ((`(,group ,method ,path)
               (dsh-emacs-plugin--select-route)))
    (let ((id (dsh-protocol-bridge-route-group-id group))
          (body (dsh-emacs-plugin--read-route-body method)))
      (insert
       (if body
           (format "(dsh-emacs-plugin-routes %S %S %S %S)"
                   id method path body)
         (format "(dsh-emacs-plugin-routes %S %S %S)"
                 id method path))))))

(provide 'dsh-emacs-plugin)

;;; dsh-emacs-plugin.el ends here
