# shellcheck shell=bash
# =============================================================================
# lib-scrub.sh — take secrets and contact details out of a support file
# (./tarleaks doctor --bundle). Sourced by ./tarleaks and by
# scripts/check-bundle-scrub.sh, which proves every rule below on seeded
# secrets.
#
# Two passes over a file, in place:
#  1. every value in .env that could be a secret (8 characters or more under
#     any key that is not on the short list of plain settings below, or 4 or
#     more under a key that names a secret) is replaced
#     by [redacted:<KEY>], wherever it appears, longest first, so a password
#     printed by a service in a log line is caught too;
#  2. known shapes: JWTs, Tarleaks licence/verdict/ticket strings and API
#     tokens, "Bearer …" / "Basic …", passwords inside addresses, tokens in
#     query strings, private-key blocks, e-mail addresses, IBANs (with or
#     without spaces), Emirates ID numbers and international phone numbers.
# Names of people cannot be recognised by a pattern: the bundle command tells
# the person to look inside before sending.
# =============================================================================

# Keys whose values help support and are not secrets: versions, apps, profiles,
# ports, addresses, image names, user names, buckets and regions. Everything
# else in .env is treated as secret. (A user name such as `tarleaks` is also the
# database and project name: redacting it would hide every line support needs.
# A password inside an address is still caught by the URL rule below.)
SCRUB_PLAIN_KEYS='^(TARLEAKS_|NEXUS_)?(VERSION|APPS|PROFILE_ENV|OFFLINE|TLS|URL|HOST|REGISTRY|ENVIRONMENT|AUTO_UPDATE|UPDATE_WINDOW|UPDATE_DAYS)$|^COMPOSE_(FILE|PROFILES|PROJECT_NAME)$|_PORT$|_BIND$|_IMAGE$|_USER$|_DB$|_BUCKET$|_REGION$|_URL$|_ENDPOINT$|_LEVEL$|_MODE$|^RUST_LOG$|^TZ$'

# A value of 4 to 7 characters counts as a secret only under a key that names
# one: short values elsewhere are words such as `info` or `true` that would
# blank out every log line. From 8 characters every non-plain value counts.
SCRUB_SECRET_KEYS='PASS|SECRET|KEY|TOKEN|CODE|PIN|CREDENTIAL'

scrub_file() { # env-file file — rewrites file
  local envf=$1 f=$2 tmp
  # Beside the file, so whoever cleans up the file's folder on an error
  # (support_bundle's trap) removes the half-scrubbed copy too.
  tmp=$(mktemp "$f.XXXXXX")
  awk -v envf="$envf" -v plain="$SCRUB_PLAIN_KEYS" -v secretish="$SCRUB_SECRET_KEYS" '
    BEGIN {
      n = 0
      while ((getline line < envf) > 0) {
        if (line !~ /^[A-Za-z_][A-Za-z0-9_]*=/) continue
        k = substr(line, 1, index(line, "=") - 1)
        v = substr(line, index(line, "=") + 1)
        sub(/\r$/, "", v)
        if (v ~ /^".*"$/ || v ~ /^\047.*\047$/) v = substr(v, 2, length(v) - 2)
        else { sub(/[ \t]+#.*$/, "", v); sub(/[ \t]+$/, "", v) }
        if (length(v) < 4 || k ~ plain) continue
        if (length(v) < 8 && k !~ secretish) continue
        n++; key[n] = k; val[n] = v
      }
      # Longest first, so a secret that starts another one cannot leave the
      # tail of the longer one behind.
      for (i = 2; i <= n; i++) {
        kv = key[i]; vv = val[i]
        for (j = i - 1; j >= 1 && length(val[j]) < length(vv); j--) { key[j + 1] = key[j]; val[j + 1] = val[j] }
        key[j + 1] = kv; val[j + 1] = vv
      }
    }
    {
      for (i = 1; i <= n; i++) {
        out = ""; rest = $0
        while ((p = index(rest, val[i])) > 0) {
          out = out substr(rest, 1, p - 1) "[redacted:" key[i] "]"
          rest = substr(rest, p + length(val[i]))
        }
        $0 = out rest
      }
      print
    }' "$f" > "$tmp"
  sed -E \
    -e 's/eyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}/[redacted:jwt]/g' \
    -e 's/(nxs1|tlk1|tlc1|nxl1|tll1|nxv1)\.[A-Za-z0-9_-]{16,}(\.[A-Za-z0-9_-]+)?/[redacted:key]/g' \
    -e 's/(nxs|tlk)_[A-Za-z0-9]{16,}/[redacted:api-token]/g' \
    -e 's/([Bb]earer|[Bb]asic|TarleaksCloud) [A-Za-z0-9._~+\/=-]{8,}/\1 [redacted]/g' \
    -e 's#://[^/:@ ]+:[^/@ ]+@#://[redacted]@#g' \
    -e 's/([?&](access_token|token|key|secret|password|sig|signature|X-Amz-Signature|X-Amz-Credential)=)[^& "]+/\1[redacted]/g' \
    -e 's/-----BEGIN [A-Z ]*PRIVATE KEY-----/[redacted:private-key]/g' \
    -e 's/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/[redacted:email]/g' \
    -e 's/(^|[^A-Za-z0-9])[A-Z]{2}[0-9]{2}[A-Z0-9]{11,30}([^A-Za-z0-9]|$)/\1[redacted:iban]\2/g' \
    -e 's/(^|[^A-Za-z0-9])[A-Z]{2}[0-9]{2}[A-Z0-9]{11,30}([^A-Za-z0-9]|$)/\1[redacted:iban]\2/g' \
    -e 's/[A-Z]{2}[0-9]{2}( [A-Z0-9]{4}){3,7}( [A-Z0-9]{1,4})?/[redacted:iban]/g' \
    -e 's/784-?[0-9]{4}-?[0-9]{7}-?[0-9]/[redacted:emirates-id]/g' \
    -e 's/(\+|00)(971|966|973|974|965|968)[0-9]{7,10}/[redacted:phone]/g' \
    -e 's/\+[1-9][0-9]{9,14}/[redacted:phone]/g' \
    "$tmp" > "$f"
  rm -f "$tmp"
}

# The names in .env, never the values: which keys are set and which are empty.
env_key_report() { # env-file
  awk -F= '/^[A-Za-z_][A-Za-z0-9_]*=/ { print $1 "=" (length(substr($0, index($0, "=") + 1)) > 0 ? "(set)" : "(empty)") }' "$1"
}
