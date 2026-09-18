# Production-ready container: Node.js 22 + Deno 2.3 + yt-dlp + ffmpeg
FROM node:22-bookworm-slim

# Install runtime dependencies
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl ffmpeg unzip \
    && rm -rf /var/lib/apt/lists/*

ARG DENO_VERSION=2.3.6
RUN curl -fsSL "https://github.com/denoland/deno/releases/download/v${DENO_VERSION}/deno-x86_64-unknown-linux-gnu.zip" -o /tmp/deno.zip \
    && unzip /tmp/deno.zip -d /usr/local/bin \
    && chmod a+rx /usr/local/bin/deno \
    && rm /tmp/deno.zip \
    && deno --version

# Download and install yt-dlp binary (Linux)
ARG YTDLP_VERSION=2026.08.19
RUN curl -fsSL "https://github.com/yt-dlp/yt-dlp/releases/download/${YTDLP_VERSION}/yt-dlp" \
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
ENV YTDLP_JS_RUNTIME=/usr/local/bin/deno

# Healthcheck so Render marks service healthy
HEALTHCHECK --interval=30s --timeout=10s --start-period=15s --retries=3 \
    CMD curl -f http://localhost:3000/health || exit 1

CMD ["node", "server.js"]
