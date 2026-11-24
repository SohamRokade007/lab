#!/usr/bin/env bash
# Applied Cybersecurity Fundamentals (CYS3001P) - consolidated practical runner
# Labs: 1, 2, 3, 4, 5, 6, 7, 8, 10
# Inspired by the menu/bootstrap/logging structure of B1ackVenom/lab.
# All scans and test traffic are restricted to localhost or a user-confirmed lab target.

set -Eeuo pipefail
IFS=$'\n\t'

VERSION="1.1.0"
BASE_DIR="${ACF_LAB_DIR:-$HOME/acf_lab_artifacts}"
LOG_DIR="$BASE_DIR/logs"
mkdir -p "$LOG_DIR"
SESSION="$(date +%Y%m%d_%H%M%S)"
SESSION_LOG="$LOG_DIR/session_${SESSION}.log"
: > "$SESSION_LOG"

if [[ -t 1 ]]; then
  RESET=$'\033[0m'; BOLD=$'\033[1m'; RED=$'\033[31m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; BLUE=$'\033[34m'; CYAN=$'\033[36m'
else
  RESET=''; BOLD=''; RED=''; GREEN=''; YELLOW=''; BLUE=''; CYAN=''
fi

OPT_LABS=""
OPT_CHECK=0
OPT_INSTALL=0
OPT_YES=0
OPT_NO_PAUSE=0
OPT_CLEANUP=0
OPT_CHILD=0
SUDO=""
ACTIVE_NS=()

say() { printf '%b\n' "$*" | tee -a "$SESSION_LOG"; }
info() { say "${BLUE}[*]${RESET} $*"; }
ok() { say "${GREEN}[+]${RESET} $*"; }
warn() { say "${YELLOW}[!]${RESET} $*"; }
err() { say "${RED}[x]${RESET} $*"; }

run() {
  local display
  printf -v display '%q ' "$@"
  display="${display% }"
  printf '\n%s$ %s%s\n' "$CYAN" "$display" "$RESET" | tee -a "$SESSION_LOG"
  "$@" 2>&1 | tee -a "$SESSION_LOG"
  local rc=${PIPESTATUS[0]}
  if (( rc != 0 )); then warn "Command returned exit code $rc: $*"; fi
  return 0
}

pause() {
  (( OPT_NO_PAUSE )) && return 0
  if [[ -t 0 ]]; then read -r -p "Press Enter to continue... " _ || true; fi
}

confirm() {
  (( OPT_YES )) && return 0
  local answer
  read -r -p "$1 [y/N]: " answer || return 1
  [[ "${answer,,}" == "y" || "${answer,,}" == "yes" ]]
}

have() { command -v "$1" >/dev/null 2>&1; }

usage() {
  cat <<'HELP'
ACF Cybersecurity Lab Runner
Usage: ./lab.sh [options]
  (no arguments)  Check tools and open the interactive menu
  --labs 1,2,4    Run selected labs
  --labs all      Run Labs 1,2,3,4,5,6,7,8,10 in order
  --list          List included practicals
  --check         Check required tools only; do not install
  --install       Offer to install missing Kali/Debian packages
  --yes, -y       Automatically confirm installation and safe local actions
  --no-pause      Do not pause between labs
  --cleanup       Stop lab containers/namespaces and remove generated artifacts
  --child         Internal: run a lab inside its own terminal window
  --help          Show this help

Safety: targets are localhost by default. Lab 1 accepts only a private lab IP
when explicitly confirmed. Lab 3/10 scanners must only be pointed at your own
isolated target/application. Lab 8 never asks for or stores credentials.
HELP
}

list_labs() {
  cat <<'LIST'
  1   Network Scanning and Reconnaissance (Nmap)
  2   Network Packet Capture and Analysis (tshark/Wireshark)
  3   Vulnerability Assessment (Greenbone/OpenVAS guidance + safe checks)
  4   Safe Malware / Simulated Malicious Program Analysis
  5   Intrusion Detection System (Suricata)
  6   Firewall Rule Configuration and Evaluation (UFW)
  7   VPN Configuration and Verification (WireGuard namespaces)
  8   Social Engineering Awareness Simulation (no credential collection)
  10  Intentionally Vulnerable Web Application Assessment (Juice Shop + ZAP)
LIST
}

while (($#)); do
  case "$1" in
    --labs) shift; OPT_LABS="${1:-}" ;;
    --check) OPT_CHECK=1 ;;
    --install) OPT_INSTALL=1 ;;
    --yes|-y) OPT_YES=1 ;;
    --no-pause) OPT_NO_PAUSE=1 ;;
    --cleanup) OPT_CLEANUP=1 ;;
    --child) OPT_CHILD=1 ;;
    --list|-l) list_labs; exit 0 ;;
    --help|-h) usage; exit 0 ;;
    *) err "Unknown option: $1"; usage; exit 2 ;;
  esac
  shift
done

if (( EUID != 0 )); then
  if have sudo; then SUDO="sudo"; else err "Run as root or install sudo."; exit 1; fi
fi

need_root() {
  if [[ -n "$SUDO" ]]; then "$SUDO" -v || { err "sudo authentication failed"; exit 1; }; fi
}

# command -> Debian/Kali package. Some are optional and are not needed by every lab.
packages() {
  cat <<'PKG'
nmap nmap
tshark tshark
wireshark wireshark
 tcpdump tcpdump
suricata suricata
ufw ufw
wg wireguard-tools
ip iproute2
ping iputils-ping
curl curl
python3 python3
strace strace
file file
strings binutils
jq jq
docker docker.io
PKG
}

# Normalize accidental leading whitespace in the package table.
missing_tools() {
  while IFS=' ' read -r cmd pkg; do
    [[ -z "${cmd:-}" ]] && continue
    if ! have "$cmd"; then printf '%s %s\n' "$cmd" "$pkg"; fi
  done < <(packages | sed 's/^ *//')
}

check_tools() {
  say "\n${BOLD}TOOL CHECK${RESET}"
  while IFS=' ' read -r cmd pkg; do
    [[ -z "${cmd:-}" ]] && continue
    if have "$cmd"; then say "  ${GREEN}OK${RESET}      $cmd ($pkg)"; else say "  ${YELLOW}MISSING${RESET}  $cmd ($pkg)"; fi
  done < <(packages | sed 's/^ *//')
}

install_tools() {
  local -a pkgs=() seen=()
  local cmd pkg p
  while IFS=' ' read -r cmd pkg; do
    [[ -z "${cmd:-}" ]] && continue
    if ! have "$cmd"; then
      local already=0
      for p in "${pkgs[@]:-}"; do [[ "$p" == "$pkg" ]] && already=1; done
      (( already )) || pkgs+=("$pkg")
    fi
  done < <(packages | sed 's/^ *//')
  if ((${#pkgs[@]} == 0)); then ok "All listed tools are already installed."; return 0; fi
  warn "Missing packages: ${pkgs[*]}"
  if ! confirm "Install these packages using apt?"; then warn "Installation skipped."; return 0; fi
  need_root
  run $SUDO apt-get update
  run $SUDO apt-get install -y "${pkgs[@]}"
  check_tools
}

make_lab_dir() { mkdir -p "$BASE_DIR/lab$1"; }

cleanup_lab7() {
  for ns in acf-vpn-a acf-vpn-b; do
    $SUDO ip netns del "$ns" >/dev/null 2>&1 || true
  done
  $SUDO ip link del acf-veth-a >/dev/null 2>&1 || true
  rm -f "$BASE_DIR"/lab7/*.key "$BASE_DIR"/lab7/*.conf 2>/dev/null || true
}

cleanup_lab10() {
  if have docker; then $SUDO docker rm -f acf-juice-shop >/dev/null 2>&1 || true; fi
}

cleanup_all() {
  info "Stopping resources created by this runner..."
  cleanup_lab7
  cleanup_lab10
  if [[ -d "$BASE_DIR" ]]; then rm -rf "$BASE_DIR"; fi
  ok "Lab artifacts and runner-created resources removed. System packages were not uninstalled."
}

lab1() {
  local d="$BASE_DIR/lab1" target
  make_lab_dir 1
  say "\n${BOLD}LAB 1 — Network Scanning and Reconnaissance using Nmap${RESET}"
  run nmap --version
  run ip -brief addr
  run hostname -I
  run ping -c 3 127.0.0.1
  info "First perform a localhost discovery scan."
  run nmap -sn 127.0.0.1
  info "Starting a temporary HTTP service on localhost:18081 for a controlled port scan."
  python3 -m http.server 18081 --bind 127.0.0.1 --directory "$d" >"$d/http.log" 2>&1 &
  local server_pid=$!
  sleep 1
  run nmap -sV -p 18081 127.0.0.1
  kill "$server_pid" 2>/dev/null || true
  wait "$server_pid" 2>/dev/null || true
  if confirm "Do you have an instructor-approved PRIVATE lab target IP to scan?"; then
    read -r -p "Enter the target IPv4 address: " target
    if [[ "$target" =~ ^(10\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[0-1])\.) ]]; then
      if confirm "Confirm $target is your own isolated lab VM and scanning is authorized?"; then
        run ping -c 3 -W 2 "$target"
        run nmap -sV --top-ports 100 "$target" -oN "$d/authorized_target_scan.txt"
      else warn "Target scan skipped."; fi
    else warn "Only RFC1918 private IPv4 targets are accepted; scan skipped."; fi
  fi
  run sha256sum "$d"/http.log 2>/dev/null || true
  ok "Lab 1 complete. Output: $d"
}

lab2() {
  local d="$BASE_DIR/lab2" iface pcap
  make_lab_dir 2
  say "\n${BOLD}LAB 2 — Network Packet Capture and Analysis${RESET}"
  run tshark --version
  iface="$(ip route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev") {print $(i+1); exit}}')"
  [[ -n "$iface" ]] || iface="lo"
  info "Available interfaces:"
  run tshark -D
  info "Capturing only loopback test traffic; no general network traffic is collected."
  pcap="$d/lab2_loopback.pcapng"
  $SUDO tshark -i lo -a duration:8 -w "$pcap" >/dev/null 2>"$d/capture.log" &
  local cap_pid=$!
  sleep 1
  ping -c 2 127.0.0.1 >/dev/null 2>&1 || true
  wait "$cap_pid" 2>/dev/null || true
  run tshark -r "$pcap" -c 20
  run tshark -r "$pcap" -Y icmp
  run tshark -r "$pcap" -Y tcp
  run capinfos "$pcap"
  if have wireshark && confirm "Open the saved capture in Wireshark GUI?"; then wireshark "$pcap" >/dev/null 2>&1 & fi
  ok "Lab 2 complete. Capture: $pcap"
}

lab3() {
  local d="$BASE_DIR/lab3"
  make_lab_dir 3
  say "\n${BOLD}LAB 3 — Vulnerability Assessment of an Intentionally Vulnerable System${RESET}"
  info "Safe baseline checks against localhost. These do not exploit services."
  run nmap -sV --top-ports 100 127.0.0.1 -oN "$d/localhost_services.txt"
  run nmap --script safe -p 1-1024 127.0.0.1 -oN "$d/nmap_safe_checks.txt"
  if have gvm; then
    run gvm-check-setup
    warn "Greenbone is installed. Start its web interface with: sudo gvm-start"
    say "Then create a target using only your instructor-approved vulnerable VM IP, select the standard/safe profile, and export the report to: $d"
  else
    warn "Greenbone/OpenVAS (gvm) is not installed. This is a separate, large scanner stack."
    say "To install on Kali: sudo apt update && sudo apt install gvm -y"
    say "Then: sudo gvm-setup  (first setup can take a long time), followed by sudo gvm-start"
    say "Open the local Greenbone URL printed by gvm-start. Scan only your isolated, instructor-approved target."
  fi
  ok "Lab 3 baseline evidence saved in $d. Greenbone scan requires the GUI and an authorized target."
}

lab4() {
  local d="$BASE_DIR/lab4"
  make_lab_dir 4
  say "\n${BOLD}LAB 4 — Safe Malware / Simulated Malicious Program Analysis${RESET}"

  # These are the two Python files supplied for Lab 4.
  # Run from the lab directory because malware_sim.py creates test.txt there.
  cat > "$d/malware_sim.py" <<'PY'
import os

# Make a dummy file
open("test.txt", "w").write("demo")

# Rename it (fake malware action)
os.rename("test.txt", "test.locked")
print("File renamed to test.locked")

# Restore it
os.rename("test.locked", "test.txt")
print("File restored to test.txt")
PY

  cat > "$d/launcher.py" <<'PY'
import os
import sys

print("Starting malware simulation...")
os.system(f'"{sys.executable}" malware_sim.py')
print("Simulation finished.")
PY

  say "Step 1 — Identify the supplied Python files"
  run file "$d/launcher.py" "$d/malware_sim.py"

  say "\nStep 2 — Calculate SHA-256 hashes before execution"
  run sha256sum "$d/launcher.py" "$d/malware_sim.py"

  say "\nStep 3 — Review the simulation source"
  run sed -n '1,120p' "$d/launcher.py"
  run sed -n '1,120p' "$d/malware_sim.py"

  say "\nStep 4 — Execute the launcher (which starts malware_sim.py)"
  (
    cd "$d"
    if have strace; then
      strace -f -e trace=openat,execve -o "$d/strace.log" python3 launcher.py
    else
      python3 launcher.py
    fi
  )

  say "\nStep 5 — Verify the file operation and restoration"
  if [[ -f "$d/test.txt" && ! -e "$d/test.locked" ]]; then
    ok "Test file was created, renamed to test.locked, then restored to test.txt."
  else
    warn "Expected restored test.txt was not found; inspect the execution output."
  fi
  run ls -l "$d/test.txt" 2>/dev/null || true
  run sha256sum "$d/test.txt" 2>/dev/null || true
  if [[ -f "$d/strace.log" ]]; then
    say "System-call trace saved at: $d/strace.log"
  fi
  ok "Lab 4 complete. Python files and evidence saved in $d"
}

lab5() {
  local d="$BASE_DIR/lab5" pcap rules out
  make_lab_dir 5
  say "\n${BOLD}LAB 5 — Intrusion Detection System (Suricata)${RESET}"
  run suricata -V
  rules="$d/local.rules"; pcap="$d/lab5_test_traffic.pcap"; out="$d/suricata_output"
  cat > "$rules" <<'RULES'
alert icmp any any -> any any (msg:"ACF LAB5 ICMP Echo Request observed"; itype:8; sid:1000001; rev:1;)
RULES
  info "Generating harmless loopback ICMP traffic for offline IDS analysis."
  $SUDO tcpdump -i lo -n -c 6 -w "$pcap" icmp >/dev/null 2>"$d/tcpdump.log" &
  local cap_pid=$!
  sleep 1
  ping -c 3 127.0.0.1 >/dev/null 2>&1 || true
  wait "$cap_pid" 2>/dev/null || true
  mkdir -p "$out"
  run suricata -r "$pcap" -S "$rules" -l "$out" -k none
  if [[ -f "$out/fast.log" ]]; then run cat "$out/fast.log"; else warn "No fast.log was produced; inspect $out/eve.json and Suricata output."; fi
  if [[ -f "$out/eve.json" ]] && have jq; then run jq -r 'select(.event_type=="alert") | [.timestamp,.alert.signature,.src_ip,.dest_ip] | @tsv' "$out/eve.json"; fi
  ok "Lab 5 complete. PCAP, rule and alerts saved in $d"
}

lab6() {
  local d="$BASE_DIR/lab6"
  make_lab_dir 6
  say "\n${BOLD}LAB 6 — Firewall Rule Configuration and Evaluation (UFW)${RESET}"
  run ufw version
  run $SUDO ufw status verbose
  info "Demonstrating the intended UFW rule syntax without changing your active firewall."
  run $SUDO ufw --dry-run allow 18086/tcp
  run $SUDO ufw --dry-run delete allow 18086/tcp
  cat > "$d/firewall_commands.txt" <<'CMDS'
# Inspect status
sudo ufw status verbose
# Permit a required service (only when approved for your isolated lab)
sudo ufw allow 22/tcp
# Add a temporary test service rule
sudo ufw allow 18086/tcp
# Review numbered rules
sudo ufw status numbered
# Remove the temporary test rule
sudo ufw delete allow 18086/tcp
CMDS
  say "The dry-run output above previews rule changes. No UFW policy was enabled or modified by this lab."
  ok "Lab 6 complete. Commands and evidence saved in $d"
}

lab7() {
  local d="$BASE_DIR/lab7" srv_priv cli_priv srv_pub cli_pub
  make_lab_dir 7
  say "\n${BOLD}LAB 7 — VPN Configuration and Verification (WireGuard)${RESET}"
  if ! have wg || ! have ip; then warn "Install wireguard-tools and iproute2 first."; return 0; fi
  need_root
  cleanup_lab7
  umask 077
  wg genkey > "$d/server_private.key"
  wg genkey > "$d/client_private.key"
  srv_priv="$(cat "$d/server_private.key")"; cli_priv="$(cat "$d/client_private.key")"
  srv_pub="$(printf '%s' "$srv_priv" | wg pubkey)"; cli_pub="$(printf '%s' "$cli_priv" | wg pubkey)"
  printf '%s\n' "$srv_pub" > "$d/server_public.key"
  printf '%s\n' "$cli_pub" > "$d/client_public.key"
  run $SUDO ip netns add acf-vpn-a
  run $SUDO ip netns add acf-vpn-b
  run $SUDO ip link add acf-veth-a type veth peer name acf-veth-b
  run $SUDO ip link set acf-veth-a netns acf-vpn-a
  run $SUDO ip link set acf-veth-b netns acf-vpn-b
  run $SUDO ip -n acf-vpn-a link set lo up
  run $SUDO ip -n acf-vpn-b link set lo up
  run $SUDO ip -n acf-vpn-a addr add 10.200.0.1/24 dev acf-veth-a
  run $SUDO ip -n acf-vpn-b addr add 10.200.0.2/24 dev acf-veth-b
  run $SUDO ip -n acf-vpn-a link set acf-veth-a up
  run $SUDO ip -n acf-vpn-b link set acf-veth-b up
  cat > "$d/server.conf" <<EOF2
[Interface]
PrivateKey = $srv_priv
ListenPort = 51820

[Peer]
PublicKey = $cli_pub
AllowedIPs = 10.10.10.2/32
EOF2
  cat > "$d/client.conf" <<EOF2
[Interface]
PrivateKey = $cli_priv

[Peer]
PublicKey = $srv_pub
Endpoint = 10.200.0.1:51820
AllowedIPs = 10.10.10.1/32
PersistentKeepalive = 5
EOF2
  run $SUDO ip -n acf-vpn-a link add wg0 type wireguard
  run $SUDO ip -n acf-vpn-b link add wg0 type wireguard
  run $SUDO ip -n acf-vpn-a addr add 10.10.10.1/24 dev wg0
  run $SUDO ip -n acf-vpn-b addr add 10.10.10.2/24 dev wg0
  run $SUDO ip netns exec acf-vpn-a wg setconf wg0 "$d/server.conf"
  run $SUDO ip netns exec acf-vpn-b wg setconf wg0 "$d/client.conf"
  run $SUDO ip -n acf-vpn-a link set wg0 up
  run $SUDO ip -n acf-vpn-b link set wg0 up
  sleep 2
  run $SUDO ip netns exec acf-vpn-b ping -c 3 -W 2 10.10.10.1
  run $SUDO ip netns exec acf-vpn-a wg show
  run $SUDO ip netns exec acf-vpn-b wg show
  chmod 600 "$d"/*.key "$d"/*.conf
  warn "Private keys are stored locally with owner-only permissions. Do not share them."
  cleanup_lab7
  ok "Lab 7 complete. Config/key evidence retained in $d; temporary namespaces removed."
}

lab8() {
  local d="$BASE_DIR/lab8" choice
  make_lab_dir 8
  say "\n${BOLD}LAB 8 — Social Engineering Awareness Simulation${RESET}"
  cat > "$d/training_message.txt" <<'MSG'
TRAINING-ONLY SIMULATED MESSAGE
From: IT Helpdesk <helpdesk@example.invalid>
Subject: Urgent: account access review

Your account may be suspended today. Visit the training portal immediately.

Training indicators to identify:
1. Urgency and threat of account suspension.
2. Generic greeting and unexpected request.
3. Link/domain should be independently verified.
4. Never disclose a password, OTP or financial information.

This simulation does not contain a login form and does not collect credentials.
MSG
  run cat "$d/training_message.txt"
  say "\nChoose the safest response:"
  say "  1) Click the link immediately"
  say "  2) Reply with password/OTP"
  say "  3) Do not click; verify sender independently and report the message"
  read -r -p "Your choice (1/2/3): " choice || choice=""
  case "$choice" in
    3) printf 'recognized_and_reported\n' > "$d/outcome.txt"; ok "Correct response. Message should be reported." ;;
    1|2) printf 'unsafe_choice_selected\n' > "$d/outcome.txt"; warn "That action is unsafe. Never enter credentials or OTPs." ;;
    *) printf 'no_response_recorded\n' > "$d/outcome.txt"; warn "No valid response recorded." ;;
  esac
  say "Outcome recorded locally without personal data: $(cat "$d/outcome.txt")"
  ok "Lab 8 complete. No credentials, names, email addresses or personal data were collected."
}

lab10() {
  local d="$BASE_DIR/lab10" url="http://127.0.0.1:3000"
  make_lab_dir 10
  say "\n${BOLD}LAB 10 — Security Assessment of an Intentionally Vulnerable Web Application${RESET}"
  if ! have docker; then
    warn "Docker is not installed. Install docker.io, start Docker, then rerun Lab 10."
    say "Alternative: use an instructor-provided local OWASP Juice Shop instance and set its URL to localhost."
    return 0
  fi
  need_root
  if ! $SUDO docker info >/dev/null 2>&1; then
    warn "Docker daemon is not running. Try: sudo systemctl enable --now docker"
    return 0
  fi
  cleanup_lab10
  info "Starting OWASP Juice Shop bound to localhost only (127.0.0.1:3000)."
  run $SUDO docker run -d --name acf-juice-shop --restart=no -p 127.0.0.1:3000:3000 bkimminich/juice-shop
  local ready=0
  for _ in $(seq 1 45); do
    if curl --noproxy '*' -fsS "$url" >/dev/null 2>&1; then ready=1; break; fi
    sleep 2
  done
  if (( ! ready )); then warn "Juice Shop did not become ready. Check: sudo docker logs acf-juice-shop"; return 0; fi
  run curl --noproxy '*' -sSI "$url"
  run nmap -sV -p 3000 127.0.0.1 -oN "$d/local_service_check.txt"
  run curl --noproxy '*' -sS "$url" -o "$d/juice_shop_home.html"
  say "\nOpen $url in your browser. Start OWASP ZAP, use a local session, configure the browser proxy as directed by ZAP, browse the app normally, and review passive alerts only."
  say "Save/export the ZAP report to: $d"
  if have zaproxy && confirm "Launch OWASP ZAP GUI now?"; then zaproxy >/dev/null 2>&1 & fi
  say "Container remains running for manual ZAP assessment. Stop it with: sudo docker stop acf-juice-shop"
  ok "Lab 10 app is available at $url and is bound to loopback only."
}

run_lab() {
  case "$1" in
    1) lab1 ;; 2) lab2 ;; 3) lab3 ;; 4) lab4 ;; 5) lab5 ;; 6) lab6 ;; 7) lab7 ;; 8) lab8 ;; 10) lab10 ;;
    *) err "Unsupported lab: $1" ;;
  esac
  pause
}

valid_selection() {
  local item
  IFS=',' read -ra items <<< "$1"
  for item in "${items[@]}"; do
    case "$item" in 1|2|3|4|5|6|7|8|10) ;; *) return 1 ;; esac
  done
  return 0
}

launch_lab_terminal() {
  local lab="$1" script_path command_line
  script_path="$(readlink -f "${BASH_SOURCE[0]}")"

  # Run the same script in child mode. The terminal displays the lab's real
  # headings, commands and command output, without an interactive shell prompt.
  printf -v command_line 'printf "\\033[1;36mAPPLIED CYBERSECURITY FUNDAMENTALS — LAB %s\\033[0m\\n\\n"; bash --noprofile --norc %q --child --labs %q; rc=$?; printf "\\nLab process finished (exit code %s).\\n" "$rc"; read -r -p "Press Enter to close this lab window... " _' "$lab" "$script_path" "$lab"

  if have xfce4-terminal; then
    xfce4-terminal --title="ACF Lab $lab" --command="bash --noprofile --norc -c $(printf '%q' "$command_line")" >/dev/null 2>&1 &
  elif have gnome-terminal; then
    gnome-terminal --title="ACF Lab $lab" -- bash --noprofile --norc -c "$command_line" >/dev/null 2>&1 &
  elif have konsole; then
    konsole --title "ACF Lab $lab" -e bash --noprofile --norc -c "$command_line" >/dev/null 2>&1 &
  elif have xterm; then
    xterm -T "ACF Lab $lab" -e bash --noprofile --norc -c "$command_line" >/dev/null 2>&1 &
  elif have x-terminal-emulator; then
    x-terminal-emulator -e bash --noprofile --norc -c "$command_line" >/dev/null 2>&1 &
  else
    err "No supported terminal emulator found. Install xfce4-terminal or xterm."
    return 1
  fi
  ok "Opened a separate terminal window for Lab $lab."
}

launch_selected_labs() {
  local lab
  IFS=',' read -ra selected <<< "$OPT_LABS"
  for lab in "${selected[@]}"; do
    launch_lab_terminal "$lab" || return 1
    sleep 0.3
  done
  say "Each selected lab is running in its own terminal window."
}

menu() {
  while true; do
    say "\n${BOLD}${CYAN}APPLIED CYBERSECURITY FUNDAMENTALS — LAB RUNNER v$VERSION${RESET}"
    list_labs
    say "  all   Run all nine included practicals"
    say "  q     Quit"
    local selection
    read -r -p "Select lab(s), e.g. 1,2,4 or all: " selection || return 1
    selection="${selection//[[:space:]]/}"
    case "${selection,,}" in
      q|quit|exit) return 1 ;;
      all|a) OPT_LABS="all"; return 0 ;;
      *) if valid_selection "$selection"; then OPT_LABS="$selection"; return 0; else warn "Invalid selection. Use 1,2,3,4,5,6,7,8,10 or all."; fi ;;
    esac
  done
}

main() {
  if (( ! OPT_CHILD )); then
    say "${BOLD}ACF Lab Runner v$VERSION${RESET}"
    say "Artifacts: $BASE_DIR"
    say "Session log: $SESSION_LOG"
  fi
  if (( OPT_CLEANUP )); then need_root; cleanup_all; return 0; fi
  if (( OPT_CHECK )); then check_tools; return 0; fi
  # The main/menu window performs the full preflight once. Child lab windows
  # start directly at the practical instead of repeating the tool inventory.
  if (( ! OPT_CHILD )); then check_tools; fi
  if (( OPT_INSTALL )); then install_tools; fi
  if (( ! OPT_CHILD )); then
    # Keep the original/menu terminal alive. Each selected lab is launched
    # in a separate child terminal; after launching, return to the menu.
    while true; do
      if [[ -z "$OPT_LABS" ]]; then menu || { info "Exiting. Main terminal remains open."; return 0; }; fi
      if [[ "$OPT_LABS" == "all" ]]; then OPT_LABS="1,2,3,4,5,6,7,8,10"; fi
      if ! valid_selection "$OPT_LABS"; then err "Invalid lab selection: $OPT_LABS"; OPT_LABS=""; continue; fi
      launch_selected_labs || warn "One or more lab windows could not be opened."
      OPT_LABS=""
    done
  fi
  if [[ -z "$OPT_LABS" ]]; then err "Internal child launch missing lab selection."; return 2; fi
  if [[ "$OPT_LABS" == "all" ]]; then OPT_LABS="1,2,3,4,5,6,7,8,10"; fi
  if ! valid_selection "$OPT_LABS"; then err "Invalid lab selection: $OPT_LABS"; return 2; fi
  IFS=',' read -ra selected <<< "$OPT_LABS"
  for lab in "${selected[@]}"; do run_lab "$lab"; done
  say "\n${GREEN}Selected practicals finished.${RESET}"
  say "Artifacts: $BASE_DIR"
  say "Session log: $SESSION_LOG"
  say "To stop the Juice Shop container: sudo docker stop acf-juice-shop"
  say "To remove generated artifacts and runner resources: ./lab.sh --cleanup"
}

main "$@"
