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
assert.equal(requestBody.max_tokens, 4096)
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
assert.equal(parsed.parseDiagnostics.status, 'parsed')

const screenshotSample = _test.parseDraft('{"courses":[{"name":"大学计算机基础","weekday":1,"startPeriod":1,"endPeriod":2,"teacher":"王老师","location":"教学楼A101","weeks":[1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16]}],"warning":""}')
assert.equal(screenshotSample.courses.length, 1)
assert.equal(screenshotSample.courses[0].weekday, 1)
assert.equal(screenshotSample.courses[0].startPeriod, 1)
assert.equal(screenshotSample.parseDiagnostics.status, 'parsed')

const aliasedRoot = _test.parseDraft('识别结果：```json\n{"courseList":[{"courseName":"网页设计","weekDay":"周四","section":"第5-6节","weekRange":"[1-16周]"}]}\n```')
assert.equal(aliasedRoot.courses.length, 1)
assert.equal(aliasedRoot.courses[0].courseName, '网页设计')

const arrayRoot = _test.parseDraft('[{"title":"大学英语","day":"Monday","start":1,"end":2}]')
assert.equal(arrayRoot.courses.length, 1)
assert.equal(arrayRoot.courses[0].title, '大学英语')

const emptyStructured = _test.parseDraft('{"courses":[],"text":"高等数学 周一 第1-2节"}')
assert.deepEqual(emptyStructured.courses, [])
assert.match(emptyStructured.warning, /courses 为空/)

const invisibleWrapped = _test.parseDraft('\uFEFF\u200B识别结果：```json\n{"courses":[{"name":"线性代数","weekday":2,"startPeriod":3,"endPeriod":4,"weeks":"[1-16周]"}]}\n```')
assert.equal(invisibleWrapped.courses.length, 1)
assert.equal(invisibleWrapped.courses[0].name, '线性代数')

const truncated = _test.parseDraft('{"courses":[{"name":"高等数学","weekday":1,"startPeriod":1,"endPeriod":2},{"name":"大学英语","weekday":2,"startPeriod":3,"endPeriod":4},{"name":"未完成课程","weekday":')
assert.equal(truncated.courses.length, 2)
assert.equal(truncated.parseDiagnostics.status, 'recovered')
assert.equal(truncated.parseDiagnostics.likelyTruncated, true)
assert.match(truncated.warning, /已恢复 2 门/)

const trailingComma = _test.parseDraft('{"courses":[{"name":"物理", "weekday":3,}],}')
assert.equal(trailingComma.courses.length, 1)

const fallback = _test.parseDraft('识别到高等数学，但模型没有返回 JSON。')
assert.deepEqual(fallback.courses, [])
assert.match(fallback.warning, /JSON 解析失败/)
assert.equal(fallback.parseDiagnostics.status, 'invalid')
assert.equal(_test.contentText({ choices: [{ message: { content: [{ text: '第一段' }, { text: '第二段' }] } }] }), '第一段\n第二段')

console.log(`courseTableOCR ${_test.constants.FUNCTION_VERSION} tests passed`)
