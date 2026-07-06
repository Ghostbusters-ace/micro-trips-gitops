#!/bin/bash
# scripts/install-deps.sh

set -e # Arrête le script si une erreur se produit

echo "🛠️  Vérification et installation des dépendances Micro-Trips..."

# 1. Détection de l'OS
OS="$(uname -s)"
case "${OS}" in
    Linux*|Darwin*)
        echo "✅ OS compatible détecté : ${OS}"
        ;;
    CYGWIN*|MINGW*|MSYS*)
        echo "⚠️  Windows détecté. Veuillez ouvrir WSL (Ubuntu) ou utiliser 'choco install kubernetes-cli kind terraform kubeseal'."
        exit 1
        ;;
    *)
        echo "❌ OS non supporté : ${OS}"
        exit 1
        ;;
esac

# 2. Vérification / Installation de Homebrew (L'outil universel Mac/Linux)
if ! command -v brew &> /dev/null; then
    echo "🍺 Homebrew n'est pas installé. Installation en cours..."
    NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    
    # Ajout de brew au PATH pour Linux/Codespaces
    if [[ "${OS}" == "Linux" ]]; then
        eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
    fi
else
    echo "🍺 Homebrew est déjà installé."
fi

# 3. Installation des outils DevOps
echo "📦 Installation de kubectl, kind, terraform et kubeseal..."
brew install kubectl kind terraform kubeseal

echo "✅ Toutes les dépendances sont installées avec succès !"
echo "👉 Vous pouvez maintenant lancer : make all"