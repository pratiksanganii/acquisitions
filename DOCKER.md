# Docker Setup — Acquisitions API

This document explains how to run the app locally with **Neon Local** (ephemeral
Postgres branches via Docker) and how to deploy it to production against the
**Neon cloud** database.

---

## How `DATABASE_URL` switches between environments

| Context | `DATABASE_URL` | `NEON_LOCAL_HOST` |
|---|---|---|
| Dev (Docker Compose) | `postgres://neon:npg@neon-local:5432/acquisitions` | `neon-local` |
| Production | `postgres://user:pass@ep-xxx.neon.tech/db?sslmode=require` | *(unset)* |

`NEON_LOCAL_HOST` is the toggle. When set, `database.js` switches the
`@neondatabase/serverless` driver into HTTP-only mode and routes queries through
the local proxy instead of the Neon cloud API. When absent, the driver connects
to Neon's cloud endpoint using the standard serverless path.

---

## Prerequisites

- [Docker Desktop](https://www.docker.com/products/docker-desktop/) (v24+)
- A [Neon account](https://console.neon.tech) with at least one project
- A Neon API key — `Project Settings → API Keys`

---

## Local Development with Neon Local

### 1. Configure your environment

Copy the template and fill in your values:

```bash
cp .env.development .env.development.local   # optional extra safety
```

Open `.env.development` and set:

```
NEON_API_KEY=<your api key>
NEON_PROJECT_ID=<your project id>
PARENT_BRANCH_ID=<branch id of your main/dev branch>
JWT_SECRET=<any string for local dev>
```

**Finding `PARENT_BRANCH_ID`:**
Go to `https://console.neon.tech` → your project → **Branches**. Click the
branch you want to fork from (usually `main`) and copy the branch ID from the
URL (`br-xxxxx-xxxxx`).

Leave `DATABASE_URL` and `NEON_LOCAL_HOST` exactly as they are — they point to
the `neon-local` service defined inside the Compose network.

### 2. Start the stack

```bash
docker compose --env-file .env.development -f docker-compose.dev.yml up --build
```

What happens:
1. Docker builds the **development** image (all deps, `--watch` hot-reload).
2. The `neon-local` container starts and **forks a fresh ephemeral branch** from
   `PARENT_BRANCH_ID`. Your app connects to this ephemeral branch.
3. The `app` container starts, waits for `neon-local`, then begins serving on
   `http://localhost:3000`.

Each `docker compose up` gives you a **clean database copy** of the parent
branch. When you run `docker compose down`, the ephemeral branch is deleted from
Neon automatically.

### 3. Run database migrations

Migrations need to be applied to the ephemeral branch after the containers start:

```bash
docker compose --env-file .env.development -f docker-compose.dev.yml exec app npm run db:migrate
```

> **Tip:** If your parent branch already has all migrations applied (which it
> should), the ephemeral branch inherits them and you can skip this step.

### 4. Verify the app is running

```bash
curl http://localhost:3000/health
```

### 5. Stop and clean up

```bash
# Stops containers AND deletes the ephemeral Neon branch
docker compose --env-file .env.development -f docker-compose.dev.yml down
```

---

## Persistent branch per Git branch (optional)

By default, a new ephemeral branch is created on every `up`. If you want to
keep the same database branch across restarts for a given Git branch, the
`neon-local` service in `docker-compose.dev.yml` already includes the required
volume mounts (`./.neon_local` and `.git/HEAD`). Just set `DELETE_BRANCH: false`
in the `neon-local` environment block.

> On Docker Desktop for Mac: use **gRPC FUSE** (not VirtioFS) in VM settings
> to avoid a known bug with git HEAD file detection inside containers.

---

## Production Deployment with Neon Cloud

### 1. Configure production environment

Fill in `.env.production`:

```
DATABASE_URL=postgres://user:password@ep-xxx.region.aws.neon.tech/dbname?sslmode=require
JWT_SECRET=<strong 64+ char random secret>
ARCJET_KEY=<production arcjet key>
```

Generate a strong JWT secret:

```bash
node -e "console.log(require('crypto').randomBytes(64).toString('hex'))"
```

> In CI/CD, inject these as secrets (GitHub Actions secrets, Docker secrets,
> Vault, etc.) rather than using the file. The file is provided for
> documentation purposes only.

### 2. Build and start

```bash
docker compose --env-file .env.production -f docker-compose.prod.yml up --build -d
```

The production image excludes `devDependencies` (`drizzle-kit`, eslint, etc.)
and does **not** start a Neon Local proxy. The app connects directly to your
Neon cloud database via the serverless HTTP driver.

### 3. Run migrations (first deploy / schema changes)

```bash
# From outside Docker, using the production DATABASE_URL
DATABASE_URL=<your-prod-url> npm run db:migrate

# Or from inside the running container (requires devDeps — use the dev image)
docker compose --env-file .env.production -f docker-compose.prod.yml exec app npx drizzle-kit migrate
```

> Best practice: run migrations as a separate step in your CI/CD pipeline
> **before** deploying the new container image.

### 4. Verify

```bash
curl https://your-domain.com/health
```

---

## Dockerfile targets reference

| Target | Command | Use case |
|---|---|---|
| `development` | `node --watch src/index.js` | Local dev with hot-reload |
| `production` | `node src/index.js` | Production / staging |

Build a specific target manually:

```bash
# Production image only
docker build --target production -t acquisitions:prod .

# Development image only
docker build --target development -t acquisitions:dev .
```

---

## Environment variable reference

| Variable | Required | Description |
|---|---|---|
| `DATABASE_URL` | Yes | Postgres connection string (Neon Local or Neon cloud) |
| `NEON_LOCAL_HOST` | Dev only | Service name of the Neon Local container (`neon-local`). When set, enables HTTP proxy mode in `database.js`. |
| `NEON_API_KEY` | Dev only | Neon API key used by the `neon-local` container |
| `NEON_PROJECT_ID` | Dev only | Neon project ID used by the `neon-local` container |
| `PARENT_BRANCH_ID` | Dev only | Branch to fork ephemeral dev branches from |
| `PORT` | No | HTTP port (default: `3000`) |
| `NODE_ENV` | Yes | `development` or `production` |
| `LOG_LEVEL` | No | Winston log level (default: `info`) |
| `JWT_SECRET` | Yes | Secret for signing JWTs |
| `ARCJET_KEY` | No | Arcjet API key for security middleware |

---

## Troubleshooting

**App fails to connect to DB on startup**
The `neon-local` container takes a few seconds to create the branch. The `app`
service uses `restart: on-failure`, so it will retry automatically. Watch logs
with `docker compose logs -f app`.

**`neon-local` container exits immediately**
Check that `NEON_API_KEY` and `NEON_PROJECT_ID` are valid. Run
`docker compose logs neon-local` to see the error.

**`npm run db:migrate` fails with SSL cert error**
This can happen when running drizzle-kit against Neon Local's self-signed cert.
Prefix the command with `NODE_TLS_REJECT_UNAUTHORIZED=0`:

```bash
docker compose exec app sh -c "NODE_TLS_REJECT_UNAUTHORIZED=0 npm run db:migrate"
```

**Port 5432 already in use**
Another Postgres instance is running locally. Either stop it or change the
`neon-local` port mapping in `docker-compose.dev.yml` (e.g., `"5433:5432"`).

**Docker Desktop for Mac — branch not detected after git checkout**
Switch Docker Desktop's VM file sharing from VirtioFS to **gRPC FUSE** in
`Settings → General → Virtual File Sharing`.
