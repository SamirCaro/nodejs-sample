# ========================================
# Dockerfile multi-etapa optimizado
# AplicaciÃ³n Node.js TypeScript (usando DHI)
# ========================================

FROM dhi.io/node:24-alpine3.22-dev AS base

# Establecer el directorio de trabajo
WORKDIR /app

# Crear un usuario no root por seguridad
RUN addgroup -g 1001 -S nodejs && \
    adduser -S nodejs -u 1001 -G nodejs && \
    chown -R nodejs:nodejs /app

# ========================================
# Etapa de dependencias
# ========================================
FROM base AS deps

# Copiar archivos de paquete
COPY package*.json ./

# Instalar dependencias de producciÃ³n
RUN --mount=type=cache,target=/root/.npm,sharing=locked \
    npm ci --omit=dev && \
    npm cache clean --force

# Establecer la propiedad adecuada
RUN chown -R nodejs:nodejs /app

# ========================================
# Etapa de dependencias de construcciÃ³n
# ========================================
FROM base AS build-deps

# Copiar archivos de paquete
COPY package*.json ./

# Instalar todas las dependencias con optimizaciones de construcciÃ³n
RUN --mount=type=cache,target=/root/.npm,sharing=locked \
    npm ci --no-audit --no-fund && \
    npm cache clean --force

# Crear los directorios necesarios y establecer permisos
RUN mkdir -p /app/node_modules/.vite && \
    chown -R nodejs:nodejs /app

# ========================================
# Etapa de construcciÃ³n
# ========================================
FROM build-deps AS build

# Copiar solo los archivos necesarios para la construcciÃ³n (respeta .dockerignore)
COPY --chown=nodejs:nodejs . .

# Construir la aplicaciÃ³n
RUN npm run build

# Establecer la propiedad adecuada
RUN chown -R nodejs:nodejs /app

# ========================================
# Etapa de desarrollo
# ========================================
FROM build-deps AS development

# Establecer el entorno
ENV NODE_ENV=development \
    NPM_CONFIG_LOGLEVEL=warn

# Copiar archivos fuente
COPY . .

# Asegurar que todos los directorios tengan los permisos adecuados
RUN mkdir -p /app/node_modules/.vite && \
    chown -R nodejs:nodejs /app && \
    chmod -R 755 /app

# Cambiar a usuario no root
USER nodejs

# Exponer puertos
EXPOSE 3000 5173 9229

# Iniciar el servidor de desarrollo
CMD ["npm", "run", "dev:docker"]

# ========================================
# Etapa de producciÃ³n
# ========================================
FROM dhi.io/node:24-alpine3.22-dev AS production

# Establecer el directorio de trabajo
WORKDIR /app

# Crear un usuario no root por seguridad
RUN addgroup -g 1001 -S nodejs && \
    adduser -S nodejs -u 1001 -G nodejs && \
    chown -R nodejs:nodejs /app

# Establecer variables de entorno optimizadas
ENV NODE_ENV=production \
    NODE_OPTIONS="--max-old-space-size=256 --no-warnings" \
    NPM_CONFIG_LOGLEVEL=silent

# Copiar las dependencias de producciÃ³n desde la etapa deps
COPY --from=deps --chown=nodejs:nodejs /app/node_modules ./node_modules
COPY --from=deps --chown=nodejs:nodejs /app/package*.json ./
# Copiar la aplicaciÃ³n construida desde la etapa build
COPY --from=build --chown=nodejs:nodejs /app/dist ./dist

# Cambiar a usuario no root por seguridad
USER nodejs

# Exponer puerto
EXPOSE 3000

# Iniciar el servidor de producciÃ³n
CMD ["node", "dist/server.js"]

# ========================================
# Etapa de pruebas
# ========================================
FROM build-deps AS test

# Establecer el entorno
ENV NODE_ENV=test \
    CI=true

# Copiar archivos fuente
COPY --chown=nodejs:nodejs . .

# Cambiar a usuario no root
USER nodejs

# Ejecutar pruebas con cobertura
CMD ["npm", "run", "test:coverage"]