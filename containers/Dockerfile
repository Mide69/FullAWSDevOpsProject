# ---- Build stage ----
FROM node:20-alpine AS builder
WORKDIR /app
COPY app/package*.json ./
RUN npm ci --only=production

# ---- Runtime stage ----
FROM node:20-alpine AS runtime
RUN addgroup -S -g 10001 appgroup && adduser -S -u 10001 -G appgroup appuser
WORKDIR /app
COPY --from=builder /app/node_modules ./node_modules
COPY app/src ./src
USER 10001
EXPOSE 3000
HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
  CMD wget -qO- http://localhost:3000/health || exit 1
CMD ["node", "src/index.js"]
