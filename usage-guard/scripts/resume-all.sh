#!/bin/sh
# Builds a paste-ready shell block that reopens every recent Claude Desktop session
# (claude --desktop --resume <id>) after a credit cut-off. macOS / Linux.
#   resume-all.sh                -> sessions active in the last 48 h, current app account
#   resume-all.sh -Hours 6       -> narrower window
#   resume-all.sh -All           -> every non-archived session of the account
#   resume-all.sh -GapSeconds 15 -> spacing between launches (default 12)
# Needs python3 (or node) to read the app's session records.
# Output: printed to stdout, and saved to ~/.claude/resume-all-latest.sh (+ a stamped copy).
# The block resolves the CLI itself at paste time: claude on PATH, else the newest CLI bundled
# with the Claude Desktop app. So it works on a Mac where claude was never added to PATH, and
# keeps working after the app has updated its bundled CLI.
hours=48; all=0; gap=12
while [ $# -gt 0 ]; do
  case "$1" in
    -Hours|--hours) hours="$2"; shift 2 ;;
    -All|--all) all=1; shift ;;
    -GapSeconds|--gap) gap="$2"; shift 2 ;;
    *) shift ;;
  esac
done

if [ -n "${CLAUDE_DESKTOP_SESSIONS_DIR:-}" ]; then
  root="$CLAUDE_DESKTOP_SESSIONS_DIR"
elif [ -d "$HOME/Library/Application Support/Claude/claude-code-sessions" ]; then
  root="$HOME/Library/Application Support/Claude/claude-code-sessions"
else
  root="${XDG_CONFIG_HOME:-$HOME/.config}/Claude/claude-code-sessions"
fi
[ -d "$root" ] || { echo "no Claude Desktop session store at $root" >&2; exit 1; }

stamp=$(date -u +"%Y-%m-%d %H:%M""Z")

# The interpreter picks the account the app is signed into (= the account/org folder holding the
# most recently written record), then prints "ACCOUNT<TAB><label>" followed by one row per session.
if python3 -c 'import sys' >/dev/null 2>&1; then
  rows=$(python3 - "$root" "$hours" "$all" <<'PY'
import json, os, sys, time, glob
root, hours, all_ = sys.argv[1], float(sys.argv[2]), sys.argv[3] == "1"
files = glob.glob(os.path.join(root, "*", "*", "local_*.json"))
if not files:
    sys.exit("no sessions found under " + root)
newest = max(files, key=os.path.getmtime)
d = os.path.dirname(newest)
print("ACCOUNT\t" + os.path.basename(os.path.dirname(d)))
cutoff = (time.time() - hours * 3600) * 1000
out = []
for p in glob.glob(os.path.join(d, "local_*.json")):
    try:
        s = json.load(open(p, encoding="utf-8"))
    except Exception:
        continue
    if not s.get("cliSessionId") or s.get("isArchived"):
        continue
    last = s.get("lastActivityAt") or 0
    if not all_ and last < cutoff:
        continue
    out.append((last, s["cliSessionId"], s.get("cwd", ""), (s.get("title") or "").replace("\n", " ").replace("\t", " ")))
for last, sid, cwd, title in sorted(out, reverse=True):
    when = time.strftime("%d-%b %H:%MZ", time.gmtime(last / 1000))
    print("\t".join([when, sid, cwd, title]))
PY
)
elif command -v node >/dev/null 2>&1; then
  rows=$(node -e '
const fs=require("fs"),p=require("path");const [root,h,a]=process.argv.slice(1);
let files=[];for(const acc of fs.readdirSync(root,{withFileTypes:true}).filter(e=>e.isDirectory()))
 for(const org of fs.readdirSync(p.join(root,acc.name),{withFileTypes:true}).filter(e=>e.isDirectory())){const dir=p.join(root,acc.name,org.name);
  for(const f of fs.readdirSync(dir).filter(x=>/^local_.*\.json$/.test(x)))files.push(p.join(dir,f))}
if(!files.length){console.error("no sessions found under "+root);process.exit(1)}
const d=p.dirname(files.map(f=>[fs.statSync(f).mtimeMs,f]).sort((x,y)=>y[0]-x[0])[0][1]);
console.log("ACCOUNT\t"+p.basename(p.dirname(d)));
const cutoff=Date.now()-parseFloat(h)*3600e3;const out=[];
for(const f of fs.readdirSync(d).filter(x=>/^local_.*\.json$/.test(x))){let s;try{s=JSON.parse(fs.readFileSync(p.join(d,f),"utf8"))}catch{continue}
 if(!s.cliSessionId||s.isArchived)continue;const last=s.lastActivityAt||0;if(a!=="1"&&last<cutoff)continue;
 out.push([last,s.cliSessionId,s.cwd||"",String(s.title||"").replace(/[\n\t]/g," ")])}
out.sort((x,y)=>y[0]-x[0]);
for(const [last,id,cwd,t] of out){const dt=new Date(last);const mon=["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"][dt.getUTCMonth()];
 const pad=n=>String(n).padStart(2,"0");console.log([`${pad(dt.getUTCDate())}-${mon} ${pad(dt.getUTCHours())}:${pad(dt.getUTCMinutes())}Z`,id,cwd,t].join("\t"))}
' "$root" "$hours" "$all")
else
  echo "resume-all needs python3 or node to read the session records" >&2; exit 1
fi
[ -n "$rows" ] || exit 1

acct_label=$(printf '%s\n' "$rows" | sed -n '1s/^ACCOUNT\t//p')
rows=$(printf '%s\n' "$rows" | sed '1d')
count=$(printf '%s\n' "$rows" | grep -c . )
scope="last $hours h"; [ "$all" = 1 ] && scope="all non-archived"
{
  echo "# Resume all Claude Desktop sessions - built $stamp, account $acct_label, $count sessions ($scope)"
  echo "# Paste the whole block into a terminal. Launches are spaced $gap s apart so the app registers each one."
  echo "# First line finds the Claude Code CLI: claude on PATH, else the one bundled with the Desktop app."
  echo "# If a line says the CLI must sign in, run once:  \"\$c\" auth login   (the CLI's sign-in is separate from the app's)."
  echo 'c=$(command -v claude 2>/dev/null || ls -d "$HOME/Library/Application Support/Claude/claude-code"/*/*/claude.app/Contents/MacOS/claude "${XDG_CONFIG_HOME:-$HOME/.config}/Claude/claude-code"/*/*/claude 2>/dev/null | sort -V | tail -1); [ -n "$c" ] || echo "claude CLI not found: install it, or open the Claude Desktop app once"'
  printf '%s\n' "$rows" | while IFS="$(printf '\t')" read -r when sid cwd title; do
    [ -z "$sid" ] && continue
    echo "# $when  $title"
    echo "(cd \"$cwd\" && \"\$c\" --desktop --resume $sid); sleep $gap"
  done
} > "$HOME/.claude/resume-all-latest.sh.tmp"
mkdir -p "$HOME/.claude"
mv "$HOME/.claude/resume-all-latest.sh.tmp" "$HOME/.claude/resume-all-latest.sh"
cp "$HOME/.claude/resume-all-latest.sh" "$HOME/.claude/resume-all-$(date -u +%Y%m%d-%H%M).sh"
cat "$HOME/.claude/resume-all-latest.sh"
