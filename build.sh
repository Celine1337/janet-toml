#!/usr/bin/env bash
# Build a launcher at bin/janet-toml (Janet is interpreted; no compilation needed).
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p bin
cat > bin/janet-toml <<'WRAP'
#!/usr/bin/env bash
DIR="$(cd "$(dirname "$0")/.." && pwd)"
export PATH="$HOME/.local/toolchains/janet/bin:$HOME/.local/bin:$PATH"
exec janet "$DIR/src/main.janet" "$@"
WRAP
chmod +x bin/janet-toml
echo "built bin/janet-toml"