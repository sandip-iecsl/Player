const express = require('express');
const cors = require('cors');
const path = require('path');
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
const YOUTUBE_COOKIES_PATH = path.join(__dirname, 'cookies.txt');

function prepareYouTubeCookies() {
  const encodedCookies = process.env.YOUTUBE_COOKIES_BASE64?.trim();
  if (!encodedCookies) {
    return fs.existsSync(YOUTUBE_COOKIES_PATH);
  }

  try {
    const cookies = Buffer.from(encodedCookies, 'base64').toString('utf8');
    if (!cookies.trim()) {
      throw new Error('decoded cookie content is empty');
    }

    fs.writeFileSync(YOUTUBE_COOKIES_PATH, cookies, { encoding: 'utf8', mode: 0o600 });
    console.log('[Microservice] YouTube cookies decoded successfully');
    return true;
  } catch (error) {
    console.error(`[Microservice] Failed to decode YouTube cookies: ${error.message}`);
    return false;
  }
}

const hasYouTubeCookies = prepareYouTubeCookies();

function getYouTubeCookieArgs() {
  return hasYouTubeCookies && fs.existsSync(YOUTUBE_COOKIES_PATH)
    ? ['--cookies', YOUTUBE_COOKIES_PATH]
    : [];
}

app.use(cors());
app.use(express.json());

// YouTube URL Validation Pattern (supports watch, shorts, embed, youtu.be, music.youtube, m.youtube, and playlists/mixes)
const YOUTUBE_REGEX = /^(https?:\/\/)?(www\.|music\.|m\.)?(youtube\.com\/(watch\?.*v=|shorts\/|live\/|v\/|embed\/|playlist\?)|youtu\.be\/)([a-zA-Z0-9_\-\?&=%#\.\+]+)$/i;

// Path to bundled yt-dlp binary (Windows and Linux / Cloud Container)
const LOCAL_YTDLP = path.join(__dirname, process.platform === 'win32' ? 'yt-dlp.exe' : 'yt-dlp');
const YTDLP_BIN = fs.existsSync(LOCAL_YTDLP) ? LOCAL_YTDLP : 'yt-dlp';

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
 * Clean track title by stripping standard YouTube clutter
 */
function cleanTrackTitle(rawTitle) {
  if (!rawTitle) return 'YouTube Audio Track';
  return rawTitle
    .replace(/\[\s*(Official\s*(Music\s*)?Video|Audio|HD|4K|Lyrics|Visualizer|Live|Full Song|Video Song|Audio Song|Video)\s*\]/gi, '')
    .replace(/\(\s*(Official\s*(Music\s*)?Video|Audio|HD|4K|Lyrics|Visualizer|Live|Full Song|Video Song|Audio Song|Video)\s*\)/gi, '')
    .replace(/\|\s*(Official\s*(Music\s*)?Video|Audio|HD|4K|Lyrics|Visualizer|Live|Full Song).*$/gi, '')
    .replace(/【.*?】/g, '')
    .replace(/\s+/g, ' ')
    .trim();
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
    youtubeCookiesConfigured: hasYouTubeCookies,
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
      ...getYouTubeCookieArgs(),
      '--dump-single-json',
      '--no-warnings',
      '--no-playlist',
      '--no-check-certificates',
      '-f', 'bestaudio/140/251/139/best',
      '--extractor-args', 'youtube:player_client=android_music,android,ios,web',
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

      console.warn(`[Extractor] ⚠️ yt-dlp failed or timed out (${error?.message || stderr}). Trying Piped streaming fallback...`);

      // Strategy 2: Piped API Multi-Instance Fallback
      const pipedInstances = [
        'https://pipedapi.kavin.rocks',
        'https://api.piped.private.coffee',
        'https://pipedapi.leptons.xyz'
      ];

      for (const instance of pipedInstances) {
        try {
          const pipedRes = await axios.get(`${instance}/streams/${videoId}`, { timeout: 6000 });
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

            console.log(`[Extractor] ⚡ Resolved via Piped instance (${instance}) for "${title}"`);
            return res.json(payloadResponse);
          }
        } catch (pipedErr) {}
      }

      console.warn(`[Extractor] ⚠️ Piped failed. Trying YouTube oEmbed + JioSaavn fallback...`);

      // Strategy 3: YouTube oEmbed + JioSaavn Instant Fallback Matcher
      try {
        const oembedRes = await axios.get('https://www.youtube.com/oembed', {
          params: { url: targetUrl, format: 'json' },
          timeout: 4000
        });

        if (oembedRes.data && oembedRes.data.title) {
          const rawTitle = oembedRes.data.title;
          const cleanTitle = cleanTrackTitle(rawTitle);
          const authorName = oembedRes.data.author_name || 'YouTube Artist';

          let query = cleanTitle.replace(/\s*(mashup|mix|remix|edit|ft\.|feat\.).*$/gi, '').trim();
          if (!query) query = cleanTitle;

          const saavnRes = await axios.get('https://www.jiosaavn.com/api.php', {
            params: {
              __call: 'search.getResults',
              _format: 'json',
              _marker: '0',
              api_version: '4',
              ctx: 'web6dot0',
              n: '5',
              p: '1',
              q: query
            },
            timeout: 5000
          });

          const results = saavnRes.data?.results || [];
          if (results.length > 0) {
            const topMatch = results[0];
            const encryptedMediaUrl = topMatch.more_info?.encrypted_media_url;
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

            const durationSec = parseInt(topMatch.more_info?.duration, 10) || 180;
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
              title: cleanTitle,
              artist: topMatch.more_info?.music || authorName,
              album: topMatch.more_info?.album || 'YouTube Imports',
              duration: durationSec,
              thumbnailUrl: topMatch.image?.replace('150x150', '500x500') || `https://i.ytimg.com/vi/${videoId}/hqdefault.jpg`,
              streamUrl: streamUrl,
              availableFormats: availableFormats,
              isYoutubeImport: true
            };

            console.log(`[Extractor] ✅ Resolved via JioSaavn fallback with 3 tiers: "${payloadResponse.title}"`);
            return res.json(payloadResponse);
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

    const outputExtension = formatId === '249' || formatId === '251' ||
      (!formatId && (quality === 'Data Saver' || quality === 'Low')) ? 'webm' : 'm4a';
    const sanitizedFileName = encodeURIComponent(`${customTitle}.${outputExtension}`);

    console.log(`[Downloader] ⬇️ Streaming audio (${formatFilter}) for: ${targetUrl} (File: ${sanitizedFileName})`);

    // Strategy 1: Resolve direct audio stream URL with yt-dlp -g
    execFile(YTDLP_BIN, [
      ...getYouTubeCookieArgs(),
      '--extractor-args', 'youtube:player_client=android_music,android,ios,web',
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

      // Strategy 3: Spawn yt-dlp process
      res.setHeader('Content-Type', outputExtension === 'webm' ? 'audio/webm' : 'audio/mp4');
      res.setHeader('Content-Disposition', `attachment; filename="${sanitizedFileName}"; filename*=UTF-8''${sanitizedFileName}`);
      res.setHeader('Accept-Ranges', 'bytes');

      const ytDlpProcess = spawn(YTDLP_BIN, [
        ...getYouTubeCookieArgs(),
        '--extractor-args', 'youtube:player_client=android_music,android,ios,web',
        '-f', formatFilter,
        '--buffer-size', '64K',
        '--audio-quality', '0',
        '-o', '-',
        '--no-playlist',
        '--no-part',
        '--no-warnings',
        '--',
        targetUrl
      ]);

      const failDownload = (message, details) => {
        console.error(`[Downloader] ❌ ${message}${details ? `: ${details}` : ''}`);
        if (!res.headersSent) {
          res.status(500).json({ error: 'Stream failed', details });
        } else if (!res.writableEnded) {
          res.destroy();
        }
      };

      res.on('error', (e) => {
        console.warn(`[Downloader] ⚠️ HTTP response stream error: ${e.message}`);
        ytDlpProcess.kill('SIGTERM');
      });

      ytDlpProcess.stdout.on('error', (e) => {
        failDownload('yt-dlp output stream error', e.message);
      });
      ytDlpProcess.stdout.pipe(res);

      ytDlpProcess.stderr.on('data', (data) => {
        console.warn(`[Downloader] yt-dlp log: ${data.toString().trim()}`);
      });

      ytDlpProcess.on('error', (e) => {
        failDownload('yt-dlp spawn error', e.message);
      });

      ytDlpProcess.on('close', (code, signal) => {
        if (code !== 0 && !res.writableEnded) {
          failDownload(`yt-dlp exited with code ${code}`, signal || undefined);
        }
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
      ...getYouTubeCookieArgs(),
      '--dump-single-json',
      '--no-warnings',
      '--flat-playlist',
      '--no-check-certificates',
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
