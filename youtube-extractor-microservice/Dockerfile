# Production-ready container: Node.js 20 + yt-dlp + ffmpeg on Alpine
FROM node:20-alpine

# Install runtime dependencies
RUN apk add --no-cache \
    python3 \
    ffmpeg \
    ca-certificates \
    curl \
    && update-ca-certificates

# Download and install yt-dlp binary (Linux)
RUN curl -fsSL https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp \
    -o /usr/local/bin/yt-dlp \
    && chmod a+rx /usr/local/bin/yt-dlp \
    && yt-dlp --version

WORKDIR /app

# Install Node dependencies first (layer caching)
COPY package*.json ./
RUN npm install --omit=dev --no-audit --no-fund

# Copy application source (excludes files in .dockerignore)
COPY . .

# Remove Windows binary — only Linux yt-dlp is used in container
RUN rm -f yt-dlp.exe

EXPOSE 3000

ENV PORT=3000
ENV NODE_ENV=production

# Healthcheck so Render marks service healthy
HEALTHCHECK --interval=30s --timeout=10s --start-period=15s --retries=3 \
    CMD curl -f http://localhost:3000/health || exit 1

CMD ["node", "server.js"]
