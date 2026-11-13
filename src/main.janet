# janet-toml - validate a practical TOML subset, reporting errors with line numbers.
# Pure Janet, standard library only. Run: janet src/main.janet <file.toml>

# ---- mutable parser state (reset per run) ----
(var src "")
(var pos 0)
(var line 1)
(var errors @[])
(var defined @{})        # path-id -> "table" | "aot"
(var tbl-keys @{})       # path-id -> @{key -> true}
(var current "")
(var current-display "root table")

(def SEP "\x1f")         # separator for table path identity (cannot appear in a bare key)
(def escapes {"b" "\b" "t" "\t" "n" "\n" "f" "\f" "r" "\r" "\"" "\"" "\\" "\\"})

(defn err [msg]
  (array/push errors (string "ERROR line " line ": " msg)))

# ---- character helpers (Janet strings index as bytes, so slice 1 char) ----
(defn peek []
  (if (< pos (length src)) (string/slice src pos (+ pos 1)) ""))

(defn peek3 []
  (string/slice src pos (min (+ pos 3) (length src))))

(defn advance []
  (when (= (peek) "\n") (++ line))
  (++ pos))

(defn skip-ws []
  (while (or (= (peek) " ") (= (peek) "\t") (= (peek) "\r"))
    (advance)))

(defn skip-comment []
  (while (and (not= (peek) "\n") (not= (peek) ""))
    (advance)))

# skip whitespace, newlines and full-line comments (used between statements
# and inside arrays)
(defn skip-blank []
  (var go true)
  (while go
    (skip-ws)
    (cond
      (= (peek) "#") (skip-comment)
      (= (peek) "\n") (advance)
      :else (set go false))))

(defn recover-line []
  (while (and (not= (peek) "\n") (not= (peek) ""))
    (advance))
  (when (= (peek) "\n") (advance)))

(defn bare-char? [c]
  (or (and (>= c "a") (<= c "z"))
      (and (>= c "A") (<= c "Z"))
      (and (>= c "0") (<= c "9"))
      (= c "_") (= c "-")))

(defn hex? [c]
  (or (and (>= c "0") (<= c "9"))
      (and (>= c "a") (<= c "f"))
      (and (>= c "A") (<= c "F"))))

(defn all-digits? [s]
  (var ok (> (length s) 0))
  (for i 0 (length s)
    (def c (string/slice s i (+ i 1)))
    (if (or (< c "0") (> c "9")) (set ok false)))
  ok)

(defn all-in? [s allowed]
  (var ok (> (length s) 0))
  (for i 0 (length s)
    (def c (string/slice s i (+ i 1)))
    (if (nil? (string/find c allowed)) (set ok false)))
  ok)

# digits with optional single underscores between them (no leading/trailing/double)
(defn num-digits? [s]
  (and (> (length s) 0)
       (not (string/has-prefix? "_" s))
       (not (string/has-suffix? "_" s))
       (nil? (string/find "__" s))
       (all (fn [p] (all-digits? p)) (string/split "_" s))))

(defn valid-number? [tok]
  (var t tok)
  (if (or (string/has-prefix? "+" t) (string/has-prefix? "-" t))
    (set t (string/slice t 1)))
  (cond
    (or (= t "inf") (= t "nan")) true
    (or (string/has-prefix? "0x" t) (string/has-prefix? "0o" t) (string/has-prefix? "0b" t))
    (do
      (def base (string/slice t 0 2))
      (def body (string/slice t 2))
      (def allowed (cond (= base "0x") "0123456789abcdefABCDEF_"
                         (= base "0o") "01234567_"
                         :else "01_"))
      (and (all-in? body allowed)
           (not (string/has-prefix? "_" body))
           (not (string/has-suffix? "_" body))
           (nil? (string/find "__" body))))
    :else
    (do
      (var epos -1)
      (for i 0 (length t)
        (def c (string/slice t i (+ i 1)))
        (if (or (= c "e") (= c "E")) (set epos i)))
      (def mant (if (>= epos 0) (string/slice t 0 epos) t))
      (def exp-ok
        (if (>= epos 0)
          (do
            (def e (string/slice t (+ epos 1)))
            (def e2 (if (or (string/has-prefix? "+" e) (string/has-prefix? "-" e))
                      (string/slice e 1) e))
            (num-digits? e2))
          true))
      (def parts (string/split "." mant))
      (def mant-ok
        (cond
          (= (length parts) 1) (num-digits? (get parts 0))
          (= (length parts) 2) (and (num-digits? (get parts 0)) (num-digits? (get parts 1)))
          :else false))
      (and exp-ok mant-ok))))

(defn valid-value-token? [tok]
  (or (= tok "true") (= tok "false") (valid-number? tok)))

# ---- string values ----
(defn parse-string []
  (def q (peek))
  (def triple (string q q q))
  (if (= (peek3) triple)
    (do
      (err "multiline strings are not supported")
      (advance) (advance) (advance)
      (var go true)
      (while go
        (cond
          (= (peek) "") (set go false)
          (= (peek3) triple) (do (advance) (advance) (advance) (set go false))
          :else (advance)))
      nil)
    (do
      (advance)  # opening quote
      (def buf @"")
      (var ok true)
      (var closed false)
      (while (and ok (not closed))
        (def c (peek))
        (cond
          (or (= c "") (= c "\n")) (do (err "unterminated string") (set ok false))
          (= c q) (do (advance) (set closed true))
          (and (= q "\"") (= c "\\"))
          (do
            (advance)
            (def e (peek))
            (cond
              (= e "") (do (err "unterminated string") (set ok false))
              (in escapes e) (do (buffer/push buf (get escapes e)) (advance))
              (or (= e "u") (= e "U"))
              (do
                (advance)
                (def n (if (= e "u") 4 8))
                (var good true)
                (for i 0 n
                  (if (hex? (peek)) (advance) (set good false)))
                (if good
                  (buffer/push buf "?")
                  (do (err "invalid unicode escape") (set ok false))))
              :else (do (err (string "invalid escape sequence \\" e)) (set ok false))))
          :else (do (buffer/push buf c) (advance))))
      (if ok buf nil))))

# ---- keys ----
(defn parse-key []
  (skip-ws)
  (def c (peek))
  (cond
    (or (= c "\"") (= c "'")) (parse-string)
    (bare-char? c)
    (do
      (def start pos)
      (while (bare-char? (peek)) (advance))
      (string/slice src start pos))
    :else nil))

(defn parse-dotted []
  (def segs @[])
  (var ok true)
  (var more true)
  (while (and ok more)
    (def k (parse-key))
    (if (nil? k)
      (set ok false)
      (do
        (array/push segs k)
        (skip-ws)
        (if (= (peek) ".")
          (do (advance) (skip-ws))
          (set more false)))))
  (if ok segs nil))

# ---- values ----
(defn atom-start? [c]
  (or (and (>= c "0") (<= c "9"))
      (and (>= c "a") (<= c "z"))
      (and (>= c "A") (<= c "Z"))
      (= c "+") (= c "-")))

(defn atom-char? [c]
  (and (not= c "") (not= c " ") (not= c "\t") (not= c "\r")
       (not= c "\n") (not= c ",") (not= c "#")
       (not= c "]") (not= c "[") (not= c "}")))

(defn parse-atom []
  (def start pos)
  (while (atom-char? (peek)) (advance))
  (def tok (string/slice src start pos))
  (if (valid-value-token? tok)
    tok
    (do (err (string "invalid value token \"" tok "\"")) nil)))

(var parse-value nil)  # forward declaration (mutual recursion with parse-array)

(defn parse-array []
  (advance)  # [
  (var ok true)
  (var done false)
  (skip-blank)
  (if (= (peek) "]")
    (do (advance) (set done true))
    (while (and ok (not done))
      (def v (parse-value))
      (when (nil? v) (set ok false))
      (when ok
        (skip-blank)
        (def c (peek))
        (cond
          (= c ",") (do (advance) (skip-blank)
                        (when (= (peek) "]") (advance) (set done true)))
          (= c "]") (do (advance) (set done true))
          (= c "") (do (err "unterminated array") (set ok false))
          :else (do (err "expected ',' or ']' in array") (set ok false))))))
  (if ok true nil))

(set parse-value (fn []
  (skip-ws)
  (def c (peek))
  (cond
    (or (= c "\"") (= c "'")) (parse-string)
    (= c "[") (parse-array)
    (atom-start? c) (parse-atom)
    :else (do (err "expected a value") nil))))

# ---- table / key registration ----
(defn path-id [segs] (string/join segs SEP))
(defn path-display [segs] (string/join segs "."))

(defn register-key [k]
  (def ks (get tbl-keys current))
  (if (nil? ks)
    (do (def nk @{}) (put nk k true) (put tbl-keys current nk))
    (if (in ks k)
      (err (string "duplicate key \"" k "\" in " current-display))
      (put ks k true))))

(defn parse-header []
  (advance)  # [
  (var aot false)
  (when (= (peek) "[") (set aot true) (advance))
  (def segs (parse-dotted))
  (var ok (not (nil? segs)))
  (when (nil? segs) (err "expected a table name"))
  (when ok
    (skip-ws)
    (if (not= (peek) "]")
      (do (err "expected ']' to close table header") (set ok false))
      (do
        (advance)
        (when aot
          (if (not= (peek) "]")
            (do (err "expected ']]' to close array-of-tables header") (set ok false))
            (advance))))))
  (when ok
    (skip-ws)
    (def c (peek))
    (if (and (not= c "") (not= c "\n") (not= c "\r") (not= c "#"))
      (do (err "unexpected content after table header") (set ok false))))
  (when ok
    (def id (path-id segs))
    (def disp (string "[" (path-display segs) "]"))
    (if aot
      (do
        (when (= (get defined id) "table")
          (err (string "cannot redefine table " disp " as array of tables")))
        (put defined id "aot")
        (put tbl-keys id @{}))
      (do
        (when (in defined id)
          (err (string "duplicate table header " disp)))
        (put defined id "table")
        (put tbl-keys id @{})))
    (set current id)
    (set current-display disp))
  (when (not ok) (recover-line)))

(defn parse-assignment []
  (def k (parse-key))
  (var ok (not (nil? k)))
  (when (nil? k) (err "expected a key"))
  (when ok
    (skip-ws)
    (if (= (peek) ".")
      (do (err "dotted keys are not supported") (set ok false))
      (if (not= (peek) "=")
        (do (err (string "expected '=' after key \"" k "\"")) (set ok false))
        (advance))))
  (when ok
    (def v (parse-value))
    (when (nil? v) (set ok false)))
  (when ok
    (skip-ws)
    (def c (peek))
    (if (and (not= c "") (not= c "\n") (not= c "\r") (not= c "#"))
      (do (err "unexpected content after value") (set ok false))))
  (when ok (register-key k))
  (when (not ok) (recover-line)))

(defn validate [text]
  (set src text)
  (set pos 0)
  (set line 1)
  (set errors @[])
  (set defined @{})
  (set tbl-keys @{})
  (put tbl-keys "" @{})
  (set current "")
  (set current-display "root table")
  (var go true)
  (while go
    (skip-blank)
    (if (= (peek) "")
      (set go false)
      (if (= (peek) "[")
        (parse-header)
        (parse-assignment))))
  errors)

(defn main []
  (def uargs (drop 1 (dyn :args)))
  (if (not= (length uargs) 1)
    (do (eprint "usage: janet-toml <file.toml>") (os/exit 2))
    (do
      (def path (get uargs 0))
      (def text (try (slurp path) ([e] nil)))
      (if (nil? text)
        (do (eprint (string "janet-toml: cannot read file: " path)) (os/exit 2))
        (do
          (validate text)
          (each e errors (print e))
          (print (string (length errors) " error(s)"))
          (os/exit (if (> (length errors) 0) 1 0)))))))

(main)