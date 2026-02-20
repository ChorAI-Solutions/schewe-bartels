# Update-Report - 28. Januar 2026

## System-Übersicht
- **OS**: Ubuntu 24.04.3 LTS (Noble)
- **Kernel**: 6.8.0-90-generic
- **Node.js**: v20.20.0
- **Docker**: 29.1.5 (Update verfügbar: 29.2.0)
- **Docker Compose**: v5.0.2

---

## 🔴 Kritische Updates

### Linux System-Updates
**Status**: Updates verfügbar
- `docker-ce`: 29.1.5 → **29.2.0** ⬆️
- `docker-ce-cli`: 29.1.5 → **29.2.0** ⬆️
- `docker-ce-rootless-extras`: 29.1.5 → **29.2.0** ⬆️

**Empfehlung**: 
```bash
sudo apt update && sudo apt upgrade docker-ce docker-ce-cli docker-ce-rootless-extras
```

---

## 📦 npm Package Updates

### Hauptdependencies
| Package | Aktuell | Verfügbar | Status |
|---------|---------|-----------|--------|
| `next` | 16.0.0 | **16.1.6** | ⬆️ Update verfügbar |
| `react` | 19.2.0 | **19.2.4** | ⬆️ Update verfügbar |
| `react-dom` | 19.2.0 | **19.2.4** | ⬆️ Update verfügbar |
| `@prisma/client` | 7.0.0 | **7.3.0** | ⬆️ **Breaking Changes** |
| `@prisma/adapter-pg` | 7.0.0 | **7.3.0** | ⬆️ **Breaking Changes** |
| `prisma` | 7.0.0 | **7.3.0** | ⬆️ **Breaking Changes** |
| `pg` | 8.12.0 | **8.17.2** | ⬆️ Update verfügbar |
| `react-markdown` | 10.1.0 | 10.1.0 | ✅ Aktuell |

### DevDependencies
| Package | Aktuell | Verfügbar | Status |
|---------|---------|-----------|--------|
| `@tailwindcss/postcss` | ^4 | (prüfen) | ⚠️ Prüfen |
| `tailwindcss` | ^4 | (prüfen) | ⚠️ Prüfen |
| `typescript` | ^5 | (prüfen) | ⚠️ Prüfen |
| `eslint` | ^9 | (prüfen) | ⚠️ Prüfen |
| `eslint-config-next` | 16.0.0 | **16.1.6** | ⬆️ Update verfügbar |

**Wichtige Hinweise zu Prisma 7.3.0**:
- ⚠️ **Breaking Changes**: Prisma 7 erfordert Node.js 20.19.0+ (aktuell: 20.20.0 ✅)
- ⚠️ **Breaking Changes**: TypeScript 5.4.0+ erforderlich
- ⚠️ **Breaking Changes**: ES Modules only (kein CommonJS mehr)
- ⚠️ **Schema-Änderung**: Generator muss von `prisma-client-js` zu `prisma-client` geändert werden
- ✅ **Performance**: Rust-Free Architecture, schnellere Runtime

**Empfehlung für npm Updates**:
```bash
cd /var/www/aam_playground
npm update next react react-dom pg eslint-config-next
# Prisma Update erfordert Schema-Anpassung - siehe Prisma 7 Migration Guide
```

---

## 🐳 Docker Image Updates

### Haupt-Container
| Image | Aktuell | Verfügbar | Status | Letztes Update |
|-------|---------|-----------|--------|----------------|
| `n8nio/n8n` | latest | **2.4.6** (stable) | ⬆️ Update verfügbar | 2026-01-23 |
| `caddy:2-alpine` | 2-alpine | **2.10.2-alpine** | ⬆️ **Großes Update** | 2026-01-16 |
| `axllent/mailpit` | latest | **v1.28.4** | ⬆️ Update verfügbar | (prüfen) |
| `node:20-alpine` | 20-alpine | (prüfen) | ⚠️ Prüfen | - |

### Supabase-Container
| Image | Aktuell | Verfügbar | Status | Letztes Update |
|-------|---------|-----------|--------|----------------|
| `supabase/studio` | 2025.11.10 | (prüfen) | ⚠️ Prüfen | 2025-11-10 |
| `supabase/realtime` | v2.63.0 | (prüfen) | ⚠️ Prüfen | 2025-11-09 |
| `supabase/storage-api` | v1.29.0 | (prüfen) | ⚠️ Prüfen | 2025-11-06 |
| `supabase/edge-runtime` | v1.69.23 | (prüfen) | ⚠️ Prüfen | 2025-11-06 |
| `supabase/gotrue` | v2.182.1 | (prüfen) | ⚠️ Prüfen | 2025-11-05 |
| `supabase/supavisor` | 2.7.4 | (prüfen) | ⚠️ Prüfen | 2025-10-28 |
| `supabase/postgres-meta` | v0.93.1 | (prüfen) | ⚠️ Prüfen | 2025-10-27 |
| `supabase/logflare` | 1.22.6 | (prüfen) | ⚠️ Prüfen | 2025-10-03 |
| `supabase/postgres` | 15.8.1.085 | (prüfen) | ⚠️ Prüfen | 2025-05-05 |
| `postgrest/postgrest` | v13.0.7 | (prüfen) | ⚠️ Prüfen | 2024-11-09 |
| `kong` | 2.8.1 | (prüfen) | ⚠️ Prüfen | 2022-10-06 |
| `darthsim/imgproxy` | v3.8.0 | (prüfen) | ⚠️ Prüfen | 2022-10-07 |
| `timberio/vector` | 0.28.1-alpine | (prüfen) | ⚠️ Prüfen | 2023-03-06 |

**Empfehlung für Docker Updates**:
```bash
# n8n auf spezifische Version setzen (Production)
# In docker-compose.yml: image: n8nio/n8n:2.4.6
docker pull n8nio/n8n:2.4.6

# Caddy Update
docker pull caddy:2.10.2-alpine
# In docker-compose.yml: image: caddy:2.10.2-alpine

# Mailpit Update
docker pull axllent/mailpit:v1.28.4
# In docker-compose.yml: image: axllent/mailpit:v1.28.4

# Alle Images neu pullen
docker compose pull
docker compose up -d --build
```

---

## ⚠️ Wichtige Hinweise

### Prisma 7 Migration
Wenn Prisma auf 7.3.0 aktualisiert werden soll, müssen folgende Schritte beachtet werden:

1. **Schema.prisma anpassen**:
   ```prisma
   generator client {
     provider = "prisma-client"  // statt "prisma-client-js"
     output   = "../app/generated/prisma"
   }
   ```

2. **Node.js Version prüfen**: ✅ 20.20.0 (erfüllt Anforderung 20.19.0+)

3. **TypeScript Version prüfen**: Aktuell ^5 (sollte 5.4.0+ sein)

4. **Migration durchführen**:
   ```bash
   npm install prisma@latest @prisma/client@latest @prisma/adapter-pg@latest
   npx prisma generate
   ```

### Next.js 16.1.6
- Enthält Bugfixes und Performance-Verbesserungen
- Keine Breaking Changes gegenüber 16.0.0
- Empfohlenes Update

### n8n 2.4.6
- Stabile Version empfohlen für Production
- Nicht `latest` Tag verwenden, sondern spezifische Version pinning
- Workflows bleiben erhalten (Daten in Volume)

### Caddy 2.10.2
- Großes Update von 2.x auf 2.10.2
- Sicherheits-Updates und Bugfixes
- Empfohlenes Update

---

## 📋 Update-Priorität

### 🔴 Hoch (Sicherheit & Stabilität)
1. Docker CE Update (29.1.5 → 29.2.0)
2. Caddy Update (2-alpine → 2.10.2-alpine)
3. n8n Update (latest → 2.4.6)

### 🟡 Mittel (Features & Performance)
1. Next.js Update (16.0.0 → 16.1.6)
2. React Updates (19.2.0 → 19.2.4)
3. pg Update (8.12.0 → 8.17.2)

### 🟢 Niedrig (Breaking Changes)
1. Prisma Update (7.0.0 → 7.3.0) - **Erfordert Migration**

---

## 🚀 Empfohlene Update-Reihenfolge

1. **System-Updates** (Docker CE)
   ```bash
   sudo apt update && sudo apt upgrade docker-ce docker-ce-cli docker-ce-rootless-extras
   ```

2. **Docker Images aktualisieren**
   ```bash
   cd /var/www/aam_playground
   # docker-compose.yml anpassen (n8n Version pinning, Caddy Version)
   docker compose pull
   docker compose up -d --build
   ```

3. **npm Packages aktualisieren** (ohne Prisma)
   ```bash
   npm update next react react-dom pg eslint-config-next
   npm run build  # Testen
   ```

4. **Prisma Update** (optional, wenn gewünscht)
   - Schema.prisma anpassen
   - Prisma Packages aktualisieren
   - `npx prisma generate` ausführen
   - Tests durchführen

---

## ✅ Nach Update-Checkliste

- [ ] Alle Container starten erfolgreich
- [ ] Health-Checks bestehen (`/api/health`)
- [ ] Next.js Build erfolgreich
- [ ] Prisma Migrations laufen durch
- [ ] n8n Workflows funktionieren
- [ ] Caddy Reverse Proxy funktioniert
- [ ] Datenbank-Verbindungen funktionieren

---

**Erstellt am**: 28. Januar 2026
**Nächste Prüfung empfohlen**: In 2-4 Wochen
