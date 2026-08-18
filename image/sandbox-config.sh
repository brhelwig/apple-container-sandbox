sandbox_config() {
    [ -r "$1" ] || { printf '%s\n' "$4"; return 0; }
    python3 - "$1" "$2" "$3" "$4" <<'PY'
import sys, tomllib
with open(sys.argv[1], "rb") as f:
    val = tomllib.load(f).get(sys.argv[2], {}).get(sys.argv[3])
if isinstance(val, bool):
    val = "true" if val else "false"
print(sys.argv[4] if val in (None, "") else val)
PY
}
