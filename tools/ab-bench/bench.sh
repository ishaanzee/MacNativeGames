#!/bin/zsh
# One benchmark run of BotW or TOTK on a COPY of the player's profile (the real profile is never used).
# usage: bench.sh <label> <app> [VAR=value ...]
#   GAME=botw|totk (default botw)  SETTLE=<s> after the load starts (default 75)  MEASURE=<s> (default 90)
#   SCEN=pan (camera pans, default) | walk (forward/back with turns)
set -u
HERE=${0:A:h}   # this folder (the script cds into the app below)
S=${BENCH_RUNS:-$HOME/Games/bench-runs}; mkdir -p $S/runs
LABEL=$1; APP=$2; shift 2
GAME=${GAME:-botw}; SETTLE=${SETTLE:-75}; MEASURE=${MEASURE:-90}; SCEN=${SCEN:-pan}
if [[ $GAME == botw ]]; then DATA="$HOME/Library/Application Support/MacNativeGames/BotW"; VDIR=botw190
else DATA="$HOME/Library/Application Support/MacNativeGames/TOTK"; VDIR=v143; fi
RUN=$S/runs/$LABEL; rm -rf $RUN; mkdir -p $RUN
cp -cR "$DATA/profile" $RUN/profile || exit 1
# KEEP_SLOT=<n>: the copy keeps only that numbered save slot, so autoload loads it (the player's profile is untouched)
if [[ -n ${KEEP_SLOT:-} ]]; then for d in $RUN/profile/save/*/[0-9]*(N/); do [[ ${d:t} == $KEEP_SLOT ]] || rm -rf $d; done; fi
: > $RUN/input.txt
# settings are read next to TOTK_CONTROLS: keep them in the run folder (the player's own files are never read or written)
[[ -f "$DATA/controls.txt" ]] && cp "$DATA/controls.txt" $RUN/controls.txt
for kv in ${(s:,:)${SETTINGS:-}}; do print -r -- "${kv#*=}" > $RUN/${kv%%=*}; done
LOG=$RUN/game.log
cmd() { print -r -- "$1" >> $RUN/input.txt; }
if pgrep -q totk-native || pgrep -qx BotW || pgrep -qx TOTK; then echo "a game is already running"; exit 1; fi
RES="$APP/Contents/Resources/totk"
cd "$RES" || exit 1
BIN=./build/totk-native
CHAIN=$(grep -o 'define DMSH_CHAIN "[^"]*"' $HERE/../../games/totk/third_party/d2r_gfx/gfx/nvn/dmsh_chain.h 2>/dev/null | sed -E 's/.*"(.*)"/\1/')
CACHE=${CACHE:-"$DATA/shader-cache/rt-$CHAIN"}
mkdir -p "$CACHE"
print -r -- "app=$APP cache=$CACHE settings=${SETTINGS:-} extra=$*" > $RUN/config
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
grep '\[autoload\]' $LOG | tail -3
sleep $SETTLE
kill -0 $PID 2>/dev/null || { echo "died while settling"; tail -30 $LOG; exit 2; }
cmd "shot $RUN/start.png"; sleep 2
F0=$(tail -1 $RUN/frames.txt 2>/dev/null | cut -d' ' -f1); F0=${F0:-0}; L0=$(wc -l < $LOG)
end=$((SECONDS + MEASURE)); k=0
while (( SECONDS < end )); do
  if [[ $SCEN == walk ]]; then
    cmd "key 13 3000"; sleep 3.3; cmd "key 124 1200"; sleep 1.5
    cmd "key 1 3000"; sleep 3.3; cmd "key 123 1200"; sleep 1.5
  else
    cmd "key 124 4000"; sleep 4.3; cmd "key 123 4000"; sleep 4.3
  fi
  k=$((k+1)); (( k % 4 == 0 )) && cmd "shot $RUN/t$k.png"
done
F1=$(tail -1 $RUN/frames.txt 2>/dev/null | cut -d' ' -f1); F1=${F1:-0}; L1=$(wc -l < $LOG)
echo "$F0 $F1 $L0 $L1" > $RUN/window
cmd "shot $RUN/end.png"; sleep 2
cmd "close"
for i in {1..40}; do kill -0 $PID 2>/dev/null || break; sleep 1; done
kill -0 $PID 2>/dev/null && { kill $PID; sleep 3; kill -9 $PID 2>/dev/null; }
echo "done $LABEL frames $F0..$F1 lines $L0..$L1"
