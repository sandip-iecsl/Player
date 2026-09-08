const axios = require('axios');

const BASE_URL = 'https://player-wwrc.onrender.com';

const testUrls = [
  'https://www.youtube.com/watch?v=kJQP7kiw5Fk', // Despacito
  'https://youtu.be/fJ9rUzIMcZQ',                 // Queen - Bohemian Rhapsody
  'https://www.youtube.com/shorts/3nQNiWdeH2Q',   // YouTube Short
  'https://music.youtube.com/watch?v=4NRXx6U8ABQ',// The Weeknd - Blinding Lights
];

async function runHealthCheck() {
  console.log('\n--- 1. Testing Health Endpoint ---');
  const start = Date.now();
  const res = await axios.get(`${BASE_URL}/health`, { timeout: 10000 });
  console.log(`✅ Health Status: ${res.status} (${Date.now() - start}ms)`);
  console.log('Response:', JSON.stringify(res.data, null, 2));
}

async function runExtractionTests() {
  console.log('\n--- 2. Testing Multi-Format Extraction for Multiple URLs ---');
  for (const url of testUrls) {
    const start = Date.now();
    try {
      console.log(`\n🔍 Extracting: ${url}`);
      const res = await axios.post(
        `${BASE_URL}/api/youtube/extract`,
        { url },
        { timeout: 25000 }
      );
      const elapsed = Date.now() - start;
      console.log(`✅ Success in ${elapsed}ms: "${res.data.title}" by ${res.data.artist}`);
      console.log(`   ID: ${res.data.id} | Duration: ${res.data.duration}s`);
      console.log(`   Available Formats: ${res.data.availableFormats?.length || 0} tiers:`);
      if (res.data.availableFormats) {
        res.data.availableFormats.forEach((f) => {
          console.log(`     • ${f.quality} (${f.bitrate}): Format ${f.formatId}, Est: ${f.estimatedSizeMb}`);
        });
      }
    } catch (err) {
      console.error(`❌ Error on ${url}: ${err.response?.status || err.message}`);
      if (err.response?.data) console.error('Details:', err.response.data);
    }
  }
}

async function runDownloadHeaderTest() {
  console.log('\n--- 3. Testing Download Endpoint (Streaming Headers) ---');
  const start = Date.now();
  try {
    const targetUrl = 'https://www.youtube.com/watch?v=kJQP7kiw5Fk';
    const res = await axios.get(`${BASE_URL}/api/youtube/download`, {
      params: { url: targetUrl, quality: 'Medium', formatId: '139' },
      responseType: 'stream',
      timeout: 15000,
    });
    console.log(`✅ Download Stream Status: ${res.status} (${Date.now() - start}ms)`);
    console.log(`   Content-Type: ${res.headers['content-type']}`);
    console.log(`   Content-Disposition: ${res.headers['content-disposition']}`);
    console.log(`   Accept-Ranges: ${res.headers['accept-ranges']}`);
    res.data.destroy(); // Abort stream after verifying headers
  } catch (err) {
    console.error(`❌ Download Endpoint Error: ${err.response?.status || err.message}`);
  }
}

async function runHeavyLoadTest(concurrency = 8) {
  console.log(`\n--- 4. Heavy Load Stress Test: ${concurrency} Concurrent Parallel Requests ---`);
  const start = Date.now();
  const promises = [];

  for (let i = 0; i < concurrency; i++) {
    const targetUrl = testUrls[i % testUrls.length];
    promises.push(
      axios
        .post(
          `${BASE_URL}/api/youtube/extract`,
          { url: targetUrl },
          { timeout: 35000 }
        )
        .then((res) => ({
          success: true,
          index: i,
          title: res.data.title,
          formats: res.data.availableFormats?.length || 0,
        }))
        .catch((err) => ({
          success: false,
          index: i,
          error: err.response?.status || err.message,
        }))
    );
  }

  const results = await Promise.all(promises);
  const totalTime = Date.now() - start;

  const passed = results.filter((r) => r.success).length;
  const failed = results.filter((r) => !r.success).length;

  console.log(`\n📊 Heavy Load Test Results in ${totalTime}ms:`);
  console.log(`   Total Requests: ${concurrency}`);
  console.log(`   ✅ Successful: ${passed}`);
  console.log(`   ❌ Failed: ${failed}`);
  results.forEach((r) => {
    if (r.success) {
      console.log(`   [Req #${r.index}] ✅ "${r.title}" (${r.formats} formats)`);
    } else {
      console.log(`   [Req #${r.index}] ❌ ${r.error}`);
    }
  });
}

async function runInvalidUrlResilienceTest() {
  console.log('\n--- 5. Error & Edge Case Resilience Test ---');
  const badInputs = [
    '',
    'not_a_url',
    'https://google.com/search?q=test',
    'https://www.youtube.com/watch?v=INVALID_ID_9999999',
  ];

  for (const input of badInputs) {
    try {
      await axios.post(
        `${BASE_URL}/api/youtube/extract`,
        { url: input },
        { timeout: 10000 }
      );
      console.log(`⚠️ Expected error for input "${input}" but got success.`);
    } catch (err) {
      console.log(`✅ Cleanly handled bad input "${input}" -> HTTP ${err.response?.status || err.message}`);
    }
  }
}

async function main() {
  console.log('====================================================');
  console.log(`🚀 Starting Comprehensive Live Backend Tests`);
  console.log(`🎯 Target: ${BASE_URL}`);
  console.log('====================================================');

  try {
    await runHealthCheck();
    await runExtractionTests();
    await runDownloadHeaderTest();
    await runHeavyLoadTest(8);
    await runInvalidUrlResilienceTest();
    console.log('\n====================================================');
    console.log('🎉 All Backend Tests Completed!');
    console.log('====================================================\n');
  } catch (e) {
    console.error('Fatal Test Runner Error:', e);
  }
}

main();
