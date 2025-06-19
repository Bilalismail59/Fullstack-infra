# Build stage
FROM node:20-alpine as builder

WORKDIR /app

# Installation des dépendances de build
RUN apk add --no-cache git python3 make g++

COPY package.json pnpm-lock.yaml ./
RUN npm install -g pnpm && \
    pnpm install --frozen-lockfile --prod

COPY . .
RUN pnpm run build

# Production stage
FROM nginxinc/nginx-unprivileged:alpine

COPY --from=builder /app/dist /usr/share/nginx/html
COPY nginx.conf /etc/nginx/conf.d/default.conf

# Suppression des fichiers inutiles
RUN rm -rf /usr/share/nginx/html/*.map

EXPOSE 8080

USER nginx