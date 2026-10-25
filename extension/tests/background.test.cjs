const { test } = require('node:test');
const assert = require('node:assert/strict');
const vm = require('node:vm');
const fs = require('node:fs');
const path = require('node:path');

test('toolbar activation injects only into standard HTTPS YouTube watch pages', async () => {
  let click;
  const injections = [];
  const chrome = {
    action: {
      onClicked: { addListener: (callback) => { click = callback; } },
      setBadgeText: async () => {}, setTitle: async () => {}
    },
    scripting: { executeScript: async (request) => injections.push(request) }
  };
  vm.runInNewContext(fs.readFileSync(path.join(__dirname, '../background.js'), 'utf8'), { chrome, URL });
  for (const url of [undefined, 'chrome://extensions', 'https://example.com/watch?v=x', 'https://youtube.com.example.com/watch?v=x', 'http://youtube.com/watch?v=x', 'https://www.youtube.com/shorts/x']) await click({ id: 1, url });
  assert.equal(injections.length, 0);
  await click({ id: 123, url: 'https://www.youtube.com/watch?v=x' });
  assert.equal(injections.length, 1);
  assert.equal(injections[0].target.tabId, 123);
  assert.equal(injections[0].files.join(','), 'core.js,content.js');
});

test('manifest grants only temporary on-click access and injection', () => {
  const manifest = JSON.parse(fs.readFileSync(path.join(__dirname, '../manifest.json')));
  assert.deepEqual(manifest.permissions, ['activeTab', 'scripting']);
  assert.equal(manifest.host_permissions, undefined);
  assert.equal(manifest.content_scripts, undefined);
});
