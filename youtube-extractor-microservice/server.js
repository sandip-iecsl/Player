const express = require('express');
const cors = require('cors');
const path = require('path');
const os = require('os');
const fs = require('fs');
const { spawn, execFile, execFileSync } = require('child_process');
const axios = require('axios');
require('dotenv').config();
const {
  YTDLP_BIN,
  buildYtDlpArgs,
  diagnostics,
  PYTHON_BIN,
  YTMUSIC_BRIDGE,
} = require('./yt_dlp_config');

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

// Initialize Innertube (pure Node.js YouTube client) as resilient fallback engine
let innerTubeClient = null;
async function getInnerTube() {
  if (!innerTubeClient) {
    try {
      const { Innertube, UniversalCache } = require('youtubei.js');
      let cookieContent = null;
      if (cookiePath && fileIsReadable(cookiePath)) {
        try {
          cookieContent = fs.readFileSync(cookiePath, 'utf8').trim();
        } catch (_) {}
      }
      innerTubeClient = await Innertube.create({
        cache: new UniversalCache(false),
        generate_session_locally: true,
        client_type: 'ANDROID',
        cookie: cookieContent || undefined,
      });
      console.log('[Microservice] ⚡ Innertube engine (ANDROID client) initialized successfully');
    } catch (err) {
      console.warn('[Microservice] ⚠️ Innertube initialization warning:', err.message);
    }
  }
  return innerTubeClient;
}
getInnerTube();

// YouTube URL Validation Pattern (supports watch, shorts, embed, youtu.be, music.youtube, m.youtube, and playlists/mixes)
const YOUTUBE_REGEX = /^(https?:\/\/)?(www\.|music\.|m\.)?(youtube\.com\/(watch\?.*|shorts\/|live\/|v\/|embed\/|playlist\?)|youtu\.be\/)([a-zA-Z0-9_\-\?&=%#\.\+]+)$/i;

function extractPlaylistId(inputUrl) {
  if (!inputUrl) return null;
  try {
    const trimmed = inputUrl.trim();
    if (/^[a-zA-Z0-9_\-]+$/.test(trimmed) && (trimmed.startsWith('PL') || trimmed.startsWith('UU') || trimmed.startsWith('RD') || trimmed.startsWith('OLAK5uy_') || trimmed.startsWith('LL'))) {
      return trimmed;
    }
    const parsed = new URL(trimmed.startsWith('http') ? trimmed : `https://${trimmed}`);
    const list = parsed.searchParams.get('list');
    if (list) return list;
    return null;
  } catch (_) {
    return null;
  }
}

const runtimeDiagnostics = diagnostics();
console.log(`[Microservice] Runtime ${JSON.stringify(runtimeDiagnostics)}`);

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
      return STRICT_VIDEO_ID_REGEX.test(mixId || '')
        ? `https://www.youtube.com/watch?v=${mixId}`
        : trimmed;
    }

    // Check if standard playlist link has a direct video parameter
    if (urlObj.pathname.includes('playlist')) {
      const v = urlObj.searchParams.get('v');
      if (v && STRICT_VIDEO_ID_REGEX.test(v)) {
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

const STRICT_VIDEO_ID_REGEX = /^[a-zA-Z0-9_\-]{11}$/;

/**
 * Extract strict 11-character YouTube Video ID from any supported format
 */
function extractVideoId(url) {
  if (!url) return null;
  const trimmed = url.trim();
  if (STRICT_VIDEO_ID_REGEX.test(trimmed)) return trimmed;

  // Do not call normalizeYouTubeUrl from here.  Normalization deliberately
  // calls this parser first; mutual calls used to recurse until a stack
  // overflow before falling back to the raw URL.
  try {
    const parsed = new URL(trimmed.startsWith('http') ? trimmed : `https://${trimmed}`);
    const host = parsed.hostname.toLowerCase().replace(/^www\./, '');
    let candidate = null;

    if (host === 'youtu.be') {
      candidate = parsed.pathname.split('/').filter(Boolean)[0];
    } else if (host === 'youtube.com' || host === 'music.youtube.com' || host === 'm.youtube.com') {
      const segments = parsed.pathname.split('/').filter(Boolean);
      if (parsed.pathname === '/watch' || parsed.pathname === '/playlist') {
        candidate = parsed.searchParams.get('v');
      } else if (['shorts', 'embed', 'live', 'v'].includes(segments[0])) {
        candidate = segments[1];
      }

      // A generated YouTube Mix has no `v` parameter; its seed is stored in
      // list=RD<videoId>.  We accept only the strict 11-character seed.
      if (!candidate) {
        const mix = parsed.searchParams.get('list');
        const mixMatch = mix?.match(/^(?:RDMM|RDCL|RD)([a-zA-Z0-9_-]{11})$/);
        candidate = mixMatch?.[1] ?? null;
      }
    }

    return candidate && STRICT_VIDEO_ID_REGEX.test(candidate) ? candidate : null;
  } catch (_) {
    return null;
  }
}

/**
 * Calculate estimated size in MB/GB given bitrate in kbps and duration in seconds
 */
function estimateSizeMb(bitrateKbps, durationSec) {
  if (!bitrateKbps || !durationSec) return 'Unknown';
  const totalBits = bitrateKbps * 1000 * durationSec;
  const totalBytes = totalBits / 8;
  const sizeMb = totalBytes / (1024 * 1024);
  if (sizeMb >= 1024) {
    return `${(sizeMb / 1024).toFixed(2)} GB`;
  }
  return `${sizeMb.toFixed(1)} MB`;
}

async function resolveWithInnerTube(videoId, targetUrl) {
  try {
    const yt = await getInnerTube();
    let info = null;
    try {
      info = await yt.getBasicInfo(videoId, 'ANDROID');
    } catch (_) {
      try {
        info = await yt.getBasicInfo(videoId, 'TV');
      } catch (_) {
        info = await yt.getBasicInfo(videoId);
      }
    }
    if (!info || !info.basic_info) return null;

    const rawTitle = info.basic_info.title || 'YouTube Audio';
    const cleanTitle = cleanTrackTitle(rawTitle);
    const artistName = info.basic_info.author || 'YouTube Artist';
    const durationSec = Math.round(Number(info.basic_info.duration) || 0) || 180;
    const thumbnail = info.basic_info.thumbnail?.[0]?.url || `https://i.ytimg.com/vi/${videoId}/hqdefault.jpg`;

    const adaptive = info.streaming_data?.adaptive_formats || [];
    const audioFormats = adaptive.filter(f => f.mime_type?.includes('audio') || f.has_audio);

    // Sort descending by bitrate
    audioFormats.sort((a, b) => (b.bitrate || 0) - (a.bitrate || 0));

    let streamUrl = null;
    const availableFormats = [];

    for (const f of audioFormats) {
      let fUrl = f.url;
      if (!fUrl && f.signature_cipher && yt.session?.player) {
        try {
          fUrl = yt.session.player.decipher(f.signature_cipher);
        } catch (_) {}
      }
      if (fUrl && !streamUrl && fUrl.startsWith('http')) {
        streamUrl = fUrl;
      }

      const abrKbps = Math.round((f.bitrate || 128000) / 1000);
      const quality = abrKbps >= 160 ? 'High' : (abrKbps >= 96 ? 'Medium' : 'Data Saver');
      availableFormats.push({
        quality,
        bitrate: `${abrKbps} kbps`,
        format: f.mime_type?.includes('webm') ? 'webm' : 'm4a',
        sourceCodec: f.audio_quality || null,
        sourceBitrateKbps: abrKbps,
        sampleRateHz: f.audio_sample_rate || 44100,
        channels: f.audio_channels || 2,
        estimatedSizeMb: estimateSizeMb(abrKbps, durationSec),
        streamUrl: fUrl || `https://www.youtube.com/watch?v=${videoId}`,
        formatId: String(f.itag || '140'),
      });
    }

    if (availableFormats.length === 0) {
      const defaultUrl = `https://www.youtube.com/watch?v=${videoId}`;
      availableFormats.push(
        {
          quality: 'High',
          bitrate: '320 kbps',
          format: 'm4a',
          sourceCodec: 'mp4a',
          sourceBitrateKbps: 320,
          sampleRateHz: 44100,
          channels: 2,
          estimatedSizeMb: estimateSizeMb(320, durationSec),
          streamUrl: streamUrl || defaultUrl,
          formatId: '140',
        },
        {
          quality: 'Medium',
          bitrate: '128 kbps',
          format: 'm4a',
          sourceCodec: 'mp4a',
          sourceBitrateKbps: 128,
          sampleRateHz: 44100,
          channels: 2,
          estimatedSizeMb: estimateSizeMb(128, durationSec),
          streamUrl: streamUrl || defaultUrl,
          formatId: '139',
        },
        {
          quality: 'Data Saver',
          bitrate: '64 kbps',
          format: 'webm',
          sourceCodec: 'opus',
          sourceBitrateKbps: 64,
          sampleRateHz: 48000,
          channels: 2,
          estimatedSizeMb: estimateSizeMb(64, durationSec),
          streamUrl: streamUrl || defaultUrl,
          formatId: '249',
        }
      );
    }

    return {
      id: `yt_${videoId}`,
      source: 'youtube',
      videoId,
      requestedVideoId: videoId,
      mediaState: 'MediaResolved',
      title: cleanTitle,
      artist: artistName,
      album: 'YouTube Imports',
      duration: durationSec,
      thumbnailUrl: thumbnail,
      streamUrl: streamUrl || availableFormats[0].streamUrl,
      availableFormats,
      isYoutubeImport: true,
    };
  } catch (err) {
    console.warn(`[InnerTube] Resolution error for ${videoId}:`, err.message);
    return null;
  }
}

function youtubeUnavailable(res, requestedVideoId, category, message) {
  return res.status(502).json({
    error: 'YOUTUBE_SOURCE_UNAVAILABLE',
    requestedVideoId,
    provider: 'youtube',
    category,
    message,
  });
}

function isLikelyAudioResponse(response) {
  const contentType = String(response.headers?.['content-type'] || '').toLowerCase();
  if (contentType.includes('text/html') || contentType.includes('application/json')) return false;
  const contentLength = Number(response.headers?.['content-length'] || 0);
  return !contentLength || contentLength >= 16 * 1024;
}

function isReadableAudioFile(filePath) {
  try {
    if (fs.statSync(filePath).size < 16 * 1024) return false;
    const header = fs.readFileSync(filePath).subarray(0, 16);
    const isOgg = header.subarray(0, 4).toString() === 'OggS';
    const isWebm = header.subarray(0, 4).equals(Buffer.from([0x1a, 0x45, 0xdf, 0xa3]));
    const isMp4 = header.length >= 8 && header.subarray(4, 8).toString() === 'ftyp';
    const isId3 = header.subarray(0, 3).toString() === 'ID3';
    return isOgg || isWebm || isMp4 || isId3;
  } catch (_) {
    return false;
  }
}

let ytmusicapiVerified = null;
function checkYtMusicApi() {
  if (ytmusicapiVerified !== null) return ytmusicapiVerified;
  if (!fs.existsSync(YTMUSIC_BRIDGE)) {
    ytmusicapiVerified = false;
    return false;
  }
  try {
    const { execFileSync } = require('child_process');
    execFileSync(PYTHON_BIN, ['-c', 'import ytmusicapi'], { stdio: 'ignore', timeout: 3000 });
    ytmusicapiVerified = true;
  } catch (_) {
    ytmusicapiVerified = false;
  }
  return ytmusicapiVerified;
}

function queryYtMusic(operation, ...args) {
  if (!checkYtMusicApi()) return null;
  try {
    const output = execFileSync(PYTHON_BIN, [YTMUSIC_BRIDGE, operation, ...args], {
      encoding: 'utf8',
      timeout: operation === 'search' ? 10000 : 8000,
      maxBuffer: 10 * 1024 * 1024,
    });
    const payload = JSON.parse(output);
    if (payload.error) {
      return null;
    }
    return payload;
  } catch (_) {
    return null;
  }
}

/**
 * Health check
 */
app.get('/health', (req, res) => {
  res.json({
    status: 'online',
    service: 'Aura Player YouTube Extractor Microservice',
    engine: `yt-dlp (${YTDLP_BIN})`,
    ...runtimeDiagnostics,
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

    const ytmusicMetadata = videoId ? queryYtMusic('song', videoId) : null;
    if (ytmusicMetadata && ytmusicMetadata.videoId !== videoId) {
      return youtubeUnavailable(res, videoId, 'SOURCE_ID_MISMATCH', 'YouTube Music metadata did not match the requested video.');
    }

    // yt-dlp dump-single-json to parse full format list without re-encoding
    const ytDlpArgs = buildYtDlpArgs({
      dumpJson: true,
      format: 'bestaudio/140/251/139/best',
    });
    ytDlpArgs.push(targetUrl);

    execFile(YTDLP_BIN, ytDlpArgs, { maxBuffer: 100 * 1024 * 1024, timeout: 60000 }, async (error, stdout, stderr) => {
      if (!error && stdout) {
        try {
          const info = JSON.parse(stdout);
          if (info.id && info.id !== videoId) {
            throw new Error(`yt-dlp returned unexpected video ID ${info.id}`);
          }
          const rawTitle = ytmusicMetadata?.title || info.title || 'YouTube Audio';
          const cleanTitle = cleanTrackTitle(rawTitle);
          const artistName = ytmusicMetadata?.artist || info.artist || info.uploader || info.channel || 'YouTube Artist';
          const durationSec = Math.round(Number(info.duration) || 0) || 180;
          const thumbnail = ytmusicMetadata?.thumbnailUrl || info.thumbnail || `https://i.ytimg.com/vi/${videoId}/hqdefault.jpg`;

          // Filter out audio-only streams or video formats with audio
          const formats = Array.isArray(info.formats) ? info.formats : [];
          const audioFormats = formats.filter(f => f.acodec && f.acodec !== 'none' && f.url);

          // Sort descending by audio bitrate (abr)
          audioFormats.sort((a, b) => (b.abr || 0) - (a.abr || 0));

          // 1. High Quality Tier (HQ: 256kbps - 320kbps or best available)
          const hqStream = audioFormats.find(f => (f.abr && f.abr >= 160) || f.format_id === '140' || f.ext === 'm4a') || audioFormats[0] || { url: info.url, format_id: 'unknown', abr: null, ext: info.ext || 'unknown' };

          // 2. Medium Quality Tier (MQ: 128kbps - 160kbps)
          const mqStream = audioFormats.find(f => f.abr && f.abr >= 96 && f.abr <= 160) || audioFormats.find(f => f.format_id === '139') || hqStream;

          // 3. Low Quality / Data Saver Tier (LQ: 48kbps - 64kbps)
          const lqStream = audioFormats.slice().reverse().find(f => (f.abr && f.abr <= 80) || f.format_id === '249' || f.format_id === '599') || audioFormats.find(f => f.format_id === '249') || mqStream;

          const availableFormats = [
            {
              quality: 'High',
              bitrate: hqStream.abr ? `${Math.round(hqStream.abr)} kbps` : 'Unknown',
              format: hqStream.ext || 'm4a',
              sourceCodec: hqStream.acodec || null,
              sourceBitrateKbps: hqStream.abr ? Math.round(hqStream.abr) : null,
              sampleRateHz: hqStream.asr || null,
              channels: hqStream.audio_channels || null,
              estimatedSizeMb: estimateSizeMb(hqStream.abr || 320, durationSec),
              streamUrl: hqStream.url || info.url,
              formatId: hqStream.format_id || '140'
            },
            {
              quality: 'Medium',
              bitrate: mqStream.abr ? `${Math.round(mqStream.abr)} kbps` : 'Unknown',
              format: mqStream.ext || 'm4a',
              sourceCodec: mqStream.acodec || null,
              sourceBitrateKbps: mqStream.abr ? Math.round(mqStream.abr) : null,
              sampleRateHz: mqStream.asr || null,
              channels: mqStream.audio_channels || null,
              estimatedSizeMb: estimateSizeMb(mqStream.abr || 128, durationSec),
              streamUrl: mqStream.url || hqStream.url || info.url,
              formatId: mqStream.format_id || '139'
            },
            {
              quality: 'Data Saver',
              bitrate: lqStream.abr ? `${Math.round(lqStream.abr)} kbps` : 'Unknown',
              format: lqStream.ext || 'm4a',
              sourceCodec: lqStream.acodec || null,
              sourceBitrateKbps: lqStream.abr ? Math.round(lqStream.abr) : null,
              sampleRateHz: lqStream.asr || null,
              channels: lqStream.audio_channels || null,
              estimatedSizeMb: estimateSizeMb(lqStream.abr || 64, durationSec),
              streamUrl: lqStream.url || mqStream.url || info.url,
              formatId: lqStream.format_id || '249'
            }
          ];

          const payloadResponse = {
            id: `yt_${videoId}`,
            source: 'youtube',
            videoId,
            requestedVideoId: videoId,
            mediaState: 'MediaResolved',
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

      console.warn(`[Extractor] ⚠️ yt-dlp failed or timed out (${error?.message || stderr}). Trying Innertube engine fallback...`);

      // Strategy 2: In-Process Pure JS Innertube Engine (solves ENOENT and bot challenges on Render)
      try {
        const innerTubeResult = await resolveWithInnerTube(videoId, targetUrl);
        if (innerTubeResult) {
          console.log(`[Extractor] ⚡ Resolved via Innertube for "${innerTubeResult.title}"`);
          return res.json(innerTubeResult);
        }
      } catch (innerErr) {
        console.warn(`[Extractor] ⚠️ Innertube fallback warning: ${innerErr.message}`);
      }

      console.warn(`[Extractor] ⚠️ Innertube unavailable. Trying Piped & Invidious streaming fallback...`);

      // Strategy 3: Multi-Instance Piped & Invidious API Fallback
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
                  sourceCodec: st.codec || null,
                  sourceBitrateKbps: abr,
                  sampleRateHz: st.sampleRate || null,
                  channels: st.channels || null,
                  estimatedSizeMb: estimateSizeMb(abr, durationSec),
                  streamUrl: st.url,
                  formatId: String(st.format || '140')
                };
              });

              const payloadResponse = {
                id: `yt_${videoId}`,
                source: 'youtube',
                videoId,
                requestedVideoId: videoId,
                mediaState: 'MediaResolved',
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
                    sourceCodec: st.type || null,
                    sourceBitrateKbps: abr,
                    sampleRateHz: st.sampleRate || null,
                    channels: null,
                    estimatedSizeMb: estimateSizeMb(abr, durationSec),
                    streamUrl: st.url,
                    formatId: String(st.itag || '140')
                  };
                });

                const payloadResponse = {
                  id: `yt_${videoId}`,
                  source: 'youtube',
                  videoId,
                  requestedVideoId: videoId,
                  mediaState: 'MediaResolved',
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

      console.warn('[Extractor] ⚠️ YouTube metadata may be available, but no same-source media was resolved.');
      return youtubeUnavailable(
        res,
        videoId,
        'MEDIA_RESOLUTION_FAILED',
        'The requested YouTube recording is unavailable for playback or download from the configured providers.',
      );
    });

  } catch (err) {
    console.error(`[Extractor] 💥 Unexpected error: ${err.message}`);
    return res.status(500).json({ error: 'Internal server error', details: err.message });
  }
});

/**
 * MODULE 1 - Endpoint 1B: POST /api/youtube/playlist
 * Extracts playlist items, titles, durations, thumbnails, and canonical video IDs
 */
app.post('/api/youtube/playlist', async (req, res) => {
  try {
    const { url } = req.body;
    if (!url || typeof url !== 'string') {
      return res.status(400).json({ error: 'Missing or invalid "url" parameter in request body' });
    }

    const playlistId = extractPlaylistId(url);
    if (!playlistId) {
      return res.status(400).json({ error: 'Provided URL is not a valid YouTube playlist or mix link' });
    }

    console.log(`[Playlist] 📋 Extracting playlist metadata and tracks for: ${url} (ID: ${playlistId})`);

    // Strategy 1: yt-dlp --flat-playlist --dump-single-json
    const ytDlpArgs = buildYtDlpArgs({
      dumpJson: true,
      noPlaylist: false,
      extraArgs: ['--flat-playlist'],
    });
    ytDlpArgs.push(`https://www.youtube.com/playlist?list=${playlistId}`);

    execFile(YTDLP_BIN, ytDlpArgs, { maxBuffer: 50 * 1024 * 1024, timeout: 45000 }, async (error, stdout, stderr) => {
      if (!error && stdout) {
        try {
          const data = JSON.parse(stdout);
          const entries = Array.isArray(data.entries) ? data.entries : [];
          const tracks = entries.map((e, idx) => {
            const vId = e.id || e.url?.replace(/.*v=/, '') || '';
            const title = cleanTrackTitle(e.title || 'YouTube Track');
            const artist = e.uploader || e.channel || e.artist || data.channel || data.uploader || 'YouTube Artist';
            const durationSec = Math.round(Number(e.duration) || 0) || 180;
            const thumb = e.thumbnails?.[0]?.url || `https://i.ytimg.com/vi/${vId}/hqdefault.jpg`;
            return {
              id: `yt_${vId}`,
              youtubeId: vId,
              title,
              artist,
              album: data.title || 'YouTube Playlist',
              duration: durationSec,
              thumbnailUrl: thumb,
              streamUrl: `https://www.youtube.com/watch?v=${vId}`,
              isYoutubeImport: true,
              index: idx,
            };
          }).filter(t => t.youtubeId && STRICT_VIDEO_ID_REGEX.test(t.youtubeId));

          if (tracks.length > 0) {
            console.log(`[Playlist] ✅ yt-dlp resolved ${tracks.length} tracks for "${data.title || playlistId}"`);
            return res.json({
              playlistId,
              playlistTitle: data.title || 'YouTube Playlist',
              channel: data.channel || data.uploader || 'YouTube Channel',
              trackCount: tracks.length,
              tracks,
            });
          }
        } catch (parseErr) {
          console.warn('[Playlist] ⚠️ yt-dlp parse warning:', parseErr.message);
        }
      }

      // Strategy 2: Innertube pure JS fallback
      try {
        console.log(`[Playlist] 🔄 Falling back to Innertube engine for playlist: ${playlistId}...`);
        const yt = await getInnerTube();
        if (yt) {
          const pl = await yt.getPlaylist(playlistId);
          if (pl && pl.videos) {
            const tracks = pl.videos.map((v, idx) => {
              const vId = v.id;
              const title = cleanTrackTitle(v.title?.text || 'YouTube Track');
              const artist = v.author?.name || pl.info?.author?.name || 'YouTube Artist';
              const durationSec = v.duration?.seconds || 180;
              const thumb = v.thumbnails?.[0]?.url || `https://i.ytimg.com/vi/${vId}/hqdefault.jpg`;
              return {
                id: `yt_${vId}`,
                youtubeId: vId,
                title,
                artist,
                album: pl.info?.title || 'YouTube Playlist',
                duration: durationSec,
                thumbnailUrl: thumb,
                streamUrl: `https://www.youtube.com/watch?v=${vId}`,
                isYoutubeImport: true,
                index: idx,
              };
            }).filter(t => t.youtubeId && STRICT_VIDEO_ID_REGEX.test(t.youtubeId));

            if (tracks.length > 0) {
              console.log(`[Playlist] ✅ Innertube resolved ${tracks.length} tracks for "${pl.info?.title || playlistId}"`);
              return res.json({
                playlistId,
                playlistTitle: pl.info?.title || 'YouTube Playlist',
                channel: pl.info?.author?.name || 'YouTube Channel',
                trackCount: tracks.length,
                tracks,
              });
            }
          }
        }
      } catch (innerErr) {
        console.warn('[Playlist] ⚠️ Innertube playlist error:', innerErr.message);
      }

      return res.status(502).json({
        error: 'PLAYLIST_EXTRACTION_FAILED',
        playlistId,
        message: 'Could not extract playlist items from the configured providers.',
      });
    });
  } catch (err) {
    console.error('[Playlist] 💥 Unexpected playlist error:', err.message);
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

    const outputExtension = formatId === '249' || formatId === '251' ||
      (!formatId && (quality === 'Data Saver' || quality === 'Low')) ? 'webm' : 'm4a';
    const sanitizedFileName = encodeURIComponent(`${customTitle}.${outputExtension}`);

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
    execFile(YTDLP_BIN, buildYtDlpArgs({ format: formatFilter, getUrl: true }).concat(targetUrl), { timeout: 35000 }, async (err, stdout, stderr) => {
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

          if (!isLikelyAudioResponse(response)) {
            throw new Error('direct response was not validated as audio');
          }

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
              console.log(`[Downloader] ⚡ Streaming same-source Piped fallback (${instance}) for ${targetUrl}`);
              const streamRes = await axios.get(stream.url, {
                responseType: 'stream',
                timeout: 120000,
                headers: {
                  'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
                  'Accept': '*/*'
                }
              });

              if (!isLikelyAudioResponse(streamRes)) {
                continue;
              }

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
      const ytDlpProcess = spawn(YTDLP_BIN, buildYtDlpArgs({
        format: formatFilter,
        outputPath: temporaryFile,
        extraArgs: ['--buffer-size', '64K', '--audio-quality', '0', '--no-part'],
      }).concat(targetUrl));
      const extractionTimeout = setTimeout(() => {
        ytDlpProcess.kill('SIGTERM');
      }, 120000);

      const failDownload = (message, details) => {
        console.error(`[Downloader] ❌ ${message}${details ? `: ${details}` : ''}`);
        try {
          if (fs.existsSync(temporaryFile)) fs.unlinkSync(temporaryFile);
        } catch (_) {}
        if (!res.headersSent) {
          youtubeUnavailable(
            res,
            videoId,
            'DOWNLOAD_FAILED',
            'The requested YouTube recording could not be validated for download.',
          );
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

        if (fileSize === 0 || !isReadableAudioFile(temporaryFile)) {
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

    const ytmusicSearch = queryYtMusic('search', cleanQuery, String(limit));
    if (Array.isArray(ytmusicSearch?.results)) {
      const results = ytmusicSearch.results.filter((item) =>
        item.youtubeId && STRICT_VIDEO_ID_REGEX.test(item.youtubeId),
      );
      if (results.length) {
        console.log(`[Search] ✅ ytmusicapi returned ${results.length} tracks for "${cleanQuery}"`);
        return res.json({ query: cleanQuery, source: 'ytmusicapi', results });
      }
      console.warn(`[Search] ⚠️ ytmusicapi returned no valid song results for "${cleanQuery}"; using fallback search.`);
    }

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
    const ytDlpArgs = buildYtDlpArgs({
      dumpJson: true,
      extraArgs: ['--flat-playlist'],
    }).concat(`ytsearch${limit}:${cleanQuery}`);

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
  console.log(`[Microservice] Server version: ${runtimeDiagnostics.serverVersion}`);
  console.log(`👉 Engine: ${YTDLP_BIN}`);
  console.log(`👉 GET  /api/search/youtube?q=... (Backend Search Proxy)`);
  console.log(`👉 POST /api/youtube/extract (Multi-format HQ/MQ/LQ)`);
  console.log(`👉 GET  /api/youtube/download?formatId=...&quality=...`);
});
