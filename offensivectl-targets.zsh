#!/usr/bin/env zsh
# offensivectl-targets.zsh
# Authorized-scope target collector for offensivectl.
# Collects and normalizes domains, subdomains, email addresses, usernames,
# IP/CIDR ranges, URLs, organizations, and notes without performing exploitation.

set -u
setopt PIPE_FAIL

SCRIPT_NAME="${0:t}"
VERSION="1.0.0"

BASE_DIR="${OFFENSIVECTL_TARGET_DIR:-$PWD/offensivectl-targets}"
TARGET_NAME=""
TARGET_DIR=""

typeset -a domains
typeset -a emails
typeset -a usernames
typeset -a ips
typeset -a urls
typeset -a organizations
typeset -a social_profiles
typeset -a notes

domains=()
emails=()
usernames=()
ips=()
urls=()
organizations=()
social_profiles=()
notes=()

print_header() {
    echo
    echo "============================================================"
    echo " offensivectl Target / Attack-Surface Collector v${VERSION}"
    echo "============================================================"
    echo
    echo "Authorized security assessment targets only."
    echo
}

die() {
    echo "[ERROR] $*" >&2
    exit 1
}

sanitize_name() {
    local input="$1"
    print -r -- "$input" |
        tr '[:upper:]' '[:lower:]' |
        sed 's/[^a-zA-Z0-9._-]/-/g; s/--*/-/g; s/^-//; s/-$//'
}

trim() {
    local value="$1"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    print -r -- "$value"
}

valid_domain() {
    [[ "$1" =~ '^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?\.[A-Za-z]{2,63}$' ]]
}

valid_email() {
    [[ "$1" =~ '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,63}$' ]]
}

valid_ipv4() {
    local ip="$1"
    local a b c d

    [[ "$ip" =~ '^([0-9]{1,3}\.){3}[0-9]{1,3}$' ]] || return 1

    IFS=. read -r a b c d <<< "$ip"

    (( a >= 0 && a <= 255 &&
       b >= 0 && b <= 255 &&
       c >= 0 && c <= 255 &&
       d >= 0 && d <= 255 ))
}

valid_cidr() {
    local value="$1"

    if [[ "$value" =~ '^([^/]+)/([0-9]{1,2})$' ]]; then
        local ip="${match[1]}"
        local prefix="${match[2]}"

        valid_ipv4 "$ip" && (( prefix >= 0 && prefix <= 32 ))
        return $?
    fi

    return 1
}

add_domain() {
    local value
    value="$(trim "$1")"
    value="${value:l}"
    value="${value#http://}"
    value="${value#https://}"
    value="${value%%/*}"
    value="${value%%:*}"
    value="${value%.}"

    if valid_domain "$value"; then
        domains+=("$value")
        echo "[+] DOMAIN: $value"
    else
        echo "[!] Invalid domain: $1"
    fi
}

add_email() {
    local value
    value="$(trim "$1")"
    value="${value:l}"

    if valid_email "$value"; then
        emails+=("$value")
        echo "[+] EMAIL: $value"

        local email_domain="${value##*@}"
        if valid_domain "$email_domain"; then
            domains+=("$email_domain")
        fi
    else
        echo "[!] Invalid email: $1"
    fi
}

add_username() {
    local value
    value="$(trim "$1")"
    value="${value#@}"

    if [[ -n "$value" ]]; then
        usernames+=("$value")
        echo "[+] USERNAME: $value"
    fi
}

add_ip() {
    local value
    value="$(trim "$1")"

    if valid_ipv4 "$value" || valid_cidr "$value"; then
        ips+=("$value")
        echo "[+] IP/CIDR: $value"
    else
        echo "[!] Invalid IPv4/CIDR: $1"
    fi
}

add_url() {
    local value
    value="$(trim "$1")"

    if [[ "$value" =~ '^https?://[^[:space:]]+$' ]]; then
        urls+=("$value")
        echo "[+] URL: $value"

        local host
        host="$(print -r -- "$value" |
            sed -E 's#^https?://##; s#/.*$##; s/:.*$//')"

        if valid_domain "$host"; then
            domains+=("${host:l}")
        elif valid_ipv4 "$host"; then
            ips+=("$host")
        fi
    else
        echo "[!] URL must start with http:// or https://"
    fi
}

add_organization() {
    local value
    value="$(trim "$1")"

    if [[ -n "$value" ]]; then
        organizations+=("$value")
        echo "[+] ORGANIZATION: $value"
    fi
}

add_social_profile() {
    local value
    value="$(trim "$1")"

    if [[ -n "$value" ]]; then
        social_profiles+=("$value")
        echo "[+] SOCIAL: $value"
    fi
}

add_note() {
    local value
    value="$(trim "$1")"

    if [[ -n "$value" ]]; then
        notes+=("$value")
        echo "[+] NOTE ADDED"
    fi
}

collect_multiple() {
    local type="$1"
    local prompt="$2"
    local value

    echo
    echo "$prompt"
    echo "Enter one item per line."
    echo "Press ENTER on an empty line when finished."
    echo

    while true; do
        read "value?> "

        [[ -z "$value" ]] && break

        case "$type" in
            domain)       add_domain "$value" ;;
            email)        add_email "$value" ;;
            username)     add_username "$value" ;;
            ip)           add_ip "$value" ;;
            url)          add_url "$value" ;;
            organization) add_organization "$value" ;;
            social)       add_social_profile "$value" ;;
            note)         add_note "$value" ;;
        esac
    done
}

import_file() {
    local filename="$1"

    [[ -f "$filename" ]] || {
        echo "[!] File does not exist: $filename"
        return 1
    }

    echo
    echo "Import file as:"
    echo "  1) Domains"
    echo "  2) Emails"
    echo "  3) Usernames"
    echo "  4) IP/CIDR"
    echo "  5) URLs"
    echo "  6) Social profiles"
    echo "  7) Auto-detect"
    echo
    read "choice?Selection: "

    local line

    while IFS= read -r line || [[ -n "$line" ]]; do
        line="$(trim "$line")"

        [[ -z "$line" ]] && continue
        [[ "$line" == \#* ]] && continue

        case "$choice" in
            1) add_domain "$line" ;;
            2) add_email "$line" ;;
            3) add_username "$line" ;;
            4) add_ip "$line" ;;
            5) add_url "$line" ;;
            6) add_social_profile "$line" ;;

            7)
                if valid_email "$line"; then
                    add_email "$line"
                elif valid_ipv4 "$line" || valid_cidr "$line"; then
                    add_ip "$line"
                elif [[ "$line" =~ '^https?://' ]]; then
                    add_url "$line"
                elif valid_domain "$line"; then
                    add_domain "$line"
                else
                    add_username "$line"
                fi
                ;;
            *)
                echo "[!] Invalid selection."
                return 1
                ;;
        esac
    done < "$filename"
}

dedupe_arrays() {
    domains=("${(@f)$(printf '%s\n' "${domains[@]}" | sed '/^$/d' | sort -fu)}")
    emails=("${(@f)$(printf '%s\n' "${emails[@]}" | sed '/^$/d' | sort -fu)}")
    usernames=("${(@f)$(printf '%s\n' "${usernames[@]}" | sed '/^$/d' | sort -fu)}")
    ips=("${(@f)$(printf '%s\n' "${ips[@]}" | sed '/^$/d' | sort -fu)}")
    urls=("${(@f)$(printf '%s\n' "${urls[@]}" | sed '/^$/d' | sort -fu)}")
    organizations=("${(@f)$(printf '%s\n' "${organizations[@]}" | sed '/^$/d' | sort -fu)}")
    social_profiles=("${(@f)$(printf '%s\n' "${social_profiles[@]}" | sed '/^$/d' | sort -fu)}")
    notes=("${(@f)$(printf '%s\n' "${notes[@]}" | sed '/^$/d' | sort -u)}")
}

write_array() {
    local filename="$1"
    shift

    : > "$filename"

    if (( $# )); then
        printf '%s\n' "$@" > "$filename"
    fi
}

save_targets() {
    dedupe_arrays

    mkdir -p "$TARGET_DIR" || die "Could not create $TARGET_DIR"

    write_array "$TARGET_DIR/domains.txt" "${domains[@]}"
    write_array "$TARGET_DIR/emails.txt" "${emails[@]}"
    write_array "$TARGET_DIR/usernames.txt" "${usernames[@]}"
    write_array "$TARGET_DIR/ip-ranges.txt" "${ips[@]}"
    write_array "$TARGET_DIR/urls.txt" "${urls[@]}"
    write_array "$TARGET_DIR/organizations.txt" "${organizations[@]}"
    write_array "$TARGET_DIR/social-profiles.txt" "${social_profiles[@]}"
    write_array "$TARGET_DIR/notes.txt" "${notes[@]}"

    {
        printf '%s\n' "${domains[@]}"
        printf '%s\n' "${emails[@]}"
        printf '%s\n' "${usernames[@]}"
        printf '%s\n' "${ips[@]}"
        printf '%s\n' "${urls[@]}"
        printf '%s\n' "${social_profiles[@]}"
    } | sed '/^$/d' | sort -fu > "$TARGET_DIR/all-targets.txt"

    local created
    created="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

    cat > "$TARGET_DIR/scope.env" <<EOF
OFFENSIVECTL_SCOPE_NAME='$TARGET_NAME'
OFFENSIVECTL_SCOPE_DIR='$TARGET_DIR'
OFFENSIVECTL_DOMAINS='$TARGET_DIR/domains.txt'
OFFENSIVECTL_EMAILS='$TARGET_DIR/emails.txt'
OFFENSIVECTL_USERNAMES='$TARGET_DIR/usernames.txt'
OFFENSIVECTL_IP_RANGES='$TARGET_DIR/ip-ranges.txt'
OFFENSIVECTL_URLS='$TARGET_DIR/urls.txt'
OFFENSIVECTL_SOCIAL_PROFILES='$TARGET_DIR/social-profiles.txt'
OFFENSIVECTL_ALL_TARGETS='$TARGET_DIR/all-targets.txt'
EOF

    cat > "$TARGET_DIR/target.json" <<EOF
{
  "schema": "offensivectl.target.v1",
  "name": "$(json_escape "$TARGET_NAME")",
  "created_utc": "$created",
  "authorization": "authorized-security-assessment",
  "files": {
    "domains": "domains.txt",
    "emails": "emails.txt",
    "usernames": "usernames.txt",
    "ip_ranges": "ip-ranges.txt",
    "urls": "urls.txt",
    "organizations": "organizations.txt",
    "social_profiles": "social-profiles.txt",
    "notes": "notes.txt",
    "all_targets": "all-targets.txt"
  },
  "counts": {
    "domains": ${#domains[@]},
    "emails": ${#emails[@]},
    "usernames": ${#usernames[@]},
    "ip_ranges": ${#ips[@]},
    "urls": ${#urls[@]},
    "organizations": ${#organizations[@]},
    "social_profiles": ${#social_profiles[@]}
  }
}
EOF

    (
        cd "$TARGET_DIR" || exit 1

        if command -v sha256sum >/dev/null 2>&1; then
            sha256sum \
                domains.txt \
                emails.txt \
                usernames.txt \
                ip-ranges.txt \
                urls.txt \
                organizations.txt \
                social-profiles.txt \
                notes.txt \
                all-targets.txt \
                target.json \
                > SHA256SUMS
        elif command -v shasum >/dev/null 2>&1; then
            shasum -a 256 \
                domains.txt \
                emails.txt \
                usernames.txt \
                ip-ranges.txt \
                urls.txt \
                organizations.txt \
                social-profiles.txt \
                notes.txt \
                all-targets.txt \
                target.json \
                > SHA256SUMS
        fi
    )

    echo
    echo "[+] Target package written:"
    echo "    $TARGET_DIR"
    echo
}

json_escape() {
    local value="$1"
    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    value="${value//$'\n'/\\n}"
    print -r -- "$value"
}

show_summary() {
    dedupe_arrays

    echo
    echo "---------------- TARGET SUMMARY ----------------"
    printf " Domains:          %d\n" "${#domains[@]}"
    printf " Emails:           %d\n" "${#emails[@]}"
    printf " Usernames:        %d\n" "${#usernames[@]}"
    printf " IP/CIDR:          %d\n" "${#ips[@]}"
    printf " URLs:             %d\n" "${#urls[@]}"
    printf " Organizations:    %d\n" "${#organizations[@]}"
    printf " Social profiles:  %d\n" "${#social_profiles[@]}"
    printf " Notes:            %d\n" "${#notes[@]}"
    echo "------------------------------------------------"
}

menu() {
    local choice
    local filename

    while true; do
        show_summary

        echo
        echo "Target Collection"
        echo
        echo "  1) Add domains / subdomains"
        echo "  2) Add email addresses"
        echo "  3) Add usernames / handles"
        echo "  4) Add IPv4 / CIDR ranges"
        echo "  5) Add URLs"
        echo "  6) Add organizations / brands"
        echo "  7) Add known social profiles"
        echo "  8) Add investigation notes"
        echo "  9) Import targets from file"
        echo " 10) Save target package"
        echo " 11) Save and exit"
        echo "  0) Exit without saving"
        echo

        read "choice?Selection: "

        case "$choice" in
            1)
                collect_multiple domain \
                    "Domains/subdomains (example.com, vpn.example.com):"
                ;;
            2)
                collect_multiple email \
                    "Known in-scope email addresses:"
                ;;
            3)
                collect_multiple username \
                    "Known usernames/handles:"
                ;;
            4)
                collect_multiple ip \
                    "Authorized IPv4 addresses/CIDR ranges:"
                ;;
            5)
                collect_multiple url \
                    "Known HTTP/HTTPS URLs:"
                ;;
            6)
                collect_multiple organization \
                    "Organization, subsidiary, product, or brand names:"
                ;;
            7)
                collect_multiple social \
                    "Known public social-network profile URLs or handles:"
                ;;
            8)
                collect_multiple note \
                    "Scope/investigation notes:"
                ;;
            9)
                read "filename?Input filename: "
                import_file "$filename"
                ;;
            10)
                save_targets
                ;;
            11)
                save_targets
                show_summary
                echo
                echo "[+] Ready for offensivectl."
                echo
                exit 0
                ;;
            0)
                echo "[*] Exiting without saving."
                exit 0
                ;;
            *)
                echo "[!] Unknown selection."
                ;;
        esac
    done
}

main() {
    print_header

    echo "Create a named authorization/scope package."
    echo
    read "TARGET_NAME?Target / engagement name: "

    TARGET_NAME="$(sanitize_name "$TARGET_NAME")"

    [[ -n "$TARGET_NAME" ]] || die "Target name cannot be empty."

    TARGET_DIR="$BASE_DIR/$TARGET_NAME"

    echo
    echo "Target directory:"
    echo "  $TARGET_DIR"
    echo
    echo "Confirm you are authorized to assess the assets entered here."
    read "authorization?Type YES to continue: "

    [[ "$authorization" == "YES" ]] || die "Authorization not confirmed."

    menu
}

main "$@"