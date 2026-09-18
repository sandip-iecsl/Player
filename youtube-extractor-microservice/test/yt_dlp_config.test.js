const test = require('node:test');
const assert = require('node:assert/strict');
const { buildYtDlpArgs } = require('../yt_dlp_config');

test('buildYtDlpArgs adds authentication and runtime flags once', () => {
  const args = buildYtDlpArgs({
    dumpJson: true,
    format: 'bestaudio',
    extraArgs: ['--flat-playlist'],
  });

  assert.ok(args.filter((arg) => arg === '--cookies').length <= 1);
  assert.equal(args.filter((arg) => arg === '--js-runtimes').length, 1);
  assert.equal(args.filter((arg) => arg === '--remote-components').length, 1);
  assert.equal(args.at(-1), '--');
});

test('buildYtDlpArgs never emits duplicate singleton flags', () => {
  const args = buildYtDlpArgs({ getUrl: true, format: '140' });
  for (const flag of ['--cookies', '--js-runtimes', '--remote-components', '--no-playlist', '--no-check-certificates']) {
    assert.ok(args.filter((arg) => arg === flag).length <= 1, `${flag} was duplicated`);
  }
});
