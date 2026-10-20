#!/usr/bin/env bash
# Proves scripts/lib-scrub.sh on seeded secrets: none may survive, and the plain
# settings support needs must. Run by CI (scripts job).
set -euo pipefail
cd "$(dirname "$0")/.."
# shellcheck source=scripts/lib-scrub.sh
. scripts/lib-scrub.sh
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
# Secret-shaped fixtures are put together here, at run time, so that no token,
# key or JWT sits in this file for a secret scanner (gitleaks in CI) to find.
H=eyJ
JWT="${H}hbGciOiJFZERTQSJ9.${H}zdWIiOiIxMjM0NTY3ODkwIn0.c2lnbmF0dXJlZm9yand0"
LIC="nxs1.${H}pbnN0YWxsYXRpb25faWQiOiIxIn0.c2lnbmF0dXJlc2lnbmF0dXJl"
TIC="tlc1.${H}0eXAiOiJjbG91ZF90aWNrZXQifQ.c2lnbmF0dXJlc2lnbmF0dXJl"
PEM="-----BEGIN PRIVATE"" KEY-----"
BASIC="dXNlcjpw""YXNzd29yZA=="
BEARER="abcdefghij""klmnop.qrstuvwx"
APITOK="nxs""_0123456789abcdef0123"
SEALVAL="b64keymaterial""ABCDEFGHIJKLMNOP=="
cat > "$work/env" <<ENV
TARLEAKS_VERSION=1.2.0-rc.2
TARLEAKS_APPS=hr,payroll,accounting
POSTGRES_USER=tarleaks
RABBITMQ_USER=tarleaks-mq
STORAGE_BUCKET=tarleaks-files
DATABASE_URL=postgres://app:Url-Pass-Secret-9@postgres:5432/app
POSTGRES_PASSWORD=Pg-Very-Secret-42
CLUSTER_DSN_KEY="$SEALVAL"
TARLEAKS_SETUP_CODE=K7QF2M9DXR4P
TARLEAKS_ENTITLEMENT_TOKEN=$LIC
SHORTVAL=abc
LOG_LEVEL=info
FEATURE_FLAG=true
SHORT_PASS=q7Zp
LONG_SECRET=prefix-secret-and-more
PREFIX_SECRET=prefix-secret
HAND_EDITED=hand-value-77   # a comment
WEIRD=redacted-loop-value
ENV
cat > "$work/log" <<LOG
auth | connecting with password Pg-Very-Secret-42 to postgres
auth | sealing with $SEALVAL
auth | setup code K7QF2M9DXR4P printed
auth | token $LIC
auth | cloud ticket $TIC
auth | Authorization: Bearer $BEARER
auth | jwt $JWT
hr   | sent payslip to someone.payroll@example.com
hr   | IBAN AE070331234567890123456 saved
db   | dsn postgres://app:hunter2secret@postgres:5432/app
key  | $PEM
odd  | value redacted-loop-value seen
short| pass q7Zp used
lvl  | info: started with feature true
pre  | prefix-secret-and-more and prefix-secret
hand | hand-value-77 kept by mistake
s3   | GET https://bucket.example/file?X-Amz-Signature=abcdef0123456789&x=1
basic| Authorization: Basic $BASIC
tok  | api token $APITOK
iban | AE070331234567890123456 AE070331234567890123457
ibsp | printed as AE07 0331 2345 6789 0123 458 on the slip
eid  | Emirates ID 784-1990-1234567-1 checked
tel  | call +971501234567 or 00966512345678
ver  | running release 1.2.0-rc.2 with apps hr,payroll,accounting as tarleaks
mq   | connected to tarleaks-mq, bucket tarleaks-files
db   | url postgres://app:Url-Pass-Secret-9@postgres:5432/app
LOG
scrub_file "$work/env" "$work/log"
fail=0
for secret in Pg-Very-Secret-42 b64keymaterialABCDEFGHIJKLMNOP K7QF2M9DXR4P \
  c2lnbmF0dXJlc2lnbmF0dXJl "$BEARER" "${JWT%%.*}" \
  someone.payroll@example.com AE070331234567890123456 hunter2secret \
  "${PEM#-----}" redacted-loop-value Url-Pass-Secret-9 q7Zp prefix-secret and-more \
  hand-value-77 abcdef0123456789 "$BASIC" "$APITOK" AE070331234567890123457 \
  "6789 0123 458" 1234567-1 501234567 512345678; do
  if grep -qF -- "$secret" "$work/log"; then echo "LEAK: $secret survived"; fail=1; fi
done
for kept in "1.2.0-rc.2" "hr,payroll,accounting" "as tarleaks" "postgres:5432/app" "[redacted:POSTGRES_PASSWORD]" \
  "connected to tarleaks-mq, bucket tarleaks-files" "info: started with feature true"; do
  grep -qF -- "$kept" "$work/log" || { echo "LOST: '$kept' should stay"; fail=1; }
done
report=$(env_key_report "$work/env")
if printf '%s' "$report" | grep -qF "Pg-Very-Secret-42"; then echo "LEAK: env_key_report printed a value"; fail=1; fi
printf '%s\n' "$report" | grep -qx "POSTGRES_PASSWORD=(set)" || { echo "env_key_report: missing POSTGRES_PASSWORD=(set)"; fail=1; }
if [ "$fail" != 0 ]; then echo "--- scrubbed file ---"; cat "$work/log"; exit 1; fi
echo "OK: every seeded secret was removed and the plain settings stayed."
