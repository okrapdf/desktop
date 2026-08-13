#!/bin/zsh
set -euo pipefail

provider_root="$1"
python_bin=""
path_python="$(command -v python3 2>/dev/null || true)"
python_candidates=(
  /opt/homebrew/bin/python3.13
  /opt/homebrew/bin/python3.12
  /opt/homebrew/bin/python3.11
  /opt/homebrew/bin/python3.10
  /opt/homebrew/bin/python3
  /usr/local/bin/python3.13
  /usr/local/bin/python3.12
  /usr/local/bin/python3.11
  /usr/local/bin/python3.10
  /usr/local/bin/python3
  /usr/bin/python3
)

if [[ -n "$path_python" ]]; then
  python_candidates+=("$path_python")
fi

for candidate in "${python_candidates[@]}"; do
  if [[ ! -x "$candidate" ]]; then
    continue
  fi
  python_version="$("$candidate" -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")' 2>/dev/null || true)"
  python_major="${python_version%%.*}"
  python_minor="${python_version#*.}"
  if [[ "$python_major" == <-> && "$python_minor" == <-> ]] \
    && (( python_major > 3 || (python_major == 3 && python_minor >= 10) )); then
    python_bin="$candidate"
    break
  fi
done

if [[ -z "$python_bin" ]]; then
  print -u2 "Dots OCR 1.5 requires Python 3.10 or newer. Install it with 'brew install python@3.13', then retry setup."
  exit 1
fi

mkdir -p "$provider_root/huggingface"
"$python_bin" -m venv --clear "$provider_root/venv"
"$provider_root/venv/bin/python" -m pip install \
  --disable-pip-version-check \
  --require-virtualenv \
  "mlx-vlm==0.6.6" \
  "huggingface-hub==1.24.0"
"$provider_root/venv/bin/python" -m pip freeze > "$provider_root/installed-packages.txt"
