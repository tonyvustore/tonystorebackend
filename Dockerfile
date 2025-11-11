# Production Dockerfile (multi-stage) for Vendure backend
# - Stage 1: build TypeScript to dist
# - Stage 2: runtime with only production deps

FROM node:20-bullseye AS build
WORKDIR /usr/src/app

# Install system dependencies needed for sharp/image processing (Vendure assets)
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    python3 \
    libvips \
 && rm -rf /var/lib/apt/lists/*

# Install dependencies
COPY package.json yarn.lock ./
RUN yarn install --frozen-lockfile

# Copy source
COPY tsconfig.json ./
COPY src ./src
COPY scripts ./scripts
COPY migrations ./migrations
COPY static ./static

# Build
RUN yarn build

# Ensure email templates exist in dist for production runtime
RUN mkdir -p dist/static/email/templates && cp -R node_modules/@vendure/email-plugin/templates/* dist/static/email/templates/

# Optional: prune dev deps to production-only in a separate step
RUN yarn install --frozen-lockfile --production

# --- Runtime image ---
FROM node:20-bullseye-slim AS runtime
WORKDIR /usr/src/app

# Install runtime libs for sharp
RUN apt-get update && apt-get install -y --no-install-recommends libvips \
 && rm -rf /var/lib/apt/lists/*

ENV NODE_ENV=production

# Copy app
COPY --from=build /usr/src/app/package.json ./package.json
COPY --from=build /usr/src/app/yarn.lock ./yarn.lock
COPY --from=build /usr/src/app/node_modules ./node_modules
COPY --from=build /usr/src/app/dist ./dist
COPY --from=build /usr/src/app/static ./static
# Ensure scripts and migrations are available for runtime tasks like migrations
COPY --from=build /usr/src/app/scripts ./scripts
COPY --from=build /usr/src/app/migrations ./migrations

# Expose Vendure default port
EXPOSE 3000

# Default command (server). Worker command is set in compose.
CMD [ "node", "dist/src/index.js" ]
