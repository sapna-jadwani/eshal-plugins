#!/bin/sh
# Builds a paste-ready shell block that reopens every recent Claude Desktop session
# (claude --desktop --resume <id>) after a credit cut-off. macOS / Linux.
#   resume-all.sh                   -> sessions active in the last 48 h
#   resume-all.sh -Hours 6          -> narrower window
#   resume-all.sh -All              -> every non-archived session
#   resume-all.sh -GapSeconds 15    -> spacing between launches (default 12)
#   resume-all.sh -IncludeChildren  -> also reopen child side-sessions (see below)
# The app keeps one record per session per store folder (<store>/<folder>/<org>/local_*.json) and a
# session touched from several app instances has a copy in each folder, so every folder of the current
# org is read and one line is built per CLI session id from its latest record.
# Child side-sessions (started from another session through a task card) are grouped under their
# parent and commented out: a resume by id opens a standalone tab that no longer sits under the
# parent, and the parent's own line already brings the parent back. -IncludeChildren turns their
# lines on. A child whose parent is not in the block is listed in a trailing group, also commented.
# The block resolves the CLI itself at paste time: claude on PATH, else the newest CLI bundled
# with the Claude Desktop app. So it works on a Mac where claude was never added to PATH, and
# keeps working after the app has updated its bundled CLI.
# Needs python3 (or node) to read the app's session records.
# Output: printed to stdout, and saved to ~/.claude/resume-all-latest.sh (+ a stamped copy).
hours=48; all=0; gap=12; kids=0
while [ $# -gt 0 ]; do
  case "$1" in
    -Hours|--hours) hours="$2"; shift 2 ;;
    -All|--all) all=1; shift ;;
    -GapSeconds|--gap) gap="$2"; shift 2 ;;
    -IncludeChildren|--include-children) kids=1; shift ;;
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

# The interpreter picks the org the app is signed into (= the org sub-folder holding the most
# recently written record), reads that org's records from every store folder, and prints
# "ORG<TAB><org id><TAB><folder count>" followed by one row per CLI session:
# when, id, cwd, title, kind (root | child | orphan), ordered parent-then-children, orphans last.
# A child's spawnedFrom.sessionId names the parent's RECORD id (local_...), which differs from the
# parent's CLI session id once the parent has been resumed, so record ids are resolved over every
# record, archived and out-of-window ones included. The latest record of a CLI id gives its title,
# cwd, time and archived flag; the parent link counts from any record of it.
if python3 -c 'import sys' >/dev/null 2>&1; then
  rows=$(python3 - "$root" "$hours" "$all" <<'PY'
import json, os, sys, time, glob
root, hours, all_ = sys.argv[1], float(sys.argv[2]), sys.argv[3] == "1"
files = glob.glob(os.path.join(root, "*", "*", "local_*.json"))
if not files:
    sys.exit("no sessions found under " + root)
org = os.path.basename(os.path.dirname(max(files, key=os.path.getmtime)))
files = [f for f in files if os.path.basename(os.path.dirname(f)) == org]
folders = {os.path.dirname(os.path.dirname(f)) for f in files}
print("ORG\t%s\t%d" % (org, len(folders)))
cutoff = (time.time() - hours * 3600) * 1000
records = []
for p in files:
    try:
        records.append(json.load(open(p, encoding="utf-8")))
    except Exception:
        continue
rec_to_cli = {s["sessionId"]: s["cliSessionId"] for s in records if s.get("sessionId") and s.get("cliSessionId")}
latest, parent_of = {}, {}
for s in records:
    sid = s.get("cliSessionId")
    if not sid:
        continue
    last = s.get("lastActivityAt") or 0
    sf = s.get("spawnedFrom") or {}
    if isinstance(sf, dict) and sf.get("sessionId"):
        rec = str(sf["sessionId"])
        p = rec_to_cli.get(rec) or (rec[6:] if rec.startswith("local_") else None)
        if p:
            parent_of[sid] = p
    if sid not in latest or latest[sid]["last"] < last:
        latest[sid] = {"last": last, "id": sid, "cwd": s.get("cwd", ""), "archived": bool(s.get("isArchived")),
                       "title": (s.get("title") or "").replace("\n", " ").replace("\t", " ")}
rows = {}
for r in latest.values():
    if r["archived"] or (not all_ and r["last"] < cutoff):
        continue
    r["parent"] = parent_of.get(r["id"])
    rows[r["id"]] = r
def emit(r, kind):
    when = time.strftime("%d-%b %H:%MZ", time.gmtime(r["last"] / 1000))
    print("\t".join([when, r["id"], r["cwd"], r["title"], kind]))
ordered = sorted(rows.values(), key=lambda r: r["last"], reverse=True)
roots = [r for r in ordered if not r["parent"]]
children = [r for r in ordered if r["parent"]]
for r in roots:
    emit(r, "root")
    for c in children:
        if c["parent"] == r["id"]:
            emit(c, "child")
for c in children:
    if c["parent"] not in rows:
        emit(c, "orphan")
PY
)
elif command -v node >/dev/null 2>&1; then
  rows=$(node -e '
const fs=require("fs"),p=require("path");const [root,h,a]=process.argv.slice(1);
let files=[];for(const acc of fs.readdirSync(root,{withFileTypes:true}).filter(e=>e.isDirectory()))
 for(const org of fs.readdirSync(p.join(root,acc.name),{withFileTypes:true}).filter(e=>e.isDirectory())){const dir=p.join(root,acc.name,org.name);
  for(const f of fs.readdirSync(dir).filter(x=>/^local_.*\.json$/.test(x)))files.push(p.join(dir,f))}
if(!files.length){console.error("no sessions found under "+root);process.exit(1)}
const org=p.basename(p.dirname(files.map(f=>[fs.statSync(f).mtimeMs,f]).sort((x,y)=>y[0]-x[0])[0][1]));
files=files.filter(f=>p.basename(p.dirname(f))===org);
const folders=new Set(files.map(f=>p.dirname(p.dirname(f))));
console.log(["ORG",org,folders.size].join("\t"));
const cutoff=Date.now()-parseFloat(h)*3600e3;const records=[];
for(const f of files){try{records.push(JSON.parse(fs.readFileSync(f,"utf8")))}catch{}}
const recToCli={};for(const s of records)if(s.sessionId&&s.cliSessionId)recToCli[s.sessionId]=s.cliSessionId;
const latest={},parentOf={};
for(const s of records){const sid=s.cliSessionId;if(!sid)continue;const last=s.lastActivityAt||0;
 const sf=s.spawnedFrom;if(sf&&typeof sf==="object"&&sf.sessionId){const rec=String(sf.sessionId);const q=recToCli[rec]||(rec.startsWith("local_")?rec.slice(6):null);if(q)parentOf[sid]=q}
 if(!latest[sid]||latest[sid].last<last)latest[sid]={last,id:sid,cwd:s.cwd||"",archived:!!s.isArchived,title:String(s.title||"").replace(/[\n\t]/g," ")}}
const rows={};
for(const r of Object.values(latest)){if(r.archived||(a!=="1"&&r.last<cutoff))continue;r.parent=parentOf[r.id]||null;rows[r.id]=r}
const emit=(r,kind)=>{const dt=new Date(r.last);const mon=["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"][dt.getUTCMonth()];
 const pad=n=>String(n).padStart(2,"0");console.log([`${pad(dt.getUTCDate())}-${mon} ${pad(dt.getUTCHours())}:${pad(dt.getUTCMinutes())}Z`,r.id,r.cwd,r.title,kind].join("\t"))};
const ordered=Object.values(rows).sort((x,y)=>y.last-x.last);
const roots=ordered.filter(r=>!r.parent),children=ordered.filter(r=>r.parent);
for(const r of roots){emit(r,"root");for(const c of children)if(c.parent===r.id)emit(c,"child")}
for(const c of children)if(!rows[c.parent])emit(c,"orphan");
' "$root" "$hours" "$all")
else
  echo "resume-all needs python3 or node to read the session records" >&2; exit 1
fi
[ -n "$rows" ] || exit 1

tab="$(printf '\t')"
org=$(printf '%s\n' "$rows" | sed -n "1s/^ORG${tab}\([^${tab}]*\)${tab}.*/\1/p")
nfolders=$(printf '%s\n' "$rows" | sed -n "1s/^ORG${tab}[^${tab}]*${tab}//p")
rows=$(printf '%s\n' "$rows" | sed '1d')
roots=$(printf '%s\n' "$rows" | grep -c "${tab}root$")
kidcount=$(printf '%s\n' "$rows" | grep -c -E "${tab}(child|orphan)$")
scope="last $hours h"; [ "$all" = 1 ] && scope="all non-archived"
childnote=""
if [ "$kidcount" -gt 0 ]; then
  if [ "$kids" = 1 ]; then childnote=" + $kidcount child side-sessions"; else childnote=" + $kidcount child side-sessions commented out"; fi
fi
{
  echo "# Resume all Claude Desktop sessions - built $stamp, org $org, $roots sessions$childnote ($scope, $nfolders store folders)"
  echo "# Paste the whole block into a terminal. Launches are spaced $gap s apart so the app registers each one."
  echo "# First line finds the Claude Code CLI: claude on PATH, else the one bundled with the Desktop app."
  echo "# If a line says the CLI must sign in, run once:  \"\$c\" auth login   (the CLI's sign-in is separate from the app's)."
  echo 'c=$(command -v claude 2>/dev/null || ls -d "$HOME/Library/Application Support/Claude/claude-code"/*/*/claude.app/Contents/MacOS/claude "${XDG_CONFIG_HOME:-$HOME/.config}/Claude/claude-code"/*/*/claude 2>/dev/null | sort -V | tail -1); [ -n "$c" ] || echo "claude CLI not found: install it, or open the Claude Desktop app once"'
  if [ "$kidcount" -gt 0 ] && [ "$kids" != 1 ]; then
    echo "# Child side-sessions sit under their parent as comments: a resume by id opens them as standalone tabs. Rerun with -IncludeChildren to reopen them too."
  fi
  orphan_header=0
  printf '%s\n' "$rows" | while IFS="$tab" read -r when sid cwd title kind; do
    [ -z "$sid" ] && continue
    cmd="(cd \"$cwd\" && \"\$c\" --desktop --resume $sid); sleep $gap"
    case "$kind" in
      root) echo "# $when  $title"; echo "$cmd" ;;
      *)
        if [ "$kind" = orphan ] && [ "$orphan_header" = 0 ]; then
          echo "# Child side-sessions whose parent is not in this block (archived or outside the window):"; orphan_header=1
        fi
        echo "#   child $when  $title"
        if [ "$kids" = 1 ]; then echo "  $cmd"; else echo "#   $cmd"; fi ;;
    esac
  done
} > "$HOME/.claude/resume-all-latest.sh.tmp"
mkdir -p "$HOME/.claude"
mv "$HOME/.claude/resume-all-latest.sh.tmp" "$HOME/.claude/resume-all-latest.sh"
cp "$HOME/.claude/resume-all-latest.sh" "$HOME/.claude/resume-all-$(date -u +%Y%m%d-%H%M).sh"
cat "$HOME/.claude/resume-all-latest.sh"
