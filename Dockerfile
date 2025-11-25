# syntax=docker/dockerfile:1.7-labs

FROM node:20-alpine AS deps
WORKDIR /app
COPY package.json package-lock.json* ./
RUN npm ci

FROM node:20-alpine AS builder
WORKDIR /app
ENV NEXT_TELEMETRY_DISABLED=1
COPY --from=deps /app/node_modules ./node_modules
COPY . .
# Generate Prisma client for build-time imports
RUN DATABASE_URL=postgresql://user:pass@localhost:5432/db npx prisma generate --schema=prisma/schema.prisma
RUN npm run build

FROM node:20-alpine AS runner
WORKDIR /app
ENV NODE_ENV=production
ENV PORT=3000
EXPOSE 3000
COPY --from=builder /app/.next/standalone ./
COPY --from=builder /app/.next/static ./.next/static
COPY --from=builder /app/app/generated ./app/generated
COPY --from=builder /app/public ./public
COPY --from=builder /app/prisma ./prisma
COPY prisma.config.js ./prisma.config.js
CMD ["sh", "-c", "npx prisma migrate deploy --schema=prisma/schema.prisma || echo 'Prisma migrate skipped (will not block app start)'; node server.js"]


