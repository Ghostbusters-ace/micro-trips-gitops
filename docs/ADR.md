# Architecture Decision Records (ADR) - Projet Micro-Trips

## ADR 1 : Communication asynchrone et choix de RabbitMQ (vs Redpanda)

* **Statut :** Accepté
* **Contexte :** Lors de la création d'une réservation dans le service `Booking`, il est nécessaire d'envoyer un e-mail de confirmation à l'utilisateur via un processus asynchrone pour ne pas bloquer l'API HTTP. Le sujet du projet suggère Redpanda par défaut comme broker de messages, tout en autorisant RabbitMQ comme alternative.
* **Décision :** Nous avons choisi d'utiliser **RabbitMQ** à la place de Redpanda.
* **Justification :** 
1. **Consommation de ressources :** Redpanda (basé sur l'architecture de type Kafka) est extrêmement puissant mais gourmand en mémoire vive et nécessite des prérequis CPU stricts, ce qui s'avère lourd pour notre cluster Kubernetes local (`kind`). RabbitMQ est beaucoup plus léger et s'exécute parfaitement avec une empreinte RAM minimale en local.
2. **Adéquation au besoin (Modèle AMQP vs Commit Log) :** Notre besoin se limite à une file d'attente simple (*Message Queue*) où chaque message (notification) est consommé puis supprimé. Le modèle de routage AMQP classique de RabbitMQ est parfait pour cela. Utiliser un journal distribué persistant comme Redpanda/Kafka aurait introduit une complexité inutile (gestion des offsets, partitions).
* **Conséquences :**
* **Positif :** Empreinte mémoire réduite sur la machine de développement, démarrage instantané du StatefulSet, intégration Go très simple via le driver `amqp091-go`.
* **Négatif :** Ne permet pas le rejeu historique des messages de la même manière qu'un log d'événements persistant (non requis pour ce projet).



## ADR 2 : Stratégie de déploiement Canary avec Argo Rollouts

* **Statut :** Accepté
* **Contexte :** Le déploiement des nouvelles versions de nos microservices (Catalog, Booking) doit se faire sans interruption de service (Zero-Downtime) et avec une détection automatique des régressions.
* **Décision :** Remplacement des `Deployments` natifs Kubernetes par des objets de type `Rollout` gérés par l'opérateur **Argo Rollouts**, couplés à des analyses automatisées via Prometheus.
* **Conséquences :**
* **Positif :** En cas d'augmentation des erreurs HTTP (code 500) détectées sur la version Canary grâce à notre métrique `http_requests_total`, le système déclenche un rollback automatique avant d'impacter la totalité de la production.
* **Négatif :** Obligation d'ajouter du code spécifique (le middleware d'observabilité Prometheus) au sein de nos applications de manière systématique.



## ADR 3 : Gestion dynamique et sécurisée des secrets avec Vault

* **Statut :** Accepté
* **Contexte :** Les identifiants de base de données (PostgreSQL) et de RabbitMQ ne doivent pas être écrits en clair dans les manifests stockés sur Git, afin de respecter les exigences fondamentales de sécurité du modèle GitOps.
* **Décision :** Utilisation de **HashiCorp Vault** (déployé en mode dev) centralisé, combiné avec **External Secrets Operator (ESO)**.
* **Conséquences :**
* **Positif :** Sécurité maximale. Les manifests Kubernetes stockés sur Git ne contiennent que des références abstraites (`ExternalSecret`). Les vrais secrets sont injectés dynamiquement dans le cluster uniquement à l'exécution.
* **Négatif :** Complexité lors de la phase d'initialisation du cluster (*bootstrapping*) car Vault doit être configuré avant de pouvoir déployer les applications.



## ADR 4 : Utilisation de la "Clean Architecture" pour les microservices Go

* **Statut :** Accepté
* **Contexte :** Structurer le code source des microservices afin d'éviter un code monolithique en un seul bloc, difficile à tester unitairement et à faire évoluer au fil du temps.
* **Décision :** Implémentation du pattern **Clean Architecture** découpé en quatre couches étanches : *Handlers* (couche transport / HTTP), *Services* (logique métier pure), *Repositories* (accès aux données SQL) et *Models* (structures de données). L'injection de dépendances est réalisée via des interfaces. De plus, chaque service gère sa propre auto-migration SQL au démarrage pour garantir son autonomie.
* **Conséquences :**
* **Positif :** Découplage fort. Il est possible de tester la logique métier d'un service en fournissant un faux repository (mock) sans avoir besoin d'ouvrir une vraie base de données. Chaque service possède son propre cycle de vie de données.
* **Négatif :** Structure de fichiers plus verbeuse (plus de fichiers et de packages à créer au départ pour une simple table).


## ADR 5 : Chiffrement des secrets sensibles dans Git via Bitnami Sealed Secrets

* **Statut :** Accepté
* **Contexte :** Pour intégrer l'outil de gestion des coûts **Kubecost**, l'application nécessite l'usage d'un token d'API ou d'identifiants sensibles. Selon les principes du GitOps, aucun secret ne doit être stocké en clair sur un dépôt public ou privé GitHub. Bien que nous utilisions HashiCorp Vault pour l'injection dynamique, certains tokens d'infrastructure (comme celui de Kubecost) doivent être présents dès l'amorçage ou interagir directement sous forme de ressources Kubernetes natives.
* **Décision :** Utilisation de **Bitnami Sealed Secrets** pour chiffrer les tokens sensibles directement dans le code Git sous forme d'objets `SealedSecret`.
* **Justification :** Sealed Secrets (développé par Bitnami) permet de s'affranchir du risque de fuite de données sur Git. On utilise l'outil en ligne de commande `kubeseal` avec la clé publique de notre cluster pour transformer un `Secret` classique en un `SealedSecret` totalement chiffré et illisible. Seul le contrôleur Sealed Secrets, s'exécutant de manière sécurisée dans notre cluster Kubernetes, possède la clé privée correspondante capable de déchiffrer le token au moment du déploiement.
* **Conséquences :**
* **Positif :** Possibilité de versionner 100% de l'infrastructure (y compris les tokens initiaux comme celui de Kubecost) sur Git en toute sécurité sans compromettre les identifiants.
* **Négatif :** Si le cluster Kubernetes est totalement détruit sans sauvegarde de la clé privée du contrôleur Sealed Secrets, les fichiers chiffrés sur Git deviennent impossibles à décoder et doivent être régénérés.