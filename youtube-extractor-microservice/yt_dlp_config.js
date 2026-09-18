const { execFileSync } = require('child_process');
const fs = require('fs');
const path = require('path');

const SERVER_VERSION = '2026.09.19';
const COOKIE_RUNTIME_PATH = path.join(require('os').tmpdir(), 'aura-youtube-cookies.txt');
const YTDLP_BIN = process.env.YTDLP_BIN || (fs.existsSync(path.join(__dirname, process.platform === 'win32' ? 'yt-dlp.exe' : 'yt-dlp'))
  ? path.join(__dirname, process.platform === 'win32' ? 'yt-dlp.exe' : 'yt-dlp')
  : 'yt-dlp');
const JS_RUNTIME = process.env.YTDLP_JS_RUNTIME || (process.platform === 'win32' ? 'node' : '/usr/local/bin/deno');

function fileIsReadable(filePath) {
  if (!filePath) return false;
  try {
    fs.accessSync(filePath, fs.constants.R_OK);
    return true;
  } catch (_) {
    return false;
  }
}

function prepareCookies() {
  const configuredFile = process.env.YOUTUBE_COOKIES_FILE?.trim();
  if (configuredFile && fileIsReadable(configuredFile)) return configuredFile;

  const encodedCookies = process.env.YOUTUBE_COOKIES_BASE64?.trim();
  if (!encodedCookies) return null;

  try {
    const decodedCookies = Buffer.from(encodedCookies, 'base64');
    if (decodedCookies.length === 0) throw new Error('empty cookie payload');
    fs.writeFileSync(COOKIE_RUNTIME_PATH, decodedCookies, { mode: 0o600 });
    return COOKIE_RUNTIME_PATH;
  } catch (error) {
    console.warn(`[YouTube] Cookie secret could not be loaded: ${error.message}`);
    return null;
  }
}

const cookiePath = prepareCookies();

function buildYtDlpArgs({ format, dumpJson = false, getUrl = false, outputPath = null, extraArgs = [] } = {}) {
  const args = [
    ...(dumpJson ? ['--dump-single-json'] : []),
    ...(getUrl ? ['-g'] : []),
    '--no-warnings',
    '--no-playlist',
    '--no-check-certificates',
    '--remote-components', 'ejs:github',
    '--js-runtimes', JS_RUNTIME,
    '--extractor-args', 'youtube:player_client=tv_embedded,mweb,android,ios',
    '--extractor-args', 'youtube:player_skip=webpage,configs',
    ...(cookiePath ? ['--cookies', cookiePath] : []),
    ...(format ? ['-f', format] : []),
    ...(outputPath ? ['-o', outputPath] : []),
    ...extraArgs,
    '--',
  ];
  return args;
}

function readCommandVersion(command, args = ['--version']) {
  try {
    return execFileSync(command, args, { encoding: 'utf8', timeout: 10000 }).trim() || null;
  } catch (_) {
    return null;
  }
}

function diagnostics() {
  const nodeVersion = process.versions.node;
  const jsRuntimeVersion = readCommandVersion(JS_RUNTIME, ['--version']);
  return {
    nodeVersion,
    ytDlpVersion: readCommandVersion(YTDLP_BIN),
    denoVersion: readCommandVersion('deno', ['--version']),
    jsRuntime: JS_RUNTIME,
    jsRuntimeVersion,
    ejsConfigured: true,
    jsRuntimeConfigured: Boolean(jsRuntimeVersion),
    cookiesConfigured: Boolean(cookiePath),
    cookiesReadable: fileIsReadable(cookiePath),
    serverVersion: SERVER_VERSION,
  };
}

module.exports = {
  COOKIE_RUNTIME_PATH,
  JS_RUNTIME,
  SERVER_VERSION,
  YTDLP_BIN,
  buildYtDlpArgs,
  cookiePath,
  diagnostics,
  fileIsReadable,
};
