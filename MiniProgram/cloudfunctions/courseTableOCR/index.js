const cloud = require('wx-server-sdk')
const https = require('https')

cloud.init({ env: cloud.DYNAMIC_CURRENT_ENV })

const FUNCTION_VERSION = '2026.08.27-normalize-v5'
const ARK_HOSTNAME = 'ark.cn-beijing.volces.com'
const ARK_PATH = '/api/v3/chat/completions'
const CONNECT_TIMEOUT_MS = 5000
const DOWNLOAD_TIMEOUT_MS = 5000
const ARK_TIMEOUT_MS = 20000
const TOTAL_TIMEOUT_MS = 21000
const SYNC_BUDGET_MS = DOWNLOAD_TIMEOUT_MS + TOTAL_TIMEOUT_MS
const MAX_IMAGE_BYTES = 2 * 1024 * 1024
const MAX_BASE64_CHARS = 3 * 1024 * 1024
const MAX_RESPONSE_BYTES = 2 * 1024 * 1024
const MAX_OUTPUT_TOKENS = 1024
const THINKING_FIELDS = new Set(['thinking', 'thinking_type', 'none'])

function requestId(context) {
  return (context && context.requestId) || `${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 8)}`
}

function log(stage, fields) {
  console.log(JSON.stringify(Object.assign({
    component: 'courseTableOCR',
    functionVersion: FUNCTION_VERSION,
    stage
  }, fields || {})))
}

function serviceError(message, code, details) {
  const error = new Error(message)
  error.code = code
  error.details = details || {}
  return error
}

function withTimeout(promise, timeoutMs, error) {
  let timer
  return Promise.race([
    promise,
    new Promise((resolve, reject) => {
      timer = setTimeout(() => reject(error), timeoutMs)
    })
  ]).finally(() => clearTimeout(timer))
}

function detectImageMime(buffer) {
  if (buffer.length >= 3 && buffer[0] === 0xff && buffer[1] === 0xd8 && buffer[2] === 0xff) return 'image/jpeg'
  if (buffer.length >= 8 && buffer.slice(0, 8).equals(Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]))) return 'image/png'
  if (buffer.length >= 12 && buffer.slice(0, 4).toString('ascii') === 'RIFF' && buffer.slice(8, 12).toString('ascii') === 'WEBP') return 'image/webp'
  throw serviceError('图片格式不受支持，请选择 JPG、PNG 或 WebP 图片', 'UNSUPPORTED_IMAGE_FORMAT')
}

function configuredThinkingField() {
  const value = String(process.env.ARK_THINKING_FIELD || 'thinking').trim().toLowerCase()
  return THINKING_FIELDS.has(value) ? value : 'thinking'
}

function buildArkRequestBody(endpointId, imageDataURL, thinkingField = configuredThinkingField()) {
  const body = {
    model: endpointId,
    temperature: 0,
    max_tokens: MAX_OUTPUT_TOKENS,
    stream: false,
    messages: [{
      role: 'user',
      content: [
        {
          type: 'text',
          text: '请读取这张课程表图片，严格只输出 JSON，不要 Markdown。按视觉上的星期列和节次行识别每门课程。格式：{"courses":[{"name":"课程名","weekday":1,"startPeriod":1,"endPeriod":2,"teacher":"教师","location":"教室","weeks":[1,2,3]}],"warning":""}。weekday 为 1-7，weeks 只填写图片明确出现的周次；无法确定时使用空数组。不要把图片标题、学期名称、星期标题或节次标题当作课程。'
        },
        { type: 'image_url', image_url: { url: imageDataURL } }
      ]
    }]
  }

  // Current Ark Chat Completions uses `thinking`. Some older endpoints only
  // accept `thinking_type`, while others reject both. Keep the fields mutually
  // exclusive so compatibility never turns into an unknown-parameter 400.
  if (thinkingField === 'thinking') body.thinking = { type: 'disabled' }
  if (thinkingField === 'thinking_type') body.thinking_type = 'disabled'
  return JSON.stringify(body)
}

function arkConfigurationHint(statusCode, message, thinkingField) {
  if (statusCode !== 400) return ''
  const normalized = String(message || '').toLowerCase()
  if (normalized.includes('thinking') || normalized.includes('unknown') || normalized.includes('parameter')) {
    return `当前端点可能不支持 ${thinkingField} 字段；请将 ARK_THINKING_FIELD 改为 none，或仅在旧端点文档明确要求时改为 thinking_type。`
  }
  if (normalized.includes('image') || normalized.includes('vision') || normalized.includes('multimodal') || normalized.includes('model')) {
    return '请确认 ARK_ENDPOINT_ID 绑定的是支持图片输入的视觉/多模态模型。'
  }
  return '请确认 ARK_ENDPOINT_ID 绑定支持图片输入的模型，并核对该端点支持的 Chat Completions 参数。'
}

function arkRequest(apiKey, endpointId, imageDataURL, diagnostics) {
  const thinkingField = configuredThinkingField()
  const body = buildArkRequestBody(endpointId, imageDataURL, thinkingField)

  return new Promise((resolve, reject) => {
    const startedAt = Date.now()
    let settled = false
    let request

    const clearTimers = () => {
      clearTimeout(connectTimer)
      clearTimeout(totalTimer)
    }
    const succeed = value => {
      if (settled) return
      settled = true
      clearTimers()
      resolve(value)
    }
    const fail = error => {
      if (settled) return
      settled = true
      clearTimers()
      reject(error)
    }
    const abort = error => {
      if (request) request.destroy(error)
      else fail(error)
    }

    const connectTimer = setTimeout(() => {
      abort(serviceError('连接火山方舟超时，请稍后重试', 'ARK_CONNECT_TIMEOUT', { timeoutMs: CONNECT_TIMEOUT_MS }))
    }, CONNECT_TIMEOUT_MS)
    const totalTimer = setTimeout(() => {
      abort(serviceError('火山方舟识别超过 21 秒，已提前终止以避免云函数 30 秒超时', 'ARK_TOTAL_TIMEOUT', { timeoutMs: TOTAL_TIMEOUT_MS }))
    }, TOTAL_TIMEOUT_MS)

    log('ark.request.start', Object.assign({}, diagnostics, {
      requestBytes: Buffer.byteLength(body),
      maxOutputTokens: MAX_OUTPUT_TOKENS,
      thinkingField,
      connectTimeoutMs: CONNECT_TIMEOUT_MS,
      responseTimeoutMs: ARK_TIMEOUT_MS,
      totalTimeoutMs: TOTAL_TIMEOUT_MS
    }))

    request = https.request({
      hostname: ARK_HOSTNAME,
      path: ARK_PATH,
      method: 'POST',
      headers: {
        Authorization: `Bearer ${apiKey}`,
        'Content-Type': 'application/json',
        'Content-Length': Buffer.byteLength(body)
      }
    }, response => {
      clearTimeout(connectTimer)
      const chunks = []
      let responseBytes = 0
      const arkLogId = response.headers['x-tt-logid'] || response.headers['x-request-id'] || ''
      log('ark.response.headers', Object.assign({}, diagnostics, {
        elapsedMs: Date.now() - startedAt,
        statusCode: response.statusCode,
        arkLogId
      }))

      response.on('data', chunk => {
        responseBytes += chunk.length
        if (responseBytes > MAX_RESPONSE_BYTES) {
          response.destroy(serviceError('火山方舟返回内容过大', 'ARK_RESPONSE_TOO_LARGE'))
          return
        }
        chunks.push(chunk)
      })
      response.on('error', fail)
      response.on('end', () => {
        const output = Buffer.concat(chunks).toString('utf8')
        log('ark.response.end', Object.assign({}, diagnostics, {
          elapsedMs: Date.now() - startedAt,
          statusCode: response.statusCode,
          responseBytes,
          arkLogId
        }))
        let data
        try {
          data = JSON.parse(output)
        } catch (error) {
          return fail(serviceError('火山方舟返回了无法解析的结果', 'ARK_INVALID_RESPONSE', { statusCode: response.statusCode, arkLogId }))
        }
        if ((response.statusCode || 500) < 200 || (response.statusCode || 500) >= 300 || data.error) {
          const message = data.error && data.error.message ? data.error.message : `火山方舟 HTTP ${response.statusCode}`
          const hint = arkConfigurationHint(response.statusCode, message, thinkingField)
          return fail(serviceError(message, 'ARK_HTTP_ERROR', { statusCode: response.statusCode, arkLogId, hint }))
        }
        succeed(data)
      })
    })

    request.on('socket', socket => {
      socket.once('secureConnect', () => {
        clearTimeout(connectTimer)
        log('ark.connection.ready', Object.assign({}, diagnostics, { elapsedMs: Date.now() - startedAt }))
      })
    })
    request.setTimeout(ARK_TIMEOUT_MS, () => {
      request.destroy(serviceError('火山方舟 20 秒内没有完成响应，已主动终止', 'ARK_RESPONSE_TIMEOUT', { timeoutMs: ARK_TIMEOUT_MS }))
    })
    request.on('error', fail)
    request.write(body)
    request.end()
  })
}

function contentText(response) {
  const content = response && response.choices && response.choices[0] && response.choices[0].message && response.choices[0].message.content
  if (typeof content === 'string') return content
  if (Array.isArray(content)) return content.map(item => item && item.text).filter(Boolean).join('\n')
  return ''
}

function jsonCandidate(content) {
  const stripped = String(content).replace(/^```json\s*/i, '').replace(/```\s*$/i, '').trim()
  const firstBrace = stripped.indexOf('{')
  const firstBracket = stripped.indexOf('[')
  let start = firstBrace
  let closing = '}'
  if (firstBracket >= 0 && (firstBrace < 0 || firstBracket < firstBrace)) {
    start = firstBracket
    closing = ']'
  }
  const end = stripped.lastIndexOf(closing)
  return start >= 0 && end > start ? stripped.slice(start, end + 1) : stripped
}

function arrayFromContainer(value) {
  if (Array.isArray(value)) return value
  if (!value || typeof value !== 'object') return []
  if (value.name || value.courseName || value.title || value['课程名']) return [value]
  return Object.keys(value).reduce((items, key) => {
    const entry = value[key]
    if (Array.isArray(entry)) return items.concat(entry)
    if (entry && typeof entry === 'object') items.push(entry)
    return items
  }, [])
}

function parsedCourses(parsed) {
  if (Array.isArray(parsed)) return parsed
  if (!parsed || typeof parsed !== 'object') return []
  const containers = [
    parsed.courses, parsed.course, parsed.courseList, parsed.course_list, parsed.schedule, parsed.items,
    parsed.data && parsed.data.courses, parsed.data && parsed.data.courseList, parsed.data && parsed.data.items, Array.isArray(parsed.data) ? parsed.data : undefined,
    parsed.result && parsed.result.courses, parsed.result && parsed.result.courseList, Array.isArray(parsed.result) ? parsed.result : undefined
  ]
  for (let index = 0; index < containers.length; index += 1) {
    const courses = arrayFromContainer(containers[index])
    if (courses.length) return courses
  }
  return []
}

function parseDraft(content) {
  try {
    const parsed = JSON.parse(jsonCandidate(content))
    const courses = parsedCourses(parsed)
    return {
      text: content,
      warning: parsed.warning || (courses.length ? '请确认识别出的课程和周次' : '识别结果没有结构化课程，不能直接导入；请查看原文后重试或手动新建。'),
      courses
    }
  } catch (error) {
    // Minimal fallback: keep the model output visible for manual confirmation
    // instead of turning a usable OCR response into another timeout/error.
    return {
      text: content,
      warning: '模型返回的内容不是结构化 JSON，请根据识别文本手动确认课程。',
      courses: []
    }
  }
}

exports.main = async (event, context) => {
  const startedAt = Date.now()
  const id = requestId(context)
  const meta = () => ({ functionVersion: FUNCTION_VERSION, requestId: id, elapsedMs: Date.now() - startedAt })

  if (event && event.action === 'health') {
    const health = {
      ok: true,
      functionVersion: FUNCTION_VERSION,
      arkConfigured: Boolean(process.env.ARK_API_KEY && process.env.ARK_ENDPOINT_ID),
      arkHostname: ARK_HOSTNAME,
      arkPath: ARK_PATH,
      endpointConfigured: Boolean(process.env.ARK_ENDPOINT_ID),
      endpointCapabilityHint: 'ARK_ENDPOINT_ID 必须绑定支持图片输入的视觉/多模态模型',
      thinkingField: configuredThinkingField(),
      maxOutputTokens: MAX_OUTPUT_TOKENS,
      maxImageBytes: MAX_IMAGE_BYTES,
      downloadTimeoutMs: DOWNLOAD_TIMEOUT_MS,
      arkTimeoutMs: ARK_TIMEOUT_MS,
      syncBudgetMs: SYNC_BUDGET_MS,
      syncBudgetHint: '同步云函数受约 30 秒平台边界限制；当前总预算 26 秒，不能直接等待 60 秒'
    }
    log('health', Object.assign({ requestId: id }, health))
    return { health, meta: meta() }
  }

  try {
    if (!event || !event.fileID) throw serviceError('没有收到图片 fileID', 'MISSING_FILE_ID')
    if (!process.env.ARK_API_KEY || !process.env.ARK_ENDPOINT_ID) {
      throw serviceError('未配置 ARK_API_KEY 或 ARK_ENDPOINT_ID', 'ARK_NOT_CONFIGURED')
    }

    log('download.start', { requestId: id })
    const file = await withTimeout(
      cloud.downloadFile({ fileID: event.fileID }),
      DOWNLOAD_TIMEOUT_MS,
      serviceError('从云存储下载图片超过 5 秒，请检查 fileID 或云环境', 'DOWNLOAD_TIMEOUT', { timeoutMs: DOWNLOAD_TIMEOUT_MS })
    )
    const image = file.fileContent
    log('download.end', { requestId: id, elapsedMs: Date.now() - startedAt, imageBytes: image.length })
    if (!Buffer.isBuffer(image) || image.length === 0) throw serviceError('下载到的图片为空', 'EMPTY_IMAGE')
    if (image.length > MAX_IMAGE_BYTES) {
      throw serviceError(`图片压缩后仍超过 ${Math.round(MAX_IMAGE_BYTES / 1024 / 1024)} MB，请裁剪后重试`, 'IMAGE_TOO_LARGE', { imageBytes: image.length, maxImageBytes: MAX_IMAGE_BYTES })
    }

    const mime = detectImageMime(image)
    const imageBase64 = image.toString('base64')
    if (imageBase64.length > MAX_BASE64_CHARS) {
      throw serviceError('Base64 图片请求体过大，请裁剪后重试', 'BASE64_TOO_LARGE', { base64Chars: imageBase64.length, maxBase64Chars: MAX_BASE64_CHARS })
    }
    log('image.ready', { requestId: id, elapsedMs: Date.now() - startedAt, imageBytes: image.length, base64Chars: imageBase64.length, mime })

    const response = await arkRequest(
      process.env.ARK_API_KEY,
      process.env.ARK_ENDPOINT_ID,
      `data:${mime};base64,${imageBase64}`,
      { requestId: id, imageBytes: image.length, base64Chars: imageBase64.length }
    )
    const content = contentText(response)
    if (!content) throw serviceError('火山方舟没有返回识别内容', 'ARK_EMPTY_CONTENT')
    const draft = parseDraft(content)
    log('complete', { requestId: id, elapsedMs: Date.now() - startedAt, courseCount: draft.courses.length })
    return { draft, meta: meta() }
  } catch (error) {
    log('failed', {
      requestId: id,
      elapsedMs: Date.now() - startedAt,
      errorCode: error.code || 'OCR_FAILED',
      message: error.message || '课程表识别失败',
      details: error.details || {}
    })
    return {
      error: error.message || '课程表识别失败',
      errorCode: error.code || 'OCR_FAILED',
      details: error.details || {},
      meta: meta()
    }
  }
}

exports._test = {
  detectImageMime,
  parseDraft,
  parsedCourses,
  jsonCandidate,
  contentText,
  buildArkRequestBody,
  arkConfigurationHint,
  constants: { FUNCTION_VERSION, DOWNLOAD_TIMEOUT_MS, ARK_TIMEOUT_MS, TOTAL_TIMEOUT_MS, SYNC_BUDGET_MS, MAX_IMAGE_BYTES, MAX_BASE64_CHARS, MAX_OUTPUT_TOKENS }
}
