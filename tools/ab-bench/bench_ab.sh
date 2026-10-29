#!/bin/zsh
# In-session A/B: one game session on a COPY of the player's profile; runtime flags switch between condition A and B in
# 30 s windows, A B B A B A A B, while the camera pans the same way. Commands per condition are ';'-separated input lines.
# usage: A="flag mfx_output 1;flag mfx_upscale 1" B="flag mfx_output 0;flag mfx_upscale 0" bench_ab.sh <label> <app> [VAR=value ...]
#   GAME=botw|totk  SETTLE=<s> (default 75)  WIN=<s> per window (default 30)  ORDER (default ABBABAAB)  BIN (default ./build/totk-native)
set -u
HERE=${0:A:h}   # this folder (the script cds into the app below)
S=${BENCH_RUNS:-$HOME/Games/bench-runs}; mkdir -p $S/runs
LABEL=$1; APP=$2; shift 2
GAME=${GAME:-botw}; SETTLE=${SETTLE:-75}; WIN=${WIN:-30}; ORDER=${ORDER:-ABBABAAB}
if [[ $GAME == botw ]]; then DATA="$HOME/Library/Application Support/MacNativeGames/BotW"; VDIR=botw190
else DATA="$HOME/Library/Application Support/MacNativeGames/TOTK"; VDIR=v143; fi
RUN=$S/runs/$LABEL; rm -rf $RUN; mkdir -p $RUN
cp -cR "$DATA/profile" $RUN/profile || exit 1
# KEEP_SLOT=<n>: the copy keeps only that numbered save slot, so autoload loads it (the player's profile is untouched)
if [[ -n ${KEEP_SLOT:-} ]]; then for d in $RUN/profile/save/*/[0-9]*(N/); do [[ ${d:t} == $KEEP_SLOT ]] || rm -rf $d; done; fi
: > $RUN/input.txt
[[ -f "$DATA/controls.txt" ]] && cp "$DATA/controls.txt" $RUN/controls.txt
for kv in ${(s:,:)${SETTINGS:-}}; do print -r -- "${kv#*=}" > $RUN/${kv%%=*}; done
LOG=$RUN/game.log
cmd() { print -r -- "$1" >> $RUN/input.txt; }
if pgrep -q totk-native || pgrep -qx BotW || pgrep -qx TOTK; then echo "a game is already running"; exit 1; fi
cd "$APP/Contents/Resources/totk" || exit 1
BIN=${BIN:-./build/totk-native}
CHAIN=$(grep -o 'define DMSH_CHAIN "[^"]*"' $HERE/../../games/totk/third_party/d2r_gfx/gfx/nvn/dmsh_chain.h | sed -E 's/.*"(.*)"/\1/')
CACHE=${CACHE:-"$DATA/shader-cache/rt-$CHAIN"}; mkdir -p "$CACHE"
print -r -- "app=$APP bin=$BIN cache=$CACHE settings=${SETTINGS:-} A=${A:-} B=${B:-} order=$ORDER win=$WIN extra=$*" > $RUN/config
env TOTK_CONTROLS=$RUN/controls.txt TOTK_PROFILE_DIR=$RUN/profile TOTK_SHADER_CACHE="$CACHE" \
    TOTK_GAME_SLOT_DIR="$DATA/game-slot" TOTK_ROMFS_PROOF_DIR="$DATA" TOTK_SHARED_FONTS=extracted/firmware/shared-fonts \
    TOTK_ROMFS_MODS="$DATA/mods/$VDIR" TOTK_LOCALE=en-US TOTK_GPU_ALLOW_SUBMIT=1 TOTK_GPU_WIDEN=1 TOTK_GPU_BLOCKRT=1 \
    TOTK_GPU_MIDCLEAR=1 TOTK_SLOT_OWNER=agent TOTK_SLOT_PURPOSE=test TOTK_SHADER_CONTRIB=$RUN/contrib.txt \
    TOTK_INPUT_FILE=$RUN/input.txt TOTK_AUTOLOAD=1 TOTK_PICTURE_MODE=$RUN/picture-mode.txt \
    TOTK_BENCH_FRAMES=$RUN/frames.txt TOTK_WINDOW_SIZE=${WSIZE:-1800x1012} "$@" \
    $BIN rewritten/$VDIR boot > $LOG 2>&1 &
PID=$!
echo "pid $PID"
for i in {1..300}; do grep -q '\[autoload\] \(load started\|gave up\|cancelled\)' $LOG 2>/dev/null && break
  kill -0 $PID 2>/dev/null || { echo "died during boot"; tail -20 $LOG; exit 2; }; sleep 1; done
grep '\[autoload\]' $LOG | tail -2
sleep $SETTLE
kill -0 $PID 2>/dev/null || { echo "died while settling"; tail -30 $LOG; exit 2; }
cmd "shot $RUN/start.png"; sleep 2
: > $RUN/windows
dir=124
for (( i = 1; i <= ${#ORDER}; i++ )); do
  c=${ORDER[$i]}
  if [[ $c == A ]]; then cmds=${A:-}; else cmds=${B:-}; fi
  for line in ${(s:;:)cmds}; do cmd "$line"; done
  sleep 3
  f0=$(tail -1 $RUN/frames.txt 2>/dev/null | cut -d' ' -f1); l0=$(wc -l < $LOG)
  end=$((SECONDS + WIN - 3))
  while (( SECONDS < end )); do cmd "key $dir 4000"; sleep 4.3; dir=$(( dir == 124 ? 123 : 124 )); done
  f1=$(tail -1 $RUN/frames.txt 2>/dev/null | cut -d' ' -f1); l1=$(wc -l < $LOG)
  print -r -- "$c ${f0:-0} ${f1:-0} $l0 $l1" >> $RUN/windows
  (( i == 1 || i == ${#ORDER} )) && cmd "shot $RUN/w$i-$c.png"
  kill -0 $PID 2>/dev/null || { echo "died during window $i"; tail -30 $LOG; exit 2; }
done
[[ -n ${PASSGPU:-} ]] && { for line in ${(s:;:)PASSGPU}; do cmd "$line"; done; sleep 4; }
cmd "close"
for i in {1..40}; do kill -0 $PID 2>/dev/null || break; sleep 1; done
kill -0 $PID 2>/dev/null && { kill $PID; sleep 3; kill -9 $PID 2>/dev/null; }
echo "done $LABEL"
