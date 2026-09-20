const fs = require('fs');
const path = require('path');
const https = require('https');
const { execSync } = require('child_process');

function installPythonDependencies() {
  try {
    console.log('[PostInstall] Attempting to install ytmusicapi for Python...');
    execSync('python3 -m pip install ytmusicapi --no-cache-dir || pip3 install ytmusicapi --no-cache-dir || pip install ytmusicapi --no-cache-dir', { stdio: 'ignore', timeout: 45000 });
    console.log('[PostInstall] Successfully verified/installed ytmusicapi.');
  } catch (e) {
    console.warn('[PostInstall] Notice: Python ytmusicapi pip setup warning:', e.message);
  }
}

// Only download on Linux / Render platforms (Windows repo already has yt-dlp.exe)
if (process.platform === 'win32') {
  console.log('[PostInstall] Windows platform detected — using local yt-dlp.exe');
  installPythonDependencies();
  process.exit(0);
}

const targetPath = path.join(__dirname, 'yt-dlp');

if (fs.existsSync(targetPath)) {
  try {
    fs.chmodSync(targetPath, 0o755);
    console.log('[PostInstall] yt-dlp already present and executable at', targetPath);
    installPythonDependencies();
    process.exit(0);
  } catch (_) {}
}

installPythonDependencies();
console.log('[PostInstall] Downloading Linux yt-dlp standalone binary...');

function downloadBinary(url, dest, callback) {
  const file = fs.createWriteStream(dest, { mode: 0o755 });
  https.get(url, (response) => {
    if (response.statusCode >= 300 && response.statusCode < 400 && response.headers.location) {
      // Follow redirect
      downloadBinary(response.headers.location, dest, callback);
      return;
    }
    if (response.statusCode !== 200) {
      console.warn(`[PostInstall] Failed to download yt-dlp: HTTP ${response.statusCode}`);
      file.close();
      if (fs.existsSync(dest)) fs.unlinkSync(dest);
      callback(new Error(`HTTP ${response.statusCode}`));
      return;
    }
    response.pipe(file);
    file.on('finish', () => {
      file.close(() => {
        try {
          fs.chmodSync(dest, 0o755);
          console.log('[PostInstall] Successfully installed executable yt-dlp at:', dest);
        } catch (err) {
          console.warn('[PostInstall] chmod warning:', err.message);
        }
        callback(null);
      });
    });
  }).on('error', (err) => {
    console.warn('[PostInstall] Download error:', err.message);
    if (fs.existsSync(dest)) fs.unlinkSync(dest);
    callback(err);
  });
}

downloadBinary('https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp', targetPath, (err) => {
  if (err) {
    console.warn('[PostInstall] yt-dlp binary download had an error, will use pure JS Innertube/youtubei.js engine.');
  }
  process.exit(0); // Never fail npm install
});
