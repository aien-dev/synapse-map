#!/bin/sh
# build.sh OMEGA_SRC OUT: compose the synapse-map unit and compile it with the pinned omc.
# Checks the omega-mv checkout and the omc binary against omega.pin before compiling, and never
# leaves a binary behind from a failed compile. Copies infer.tsv and topics.tsv next to OUT (the
# binary's default rule and topic files).
set -eu
if [ "$#" -ne 2 ]; then
  echo "usage: build.sh OMEGA_SRC OUT" >&2
  exit 64
fi
src=$1
out=$2
here=$(cd "$(dirname "$0")" && pwd)
want_head=$(sed -n '1s/^aien-dev\/omega-mv@//p' "$here/omega.pin")
want_omc=$(sed -n '2s/^omc-sha256 //p' "$here/omega.pin")
have_head=$(git -C "$src" rev-parse HEAD)
have_omc=$(sha256sum "$src/seed/out/omc" | cut -d' ' -f1)
if [ "$have_head" != "$want_head" ]; then
  echo "build.sh: omega-mv HEAD $have_head != pin $want_head" >&2
  exit 65
fi
if [ "$have_omc" != "$want_omc" ]; then
  echo "build.sh: omc sha256 $have_omc != pin $want_omc" >&2
  exit 65
fi
mkdir -p "$(dirname "$out")"
rm -f "$out"
{
  printf 'om2\n'
  cat "$src/seed/json/json.om" "$src/seed/json/jsonw.om" "$src/seed/net/http.om" "$here"/src/*.om
} > "$out.unit.om"
if ! "$src/seed/out/omc" < "$out.unit.om" > "$out.tmp"; then
  rm -f "$out.tmp"
  echo "build.sh: omc refused $out.unit.om" >&2
  exit 70
fi
chmod 755 "$out.tmp"
mv "$out.tmp" "$out"
cp "$here/infer.tsv" "$here/topics.tsv" "$(dirname "$out")/"
sha256sum "$out" >&2
