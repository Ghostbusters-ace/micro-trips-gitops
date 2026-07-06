# Rapport Technique d'Architecture Cloud-Native : Projet Micro-Trips ( Local-First)

**Auteur :** Ghostbusters-ace

**Date :** Juillet 2026

**Version :** v1.0-soutenance

**Statut :** Livrable Final d'Architecture & DevOps

---

## Table des Matières

1. [Introduction et Vision Globale](#1-introduction-et-vision-globale)
2. [Architecture Logicielle et Design Patterns (Clean Architecture)](#2-architecture-logicielle-et-design-patterns-clean-architecture)
3. [Philosophie du Day-0 vs Day-1 (Provisioning Terraform)](#3-philosophie-du-day-0-vs-day-1)
4. [Stratégie GitOps et Déploiement Continu avec ArgoCD](#4-stratégie-gitops-et-déploiement-continu-avec-argocd)
5. [Gestion Avancée des Secrets et Sécurité (Vault, ESO, Sealed Secrets)](#5-gestion-avancée-des-secrets-et-sécurité-vault-eso-sealed-secrets)
6. [Routage et Maillage de Services avec Linkerd Service Mesh](#6-routage-et-maillage-de-services-avec-linkerd-service-mesh)
7. [Ingénierie du Déploiement Canary avec Argo Rollouts](#7-ingénierie-du-déploiement-canary-avec-argo-rollouts)
8. [Observabilité, Télémétrie et Gestion des Coûts (Prometheus, Grafana, Kubecost)](#8-observabilité-télémétrie-et-gestion-des-coûts-prometheus-grafana-kubecost)
9. [Conclusion et Perspectives Évolutives](#9-conclusion-et-perspectives-évolutives)

---

## 1. Introduction et Vision Globale

### 1.1 Contexte du Projet

Le projet **Micro-Trips** consiste en la conception, le développement et le déploiement d'une application distribuée de réservation de voyages de niveau production. Face aux enjeux modernes de scalabilité, de résilience et de haute disponibilité, l'infrastructure historique monolithique a été entièrement déconstruite au profit d'une **architecture microservices décentralisée**.

### 1.2 Objectifs Stratégiques

L'objectif principal est de valider une infrastructure répondant aux critères stricts du modèle *Cloud-Native* :

* **Autonomie opérationnelle :** Isolation complète des cycles de vie applicatifs et des bases de données de chaque service.
* **Sécurité Zero-Trust :** Chiffrement systématique des flux réseaux internes et externalisation absolue des secrets de configuration.
* **Déploiement progressif et automatisé :** Élimination des interventions humaines lors des mises à jour applicatives grâce à des boucles de rétroaction basées sur des métriques réelles.
* **Sobriété et efficacité FinOps :** Analyse granulaire de l'utilisation des ressources financières et matérielles pour éviter le sur-dimensionnement (*over-provisioning*).

### 1.3 Choix du Modèle "v3 Local-First"

Afin de concilier la complexité d'un environnement multi-noeuds de production avec les contraintes d'une machine de développement, l'architecture logicielle s'appuie sur une approche **v3 Local-First**. Le cluster est orchestré localement via `kind` (Kubernetes in Docker), simulant fidèlement un comportement multi-noeuds cloud sans dépendre des coûts prohibitifs ni de la latence d'un fournisseur cloud public tiers (`GCP`, `AWS`).

---

## 2. Architecture Logicielle et Design Patterns (Clean Architecture)

L'ensemble des services applicatifs a été développé en **Go (Golang)**, sélectionné pour ses performances d'exécution, sa faible empreinte mémoire, sa gestion native de la concurrence (Goroutines) et sa robustesse au sein des environnements de conteneurs.

### 2.1 Les Trois Microservices Applicatifs

L'écosystème applicatif est divisé en trois entités distinctes résidant au sein du namespace isolé `app` :

1. **Catalog API :** Service REST chargé de lire et d'exposer la liste des voyages disponibles. Il interagit exclusivement en lecture avec sa propre base de données PostgreSQL.
2. **Booking API :** Point d'entrée pour la création des réservations. Ce service reçoit les requêtes d'achat, les persiste dans sa base de données PostgreSQL dédiée, puis émet un événement asynchrone.
3. **Notification Worker :** Consommateur d'événements d'arrière-plan. Il écoute en continu les messages provenant du broker, extrait les données, et déclenche l'envoi d'e-mails de confirmation via le protocole SMTP.

```
+-----------------------------------------------------------------+
|                         NAMESPACE: app                          |
|                                                                 |
|   +----------------+          +----------------+                |
|   |  Catalog API   |          |  Booking API   |                |
|   +-------+--------+          +-------+--------+                |
|           | (Lecture)                 | (Écriture)              |
|           v                           v                         |
|   +--------------------------------------------+                |
|   |         Clean Architecture Layers          |                |
|   |  [Handler] -> [Service] -> [Repository]    |                |
|   +--------------------------------------------+                |
|                                       |                         |
|                                       v (Publish Event)         |
|                               +-------+--------+                |
|                               |  Notif Worker  |                |
|                               +-------+--------+                |
|                                       | (Send SMTP)             |
|                                       v                         |
|                               +-------+--------+                |
|                               |    MailHog     |                |
|                               +----------------+                |
+-----------------------------------------------------------------+

```

### 2.2 Implémentation de la Clean Architecture

Chaque microservice applicatif abandonne la structure classique en script unique pour adopter une stricte **Clean Architecture**, découpée en quatre couches d'abstraction étanches :

* **Models (Entités) :** Définition pure des structures de données métier (`Trip`, `Booking`), exemptes de toute logique technique ou de tags liés à des frameworks externes.
* **Repositories (Couche Données) :** Interfaces et implémentations responsables des interactions SQL avec PostgreSQL. Cette couche encapsule la complexité des requêtes, protégeant le reste du code des spécificités du driver de base de données.
* **Services (Couche Métier) :** Cœur de l'application contenant les règles de gestion (ex: validation d'une réservation, formatage de l'événement). Cette couche communique uniquement avec les abstractions (interfaces) des Repositories.
* **Handlers (Couche Transport) :** Gestion de l'interface d'entrée/sortie HTTP. Elle décode les payloads JSON reçus, invoque la couche Service, intercepte les erreurs métiers pour les traduire en codes de statut HTTP standardisés (`201 Created`, `400 Bad Request`, `500 Internal Server Error`).

L'injection de dépendances est réalisée de manière systématique au sein du point d'entrée `main.go`, garantissant la testabilité unitaire de chaque bloc fonctionnel grâce au mécanisme de *mocking*.

### 2.3 Cycle de Vie des Données et Auto-Migration Dynamique

Pour éliminer le couplage temporel et manuel consistant à devoir exécuter des scripts SQL externes avant le déploiement des services, la responsabilité de la structure des données a été déléguée au code Go lui-même via un mécanisme d'**Auto-Migration**.
Au démarrage, chaque service tente de joindre sa base de données (avec une stratégie de *retry* de 5 tentatives espacées de 3 secondes). Une fois la connexion établie, le service exécute une requête de type `CREATE TABLE IF NOT EXISTS`. Pour le service `Catalog`, un mécanisme complémentaire de **Database Seeding** vérifie le nombre de lignes présentes et injecte automatiquement un jeu de données initial (Paris, Tokyo, Bali) si la table est vierge.

---

## 3. Philosophie du Day-0 vs Day-1
Un anti-pattern fréquent dans les projets Kubernetes consiste à configurer l'opérateur GitOps (ArgoCD) manuellement via des lignes de commandes impératives (`kubectl apply` ou `helm install`). Pour pallier ce problème et garantir une reproductibilité absolue en environnement d'entreprise, nous avons implémenté une couche d'**Infrastructure as Code (IaC)** via HashiCorp Terraform.

Terraform intervient au **Day-0** : son unique rôle est de s'assurer que le cluster (qu'il soit local sur Kind ou managé dans le Cloud comme GKE/EKS) possède son moteur GitOps fonctionnel et ses clés de déchiffrement de secrets. Une fois ces ressources provisionnées, Terraform se retire et laisse ArgoCD piloter le cluster (Day-1).

### 3.1 Analyse du Design des Manifestes Terraform
Le module Terraform développé s'appuie sur deux *providers* officiels pour interagir de manière déclarative avec l'API du cluster :

#### A. Le Provider Kubernetes (HashiCorp)
Utilisé pour isoler logiquement les environnements via la création de ressources `kubernetes_namespace`. Cela garantit que les briques d'outillage ne polluent pas le namespace applicatif par défaut.

#### B. Le Provider Helm (HashiCorp)
Plutôt que d'utiliser des scripts bash, Terraform utilise la ressource `helm_release`. Ce choix permet de :
* Fixer des versions de charts strictes (ex: ArgoCD v6.7.11) pour éviter les ruptures de compatibilité.
* Surcharger dynamiquement les configurations (*values.yaml*) grâce aux blocs `set {}`. Par exemple, la Haute Disponibilité (HA) de Redis a été désactivée programmatiquement dans le code Terraform pour optimiser la consommation de la mémoire vive (RAM) lors de la simulation.

### 3.2 Gestion des Variables et Modularité
L'architecture du code refuse toute valeur codée en dur (*hardcoded*). Le fichier `variables.tf` centralise les types, les descriptions et les valeurs par défaut. Cette approche permet de transiter d'un cluster local à un cluster de production Cloud (AWS/GCP) en modifiant uniquement la variable `kubeconfig_path`, sans altérer la logique du fichier principal `main.tf`.

---


## 4. Stratégie GitOps et Déploiement Continu avec ArgoCD

### 4.1 Séparation Stricte du Code et de la Configuration

Conformément aux prérequis de l'ingénierie GitOps moderne, le projet est scindé en deux dépôts de code distincts et étanches :

1. **Dépôt Applicatif (`micro-trips-infra`) :** Contient exclusivement le code source Go, l'ingénierie logicielle, les fichiers `Dockerfile` multi-stages, et les pipelines d'intégration continue (CI).
2. **Dépôt GitOps (`micro-trips-gitops`) :** Contient l'intégralité de l'état désiré du cluster Kubernetes exprimé sous forme de manifestes déclaratifs structurés via **Kustomize**.

### 4.2 Implémentation d'ArgoCD et Reconciliation Loop

**ArgoCD** a été déployé au cœur du cluster pour servir de contrôleur GitOps unique. Il surveille en permanence le dépôt GitOps et applique une boucle de réconciliation active (*Reconciliation Loop*). Toute dérive de configuration (*Configuration Drift*) survenue manuellement sur le cluster via des commandes `kubectl` impromptues est immédiatement détectée et écrasée par ArgoCD pour rétablir la vérité définie sur Git.

L'architecture des manifestes repose sur le pattern **Application-of-Applications**, où une application racine ArgoCD orchestre le déploiement de sous-applications (Infrastructures de stockage, opérateurs de sécurité, microservices métiers), standardisant l'ensemble du cycle de vie du cluster en une seule entité logique.

---

## 5. Gestion Avancée des Secrets et Sécurité (Vault, ESO, Sealed Secrets)

La sécurité d'un cluster cloud-native interdit la présence de chaînes de caractères en clair dans les fichiers de configuration versionnés. Deux mécanismes complémentaires ont été mis en œuvre au sein du projet.

### 5.1 Injection Dynamique via HashiCorp Vault et External Secrets Operator (ESO)

Pour les secrets applicatifs changeant fréquemment ou partagés (tels que les identifiants PostgreSQL et les credentials RabbitMQ), nous avons déployé **HashiCorp Vault** (dans le namespace `vault`) couplé à l'**External Secrets Operator (ESO)**.

Le flux de sécurisation s'articule ainsi :

1. Les données sensibles sont injectées de manière sécurisée dans l'instance Vault.
2. Un objet `ClusterSecretStore` fournit les accès et la méthode d'authentification de confiance entre le cluster K8s et Vault.
3. Pour chaque microservice, un manifeste `ExternalSecret` déclare les clés exactes à extraire de Vault.
4. Le contrôleur ESO intercepte cet objet, interroge Vault de manière transparente, et génère dynamiquement une ressource native Kubernetes de type `Secret` au sein du namespace applicatif cible.
5. Les microservices consomment ensuite ces secrets sous forme de variables d'environnement cryptées en mémoire vive, isolant totalement le dépôt Git de la moindre donnée sensible.

```
+------------------+          +------------------------+           +---------------------+
|                  |  (Sync)  |    External Secrets    |  (Create) |   Native K8s        |
| HashiCorp Vault  |<-------->|     Operator (ESO)     |---------->|  Secret (InMemory)  |
|                  |          +------------------------+           +----------+----------+
+------------------+                      ^                                  |
                                          | (Reads)                          | (Injects)
                              +-----------+------------+                     v
                              |  ExternalSecret Spec   |          +----------+----------+
                              |      (On GitHub)       |          |   Applicative Pod   |
                              +------------------------+          +---------------------+

```

### 5.2 Chiffrement Asymétrique Asynchrone avec Bitnami Sealed Secrets

Pour certains jetons d'infrastructure spécifiques dont la présence est requise dès la phase d'amorçage initial (*bootstrapping*) avant que Vault ne soit opérationnel — comme le jeton d'authentification de l'outil **Kubecost** —, l'architecture intègre la technologie **Bitnami Sealed Secrets**.

En utilisant la clé publique du contrôleur récupérée depuis le cluster, l'administrateur chiffre localement son secret via l'utilitaire `kubeseal`. Le résultat est un objet de type `SealedSecret` contenant une chaîne de caractères chiffrée de manière asymétrique, rendant son stockage sur un dépôt GitHub public totalement sûr. Lors du déploiement, le contrôleur Sealed Secrets s'exécutant dans le cluster utilise sa clé privée exclusive pour décoder la ressource et instancier le secret Kubernetes natif.

---

## 6. Routage et Maillage de Services avec Linkerd Service Mesh

Les communications inter-services au sein d'un cluster microservices classique souffrent historiquement d'un manque de visibilité et de failles de sécurité (trafic en clair en interne). Pour y pallier, le projet intègre **Linkerd**, un maillage de services (*Service Mesh*) ultra-léger et performant.

### 6.1 Injection de Proxies Sidecars et Sécurité mTLS

Lors du déploiement des pods applicatifs au sein du namespace `app`, l'annotation `linkerd.io/inject: enabled` déclenche l'injection automatique d'un conteneur proxy sidecar extrêmement compact (écrit en Rust) aux côtés du conteneur Go de l'application.

Toutes les entrées et sorties réseau du pod sont interceptées par ce proxy. Les proxies négocient de manière totalement transparente des connexions sécurisées via **mTLS (Mutual TLS)** avec échange de certificats éphémères, garantissant le chiffrement de bout en bout de l'intégralité du trafic réseau au sein du cluster sans qu'aucune ligne de code applicative n'ait besoin d'intégrer de logique de chiffrement.

### 6.2 Les Quatre Métriques Dorées (Golden Signals)

En interceptant les flux au niveau de la couche transport, Linkerd génère nativement de la télémétrie de haut niveau sur les communications réseaux sans aucune surcharge logicielle. Il remonte en continu à la stack d'observabilité les quatre indicateurs clés (Golden Signals) :

* **Le Taux de Succès (Success Rate) :** Pourcentage de requêtes HTTP se soldant par un code de retour valide.
* **La Latence (Latency P50, P95, P99) :** Distribution fine du temps de réponse des API.
* **Le Volume (Throughput) :** Nombre de requêtes traitées par seconde (RPS).

---

## 7. Ingénierie du Déploiement Canary avec Argo Rollouts

Le déploiement continu d'applications en production exige une élimination totale du risque d'interruption de service lors des mises à jour. Nous avons implémenté une stratégie de **déploiement progressif de type Canary** via l'opérateur **Argo Rollouts**, couplé à une analyse de métriques automatisée.

### 7.1 Remplacement des Déploiements Classiques par les Objets Rollout

Les abstractions Kubernetes standards de type `Deployment` ont été converties en ressources de type `Rollout`. Un objet `Rollout` définit la stratégie d'aiguillage progressif du trafic vers la nouvelle version de l'application (la version *Canary*) tout en maintenant la version précédente stable.

Notre stratégie est configurée selon les étapes séquentielles suivantes :

1. Injection de la nouvelle image de conteneur.
2. Redirection automatique de **10%** du trafic utilisateur global vers la version Canary.
3. Déclenchement d'une phase d'analyse automatique de **2 minutes**.
4. Si l'analyse est valide, augmentation du trafic Canary à **50%**.
5. Nouvelle phase d'analyse de **2 minutes**.
6. Si aucune anomalie n'est détectée, promotion finale de la version Canary qui devient la nouvelle version stable à **100%**.

### 7.2 Automatisation de l'Analyse d'Erreurs et Rollback PromQL

La force majeure de cette architecture réside dans son indépendance vis-à-vis de l'action humaine pour valider le déploiement. L'objet `Rollout` est adossé à un **`AnalysisTemplate`**. Cet outil exécute de manière cyclique des requêtes directes au format **PromQL** auprès du serveur Prometheus du cluster.

L'analyse surveille la métrique métier collectée via notre middleware applicatif Go :

```promql
sum(rate(http_requests_total{status="error", version="canary"}[2m])) 
/ 
sum(rate(http_requests_total{version="canary"}[2m]))

```

Si le ratio d'erreurs HTTP (codes 5xx) générées par la version Canary dépasse le seuil critique toléré de **1%** au cours de la fenêtre d'analyse, Argo Rollouts interrompt immédiatement le déploiement, isole la version défaillante et effectue un **rollback instantané à 100%** du trafic vers la version stable précédente, protégeant ainsi l'expérience des utilisateurs finaux.

---

## 8. Observabilité, Télémétrie et Gestion des Coûts (Prometheus, Grafana, Kubecost)

L'infrastructure intègre une pile d'observabilité complète tridimensionnelle couvrant les métriques applicatives, la validation fonctionnelle et le suivi financier.

### 8.1 Collecte des Métriques avec Prometheus et Tableaux de Bord Grafana

**Prometheus** agit comme le collecteur central du cluster via un modèle de tirage (*Pull-based scraping*). Il interroge périodiquement les points de terminaisons `/metrics` exposés par :

* Les microservices applicatifs Go (via l'import du package `promhttp`).
* Les proxies sidecars de Linkerd.
* Les exportateurs d'infrastructure (PostgreSQL Exporter, RabbitMQ Management Plugin).

Ces données brutes temporelles sont ensuite agrégées et visualisées sur des tableaux de bord dynamiques au sein de **Grafana**. Ces dashboards permettent de corréler instantanément une hausse d'utilisation CPU/RAM au niveau de l'infrastructure avec une augmentation de la latence des requêtes HTTP au niveau métier.

### 8.2 Validation Fonctionnelle Asynchrone avec MailHog

Dans le but de valider le comportement du système événementiel asynchrone en environnement local sans dépendre d'un véritable fournisseur de messagerie (ex: SendGrid) et sans risquer de spammer de vraies boîtes de réception, l'infrastructure déploie l'outil **MailHog** au sein du cluster.
Le microservice `Notification Worker` envoie ses requêtes SMTP vers l'adresse interne de MailHog sur le port `1025`. MailHog intercepte ces e-mails en mémoire et propose une interface Web complète permettant aux développeurs et aux correcteurs de valider visuellement la bonne réception et le contenu exact de l'e-mail de confirmation de réservation.

### 8.3 Analyse FinOps Fine avec Kubecost

Le respect des contraintes économiques étant devenu crucial dans l'ingénierie Cloud, l'outil **Kubecost** a été intégré à l'infrastructure. Kubecost croise les métriques d'utilisation réelles des conteneurs (CPU, Mémoire vive, Allocations de volumes persistants PVC) avec les grilles tarifaires réelles des grands fournisseurs de cloud.

Grâce à son tableau de bord, Kubecost fournit une visibilité complète des coûts par namespace et par application. Cela permet d'identifier précisément les microservices sur-dimensionnés par rapport à leur charge réelle et d'ajuster finement les déclarations de `resources.requests` et `resources.limits` au sein des manifestes Kustomize pour minimiser l'empreinte carbone et financière du projet.

---

## 9. Conclusion et Perspectives Évolutives

L'architecture **Local-First** mise en œuvre pour le projet Micro-Trips démontre la viabilité du paradigme cloud-native. En combinant un découpage logiciel strict en Clean Architecture avec des opérateurs Kubernetes de pointe (ArgoCD, Argo Rollouts, Vault, Linkerd), l'infrastructure se montre résiliente aux pannes, sécurisée par défaut et entièrement automatisée dans son cycle de déploiement.

### Perspectives d'Évolution (Production à Grande Échelle)

Pour projeter cette architecture vers un environnement de production de classe d'entreprise multi-régions, les axes d'amélioration suivants sont préconisés :

1. **Transition vers des bases de données managées (Cloud SQL / AWS RDS) :** Remplacer les StatefulSets locaux par des instances managées hautement disponibles avec réplication géographique pour décharger la responsabilité de la maintenance des données.
2. **Mise en œuvre d'un auto-scaling horizontal basé sur les messages (KEDA) :** Configurer l'opérateur KEDA (*Kubernetes Event-driven Autoscaling*) pour scaler dynamiquement le nombre de pods du `Notification Worker` non pas sur des critères CPU/RAM classiques, mais directement en fonction du nombre de messages en attente dans la file RabbitMQ.
3. **Mise en œuvre de politiques réseau strictes (NetworkPolicies) :** Compléter la sécurité mTLS de Linkerd en appliquant des règles pare-feu natives Kubernetes pour interdire physiquement au namespace `vault` ou aux pods de stockage d'accepter des connexions directes en dehors des composants explicitement autorisés.