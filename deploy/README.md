# Déploiement — serveur Doodo

Le serveur est un **binaire Go unique** (`doodo-server`) qui écoute en HTTP
clair sur `DOODO_ADDR` (défaut `:8080`, endpoint `/ws`). La terminaison TLS
est assurée par la couche devant lui : **tunnel Cloudflare** (beta, sans VPS)
ou **Caddy** (VPS en prod).

## Option A — tunnel Cloudflare (beta, 0 €)

Le serveur tourne sur ta machine ; `cloudflared` l'expose en `wss://` sans
ouvrir de ports ni configurer de box.

### A.1 Tunnel rapide (éphémère, sans compte)

```bash
# 1. Lancer le serveur
./doodo-server                      # ou : go run ./cmd/doodo-server

# 2. Lancer le tunnel — l'URL https://<alea>.trycloudflare.com s'affiche
cloudflared tunnel --url http://localhost:8080 --no-autoupdate
```

Côté client : champ **Serveur** de l'écran d'accueil → `<alea>.trycloudflare.com`
(le client ajoute `wss://` et `/ws`). L'URL change à chaque redémarrage du
tunnel.

### A.2 Tunnel nommé (stable, ton domaine sur Cloudflare)

Une fois par machine :

```bash
cloudflared tunnel login            # ouvre le navigateur → autoriser le domaine
cloudflared tunnel create doodo     # affiche l'UUID du tunnel + écrit le JSON creds
cloudflared tunnel route dns doodo doodo.<ton-domaine>
```

Puis `deploy/cloudflared-config.yml` (éditer `<UUID>` et `<ton-domaine>`) :

```bash
cloudflared tunnel --config deploy/cloudflared-config.yml run
```

Côté client : champ **Serveur** → `doodo.<ton-domaine>`.

## Option B — VPS + Caddy (prod)

```bash
sudo apt install caddy              # ou le dépôt officiel Caddy
sudo cp deploy/Caddyfile /etc/caddy/Caddyfile   # éditer le domaine
sudo cp deploy/doodo-server.service /etc/systemd/system/
sudo cp doodo-server /usr/local/bin/
sudo systemctl daemon-reload
sudo systemctl enable --now doodo-server caddy
```

Caddy obtient le certificat Let's Encrypt tout seul → `wss://<domaine>/ws`.

## Notes

- **Ne jamais exposer le port 8080 directement** : il parle HTTP clair,
  c'est Caddy/cloudflared qui terminent le TLS.
- Vérifier l'exposition : `curl https://<domaine>/ws` doit répondre **426**
  (Upgrade Required) — signe que le WS endpoint est bien routé.
- Client mobile : le champ **Serveur** accepte `hote.fr` tel quel (le client
  normalise en `wss://hote.fr/ws`).
