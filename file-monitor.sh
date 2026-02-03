#!/bin/bash

# ==============================================================================
# Script de surveillance des fichiers modifiés
# Description : Recherche tous les fichiers modifiés depuis minuit dans un 
#               répertoire spécifié et enregistre la liste dans un fichier.
# Auteur : ledokter
# ==============================================================================

set -e

# Couleurs pour l'affichage
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# ==============================================================================
# Configuration
# ==============================================================================

# Demander le répertoire à surveiller
if [ $# -lt 1 ]; then
    read -p "Entrez le chemin du répertoire à surveiller (ex: /srv/www) : " SEARCH_DIR
else
    SEARCH_DIR=$1
fi

# Demander le fichier de sortie
if [ $# -lt 2 ]; then
    read -p "Entrez le nom du fichier de sortie (défaut: modified-files.txt) : " OUTPUT_FILE
    OUTPUT_FILE=${OUTPUT_FILE:-"modified-files.txt"}
else
    OUTPUT_FILE=$2
fi

# Vérifications
if [ -z "$SEARCH_DIR" ]; then
    echo -e "${RED}Erreur : le répertoire est obligatoire${NC}"
    exit 1
fi

if [ ! -d "$SEARCH_DIR" ]; then
    echo -e "${RED}Erreur : le répertoire $SEARCH_DIR n'existe pas${NC}"
    exit 1
fi

# ==============================================================================
# Recherche des fichiers modifiés
# ==============================================================================

echo -e "${YELLOW}Recherche des fichiers modifiés depuis minuit dans $SEARCH_DIR...${NC}"

# Recherche récursive des fichiers modifiés depuis minuit
sudo find "$SEARCH_DIR" -type f -newermt "$(date +%Y-%m-%d) 00:00:00" -print > "$OUTPUT_FILE"

# Comptage des fichiers trouvés
FILE_COUNT=$(wc -l < "$OUTPUT_FILE")

echo -e "${GREEN}✓ Recherche terminée${NC}"
echo "  Répertoire surveillé : $SEARCH_DIR"
echo "  Fichiers modifiés trouvés : $FILE_COUNT"
echo "  Résultats enregistrés dans : $OUTPUT_FILE"
echo ""
echo "Pour afficher les résultats : cat $OUTPUT_FILE"
