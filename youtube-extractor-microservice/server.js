const express = require('express');
const cors = require('cors');
const path = require('path');
const os = require('os');
const fs = require('fs');
const { spawn, execFile } = require('child_process');
const axios = require('axios');
require('dotenv').config();

process.on('uncaughtException', (error) => {
  console.error('[Process] Uncaught exception:', error);
});

process.on('unhandledRejection', (reason) => {
  console.error('[Process] Unhandled rejection:', reason);
});

const app = express();
const PORT = process.env.PORT || 3000;
app.use(cors());
app.use(express.json());

// YouTube URL Validation Pattern (supports watch, shorts, embed, youtu.be, music.youtube, m.youtube, and playlists/mixes)
const YOUTUBE_REGEX = /^(https?:\/\/)?(www\.|music\.|m\.)?(youtube\.com\/(watch\?.*v=|shorts\/|live\/|v\/|embed\/|playlist\?)|youtu\.be\/)([a-zA-Z0-9_\-\?&=%#\.\+]+)$/i;

// Path to bundled yt-dlp binary (Windows and Linux / Cloud Container)
const LOCAL_YTDLP = path.join(__dirname, process.platform === 'win32' ? 'yt-dlp.exe' : 'yt-dlp');
const YTDLP_BIN = fs.existsSync(LOCAL_YTDLP) ? LOCAL_YTDLP : 'yt-dlp';

// Render can provide an authenticated Netscape cookie file through a secret.
// Prefer YOUTUBE_COOKIES_BASE64 so credentials are never committed or logged.
const COOKIE_RUNTIME_PATH = path.join(os.tmpdir(), 'aura-youtube-cookies.txt');
let ytCookiesPath = null;

function prepareYtDlpCookies() {
  const configuredFile = process.env.YOUTUBE_COOKIES_FILE?.trim();
  if (configuredFile && fs.existsSync(configuredFile)) {
    ytCookiesPath = configuredFile;
    return;
  }

  const encodedCookies = process.env.YOUTUBE_COOKIES_BASE64?.trim();
  if (!encodedCookies) return;

  try {
    const decodedCookies = Buffer.from(encodedCookies, 'base64');
    if (decodedCookies.length === 0) throw new Error('empty cookie payload');
    fs.writeFileSync(COOKIE_RUNTIME_PATH, decodedCookies, { mode: 0o600 });
    ytCookiesPath = COOKIE_RUNTIME_PATH;
  } catch (error) {
    console.warn(`[YouTube] Cookie secret could not be loaded: ${error.message}`);
  }
}

prepareYtDlpCookies();

function ytDlpCommonArgs() {
  const args = [
    '--remote-components', 'ejs:github',
    '--extractor-args', 'youtube:player_client=tv_embedded,mweb,android,ios',
    '--extractor-args', 'youtube:player_skip=webpage,configs',
  ];
  if (ytCookiesPath) args.push('--cookies', ytCookiesPath);
  return args;
}

// Helper to clean, sanitize, and re-format YouTube Mix / Radio & Standard URLs
function normalizeYouTubeUrl(inputUrl) {
  try {
    const trimmed = inputUrl.trim();
    const videoId = extractVideoId(trimmed);
    if (videoId && STRICT_VIDEO_ID_REGEX.test(videoId)) {
      return `https://www.youtube.com/watch?v=${videoId}`;
    }

    const urlObj = new URL(trimmed.startsWith('http') ? trimmed : `https://${trimmed}`);
    
    // Check if link contains a Mix / Radio playlist (list starts with 'RD')
    const listParam = urlObj.searchParams.get('list');
    
    if (listParam && listParam.startsWith('RD')) {
      let mixId = urlObj.searchParams.get('v');
      if (!mixId) {
        mixId = listParam.replace(/^(RDMM|RDCL|RD)/, '');
      }
      return `https://www.youtube.com/watch?v=${mixId}`;
    }

    // Check if standard playlist link has a direct video parameter
    if (urlObj.pathname.includes('playlist')) {
      const v = urlObj.searchParams.get('v');
      if (v) {
        return `https://www.youtube.com/watch?v=${v}`;
      }
    }

    // Strip unnecessary tracking and playlist parameters to prevent drift
    urlObj.searchParams.delete('list');
    urlObj.searchParams.delete('playnext');
    urlObj.searchParams.delete('si');
    urlObj.searchParams.delete('feature');
    urlObj.searchParams.delete('pp');
    urlObj.searchParams.delete('index');
    urlObj.searchParams.delete('start_radio');
    
    return urlObj.toString();
  } catch (err) {
    return inputUrl; // Fallback to raw string if parsing fails
  }
}

/**
 * Deep clean track title: strips emojis, handles, hashtags, video tags, status fluff
 */
function cleanTrackTitle(rawTitle) {
  if (!rawTitle) return 'YouTube Audio Track';
  return rawTitle
    .replace(/[\u{1F300}-\u{1F9FF}]|[\u{2600}-\u{26FF}]|[\u{2700}-\u{27BF}]|[\u{1F600}-\u{1F64F}]|[\u{1F680}-\u{1F6FF}]|[\u{1F1E0}-\u{1F1FF}]|[\u{1FA70}-\u{1FAFF}]|[\u{200D}\u{FE0F}]/gu, '')
    .replace(/#[\w\u0900-\u097F\u0980-\u09FF]+/g, '')
    .replace(/@[\w\u0900-\u097F\u0980-\u09FF_.]+/g, '')
    .replace(/\[\s*(Official\s*(Music\s*)?Video|Audio|HD|4K|Lyrics|Visualizer|Live|Full Song|Video Song|Audio Song|Video|Status|Bengali Status|WhatsApp Status|Lyrical)\s*\]/gi, '')
    .replace(/\(\s*(Official\s*(Music\s*)?Video|Audio|HD|4K|Lyrics|Visualizer|Live|Full Song|Video Song|Audio Song|Video|Status|Bengali Status|WhatsApp Status|Lyrical)\s*\)/gi, '')
    .replace(/\|\s*(Official\s*(Music\s*)?Video|Audio|HD|4K|Lyrics|Visualizer|Live|Full Song|Status|WhatsApp|Bengali).*$/gi, '')
    .replace(/\|\|.*$/g, '')
    .replace(/【.*?】/g, '')
    .replace(/\s+/g, ' ')
    .trim();
}

/**
 * Extract clean query words suitable for high-accuracy search matchers
 */
function extractCleanSongQuery(rawTitle, rawArtist) {
  let cleaned = cleanTrackTitle(rawTitle);
  // Remove trailing pipe sections or parentheses
  cleaned = cleaned.replace(/\|.*$/, '').replace(/\[.*?\]/g, '').replace(/\(.*?\)/g, '').trim();
  if (cleaned.includes(' - ')) {
    const parts = cleaned.split(' - ');
    return `${parts[0].trim()} ${parts[1].trim()}`;
  }
  if (rawArtist && !cleaned.toLowerCase().includes(rawArtist.toLowerCase())) {
    return `${cleaned} ${rawArtist}`.trim();
  }
  return cleaned;
}

/**
 * Token-based title similarity score between 0.0 and 1.0
 */
function calculateTitleSimilarity(query, candidateTitle) {
  if (!query || !candidateTitle) return 0;
  const qTokens = query.toLowerCase().replace(/[^a-z0-9\u0900-\u097F\u0980-\u09FF]/g, ' ').split(/\s+/).filter(t => t.length >= 2);
  const cTokens = candidateTitle.toLowerCase().replace(/[^a-z0-9\u0900-\u097F\u0980-\u09FF]/g, ' ').split(/\s+/).filter(t => t.length >= 2);
  if (qTokens.length === 0 || cTokens.length === 0) return 0;

  let matches = 0;
  for (const qt of qTokens) {
    if (cTokens.some(ct => ct === qt || ct.includes(qt) || qt.includes(ct))) {
      matches++;
    }
  }
  return matches / qTokens.length;
}

const STRICT_VIDEO_ID_REGEX = /^[a-zA-Z0-9_\-]{11}$/;

/**
 * Extract strict 11-character YouTube Video ID from any supported format
 */
function extractVideoId(url) {
  if (!url) return null;
  const trimmed = url.trim();
  if (STRICT_VIDEO_ID_REGEX.test(trimmed)) return trimmed;

  const normalized = normalizeYouTubeUrl(trimmed);
  const match1 = normalized.match(/(?:watch\?v=|youtu\.be\/|shorts\/|embed\/|v\/)([a-zA-Z0-9_\-]{11})/);
  if (match1 && match1[1] && STRICT_VIDEO_ID_REGEX.test(match1[1])) return match1[1];
  
  const match2 = url.match(/(?:list=(?:RDMM|RDCL|RD))([a-zA-Z0-9_\-]{11})/);
  if (match2 && match2[1] && STRICT_VIDEO_ID_REGEX.test(match2[1])) return match2[1];

  const match3 = url.match(/(?:v=)([a-zA-Z0-9_\-]{11})/);
  if (match3 && match3[1] && STRICT_VIDEO_ID_REGEX.test(match3[1])) return match3[1];
  
  return null;
}

/**
 * Calculate estimated size in MB given bitrate in kbps and duration in seconds
 */
function estimateSizeMb(bitrateKbps, durationSec) {
  if (!bitrateKbps || !durationSec) return '3.5 MB';
  const totalBits = bitrateKbps * 1000 * durationSec;
  const totalBytes = totalBits / 8;
  const sizeMb = (totalBytes / (1024 * 1024)).toFixed(1);
  return `${sizeMb} MB`;
}

/**
 * Health check
 */
app.get('/health', (req, res) => {
  res.json({
    status: 'online',
    service: 'Aura Player YouTube Extractor Microservice',
    engine: `yt-dlp (${YTDLP_BIN})`,
    ytDlpCookiesConfigured: Boolean(ytCookiesPath),
    supportedQualities: ['High (320 kbps)', 'Medium (128 kbps)', 'Data Saver (64 kbps)'],
    timestamp: new Date().toISOString()
  });
});

/**
 * MODULE 1 - Endpoint 1: POST /api/youtube/extract
 * Extracts audio streams, metadata, and standardized Multi-Format Quality Tiers
 */
app.post('/api/youtube/extract', async (req, res) => {
  try {
    const { url } = req.body;

    if (!url || typeof url !== 'string') {
      return res.status(400).json({ error: 'Missing or invalid "url" parameter in request body' });
    }

    const trimmedUrl = url.trim();
    const cleanUrl = normalizeYouTubeUrl(trimmedUrl);
    if (!YOUTUBE_REGEX.test(trimmedUrl) && !YOUTUBE_REGEX.test(cleanUrl)) {
      return res.status(400).json({ error: 'Provided URL is not a valid YouTube, YouTube Music, or youtu.be link' });
    }

    const videoId = extractVideoId(cleanUrl) || extractVideoId(trimmedUrl);
    const targetUrl = videoId ? `https://www.youtube.com/watch?v=${videoId}` : cleanUrl;

    console.log(`[Extractor] 🔍 Resolving multi-format audio streams with yt-dlp for: ${targetUrl} (ID: ${videoId})`);

    // yt-dlp dump-single-json to parse full format list without re-encoding
    const ytDlpArgs = [
      '--dump-single-json',
      '--no-warnings',
      '--no-playlist',
      '--no-check-certificates',
      '-f', 'bestaudio/140/251/139/best',
      ...ytDlpCommonArgs(),
      '--',
      targetUrl
    ];

    execFile(YTDLP_BIN, ytDlpArgs, { maxBuffer: 100 * 1024 * 1024, timeout: 60000 }, async (error, stdout, stderr) => {
      if (!error && stdout) {
        try {
          const info = JSON.parse(stdout);
          const rawTitle = info.title || 'YouTube Audio';
          const cleanTitle = cleanTrackTitle(rawTitle);
          const artistName = info.artist || info.uploader || info.channel || 'YouTube Artist';
          const durationSec = Math.round(Number(info.duration) || 0) || 180;
          const thumbnail = info.thumbnail || `https://i.ytimg.com/vi/${videoId}/hqdefault.jpg`;

          // Filter out audio-only streams or video formats with audio
          const formats = Array.isArray(info.formats) ? info.formats : [];
          const audioFormats = formats.filter(f => f.acodec && f.acodec !== 'none' && f.url);

          // Sort descending by audio bitrate (abr)
          audioFormats.sort((a, b) => (b.abr || 0) - (a.abr || 0));

          // 1. High Quality Tier (HQ: 256kbps - 320kbps or best available)
          const hqStream = audioFormats.find(f => (f.abr && f.abr >= 160) || f.format_id === '140' || f.ext === 'm4a') || audioFormats[0] || { url: info.url, format_id: '140', abr: 320, ext: 'm4a' };

          // 2. Medium Quality Tier (MQ: 128kbps - 160kbps)
          const mqStream = audioFormats.find(f => f.abr && f.abr >= 96 && f.abr <= 160) || audioFormats.find(f => f.format_id === '139') || hqStream;

          // 3. Low Quality / Data Saver Tier (LQ: 48kbps - 64kbps)
          const lqStream = audioFormats.slice().reverse().find(f => (f.abr && f.abr <= 80) || f.format_id === '249' || f.format_id === '599') || audioFormats.find(f => f.format_id === '249') || mqStream;

          const availableFormats = [
            {
              quality: 'High',
              bitrate: hqStream.abr ? `${Math.round(hqStream.abr)} kbps` : '320 kbps',
              format: hqStream.ext || 'm4a',
              estimatedSizeMb: estimateSizeMb(hqStream.abr || 320, durationSec),
              streamUrl: hqStream.url || info.url,
              formatId: hqStream.format_id || '140'
            },
            {
              quality: 'Medium',
              bitrate: mqStream.abr ? `${Math.round(mqStream.abr)} kbps` : '128 kbps',
              format: mqStream.ext || 'm4a',
              estimatedSizeMb: estimateSizeMb(mqStream.abr || 128, durationSec),
              streamUrl: mqStream.url || hqStream.url || info.url,
              formatId: mqStream.format_id || '139'
            },
            {
              quality: 'Data Saver',
              bitrate: lqStream.abr ? `${Math.round(lqStream.abr)} kbps` : '64 kbps',
              format: lqStream.ext || 'm4a',
              estimatedSizeMb: estimateSizeMb(lqStream.abr || 64, durationSec),
              streamUrl: lqStream.url || mqStream.url || info.url,
              formatId: lqStream.format_id || '249'
            }
          ];

          const payloadResponse = {
            id: `yt_${videoId}`,
            title: cleanTitle,
            artist: artistName,
            album: 'YouTube Imports',
            duration: durationSec,
            thumbnailUrl: thumbnail,
            streamUrl: availableFormats[0].streamUrl,
            availableFormats: availableFormats,
            isYoutubeImport: true
          };

          console.log(`[Extractor] ✅ Multi-format resolved for "${payloadResponse.title}" (${availableFormats.length} quality tiers)`);
          return res.json(payloadResponse);
        } catch (parseErr) {
          console.warn(`[Extractor] ⚠️ yt-dlp json parse warning: ${parseErr.message}`);
        }
      }

      console.warn(`[Extractor] ⚠️ yt-dlp failed or timed out (${error?.message || stderr}). Trying Piped & Invidious streaming fallback...`);

      // Strategy 2: Multi-Instance Piped & Invidious API Fallback
      const streamingInstances = [
        { url: 'https://pipedapi.leptons.xyz', type: 'piped' },
        { url: 'https://piped-api.lunar.icu', type: 'piped' },
        { url: 'https://api.piped.privacydev.net', type: 'piped' },
        { url: 'https://pipedapi.tokhmi.xyz', type: 'piped' },
        { url: 'https://inv.tux.pizza/api/v1/videos', type: 'invidious' },
        { url: 'https://invidious.nerdvpn.de/api/v1/videos', type: 'invidious' },
      ];

      for (const instance of streamingInstances) {
        try {
          if (instance.type === 'piped') {
            const pipedRes = await axios.get(`${instance.url}/streams/${videoId}`, { timeout: 6000 });
            if (pipedRes.data && pipedRes.data.audioStreams && pipedRes.data.audioStreams.length > 0) {
              const streams = pipedRes.data.audioStreams;
              const title = cleanTrackTitle(pipedRes.data.title || 'YouTube Audio');
              const uploader = pipedRes.data.uploader || 'YouTube Artist';
              const durationSec = pipedRes.data.duration || 180;
              const thumbnail = pipedRes.data.thumbnailUrl || `https://i.ytimg.com/vi/${videoId}/hqdefault.jpg`;

              const formats = streams.map(st => {
                const abr = st.bitrate ? Math.round(st.bitrate / 1000) : 128;
                const qualityTier = abr >= 160 ? 'High' : (abr >= 96 ? 'Medium' : 'Data Saver');
                return {
                  quality: qualityTier,
                  bitrate: `${abr} kbps`,
                  format: (st.format || 'm4a').toLowerCase().replace('webm', 'opus'),
                  estimatedSizeMb: estimateSizeMb(abr, durationSec),
                  streamUrl: st.url,
                  formatId: String(st.format || '140')
                };
              });

              const payloadResponse = {
                id: `yt_${videoId}`,
                title: title,
                artist: uploader,
                album: 'YouTube Imports',
                duration: durationSec,
                thumbnailUrl: thumbnail,
                streamUrl: formats[0].streamUrl,
                availableFormats: formats,
                isYoutubeImport: true
              };

              console.log(`[Extractor] ⚡ Resolved via Piped instance (${instance.url}) for "${title}"`);
              return res.json(payloadResponse);
            }
          } else if (instance.type === 'invidious') {
            const invRes = await axios.get(`${instance.url}/${videoId}`, { timeout: 6000 });
            if (invRes.data && invRes.data.adaptiveFormats && invRes.data.adaptiveFormats.length > 0) {
              const audioFormats = invRes.data.adaptiveFormats.filter(f => f.type && f.type.startsWith('audio/'));
              if (audioFormats.length > 0) {
                const title = cleanTrackTitle(invRes.data.title || 'YouTube Audio');
                const author = invRes.data.author || 'YouTube Artist';
                const durationSec = invRes.data.lengthSeconds || 180;
                const thumbnail = `https://i.ytimg.com/vi/${videoId}/hqdefault.jpg`;

                const formats = audioFormats.map(st => {
                  const abr = st.bitrate ? Math.round(st.bitrate / 1000) : 128;
                  const qualityTier = abr >= 160 ? 'High' : (abr >= 96 ? 'Medium' : 'Data Saver');
                  return {
                    quality: qualityTier,
                    bitrate: `${abr} kbps`,
                    format: (st.container || 'm4a').toLowerCase().replace('webm', 'opus'),
                    estimatedSizeMb: estimateSizeMb(abr, durationSec),
                    streamUrl: st.url,
                    formatId: String(st.itag || '140')
                  };
                });

                const payloadResponse = {
                  id: `yt_${videoId}`,
                  title: title,
                  artist: author,
                  album: 'YouTube Imports',
                  duration: durationSec,
                  thumbnailUrl: thumbnail,
                  streamUrl: formats[0].streamUrl,
                  availableFormats: formats,
                  isYoutubeImport: true
                };

                console.log(`[Extractor] ⚡ Resolved via Invidious instance (${instance.url}) for "${title}"`);
                return res.json(payloadResponse);
              }
            }
          }
        } catch (streamErr) {}
      }

      console.warn(`[Extractor] ⚠️ Piped & Invidious failed. Trying YouTube oEmbed + JioSaavn fallback...`);

      // Strategy 3: YouTube oEmbed + High-Accuracy JioSaavn Matcher
      try {
        const oembedRes = await axios.get('https://www.youtube.com/oembed', {
          params: { url: targetUrl, format: 'json' },
          timeout: 4000
        });

        if (oembedRes.data && oembedRes.data.title) {
          const rawTitle = oembedRes.data.title;
          const cleanTitle = cleanTrackTitle(rawTitle);
          const authorName = oembedRes.data.author_name || 'YouTube Artist';
          const cleanQuery = extractCleanSongQuery(rawTitle, authorName);

          console.log(`[Extractor] 🔎 Searching JioSaavn for clean extracted query: "${cleanQuery}"`);

          const saavnRes = await axios.get('https://www.jiosaavn.com/api.php', {
            params: {
              __call: 'search.getResults',
              _format: 'json',
              _marker: '0',
              api_version: '4',
              ctx: 'web6dot0',
              n: '10',
              p: '1',
              q: cleanQuery
            },
            timeout: 5000
          });

          const results = saavnRes.data?.results || [];
          if (results.length > 0) {
            // Find best matching song by title similarity
            let bestMatch = null;
            let highestSim = 0;

            for (const candidate of results) {
              const candTitle = cleanTrackTitle(candidate.title || candidate.song || '');
              const sim = calculateTitleSimilarity(cleanQuery, candTitle);
              if (sim > highestSim) {
                highestSim = sim;
                bestMatch = candidate;
              }
            }

            // Accept match only if similarity score is adequate (>= 0.40)
            if (bestMatch && highestSim >= 0.40) {
              const encryptedMediaUrl = bestMatch.more_info?.encrypted_media_url;
              let streamUrl = null;

              if (encryptedMediaUrl) {
                const authRes = await axios.get('https://www.jiosaavn.com/api.php', {
                  params: {
                    __call: 'song.generateAuthToken',
                    _format: 'json',
                    bitrate: '320',
                    url: encryptedMediaUrl,
                    api_version: '4',
                    ctx: 'web6dot0'
                  },
                  timeout: 4000
                });
                streamUrl = authRes.data?.auth_url;
              }

              const durationSec = parseInt(bestMatch.more_info?.duration, 10) || 180;
              const availableFormats = [
                {
                  quality: 'High',
                  bitrate: '320 kbps',
                  format: 'mp4',
                  estimatedSizeMb: estimateSizeMb(320, durationSec),
                  streamUrl: streamUrl,
                  formatId: '320'
                },
                {
                  quality: 'Medium',
                  bitrate: '128 kbps',
                  format: 'mp4',
                  estimatedSizeMb: estimateSizeMb(128, durationSec),
                  streamUrl: streamUrl,
                  formatId: '128'
                },
                {
                  quality: 'Data Saver',
                  bitrate: '64 kbps',
                  format: 'mp4',
                  estimatedSizeMb: estimateSizeMb(64, durationSec),
                  streamUrl: streamUrl,
                  formatId: '64'
                }
              ];

              const payloadResponse = {
                id: `yt_${videoId}`,
                source: 'jiosaavn-fallback',
                title: cleanTitle,
                artist: bestMatch.more_info?.music || authorName,
                album: bestMatch.more_info?.album || 'YouTube Imports',
                duration: durationSec,
                thumbnailUrl: bestMatch.image?.replace('150x150', '500x500') || `https://i.ytimg.com/vi/${videoId}/hqdefault.jpg`,
                streamUrl: streamUrl,
                availableFormats: availableFormats,
                isYoutubeImport: true
              };

              console.log(`[Extractor] ✅ Resolved via verified JioSaavn match (${Math.round(highestSim * 100)}% match): "${bestMatch.title}" -> "${payloadResponse.title}"`);
              return res.json(payloadResponse);
            } else {
              console.warn(`[Extractor] ⚠️ JioSaavn candidate did not match "${cleanQuery}" (similarity: ${highestSim.toFixed(2)}). Refusing unrelated song replacement.`);
            }
          }
        }
      } catch (fallbackErr) {
        console.warn(`[Extractor] ⚠️ JioSaavn fallback failed: ${fallbackErr.message}`);
      }

      return res.status(502).json({ error: 'All stream extraction providers failed to resolve direct audio URL.' });
    });

  } catch (err) {
    console.error(`[Extractor] 💥 Unexpected error: ${err.message}`);
    return res.status(500).json({ error: 'Internal server error', details: err.message });
  }
});

/**
 * MODULE 1 - Endpoint 2: GET /api/youtube/download
 * Streams the requested bitrate binary with formatId or quality selector
 */
app.get('/api/youtube/download', async (req, res) => {
  try {
    const rawUrl = req.query.url || (req.query.id ? `https://www.youtube.com/watch?v=${req.query.id.replace(/^yt_/, '')}` : null);
    const formatId = req.query.formatId;
    const quality = req.query.quality; // 'High', 'Medium', 'Data Saver'
    const suppliedStreamUrl = req.query.streamUrl;

    if (!rawUrl || typeof rawUrl !== 'string') {
      return res.status(400).json({ error: 'Missing required "url" or "id" query parameter' });
    }

    const trimmedUrl = rawUrl.trim();
    const cleanUrl = normalizeYouTubeUrl(trimmedUrl);
    if (!YOUTUBE_REGEX.test(trimmedUrl) && !YOUTUBE_REGEX.test(cleanUrl)) {
      return res.status(400).json({ error: 'Provided URL is not a valid YouTube URL' });
    }

    const videoId = extractVideoId(cleanUrl) || extractVideoId(trimmedUrl) || 'audio_track';
    const targetUrl = videoId !== 'audio_track'
      ? `https://www.youtube.com/watch?v=${videoId}`
      : cleanUrl;
    const customTitle = req.query.title ? cleanTrackTitle(req.query.title) : `yt_${videoId}`;

    const outputExtension = formatId === '249' || formatId === '251' ||
      (!formatId && (quality === 'Data Saver' || quality === 'Low')) ? 'webm' : 'm4a';
    const sanitizedFileName = encodeURIComponent(`${customTitle}.${outputExtension}`);

    // Fast-path 0: Direct proxy if a valid streamUrl was supplied in query
    if (suppliedStreamUrl && typeof suppliedStreamUrl === 'string' && suppliedStreamUrl.startsWith('http') && !suppliedStreamUrl.includes('youtube.com/watch')) {
      console.log(`[Downloader] ⚡ Streaming via supplied streamUrl for: ${targetUrl}`);
      try {
        const directRes = await axios.get(suppliedStreamUrl, {
          responseType: 'stream',
          timeout: 120000,
          headers: {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
            'Accept': '*/*'
          }
        });

        res.setHeader('Content-Type', directRes.headers['content-type'] || (outputExtension === 'webm' ? 'audio/webm' : 'audio/mp4'));
        if (directRes.headers['content-length']) {
          res.setHeader('Content-Length', directRes.headers['content-length']);
        }
        res.setHeader('Content-Disposition', `attachment; filename="${sanitizedFileName}"; filename*=UTF-8''${sanitizedFileName}`);
        res.setHeader('Accept-Ranges', 'bytes');
        directRes.data.pipe(res);
        return;
      } catch (directErr) {
        console.warn(`[Downloader] ⚠️ Supplied streamUrl failed (${directErr.message}), falling back to stream resolver...`);
      }
    }

    let formatFilter = 'bestaudio/140/251/139';
    if (formatId && formatId !== 'undefined') {
      formatFilter = `${formatId}/${formatFilter}`;
    } else if (quality === 'Data Saver' || quality === 'Low') {
      formatFilter = '249/139/bestaudio';
    } else if (quality === 'Medium') {
      formatFilter = '139/140/bestaudio';
    } else {
      formatFilter = 'bestaudio/140/251/139';
    }

    console.log(`[Downloader] ⬇️ Streaming audio (${formatFilter}) for: ${targetUrl} (File: ${sanitizedFileName})`);

    // Strategy 1: Resolve direct audio stream URL with yt-dlp -g
    execFile(YTDLP_BIN, [
      ...ytDlpCommonArgs(),
      '-f', formatFilter,
      '-g',
      '--no-playlist',
      '--no-warnings',
      '--',
      targetUrl
    ], { timeout: 35000 }, async (err, stdout, stderr) => {
      if (!err && stdout && stdout.trim().startsWith('http')) {
        const directAudioUrl = stdout.trim().split('\n')[0].trim();
        console.log(`[Downloader] 🎯 Resolved direct audio CDN URL via yt-dlp for: ${targetUrl}`);

        try {
          const response = await axios.get(directAudioUrl, {
            responseType: 'stream',
            timeout: 120000,
            headers: {
              'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
              'Accept': '*/*'
            }
          });

          res.setHeader('Content-Type', response.headers['content-type'] || (outputExtension === 'webm' ? 'audio/webm' : 'audio/mp4'));
          if (response.headers['content-length']) {
            res.setHeader('Content-Length', response.headers['content-length']);
          }
          res.setHeader('Content-Disposition', `attachment; filename="${sanitizedFileName}"; filename*=UTF-8''${sanitizedFileName}`);
          res.setHeader('Accept-Ranges', 'bytes');

          response.data.pipe(res);
          return;
        } catch (proxyErr) {
          console.warn(`[Downloader] ⚠️ Proxy stream redirecting directly: ${proxyErr.message}`);
          return res.redirect(directAudioUrl);
        }
      }

      // Strategy 2: Fallback to Piped stream proxy
      const pipedInstances = [
        'https://pipedapi.kavin.rocks',
        'https://api.piped.private.coffee',
        'https://pipedapi.leptons.xyz'
      ];

      for (const instance of pipedInstances) {
        try {
          const pipedRes = await axios.get(`${instance}/streams/${videoId}`, { timeout: 8000 });
          if (pipedRes.data && pipedRes.data.audioStreams && pipedRes.data.audioStreams.length > 0) {
            const stream = pipedRes.data.audioStreams[0];
            if (stream && stream.url) {
              console.log(`[Downloader] ⚡ Streaming via Piped fallback (${instance}) for ${targetUrl}`);
              const streamRes = await axios.get(stream.url, {
                responseType: 'stream',
                timeout: 120000,
                headers: {
                  'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
                  'Accept': '*/*'
                }
              });

              res.setHeader('Content-Type', streamRes.headers['content-type'] || (outputExtension === 'webm' ? 'audio/webm' : 'audio/mp4'));
              if (streamRes.headers['content-length']) {
                res.setHeader('Content-Length', streamRes.headers['content-length']);
              }
              res.setHeader('Content-Disposition', `attachment; filename="${sanitizedFileName}"; filename*=UTF-8''${sanitizedFileName}`);
              res.setHeader('Accept-Ranges', 'bytes');

              streamRes.data.pipe(res);
              return;
            }
          }
        } catch (pipedErr) {}
      }

      // Strategy 3: Download to a temporary file before sending a success response.
      const temporaryFile = path.join(os.tmpdir(), `aura-${videoId}-${Date.now()}.${outputExtension}`);
      const ytDlpProcess = spawn(YTDLP_BIN, [
        ...ytDlpCommonArgs(),
        '-f', formatFilter,
        '--buffer-size', '64K',
        '--audio-quality', '0',
        '-o', temporaryFile,
        '--no-playlist',
        '--no-part',
        '--no-warnings',
        '--',
        targetUrl
      ]);
      const extractionTimeout = setTimeout(() => {
        ytDlpProcess.kill('SIGTERM');
      }, 120000);

      const failDownload = (message, details) => {
        console.error(`[Downloader] ❌ ${message}${details ? `: ${details}` : ''}`);
        try {
          if (fs.existsSync(temporaryFile)) fs.unlinkSync(temporaryFile);
        } catch (_) {}
        if (!res.headersSent) {
          res.status(502).json({ error: 'Stream failed', details });
        }
      };

      ytDlpProcess.stderr.on('data', (data) => {
        console.warn(`[Downloader] yt-dlp log: ${data.toString().trim()}`);
      });

      ytDlpProcess.on('error', (e) => {
        clearTimeout(extractionTimeout);
        failDownload('yt-dlp spawn error', e.message);
      });

      ytDlpProcess.on('close', (code, signal) => {
        clearTimeout(extractionTimeout);
        if (code !== 0) {
          failDownload(`yt-dlp exited with code ${code}`, signal || undefined);
          return;
        }

        let fileSize = 0;
        try {
          fileSize = fs.statSync(temporaryFile).size;
        } catch (_) {}

        if (fileSize === 0) {
          failDownload('yt-dlp produced an empty audio file');
          return;
        }

        res.setHeader('Content-Type', outputExtension === 'webm' ? 'audio/webm' : 'audio/mp4');
        res.setHeader('Content-Length', fileSize);
        res.setHeader('Content-Disposition', `attachment; filename="${sanitizedFileName}"; filename*=UTF-8''${sanitizedFileName}`);
        res.setHeader('Accept-Ranges', 'bytes');

        const fileStream = fs.createReadStream(temporaryFile);
        fileStream.on('error', (error) => failDownload('Temporary audio read failed', error.message));
        fileStream.on('close', () => {
          try {
            if (fs.existsSync(temporaryFile)) fs.unlinkSync(temporaryFile);
          } catch (_) {}
        });
        fileStream.pipe(res);
      });
    });

  } catch (err) {
    console.error(`[Downloader] 💥 Unexpected download error: ${err.message}`);
    if (!res.headersSent) {
      return res.status(500).json({ error: 'Download stream failed', details: err.message });
    }
  }
});

/**
 * MODULE 2 - Endpoint 3: GET /api/search/youtube
 * Server-side secure YouTube search proxy protecting API keys
 */
app.get('/api/search/youtube', async (req, res) => {
  try {
    const query = req.query.q || req.query.query;
    const limit = Math.min(parseInt(req.query.limit, 10) || 20, 50);

    if (!query || typeof query !== 'string' || !query.trim()) {
      return res.status(400).json({ error: 'Missing or empty "q" search parameter' });
    }

    const cleanQuery = query.trim();
    console.log(`[Search] 🔍 Searching YouTube for: "${cleanQuery}" (limit: ${limit})`);

    const apiKey = process.env.YOUTUBE_API_KEY?.trim();

    // Strategy 1: Official YouTube Data API v3 (Server-Side only)
    if (apiKey) {
      try {
        const ytRes = await axios.get('https://www.googleapis.com/youtube/v3/search', {
          params: {
            part: 'snippet',
            type: 'video',
            videoCategoryId: '10', // Music Category
            maxResults: limit,
            q: cleanQuery,
            key: apiKey,
          },
          timeout: 5000,
        });

        if (ytRes.data && Array.isArray(ytRes.data.items)) {
          const results = ytRes.data.items.map((item) => {
            const videoId = item.id?.videoId;
            const snippet = item.snippet || {};
            const rawTitle = snippet.title || 'YouTube Track';
            const cleanTitle = cleanTrackTitle(rawTitle);

            return {
              id: videoId,
              youtubeId: videoId,
              title: cleanTitle,
              artist: snippet.channelTitle || 'YouTube Artist',
              channelTitle: snippet.channelTitle,
              album: 'YouTube Music',
              duration: 210,
              thumbnail: snippet.thumbnails?.high?.url || snippet.thumbnails?.medium?.url || `https://i.ytimg.com/vi/${videoId}/hqdefault.jpg`,
              artworkUrl: snippet.thumbnails?.high?.url || snippet.thumbnails?.medium?.url || `https://i.ytimg.com/vi/${videoId}/hqdefault.jpg`,
              publishedAt: snippet.publishedAt,
              streamUrl: `https://www.youtube.com/watch?v=${videoId}`,
            };
          });

          console.log(`[Search] ✅ YouTube Data API returned ${results.length} tracks for "${cleanQuery}"`);
          return res.json({ query: cleanQuery, source: 'youtube_data_api_v3', results });
        }
      } catch (apiErr) {
        console.warn(`[Search] ⚠️ YouTube Data API failed (${apiErr.response?.status || apiErr.message}). Falling back to yt-dlp search...`);
      }
    }

    // Strategy 2: yt-dlp ytsearch dump fallback
    const ytDlpArgs = [
      '--dump-single-json',
      '--no-warnings',
      '--flat-playlist',
      '--no-check-certificates',
      ...ytDlpCommonArgs(),
      '--',
      `ytsearch${limit}:${cleanQuery}`,
    ];

    execFile(YTDLP_BIN, ytDlpArgs, { timeout: 12000, maxBuffer: 15 * 1024 * 1024 }, (error, stdout, stderr) => {
      if (!error && stdout) {
        try {
          const json = JSON.parse(stdout);
          const entries = Array.isArray(json.entries) ? json.entries : [json];

          const results = entries.filter((e) => e && (e.id || e.url)).map((item) => {
            const videoId = item.id || extractVideoId(item.url || '');
            const rawTitle = item.title || 'YouTube Audio';
            const cleanTitle = cleanTrackTitle(rawTitle);
            const artist = item.uploader || item.channel || 'YouTube Artist';
            const durationSec = Math.round(Number(item.duration) || 0) || 180;
            const thumbnail = item.thumbnail || (videoId ? `https://i.ytimg.com/vi/${videoId}/hqdefault.jpg` : null);

            return {
              id: videoId,
              youtubeId: videoId,
              title: cleanTitle,
              artist: artist,
              channelTitle: item.channel || item.uploader,
              album: 'YouTube Music',
              duration: durationSec,
              thumbnail: thumbnail,
              artworkUrl: thumbnail,
              viewCount: item.view_count,
              streamUrl: videoId ? `https://www.youtube.com/watch?v=${videoId}` : item.url,
            };
          });

          console.log(`[Search] ✅ yt-dlp search resolved ${results.length} tracks for "${cleanQuery}"`);
          return res.json({ query: cleanQuery, source: 'yt_dlp_search', results });
        } catch (parseErr) {
          console.warn(`[Search] ⚠️ yt-dlp parse warning: ${parseErr.message}`);
        }
      }

      // Strategy 3: Fast JioSaavn fallback
      axios.get('https://www.jiosaavn.com/api.php', {
        params: {
          __call: 'search.getResults',
          _format: 'json',
          _marker: '0',
          api_version: '4',
          ctx: 'web6dot0',
          n: limit.toString(),
          p: '1',
          q: cleanQuery,
        },
        timeout: 4000,
      }).then((saavnRes) => {
        const rawResults = saavnRes.data?.results || [];
        const fallbackResults = rawResults.map((item) => ({
          id: item.id,
          youtubeId: null,
          title: cleanTrackTitle(item.title || item.song),
          artist: item.more_info?.music || item.more_info?.primary_artists || 'Artist',
          album: item.more_info?.album || 'Music',
          duration: parseInt(item.more_info?.duration, 10) || 180,
          thumbnail: item.image?.replace('150x150', '500x500'),
          artworkUrl: item.image?.replace('150x150', '500x500'),
          streamUrl: item.more_info?.encrypted_media_url ? `saavn_${item.id}` : null,
        }));

        console.log(`[Search] ✅ Fast fallback returned ${fallbackResults.length} tracks`);
        return res.json({ query: cleanQuery, source: 'saavn_search_fallback', results: fallbackResults });
      }).catch((fallbackErr) => {
        return res.status(502).json({ error: 'Search failed across all backend engines', details: fallbackErr.message });
      });
    });

  } catch (err) {
    console.error(`[Search] 💥 Unexpected search error: ${err.message}`);
    return res.status(500).json({ error: 'Internal search error', details: err.message });
  }
});

/**
 * Universal GET /api/search alias
 */
app.get('/api/search', (req, res) => {
  req.url = '/api/search/youtube';
  app.handle(req, res);
});

app.listen(PORT, () => {
  console.log(`🚀 Aura Player YouTube Extractor Microservice running on port ${PORT}`);
  console.log(`👉 Engine: ${YTDLP_BIN}`);
  console.log(`👉 GET  /api/search/youtube?q=... (Backend Search Proxy)`);
  console.log(`👉 POST /api/youtube/extract (Multi-format HQ/MQ/LQ)`);
  console.log(`👉 GET  /api/youtube/download?formatId=...&quality=...`);
});
