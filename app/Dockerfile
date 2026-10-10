# Build: client (Vite) + server (tsc). Runtime: production deps only, non-root.
FROM node:24-slim AS build
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci
COPY . .
RUN npm run build && npm prune --omit=dev

FROM node:24-slim
ENV NODE_ENV=production PORT=8080
WORKDIR /app
COPY --from=build /app/node_modules ./node_modules
COPY --from=build /app/dist ./dist
COPY --from=build /app/client/dist ./client/dist
COPY --from=build /app/package.json ./
COPY queries ./queries
USER node
EXPOSE 8080
CMD ["node", "dist/server/index.js"]
