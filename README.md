<p align="center">
  <img src="assets/banner.svg" width="830" alt="janet-toml banner">
</p>
<p align="center">
  <a href="https://github.com/Celine1337/janet-toml/releases"><img src="assets/nav-releases.svg" alt="Releases"></a>
  <a href="https://toml.io/en/"><img src="assets/nav-spec.svg" alt="TOML spec"></a>
  <a href="LICENSE"><img src="assets/nav-mit.svg" alt="MIT"></a>
</p>

<img src="assets/section-about.svg" width="830" alt="About">

**janet-toml** is a fast, dependency-free validator for a practical subset of [TOML](https://toml.io/en/). Point it at a `.toml` file and it reports structural problems with exact line numbers — `ERROR line N: …` — then a summary `X error(s)`. It catches the mistakes that silently break config: duplicate keys in the same table, duplicate table headers, lines with no `=`, unterminated strings and arrays, and invalid value tokens. It exits `1` on any error and `0` when the file is clean, so it drops straight into a pre-commit hook or CI step.

Why Janet? Janet is a small, embeddable Lisp with a byte-code VM that starts instantly and ships a real standard library — strings, tables, arrays and buffers are all built in, so a single self-contained `.janet` file is a legitimate parser, not a toy. No runtime to install beyond the `janet` binary, no package manager, no build step.

<img src="assets/section-features.svg" width="830" alt="Features">

- **Line-numbered diagnostics** — every problem is reported as `ERROR line N: …`, followed by an `X error(s)` summary.
- **Duplicate detection** — duplicate keys within a table and duplicate `[table]` headers are errors; `[[array.of.tables]]` may repeat, and each element gets a fresh key scope.
- **Real value parsing** — basic strings `"…"` with escapes (`\n`, `\t`, `\"`, `\\`, `\uXXXX`, `\UXXXXXXXX`), literal strings `'…'`, integers (decimal / `0x` / `0o` / `0b`, signs, `1_000` underscores), floats (`3.14`, `1e6`, `-2.5E-3`, `inf`, `nan`), booleans, and arrays.
- **Multiline arrays** — `[ … ]` may span lines, with comments and a trailing comma; nested arrays work too.
- **Tables & comments** — `[table]`, `[[array.of.tables]]`, dotted table names (`[a.b.c]`), bare and quoted keys, and inline `#` comments (a `#` inside a string is not a comment).
- **Honest subset** — multiline strings (`"""`), dotted assignment keys (`a.b = 1`) and datetimes are reported as unsupported rather than silently mis-parsed; leading zeros are accepted leniently.
- **Zero dependencies & tested** — one Janet file; a self-contained `test.sh` builds fixtures and asserts exit codes and output.

<img src="assets/section-stack.svg" width="830" alt="Tech stack">

<img src="assets/section-install.svg" width="830" alt="Install">

Requires the [Janet](https://janet-lang.org/) binary (1.x) on your `PATH`.

```bash
git clone https://github.com/Celine1337/janet-toml.git
cd janet-toml
./build.sh          # writes a launcher at bin/janet-toml
./bin/janet-toml config.toml
```

Or run the source directly, no build at all:

```bash
janet src/main.janet config.toml
```

<img src="assets/section-usage.svg" width="830" alt="Usage">

```bash
janet-toml config.toml            # validate; exit 1 on errors, 0 when clean
```

```text
$ janet-toml broken.toml
ERROR line 3: duplicate key "port" in [server]
ERROR line 4: duplicate table header [server]
ERROR line 5: unterminated string
ERROR line 7: invalid value token "notatoken"
4 error(s)
```

```text
$ janet-toml good.toml
0 error(s)
```

**Supported subset:** bare/quoted keys, `key = value`, `[table]` / `[[array.of.tables]]` headers with dotted names, basic & literal strings, integers, floats, booleans, (multiline) arrays, and `#` comments. **Not supported** (reported as errors): multiline `"""`/`'''` strings, dotted assignment keys, and datetimes.

Exit codes: `0` clean, `1` validation errors, `2` missing file or bad usage.

<img src="assets/section-license.svg" width="830" alt="License">

MIT — see [LICENSE](LICENSE).