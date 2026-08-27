const assert = require('node:assert/strict')
const { _test } = require('./index')

assert.equal(_test.constants.ARK_TIMEOUT_MS, 20000)
assert.equal(_test.constants.DOWNLOAD_TIMEOUT_MS, 5000)
assert.equal(_test.constants.TOTAL_TIMEOUT_MS, 21000)
assert.equal(_test.constants.SYNC_BUDGET_MS, 26000)
assert.equal(_test.constants.MAX_IMAGE_BYTES, 2 * 1024 * 1024)
const requestBody = JSON.parse(_test.buildArkRequestBody('endpoint-test', 'data:image/png;base64,AA=='))
assert.deepEqual(requestBody.thinking, { type: 'disabled' })
assert.equal(requestBody.thinking_type, undefined)
assert.equal(requestBody.max_tokens, 1024)
assert.equal(requestBody.model, 'endpoint-test')
assert.equal(requestBody.messages[0].content[1].image_url.url, 'data:image/png;base64,AA==')

const legacyBody = JSON.parse(_test.buildArkRequestBody('endpoint-test', 'data:image/png;base64,AA==', 'thinking_type'))
assert.equal(legacyBody.thinking, undefined)
assert.equal(legacyBody.thinking_type, 'disabled')

const noThinkingBody = JSON.parse(_test.buildArkRequestBody('endpoint-test', 'data:image/png;base64,AA==', 'none'))
assert.equal(noThinkingBody.thinking, undefined)
assert.equal(noThinkingBody.thinking_type, undefined)

assert.match(_test.arkConfigurationHint(400, 'unknown parameter thinking', 'thinking'), /ARK_THINKING_FIELD/)
assert.match(_test.arkConfigurationHint(400, 'the model does not support image input', 'thinking'), /视觉\/多模态模型/)
assert.equal(_test.arkConfigurationHint(401, 'unauthorized', 'thinking'), '')
assert.equal(_test.detectImageMime(Buffer.from([0xff, 0xd8, 0xff, 0x00])), 'image/jpeg')
assert.equal(
  _test.detectImageMime(Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])),
  'image/png'
)

const parsed = _test.parseDraft('{"courses":[{"name":"高等数学"}],"warning":""}')
assert.equal(parsed.courses.length, 1)
assert.equal(parsed.courses[0].name, '高等数学')

const fallback = _test.parseDraft('识别到高等数学，但模型没有返回 JSON。')
assert.deepEqual(fallback.courses, [])
assert.match(fallback.warning, /不是结构化 JSON/)
assert.equal(_test.contentText({ choices: [{ message: { content: [{ text: '第一段' }, { text: '第二段' }] } }] }), '第一段\n第二段')

console.log(`courseTableOCR ${_test.constants.FUNCTION_VERSION} tests passed`)
