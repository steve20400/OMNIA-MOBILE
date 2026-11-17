#!/usr/bin/env bash
# Exécute une commande de la CI et, si elle échoue, publie la fin de sa sortie
# comme annotation d'erreur : la cause se lit sur la page de l'exécution, sans
# ouvrir les journaux complets.
#
# Usage : bash tool/ci/run.sh "Titre de l'étape" commande [arguments...]
set -uo pipefail

if [ "$#" -lt 2 ]; then
  echo "Usage : bash tool/ci/run.sh \"Titre\" commande [arguments...]" >&2
  exit 64
fi

title=$1
shift
log=$(mktemp)
"$@" 2>&1 | tee "$log"
status=${PIPESTATUS[0]}

if [ "$status" -ne 0 ]; then
  # GitHub ne garde que les 4096 premiers caractères d'une annotation.
  #
  # D'abord les lignes d'erreur nommées : le compilateur Kotlin (« e: »),
  # Dart (« Error: »), Gradle (« What went wrong »). Une compilation Android
  # finit par vingt lignes de conseils génériques ; la vraie cause est plus
  # haut, et la fin seule ne la montrait pas. Puis la fin de la sortie.
  # %, CR et LF doivent être encodés (%25, %0D, %0A).
  errors=$(grep -E '^e: |[Ee]rror[: ]|What went wrong' "$log" | sed -e 's/\r$//' | head -n 20 | head -c 1500)
  ending=$(tail -n 40 "$log" | sed -e 's/\r$//' | tail -c 2000)
  message=$(printf '%s\n----\n%s\n' "$errors" "$ending" | sed -e 's/%/%25/g' | awk '{ printf "%s%%0A", $0 }')
  echo "::error title=${title} (code ${status})::${message}"
fi

rm -f "$log"
exit "$status"
