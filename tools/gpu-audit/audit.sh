#!/bin/sh
# GPU rendering audit (PLANO, Fase 27): runs the same scenarios in a hidden Glove session
# (Xvfb + the winit backend, nothing on the user's screen) with GLOVE_PROF=1 and writes a
# table with the time of each frame: the compositor (prepare on the CPU, render) and each
# app (paint on the CPU). Run it before and after every step and compare.
#
#   tools/gpu-audit/audit.sh [OUT_DIR] [LABEL]
#
# Needs: Xvfb, the release binaries (cargo build --release -p glove -p glove-apps).
# Under Xvfb the GPU is software (llvmpipe): the "render" numbers are only comparable
# with each other; the CPU paint numbers are the ones this phase moves to the GPU.
set -e
pausa() { timeout "$1" tail -f /dev/null || true; }
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
B=$ROOT/target/release
OUT=${1:-${TMPDIR:-/tmp}/glove-gpu-audit}
LABEL=${2:-$(git -C "$ROOT" describe --tags --always 2>/dev/null)}
DISP=${GLOVE_AUDIT_DISPLAY:-:78}
# The Wayland socket path must be short: the runtime folder goes to a short temporary one.
RT=$(mktemp -d "${TMPDIR:-/tmp}/ga.XXXXXX")
H=$OUT/home
mkdir -p "$OUT" "$H/.config/glove" "$RT" "$H/Documentos" "$H/Imagens" "$H/Muitos"
chmod 700 "$RT"
rm -f "$RT/wayland-1" "$RT/wayland-1.lock" "$RT/glove-ctl" "$OUT/glove.log"

# A fixed home: the defaults, the Dock on, no lock, no welcome.
cat > "$H/.config/glove/config.toml" <<CFG
welcome_done = true
[security]
require_password = false
[dock]
autohide = false
magnification = true
CFG
# Content: a long document, a folder with many files, a picture.
[ -f "$H/Documentos/longo.txt" ] || python3 -c "
import random
random.seed(1)
w='o glove desenha cada quadro da tela com cuidado e rapidez para ficar leve'.split()
open('$H/Documentos/longo.txt','w').write('\n\n'.join(' '.join(random.choice(w) for _ in range(90)) for _ in range(400)))"
[ -f "$H/Muitos/arquivo-599.txt" ] || for i in $(seq 0 599); do echo x > "$H/Muitos/arquivo-$i.txt"; done
cp -f "$ROOT/data/wallpapers/glove-os.png" "$H/Imagens/foto.png"

setsid nice -n 19 Xvfb "$DISP" -screen 0 1280x800x24 > "$OUT/xvfb.log" 2>&1 &
XPID=$!
pausa 2
env -u WAYLAND_DISPLAY LP_NUM_THREADS=2 GLOVE_PROF=1 PATH="$B:$PATH" HOME="$H" DISPLAY="$DISP" GLOVE_BACKEND=winit GLOVE_DEBUG_CTL=1 XDG_RUNTIME_DIR="$RT" \
  setsid nice -n 19 dbus-run-session -- "$B/glove" > "$OUT/glove.log" 2>&1 &
pausa 9
C=$RT/glove-ctl
c() { echo "$1" > "$C"; pausa "${2:-0.3}"; }
mark() { c "profmark $1" 0.3; }
dump() { c "profdump" 0.5; }

mark idle; pausa 3; dump

mark dock_hover
for pass in 1 2; do x=80; while [ $x -le 1200 ]; do c "move $x 765" 0.03; x=$((x+20)); done; done
c "move 640 400" 0.5; dump

c "run glove-files $H/Muitos" 4
mark menus
for x in 165 228 300 366 228 165; do c "move $x 10" 0.05; c "click" 0.4; done
c "key esc" 0.5; dump

mark files_scroll
c "move 640 420" 0.3
for i in $(seq 1 30); do c "scroll 120" 0.05; done
for i in $(seq 1 30); do c "scroll -120" 0.05; done
pausa 0.5; dump

c "run glove-edit $H/Documentos/longo.txt" 5
mark editor_scroll
c "move 640 420" 0.3
for i in $(seq 1 40); do c "scroll 150" 0.05; done
pausa 0.5; dump

mark editor_type
c "key ctrl+end" 0.5
c "type o glove fica rapido quando desenha na placa de video e leve quando fica parado " 2
dump

mark window_drag
c "down" 0.1
for i in $(seq 1 40); do c "move $((400 + i * 8)) $((300 + i * 3))" 0.03; done
c "up" 0.5; dump

c "run glove-view $H/Imagens/foto.png" 4
mark viewer_zoom
for i in 1 2 3 4 5; do c "key ctrl+equal" 0.3; done
for i in 1 2 3 4 5; do c "key ctrl+minus" 0.3; done
dump

mark expose
c "key f9" 1.5; c "key f9" 1.5
dump

# End: only what this audit started.
for p in $(pgrep -f "dbus-run-session -- $B/glove") $(pgrep -x glove) $(pgrep -x glove-apps); do
  if tr '\0' '\n' < /proc/$p/environ 2>/dev/null | grep -q "^XDG_RUNTIME_DIR=$RT"; then kill $p 2>/dev/null || true; fi
done
kill $XPID 2>/dev/null || true
rm -rf "$RT"
python3 "$ROOT/tools/gpu-audit/report.py" "$OUT/glove.log" "$LABEL"
