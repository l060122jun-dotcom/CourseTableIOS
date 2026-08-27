const assert = require('node:assert/strict')
const { _test } = require('./index')

assert.equal(_test.constants.ARK_TIMEOUT_MS, 20000)
assert.equal(_test.constants.MAX_IMAGE_BYTES, 2 * 1024 * 1024)
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
