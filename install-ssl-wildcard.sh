#!/bin/bash

# ==============================================================================
# Script d'installation Apache2 VirtualHost + Certificat SSL Wildcard
# Description : Configure automatiquement un VirtualHost Apache2 avec 
#               certificat SSL wildcard Let's Encrypt
# Auteur : ledokter
# Usage : sudo bash install-ssl-wildcard.sh [domaine] [email] [repertoire]
# Exemple : sudo bash install-ssl-wildcard.sh example.com admin@example.com
# ==============================================================================

set -e  # Arrêter si une erreur survient

# Couleurs pour l'affichage
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# ==============================================================================
# 1. VÉRIFICATIONS PRÉALABLES
# ==============================================================================

if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}Ce script doit être exécuté en tant que root (sudo)${NC}"
   exit 1
fi

# Demander les paramètres à l'utilisateur
if [ $# -lt 1 ]; then
    echo -e "${YELLOW}Usage: sudo bash $0 <domaine> [email] [repertoire]${NC}"
    echo "Exemple: sudo bash $0 example.com admin@example.com /var/www/example.com"
    echo ""
    read -p "Entrez le domaine principal (ex: example.com) : " DOMAIN
    read -p "Entrez l'email Let's Encrypt (ex: admin@example.com) : " EMAIL
    read -p "Entrez le chemin du répertoire racine (ex: /var/www/example.com) : " DOCROOT
else
    DOMAIN=$1
    EMAIL=${2:-"admin@${DOMAIN}"}
    DOCROOT=${3:-"/var/www/${DOMAIN}"}
fi

# Vérifications
if [ -z "$DOMAIN" ]; then
    echo -e "${RED}Erreur : le domaine est obligatoire${NC}"
    exit 1
fi

if [ ! -d "$DOCROOT" ]; then
    echo -e "${YELLOW}Le répertoire $DOCROOT n'existe pas, création...${NC}"
    mkdir -p "$DOCROOT"
    chmod 755 "$DOCROOT"
fi

VHOST_FILE="/etc/apache2/sites-available/${DOMAIN}.conf"
CERT_PATH="/etc/letsencrypt/live/${DOMAIN}"

echo -e "${GREEN}========================================${NC}"
echo "Configuration Apache2 + SSL Wildcard"
echo -e "${GREEN}========================================${NC}"
echo "Domaine : $DOMAIN"
echo "Email : $EMAIL"
echo "Répertoire racine : $DOCROOT"
echo "Config VirtualHost : $VHOST_FILE"
echo ""

# ==============================================================================
# 2. CRÉER LE VHOST HTTP (pour la validation Certbot)
# ==============================================================================

echo -e "${YELLOW}[1/4] Création du VirtualHost HTTP (port 80)...${NC}"

cat > "$VHOST_FILE" <<'HTTPVHOST'
<VirtualHost *:80>
    ServerName DOMAIN_PLACEHOLDER
    ServerAlias *.DOMAIN_PLACEHOLDER
    DocumentRoot DOCROOT_PLACEHOLDER

    # Logs
    ErrorLog ${APACHE_LOG_DIR}/DOMAIN_PLACEHOLDER-http-error.log
    CustomLog ${APACHE_LOG_DIR}/DOMAIN_PLACEHOLDER-http-access.log combined

    # Dossier pour validation Let's Encrypt
    <Directory DOCROOT_PLACEHOLDER>
        DirectoryIndex index.php index.html index.htm
        Options FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>
</VirtualHost>
HTTPVHOST

# Remplacer les placeholders
sed -i "s|DOMAIN_PLACEHOLDER|${DOMAIN}|g" "$VHOST_FILE"
sed -i "s|DOCROOT_PLACEHOLDER|${DOCROOT}|g" "$VHOST_FILE"

echo -e "${GREEN}✓ VirtualHost HTTP créé : $VHOST_FILE${NC}"

# ==============================================================================
# 3. ACTIVER LE VHOST HTTP ET REDÉMARRER APACHE2
# ==============================================================================

echo -e "${YELLOW}[2/4] Activation du VirtualHost HTTP...${NC}"

# Vérifier que le site n'est pas déjà activé
if [ ! -f "/etc/apache2/sites-enabled/${DOMAIN}.conf" ]; then
    a2ensite "$DOMAIN.conf" > /dev/null 2>&1
fi

# Activer les modules SSL et Rewrite si absent
a2enmod ssl > /dev/null 2>&1
a2enmod rewrite > /dev/null 2>&1
a2enmod headers > /dev/null 2>&1

# Vérifier la syntaxe Apache
if ! apache2ctl configtest > /dev/null 2>&1; then
    echo -e "${RED}Erreur de syntaxe Apache${NC}"
    apache2ctl configtest
    exit 1
fi

systemctl restart apache2
echo -e "${GREEN}✓ Apache2 redémarré (VirtualHost HTTP actif)${NC}"

# ==============================================================================
# 4. GÉNÉRER LE CERTIFICAT SSL WILDCARD AVEC CERTBOT
# ==============================================================================

echo -e "${YELLOW}[3/4] Génération du certificat SSL wildcard...${NC}"
echo "Veuillez vérifier votre registrar (OVH, etc.) pour confirmer les DNS"
echo ""

# Demander la validation DNS manuelle
read -p "Appuyez sur Entrée pour continuer la validation DNS..."

# Générer le certificat wildcard
certbot certonly \
    --manual \
    --preferred-challenges=dns \
    --email "$EMAIL" \
    --server https://acme-v02.api.letsencrypt.org/directory \
    --agree-tos \
    --no-eff-email \
    -d "$DOMAIN" \
    -d "*.$DOMAIN"

if [ ! -d "$CERT_PATH" ]; then
    echo -e "${RED}Erreur : le certificat n'a pas été généré correctement${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Certificat SSL wildcard généré${NC}"
echo "Chemin : $CERT_PATH"
echo ""

# ==============================================================================
# 5. CRÉER LE VHOST HTTPS (EN REMPLAÇANT LE HTTP)
# ==============================================================================

echo -e "${YELLOW}[4/4] Création du VirtualHost HTTPS...${NC}"

cat > "$VHOST_FILE" <<'HTTPSCONFIG'
# Redirection HTTP vers HTTPS
<VirtualHost *:80>
    ServerName DOMAIN_PLACEHOLDER
    ServerAlias *.DOMAIN_PLACEHOLDER
    DocumentRoot DOCROOT_PLACEHOLDER

    # Rediriger tout vers HTTPS
    Redirect permanent / https://DOMAIN_PLACEHOLDER/

    ErrorLog ${APACHE_LOG_DIR}/DOMAIN_PLACEHOLDER-http-error.log
    CustomLog ${APACHE_LOG_DIR}/DOMAIN_PLACEHOLDER-http-access.log combined
</VirtualHost>

# Configuration HTTPS (tous les sous-domaines)
<VirtualHost *:443>
    ServerName DOMAIN_PLACEHOLDER
    ServerAlias *.DOMAIN_PLACEHOLDER
    DocumentRoot DOCROOT_PLACEHOLDER

    # ============ SSL/TLS ============
    SSLEngine on
    SSLCertificateFile CERT_PATH_PLACEHOLDER/fullchain.pem
    SSLCertificateKeyFile CERT_PATH_PLACEHOLDER/privkey.pem

    # Protocoles modernes
    SSLProtocol TLSv1.2 TLSv1.3
    SSLCipherSuite HIGH:!aNULL:!MD5
    SSLHonorCipherOrder on
    SSLCompression off

    # Headers de sécurité
    Header always set Strict-Transport-Security "max-age=31536000; includeSubDomains"
    Header always set X-Frame-Options "SAMEORIGIN"
    Header always set X-Content-Type-Options "nosniff"
    Header always set X-XSS-Protection "1; mode=block"
    Header always set Referrer-Policy "strict-origin-when-cross-origin"

    # ============ WordPress/PHP ============
    <Directory DOCROOT_PLACEHOLDER>
        DirectoryIndex index.php index.html index.htm
        Options FollowSymLinks -Indexes
        AllowOverride All
        Require all granted

        # Rewrite rules pour WordPress
        <IfModule mod_rewrite.c>
            RewriteEngine On
            RewriteBase /
            RewriteRule ^index\.php$ - [L]
            RewriteCond %{REQUEST_FILENAME} !-f
            RewriteCond %{REQUEST_FILENAME} !-d
            RewriteRule . /index.php [L]
        </IfModule>
    </Directory>

    # ============ Logs ============
    ErrorLog ${APACHE_LOG_DIR}/DOMAIN_PLACEHOLDER-https-error.log
    CustomLog ${APACHE_LOG_DIR}/DOMAIN_PLACEHOLDER-https-access.log combined
</VirtualHost>
HTTPSCONFIG

# Remplacer les placeholders
sed -i "s|DOMAIN_PLACEHOLDER|${DOMAIN}|g" "$VHOST_FILE"
sed -i "s|DOCROOT_PLACEHOLDER|${DOCROOT}|g" "$VHOST_FILE"
sed -i "s|CERT_PATH_PLACEHOLDER|${CERT_PATH}|g" "$VHOST_FILE"

echo -e "${GREEN}✓ VirtualHost HTTPS configuré${NC}"

# ==============================================================================
# 6. REDÉMARRER APACHE2 ET VÉRIFIER
# ==============================================================================

echo -e "${YELLOW}Vérification et redémarrage Apache2...${NC}"

if ! apache2ctl configtest > /dev/null 2>&1; then
    echo -e "${RED}Erreur de syntaxe Apache${NC}"
    apache2ctl configtest
    exit 1
fi

systemctl restart apache2
sleep 2

# ==============================================================================
# 7. TESTS FINAUX
# ==============================================================================

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}✓ Installation terminée avec succès !${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Informations de configuration :"
echo "  Domaine : $DOMAIN"
echo "  Sous-domaines : *.$DOMAIN"
echo "  Répertoire racine : $DOCROOT"
echo "  VirtualHost config : $VHOST_FILE"
echo "  Certificat SSL : $CERT_PATH"
echo ""
echo "Tests à effectuer :"
echo "  1. HTTP redirige vers HTTPS : curl -I http://$DOMAIN"
echo "  2. HTTPS fonctionne : curl -I https://$DOMAIN"
echo "  3. Sous-domaine HTTPS : curl -I https://test.$DOMAIN"
echo "  4. Certificat SSL : echo | openssl s_client -servername $DOMAIN -connect $DOMAIN:443 2>/dev/null | grep -i subject"
echo ""
echo "Renouvellement auto du certificat :"
echo "  Vérifier : sudo systemctl list-timers certbot"
echo "  Test : sudo certbot renew --dry-run"
echo ""
echo "Logs Apache :"
echo "  Erreur HTTPS : sudo tail -f /var/log/apache2/${DOMAIN}-https-error.log"
echo "  Accès HTTPS : sudo tail -f /var/log/apache2/${DOMAIN}-https-access.log"
echo ""

# Test avec curl si disponible
if command -v curl &> /dev/null; then
    echo "Test rapide :"
    echo "  HTTP → HTTPS..."
    curl -I -L "http://$DOMAIN" 2>/dev/null | head -1
    echo ""
fi
