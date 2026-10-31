# 082.002 — Spike Findings (L0–L2)

## Context

Spike run on 2026-10-16 before any production code, to verify the assumptions behind
[000-plan.md](000-plan.md). No production code changed. All test state on the hosts was
removed afterwards.

| Host | Details |
| --- | --- |
| Local | macOS 27, OpenSSH 10.3p1, Prowl Release running |
| `mini` | macOS 26.5.2 arm64, OpenSSH sshd with `/etc/ssh/sshd_config.d/100-macos.conf` (`AcceptEnv LANG LC_*`), zsh login shell, `/bin/bash` 3.2, git 2.50.1, tmux 3.7c, Claude Code 2.1.296 (updated itself to 2.1.301 during the spike), Codex 0.162.1 |
| Linux | Debian trixie container (OrbStack docker), OpenSSH 10.0p2 (`AcceptEnv LANG LC_* COLORTERM NO_COLOR`), bash 5.2, git 2.47.3, tmux; a second check on OrbStack Ubuntu 18.04 without sshd covered only `/proc` parsing |

Method: `scripts/program_status_probe.py` played the terminal (a pty that answers the
OSC 7501 query, DA1 and the kitty keyboard query) around `ssh -tt <host>`; scripted keys
started a shell command or an agent by hand. The probe script (appendix) ran over a separate
ControlMaster connection with `sh -s`.

## Findings — L0 (detection)

| Check | Result | Observation |
| --- | --- | --- |
| `LC_PROWL_PANE` over ssh | Pass | Carried by the default client `SendEnv LANG LC_*` and server `AcceptEnv LANG LC_*`, in tty and non-tty sessions. `ssh -F <file>` skips `/etc/ssh/ssh_config` and loses `SendEnv` |
| ControlMaster | Pass, with a condition | Each multiplexed session carries its own value, but the master's config must contain `SendEnv`. First connect 0.48 s, later sessions 29 ms. ControlPath limit 104 bytes |
| GUI environment | Pass | The running `ProwlApp` process has launchd's `SSH_AUTH_SOCK` and `PATH=/usr/bin:/bin:/usr/sbin:/sbin`; `ssh -o BatchMode=yes` connects with that environment |
| OSC 7501 through ssh | Pass | Query answered across ssh; `idle`, `working` (0.13 s after Enter), `done`, `clear` arrive as locally |
| Identity on macOS host | Pass | Claude Code and Codex identified as the tty's foreground job; Claude's helper children (`ps aux | grep …`, `caffeinate`) share the group. Probe run 0.17–0.33 s including ssh |
| Two panes, one host | Pass | Distinct UUIDs map separately |
| macOS environment visibility | Constraint | `ps -E` shows no environment for platform binaries (`/bin/zsh` login shell, `/bin/sleep`, `/usr/bin/perl`); Homebrew and agent binaries show it. Anchor = parent `sshd-session:` + tty; pane id from foreground members. At a bare system-zsh prompt the pane id is unknown (`-`) |
| Linux `/proc` | Pass | Login shell environ readable; anchor parent `comm` is `sshd-session` on OpenSSH 10.0; tty and foreground group correct. Older `sshd` naming not tested |
| tmux path | Pass | Foreground tmux client → `list-clients` by client tty → pane tty → foreground group. Linux names the client `tmux: client` |
| tmux environment | Constraint | The tmux server keeps the first client's `LC_PROWL_PANE`; map by client tty only |
| OSC 7501 inside tmux | Fail | No query reaches the terminal with default options or `allow-passthrough on`; Claude Code sends no report |
| `tmux capture-pane` | Pass | Clean pane text distinguishes an empty composer (Idle) from `esc to interrupt` (Working); probe plus capture 0.26 s |
| Elapsed time | Pass | `etime` (macOS) and `/proc` start ticks (Linux) give skew-free start times |
| Claude process name | Note | `comm` of the native binary is its version (`2.1.301`); use argv |
| Codex | Note | Emits no OSC 7501; screen rules give state |

## Findings — L1 (remote folders)

| Check | Result | Observation |
| --- | --- | --- |
| git over the side channel | Pass | `status --porcelain=v2 --branch`, `worktree list --porcelain`, `for-each-ref`: 40–60 ms on LAN, 10 ms to the container |
| Bundled `wt` via stdin | Pass | `/bin/bash -s -- <args> < ThirdParty/git-wt/wt` runs `ls --json` and `--base-dir <dir> sw --copy-ignored --copy-untracked --from main --verbose <name>` (the arguments `GitClient` uses) on bash 3.2 and 5; 0.40 s on mini. `rm` refuses a dirty worktree, as locally |
| Tab launch command | Pass | `ssh -tt <host> 'cd "$HOME/repo" && exec "$SHELL" -l'` opens at the path; the probe sees it as a normal anchor |
| Remote cwd | Pass | macOS `lsof -a -p <pid> -d cwd -Fn`; Linux `readlink /proc/<pid>/cwd` |
| Pane close without tmux | Confirmed | SIGHUP to the local `ssh` kills the remote foreground job on both hosts |
| Hook channel | Pass | `ssh -R /tmp/x.sock:<local socket> -o StreamLocalBindUnlink=yes` delivered a line from remote `nc -U` to a local socket and returned the reply. Remote hooks still need a client that speaks Prowl's socket protocol |

## Findings — L2 (persistent sessions)

| Check | Result | Observation |
| --- | --- | --- |
| Prowl-managed tmux launch | Pass | `exec "$SHELL" -lc 'exec tmux -L prowl -f /dev/null new-session -A -s prowl-<id> -c <path> \; set-option -g status off'`; the login shell provides the Homebrew tmux PATH |
| Survival | Pass | Closing the attaching pty detached the session; Claude kept running |
| Reattach | Pass | The same command reattached the same Claude process (same pid) with the screen redrawn |
| Local screen = agent screen | Pass | With the status bar off, the local surface shows only the agent TUI, so local screen rules apply without capture |
| Probe mapping | Pass | Anchor is the exec'd tmux client; `M` record leads to the agent |
| tmux options | Note | Claude prints `tmux focus-events off · add 'set -g focus-events on'`; the option set needs `focus-events on` |
| Alternate screen | Constraint | The attach stream contains `ESC[?1049h`: Ghostty scrollback does not collect history |

## Not verified

- A real network loss (half-open TCP) and `ServerAliveInterval` behaviour for the side channel.
- OpenSSH < 9.8 (`sshd` parent naming), Alpine and other sshd defaults for `AcceptEnv`.
- mosh, nested ssh, `sudo -i` chains.
- Probe cost on hosts with many processes: the macOS branch calls `ps` per process.
- Integration inside Prowl (the spike used a pty harness, not a Prowl pane).

## Appendix — spike probe script

The final text below was rerun on mini (macOS, tmux path). The Linux branch ran in the
Debian container before two small edits (comments, and a simplified foreground-group test
with the same logic). Production code will rewrite it (one `ps` pass on macOS, structured
escaping).

```sh
# Prowl remote process probe (spike). POSIX sh, no install: `ssh host sh -s < probe.sh`.
# For every SSH session whose login shell carries LC_PROWL_PANE, print the session
# anchor and the tty's foreground process group:
#   S <pane> <anchor_pid> <tty> <tpgid>
#   P <pane> <pid> <ppid> <pgid> <comm> <args...>
#   E <pane> <pid> <elapsed_seconds> <cwd>
#   M <pane> tmux <socket> <pane_id> <pane_tty> <pane_path>   (foreground is a tmux client)
#   C-BEGIN <pane> <pane_id> ... C-END <pane>                (PROBE_CAPTURE=1)
# Only a process whose parent is sshd/sshd-session counts as an anchor, so a tmux
# server (or anything else) that inherited the variable is never attributed.
LC_ALL=C
export LC_ALL
uid=$(id -u)
now=$(date +%s)
echo "T $now $(uname -s)"

anchors() {
  if [ -r /proc/self/stat ]; then
    for d in /proc/[0-9]*; do
      [ -O "$d" ] || continue
      pane=$(tr '\0' '\n' 2>/dev/null < "$d/environ" | sed -n 's/^LC_PROWL_PANE=//p' | head -n 1)
      [ -n "$pane" ] || continue
      pid=${d#/proc/}
      ppid=$(awk '{ sub(/^.*\) /, ""); print $2 }' "$d/stat" 2>/dev/null)
      pcomm=$(cat "/proc/$ppid/comm" 2>/dev/null)
      case "$pcomm" in sshd*) ;; *) continue ;; esac
      # fields after "(comm) ": state ppid pgrp session tty_nr tpgid
      set -- $(sed 's/^.*) //' "$d/stat")
      tty=$(readlink "$d/fd/0" 2>/dev/null)
      echo "S $pane $pid ${tty:-?} $6"
    done
  else
    # macOS hides the environment of platform binaries (the /bin/zsh login
    # shell), so anchor on "parent is sshd-session with a tty" and read the pane
    # id from the foreground job's own environment instead.
    ps -ww -U "$uid" -o pid=,ppid=,tpgid=,tty= | while read -r pid ppid tpgid tty; do
      [ "$tty" = "??" ] && continue
      pcomm=$(ps -o comm= -p "$ppid" 2>/dev/null)
      case "$pcomm" in sshd-session:*|sshd:*) ;; *) continue ;; esac
      pane=-
      for fp in $(ps -t "$tty" -o pid=,pgid= | awk -v g="$tpgid" '$2 == g { print $1 }'); do
        v=$(ps -wwE -o command= -p "$fp" 2>/dev/null | sed -n 's/.*LC_PROWL_PANE=\([^ ]*\).*/\1/p')
        [ -n "$v" ] && { pane=$v; break; }
      done
      echo "S $pane $pid $tty $tpgid"
    done
  fi
}

# Foreground job of a tty: "P <pane> <pid> <ppid> <pgid> <comm> <args...>".
fg_job() { # pane tty tpgid
  if [ -r /proc/self/stat ]; then
    for d in /proc/[0-9]*; do
      [ -O "$d" ] || continue
      set -- $(sed 's/^.*) //' "$d/stat" 2>/dev/null)
      [ "${3:-}" = "$_tpgid" ] || continue
      echo "P $_pane ${d#/proc/} $2 $3 $(cat "$d/comm" 2>/dev/null | tr ' ' '_') $(tr "\0" " " 2>/dev/null < "$d/cmdline")"
      # elapsed seconds (skew-free) and cwd
      st=$(awk '{ sub(/^.*\) /, ""); print $20 }' "$d/stat"); up=$(cut -d' ' -f1 /proc/uptime)
      echo "E $_pane ${d#/proc/} $(awk -v s="$st" -v u="$up" -v hz="$(getconf CLK_TCK)" 'BEGIN { printf "%d", u - s / hz }') $(readlink "$d/cwd" 2>/dev/null)"
    done
  else
    ps -ww -t "${_tty#/dev/}" -o pid=,ppid=,pgid=,comm=,args= | while read -r p pp pg comm args; do
      [ "$pg" = "$_tpgid" ] || continue
      echo "P $_pane $p $pp $pg ${comm##*/} $args"
      et=$(ps -o etime= -p "$p" | awk '{ n = split($1, a, /[-:]/); s = 0; m = 1
        for (i = n; i > 0; i--) { s += a[i] * m; m = (m == 1 ? 60 : (m == 60 ? 3600 : 86400)) } print s }')
      echo "E $_pane $p $et $(lsof -a -p "$p" -d cwd -Fn 2>/dev/null | sed -n 's/^n//p')"
    done
  fi
}

tpgid_of_tty() { # tty -> foreground process group
  if [ -r /proc/self/stat ]; then
    for d in /proc/[0-9]*; do
      [ -O "$d" ] || continue
      [ "$(readlink "$d/fd/0" 2>/dev/null)" = "$1" ] || continue
      set -- $(sed 's/^.*) //' "$d/stat" 2>/dev/null); echo "$6"; return
    done
  else
    ps -t "${1#/dev/}" -o tpgid= | head -n 1 | tr -d ' '
  fi
}

# A tmux client in the foreground: follow it to the pane it shows, by client tty
# (never by environment: the tmux server keeps the first client's variables).
follow_tmux() { # pane client_tty tmux_bin
  for sock in "${TMUX_TMPDIR:-/tmp}"/tmux-"$uid"/* /private/tmp/tmux-"$uid"/*; do
    [ -S "$sock" ] || continue
    line=$("$3" -S "$sock" list-clients -F '#{client_tty} #{pane_id} #{pane_tty} #{pane_current_path}' 2>/dev/null \
      | awk -v t="$2" '$1 == t { print; exit }')
    [ -n "$line" ] || continue
    set -- "$1" "$2" "$3" $line
    echo "M $1 tmux $sock $5 $6 $7"
    _pane=$1 _tty=$6 _tpgid=$(tpgid_of_tty "$6") fg_job
    if [ -n "${PROBE_CAPTURE:-}" ]; then
      echo "C-BEGIN $1 $5"; "$3" -S "$sock" capture-pane -p -t "$5" 2>/dev/null; echo "C-END $1"
    fi
    return
  done
}

anchors | while read -r _ pane pid tty tpgid; do
  case "$tty" in /dev/*) ;; *) tty=/dev/$tty ;; esac
  echo "S $pane $pid $tty $tpgid"
  _pane=$pane _tty=$tty _tpgid=$tpgid fg_job | while read -r tag pn p pp pg comm args; do
    echo "$tag $pn $p $pp $pg $comm $args"
    [ "$tag" = P ] || continue
    case "$comm" in tmux|tmux:*) ;; *) continue ;; esac  # Linux comm is "tmux:_client"
    bin=$(ps -o comm= -p "$p" 2>/dev/null); [ -x "$bin" ] || bin=$(command -v tmux)
    [ -x "/proc/$p/exe" ] && bin=$(readlink "/proc/$p/exe")
    follow_tmux "$pn" "$tty" "$bin"
  done
done
```
