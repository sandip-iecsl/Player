const express = require('express');
const cors = require('cors');
const path = require('path');
const fs = require('fs');
const { spawn, execFile } = require('child_process');
const axios = require('axios');
require('dotenv').config();

const app = express();
const PORT = process.env.PORT || 3000;

app.use(cors());
app.use(express.json());

// YouTube URL Validation Pattern (supports watch, shorts, embed, youtu.be, music.youtube, and playlists/mixes)
const YOUTUBE_REGEX = /^(https?:\/\/)?(www\.|music\.)?(youtube\.com\/(watch\?v=|shorts\/|v\/|embed\/|playlist\?)|youtu\.be\/)([a-zA-Z0-9_\-\?&=]+)$/;

// Path to bundled yt-dlp binary (Windows and Linux / Cloud Container)
const LOCAL_YTDLP = path.join(__dirname, process.platform === 'win32' ? 'yt-dlp.exe' : 'yt-dlp');
const YTDLP_BIN = fs.existsSync(LOCAL_YTDLP) ? LOCAL_YTDLP : 'yt-dlp';

// Helper to clean, sanitize, and re-format YouTube Mix / Radio & Standard URLs
function normalizeYouTubeUrl(inputUrl) {
  try {
    const trimmed = inputUrl.trim();
    const urlObj = new URL(trimmed.startsWith('http') ? trimmed : `https://${trimmed}`);
    
    // Check if link contains a Mix / Radio playlist (list starts with 'RD')
    const listParam = urlObj.searchParams.get('list');
    
    if (listParam && listParam.startsWith('RD')) {
      // Extract video ID from 'v' query or from RD suffix (RD_JL6JAf-HKw -> _JL6JAf-HKw)
      let videoId = urlObj.searchParams.get('v');
      if (!videoId) {
        videoId = listParam.replace(/^RD/, '');
      }
      
      // Reconstruct as a clean watch link with the Mix playlist parameter
      return `https://www.youtube.com/watch?v=${videoId}&list=${listParam}`;
    }

    // Check if standard playlist link has a direct video parameter
    if (urlObj.pathname.includes('playlist')) {
      const v = urlObj.searchParams.get('v');
      if (v) {
        return `https://www.youtube.com/watch?v=${v}`;
      }
    }

    // Strip unnecessary tracking parameters (e.g., playnext, si, feature, pp, index)
    urlObj.searchParams.delete('playnext');
    urlObj.searchParams.delete('si');
    urlObj.searchParams.delete('feature');
    urlObj.searchParams.delete('pp');
    
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

/**
 * Extract YouTube Video ID from any supported format
 */
function extractVideoId(url) {
  const normalized = normalizeYouTubeUrl(url);
  const match1 = normalized.match(/(?:watch\?v=|youtu\.be\/|shorts\/|embed\/)([a-zA-Z0-9_\-]{11})/);
  if (match1 && match1[1]) return match1[1];
  
  const match2 = url.match(/(?:list=RD_?)([a-zA-Z0-9_\-]{11})/);
  if (match2 && match2[1]) return match2[1];

  const match3 = url.match(/([a-zA-Z0-9_\-]{11})/);
  if (match3 && match3[1]) return match3[1];
  
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

    // yt-dlp dump-single-json to parse full format list
    const ytDlpArgs = [
      '--dump-single-json',
      '--no-warnings',
      '--no-playlist',
      '--no-check-certificates',
      '--extractor-args', 'youtube:player_client=android,ios,web',
      '--',
      targetUrl
    ];

    execFile(YTDLP_BIN, ytDlpArgs, { maxBuffer: 25 * 1024 * 1024, timeout: 14000 }, async (error, stdout, stderr) => {
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

      console.warn(`[Extractor] ⚠️ yt-dlp failed or timed out (${error?.message || stderr}). Trying JioSaavn fallback...`);

      // Strategy 2: YouTube oEmbed + JioSaavn Instant Fallback Matcher
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

    // Select a native audio stream. No -x/ffmpeg post-processing is used, so
    // the source container and codec are streamed without re-encoding.
    let formatFilter = 'bestaudio[ext=m4a]/bestaudio[ext=webm]/bestaudio';
    if (formatId && formatId !== 'undefined') {
      formatFilter = `${formatId}/${formatFilter}`;
    } else if (quality === 'Data Saver' || quality === 'Low') {
      formatFilter = '249/139/bestaudio[ext=m4a]/bestaudio[ext=webm]/bestaudio';
    } else if (quality === 'Medium') {
      formatFilter = '139/140/bestaudio[ext=m4a]/bestaudio[ext=webm]/bestaudio';
    }

    const outputExtension = formatId === '249' || formatId === '251' ||
      (!formatId && (quality === 'Data Saver' || quality === 'Low')) ? 'webm' : 'm4a';
    const sanitizedFileName = encodeURIComponent(`${customTitle}.${outputExtension}`);

    console.log(`[Downloader] ⬇️ Streaming audio (${formatFilter}) for: ${targetUrl} (File: ${sanitizedFileName})`);

    // Set streaming headers
    res.setHeader('Content-Type', outputExtension === 'webm' ? 'audio/webm' : 'audio/mp4');
    res.setHeader('Content-Disposition', `attachment; filename="${sanitizedFileName}"; filename*=UTF-8''${sanitizedFileName}`);
    res.setHeader('Accept-Ranges', 'bytes');

    const ytDlpProcess = spawn(YTDLP_BIN, [
      '--extractor-args', 'youtube:player_client=android,ios,web',
      '-f', formatFilter,
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

    res.on('error', (err) => {
      console.warn(`[Downloader] ⚠️ HTTP response stream error: ${err.message}`);
      ytDlpProcess.kill('SIGTERM');
    });

    ytDlpProcess.stdout.on('error', (err) => {
      failDownload('yt-dlp output stream error', err.message);
    });
    ytDlpProcess.stdout.pipe(res);

    ytDlpProcess.stderr.on('data', (data) => {
      console.warn(`[Downloader] yt-dlp log: ${data.toString().trim()}`);
    });

    ytDlpProcess.on('error', (err) => {
      failDownload('yt-dlp spawn error', err.message);
    });

    ytDlpProcess.on('close', (code, signal) => {
      if (code !== 0 && !res.writableEnded) {
        failDownload(`yt-dlp exited with code ${code}`, signal || undefined);
      }
    });

  } catch (err) {
    console.error(`[Downloader] 💥 Unexpected download error: ${err.message}`);
    if (!res.headersSent) {
      return res.status(500).json({ error: 'Download stream failed', details: err.message });
    }
  }
});

app.listen(PORT, () => {
  console.log(`🚀 Aura Player YouTube Extractor Microservice running on port ${PORT}`);
  console.log(`👉 Engine: ${YTDLP_BIN}`);
  console.log(`👉 POST /api/youtube/extract (Multi-format HQ/MQ/LQ)`);
  console.log(`👉 GET  /api/youtube/download?formatId=...&quality=...`);
});
