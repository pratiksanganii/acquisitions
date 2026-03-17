# AGENTS.md

This file provides guidance to WARP (warp.dev) when working with code in this repository.

## Project Overview

`acquisitions` is a Node.js REST API built with Express 5, using Drizzle ORM against a Neon (serverless PostgreSQL) database. It uses ES modules (`"type": "module"`). Authentication is JWT-based with tokens stored in HTTP-only cookies.

## Environment Setup

Copy `.env.example` to `.env` and fill in the values:

```
PORT=3000
NODE_ENV=development
LOG_LEVEL=info
DATABASE_URL=<neon-postgres-connection-string>
JWT_SECRET=<your-secret>
```

> `JWT_SECRET` is used in `src/utils/jwt.js` but is not listed in `.env.example` — add it manually.

## Commands

```bash
# Start with file watching (development)
npm run dev

# Lint
npm run lint
npm run lint:fix

# Format
npm run format
npm run format:check

# Database — generate migration files from schema changes
npm run db:generate

# Database — apply pending migrations
npm run db:migrate

# Database — open Drizzle Studio (visual DB browser)
npm run db:studio
```

There is no test runner configured (no `test` script, no test framework installed). The ESLint config has globals defined for Jest in `tests/**/*.js`, but no tests exist yet.

## Architecture

**Entry point:** `src/index.js` loads `dotenv/config` then imports `src/server.js`, which starts the HTTP listener. The Express app itself is defined in `src/app.js` and exported as default.

**Path aliases:** `package.json#imports` maps `#config/*`, `#controllers/*`, `#middleware/*`, `#models/*`, `#routes/*`, `#services/*`, `#utils/*`, and `#validations/*` to corresponding subdirectories under `src/`. Always use these aliases for intra-package imports rather than relative paths — except in `src/services/auth.service.js` which currently imports `database.js` via a relative path (`../../database.js`).

**Database:** `database.js` (project root) exports `db` (Drizzle ORM instance) and `sql` (raw Neon client). Schema files live in `src/models/*.js`. Drizzle config (`drizzle.config.js`) reads `DATABASE_URL` from the environment and outputs migrations to `./drizzle/`.

**Request lifecycle for a new route:**
1. Define a Zod schema in `src/validations/`
2. Implement business logic in `src/services/` (DB access goes here via `db` from `database.js`)
3. Write a controller in `src/controllers/` — validate with the schema, call the service, handle errors
4. Register the route in `src/routes/` and mount it in `src/app.js`

**Auth flow:** On sign-up, the controller validates with `signUpSchema`, calls `createUser` (service), signs a JWT via `jwttoken.sign`, and sets it as an HTTP-only cookie via `cookies.set`. The JWT expires in 1 day; the cookie `maxAge` is 15 minutes (mismatch to be aware of).

**Logging:** Winston logger in `src/config/logger.js`. Writes `logs/error.log` (errors only) and `logs/combined.log` (info+). Console transport is added when `NODE_ENV !== 'production'`. Morgan HTTP access logs are piped into Winston at `info` level.

## Code Style

ESLint enforces: 2-space indentation, single quotes, semicolons, `prefer-const`, `no-var`, `object-shorthand`, `prefer-arrow-callback`. Prettier is integrated via `eslint-plugin-prettier`. Linebreak style is Unix (`\n`).
