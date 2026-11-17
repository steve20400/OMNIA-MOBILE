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
  # GitHub ne garde que les 4096 premiers caractères d'une annotation : on
  # n'y met que la fin de la sortie, là où se trouve l'erreur, bornée avant
  # l'encodage. %, CR et LF doivent être encodés (%25, %0D, %0A).
  message=$(tail -n 60 "$log" | sed -e 's/\r$//' | tail -c 3500 | sed -e 's/%/%25/g' | awk '{ printf "%s%%0A", $0 }')
  echo "::error title=${title} (code ${status})::${message}"
fi

rm -f "$log"
exit "$status"
