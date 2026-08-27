const cloud = require('wx-server-sdk')
const https = require('https')

cloud.init({ env: cloud.DYNAMIC_CURRENT_ENV })

const FUNCTION_VERSION = '2026.08.27-deepseek-provider-v10'
const ARK_HOSTNAME = 'ark.cn-beijing.volces.com'
const ARK_PATH = '/api/v3/chat/completions'
const DEEPSEEK_DEFAULT_BASE_URL = 'https://api.deepseek.com'
const DEEPSEEK_DEFAULT_MODEL = 'deepseek-v4-flash-vision-exp'
const CONNECT_TIMEOUT_MS = 5000
const DOWNLOAD_TIMEOUT_MS = 5000
const ARK_TIMEOUT_MS = 26000
const TOTAL_TIMEOUT_MS = 27000
const SYNC_BUDGET_MS = 29000
const MAX_IMAGE_BYTES = 2 * 1024 * 1024
const MAX_BASE64_CHARS = 3 * 1024 * 1024
const MAX_RESPONSE_BYTES = 2 * 1024 * 1024
const MAX_OUTPUT_TOKENS = 4096
const THINKING_FIELDS = new Set(['thinking', 'thinking_type', 'none'])
const OCR_PROMPT = '读取课程表图片。只输出紧凑单行 JSON，不要 Markdown、解释或换行。格式：{"courses":[{"name":"课程名","weekday":1,"startPeriod":1,"endPeriod":2,"teacher":"教师","location":"教室","weeks":[1,2,3]}],"warning":""}。weekday 为 1-7，weeks 只填图片明确出现的周次；无法确定用空数组。不要把标题、星期标题或节次标题当课程。'

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

function deepseekEndpoint(baseUrl) {
  let endpoint
  try {
    endpoint = new URL(baseUrl || DEEPSEEK_DEFAULT_BASE_URL)
  } catch (_) {
    throw serviceError('DEEPSEEK_BASE_URL 不是有效的 HTTPS 地址', 'DEEPSEEK_INVALID_BASE_URL')
  }
  if (endpoint.protocol !== 'https:' || endpoint.username || endpoint.password || endpoint.search || endpoint.hash) {
    throw serviceError('DEEPSEEK_BASE_URL 必须是无账号、查询参数或锚点的 HTTPS 地址', 'DEEPSEEK_INVALID_BASE_URL')
  }
  const basePath = endpoint.pathname.replace(/\/+$/, '')
  const path = basePath.endsWith('/chat/completions') ? basePath : `${basePath}/chat/completions`
  return { hostname: endpoint.hostname, port: endpoint.port ? Number(endpoint.port) : undefined, path: path || '/chat/completions' }
}

function providerSettings(environment = process.env) {
  const provider = String(environment.AI_PROVIDER || 'ark').trim().toLowerCase()
  if (provider === 'deepseek') {
    const endpoint = deepseekEndpoint(environment.DEEPSEEK_BASE_URL || DEEPSEEK_DEFAULT_BASE_URL)
    return {
      provider,
      label: 'DeepSeek',
      apiKey: environment.DEEPSEEK_API_KEY || '',
      model: environment.DEEPSEEK_MODEL || DEEPSEEK_DEFAULT_MODEL,
      hostname: endpoint.hostname,
      port: endpoint.port,
      path: endpoint.path,
      configured: Boolean(environment.DEEPSEEK_API_KEY),
      officialBase: endpoint.hostname === 'api.deepseek.com'
    }
  }
  if (provider !== 'ark') throw serviceError('AI_PROVIDER 仅支持 ark 或 deepseek', 'AI_PROVIDER_UNSUPPORTED')
  return {
    provider,
    label: '火山方舟',
    apiKey: environment.ARK_API_KEY || '',
    model: environment.ARK_ENDPOINT_ID || '',
    hostname: ARK_HOSTNAME,
    path: ARK_PATH,
    configured: Boolean(environment.ARK_API_KEY && environment.ARK_ENDPOINT_ID),
    officialBase: true
  }
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
          text: OCR_PROMPT
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

function buildDeepSeekRequestBody(model, imageDataURL) {
  return JSON.stringify({
    model,
    temperature: 0,
    max_tokens: MAX_OUTPUT_TOKENS,
    stream: false,
    thinking: { type: 'disabled' },
    response_format: { type: 'json_object' },
    messages: [{
      role: 'user',
      content: [
        { type: 'text', text: OCR_PROMPT },
        { type: 'image_url', image_url: { url: imageDataURL } }
      ]
    }]
  })
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

function providerConfigurationHint(settings, statusCode, message, thinkingField) {
  if (settings.provider === 'ark') return arkConfigurationHint(statusCode, message, thinkingField)
  if (statusCode !== 400 && statusCode !== 404) return ''
  const normalized = String(message || '').toLowerCase()
  if (normalized.includes('image') || normalized.includes('vision') || normalized.includes('content') || normalized.includes('model') || settings.officialBase) {
    return 'DeepSeek 官方 API 当前未公开支持图片 image_url；请确认 DEEPSEEK_MODEL 与 DEEPSEEK_BASE_URL 指向支持 OpenAI-compatible 视觉输入的实验端点，或切回 AI_PROVIDER=ark。'
  }
  return '请核对 DeepSeek 兼容端点的 Chat Completions 路径、模型名和 image_url data URL 支持情况。'
}

function effectiveArkTotalTimeout(syncDeadlineAt, now = Date.now()) {
  if (!Number.isFinite(syncDeadlineAt)) return TOTAL_TIMEOUT_MS
  return Math.max(1000, Math.min(TOTAL_TIMEOUT_MS, syncDeadlineAt - now))
}

function providerRequest(settings, imageDataURL, diagnostics, syncDeadlineAt) {
  const thinkingField = configuredThinkingField()
  const body = settings.provider === 'deepseek'
    ? buildDeepSeekRequestBody(settings.model, imageDataURL)
    : buildArkRequestBody(settings.model, imageDataURL, thinkingField)
  const effectiveTotalTimeoutMs = effectiveArkTotalTimeout(syncDeadlineAt)
  const codePrefix = settings.provider.toUpperCase()
  const stagePrefix = settings.provider

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
      abort(serviceError(`连接${settings.label}超时，请稍后重试`, `${codePrefix}_CONNECT_TIMEOUT`, { timeoutMs: CONNECT_TIMEOUT_MS }))
    }, CONNECT_TIMEOUT_MS)
    const totalTimer = setTimeout(() => {
      abort(serviceError(`${settings.label}未能在本次剩余的 ${Math.round(effectiveTotalTimeoutMs / 1000)} 秒同步预算内完成，已提前终止以避免云函数 30 秒超时`, `${codePrefix}_TOTAL_TIMEOUT`, { timeoutMs: effectiveTotalTimeoutMs, configuredTimeoutMs: TOTAL_TIMEOUT_MS }))
    }, effectiveTotalTimeoutMs)

    log(`${stagePrefix}.request.start`, Object.assign({}, diagnostics, {
      provider: settings.provider,
      model: settings.model,
      requestBytes: Buffer.byteLength(body),
      maxOutputTokens: MAX_OUTPUT_TOKENS,
      thinkingField: settings.provider === 'ark' ? thinkingField : 'thinking',
      connectTimeoutMs: CONNECT_TIMEOUT_MS,
      responseTimeoutMs: ARK_TIMEOUT_MS,
      totalTimeoutMs: effectiveTotalTimeoutMs,
      configuredTotalTimeoutMs: TOTAL_TIMEOUT_MS
    }))

    request = https.request({
      hostname: settings.hostname,
      port: settings.port,
      path: settings.path,
      method: 'POST',
      headers: {
        Authorization: `Bearer ${settings.apiKey}`,
        'Content-Type': 'application/json',
        'Content-Length': Buffer.byteLength(body)
      }
    }, response => {
      clearTimeout(connectTimer)
      const chunks = []
      let responseBytes = 0
      const providerRequestId = response.headers['x-tt-logid'] || response.headers['x-request-id'] || ''
      log(`${stagePrefix}.response.headers`, Object.assign({}, diagnostics, {
        elapsedMs: Date.now() - startedAt,
        statusCode: response.statusCode,
        providerRequestId
      }))

      response.on('data', chunk => {
        responseBytes += chunk.length
        if (responseBytes > MAX_RESPONSE_BYTES) {
          response.destroy(serviceError(`${settings.label}返回内容过大`, `${codePrefix}_RESPONSE_TOO_LARGE`))
          return
        }
        chunks.push(chunk)
      })
      response.on('error', fail)
      response.on('end', () => {
        const output = Buffer.concat(chunks).toString('utf8')
        log(`${stagePrefix}.response.end`, Object.assign({}, diagnostics, {
          elapsedMs: Date.now() - startedAt,
          statusCode: response.statusCode,
          responseBytes,
          providerRequestId
        }))
        let data
        try {
          data = JSON.parse(output)
        } catch (error) {
          return fail(serviceError(`${settings.label}返回了无法解析的结果`, `${codePrefix}_INVALID_RESPONSE`, { statusCode: response.statusCode, providerRequestId }))
        }
        if ((response.statusCode || 500) < 200 || (response.statusCode || 500) >= 300 || data.error) {
          const message = data.error && data.error.message ? data.error.message : `${settings.label} HTTP ${response.statusCode}`
          const hint = providerConfigurationHint(settings, response.statusCode, message, thinkingField)
          return fail(serviceError(message, `${codePrefix}_HTTP_ERROR`, { statusCode: response.statusCode, providerRequestId, hint }))
        }
        succeed(data)
      })
    })

    request.on('socket', socket => {
      socket.once('secureConnect', () => {
        clearTimeout(connectTimer)
        log(`${stagePrefix}.connection.ready`, Object.assign({}, diagnostics, { elapsedMs: Date.now() - startedAt }))
      })
    })
    request.setTimeout(ARK_TIMEOUT_MS, () => {
      request.destroy(serviceError(`${settings.label} 26 秒内没有完成响应，已主动终止`, `${codePrefix}_RESPONSE_TIMEOUT`, { timeoutMs: ARK_TIMEOUT_MS }))
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

function cleanModelText(content) {
  return String(content == null ? '' : content)
    .replace(/[\uFEFF\u200B\u200C\u200D\u2060]/g, '')
    .trim()
}

function normalizedJsonPunctuation(content) {
  return content.replace(/[“”]/g, '"').replace(/：/g, ':').replace(/，/g, ',')
}

function balancedSegments(content, opener) {
  const closer = opener === '{' ? '}' : ']'
  const segments = []
  let depth = 0
  let start = -1
  let inString = false
  let escaped = false
  for (let index = 0; index < content.length; index += 1) {
    const character = content[index]
    if (inString) {
      if (escaped) escaped = false
      else if (character === '\\') escaped = true
      else if (character === '"') inString = false
      continue
    }
    if (character === '"') {
      inString = true
      continue
    }
    if (character === opener) {
      if (depth === 0) start = index
      depth += 1
    } else if (character === closer && depth > 0) {
      depth -= 1
      if (depth === 0 && start >= 0) {
        segments.push(content.slice(start, index + 1))
        start = -1
      }
    }
  }
  return segments
}

function repairJsonCandidate(candidate) {
  let inString = false
  let escaped = false
  let repaired = ''
  for (let index = 0; index < candidate.length; index += 1) {
    const character = candidate[index]
    if (inString && (character === '\n' || character === '\r' || character === '\t')) {
      repaired += character === '\t' ? '\\t' : '\\n'
      continue
    }
    repaired += character
    if (escaped) escaped = false
    else if (character === '\\' && inString) escaped = true
    else if (character === '"') inString = !inString
  }
  return repaired.replace(/,\s*([}\]])/g, '$1')
}

function tryParseJson(candidate) {
  const attempts = [candidate, repairJsonCandidate(candidate)]
  for (let index = 0; index < attempts.length; index += 1) {
    try {
      let parsed = JSON.parse(attempts[index])
      if (typeof parsed === 'string' && /^[\[{]/.test(parsed.trim())) parsed = JSON.parse(repairJsonCandidate(parsed.trim()))
      return parsed
    } catch (_) {
      // Continue through conservative repairs; never invent coordinates or fields.
    }
  }
  return undefined
}

function candidateTexts(content) {
  const cleaned = cleanModelText(content)
  const normalized = normalizedJsonPunctuation(cleaned)
  const candidates = [cleaned]
  const fencePattern = /```(?:json)?\s*([\s\S]*?)```/gi
  let fence
  while ((fence = fencePattern.exec(cleaned))) candidates.push(fence[1].trim())
  if (normalized !== cleaned) candidates.push(normalized)
  ;[cleaned, normalized].forEach(text => {
    candidates.push(...balancedSegments(text, '{'), ...balancedSegments(text, '['))
  })
  const seen = new Set()
  return candidates.filter(candidate => {
    const value = candidate.trim()
    if (!value || seen.has(value)) return false
    seen.add(value)
    return true
  })
}

function jsonCandidate(content) {
  const candidates = candidateTexts(content)
  return candidates.find(candidate => tryParseJson(candidate) !== undefined) || cleanModelText(content)
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

function recoveredCourseObjects(content) {
  const text = normalizedJsonPunctuation(cleanModelText(content))
  const key = /["']?courses["']?\s*:\s*\[/ig
  const match = key.exec(text)
  if (!match) return []
  const arrayText = text.slice(match.index + match[0].length)
  return balancedSegments(arrayText, '{').reduce((courses, candidate) => {
    const parsed = tryParseJson(candidate)
    if (parsed && typeof parsed === 'object' && !Array.isArray(parsed)) courses.push(parsed)
    return courses
  }, [])
}

function parseModelPayload(content) {
  const cleaned = cleanModelText(content)
  const candidates = candidateTexts(cleaned)
  let firstParsed
  for (let index = 0; index < candidates.length; index += 1) {
    const parsed = tryParseJson(candidates[index])
    if (parsed === undefined) continue
    if (firstParsed === undefined) firstParsed = parsed
    const courses = parsedCourses(parsed)
    if (courses.length) {
      const candidateTrimmed = candidates[index].trim()
      const whole = candidateTrimmed === cleaned || /^```(?:json)?[\s\S]*```$/i.test(cleaned)
      return { parsed, courses, recovered: !whole }
    }
  }
  const courses = recoveredCourseObjects(cleaned)
  if (courses.length) return { parsed: firstParsed, courses, recovered: true }
  return { parsed: firstParsed, courses: [], recovered: false }
}

function parseDraft(content) {
  const cleaned = cleanModelText(content)
  const payload = parseModelPayload(cleaned)
  const hasCoursesKey = /["'“”]?courses["'“”]?\s*[:：]/i.test(cleaned)
  const likelyTruncated = hasCoursesKey && !/[}\]]\s*(?:```)?\s*$/.test(cleaned)
  const status = payload.courses.length ? (payload.recovered ? 'recovered' : 'parsed') : (payload.parsed === undefined ? 'invalid' : 'empty')
  let warning = payload.parsed && payload.parsed.warning
  if (!warning && status === 'parsed') warning = '请确认识别出的课程和周次'
  if (!warning && status === 'recovered') warning = `模型 JSON 可能被截断或带有异常包裹，已恢复 ${payload.courses.length} 门完整课程；请重点核对最后一门。`
  if (!warning && status === 'empty') warning = 'JSON 可以解析，但 courses 为空；不能直接导入，请查看原文后重试或手动新建。'
  if (!warning && status === 'invalid') warning = `JSON 解析失败${likelyTruncated ? '，模型输出疑似被截断' : ''}；已保留 ${cleaned.length} 个字符的原文，请重试或手动新建。`
  return {
    text: content,
    warning,
    courses: payload.courses,
    parseDiagnostics: {
      status,
      contentChars: cleaned.length,
      hasCoursesKey,
      likelyTruncated,
      recoveredCourseCount: payload.recovered ? payload.courses.length : 0
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
      arkTotalTimeoutMs: TOTAL_TIMEOUT_MS,
      syncBudgetMs: SYNC_BUDGET_MS,
      syncBudgetHint: '同步云函数受约 30 秒平台边界限制；端到端预算 29 秒，图片下载耗时会从方舟 27 秒上限中扣除，不能直接等待 60 秒'
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
      { requestId: id, imageBytes: image.length, base64Chars: imageBase64.length },
      startedAt + SYNC_BUDGET_MS
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
  parseModelPayload,
  recoveredCourseObjects,
  contentText,
  buildArkRequestBody,
  effectiveArkTotalTimeout,
  arkConfigurationHint,
  constants: { FUNCTION_VERSION, DOWNLOAD_TIMEOUT_MS, ARK_TIMEOUT_MS, TOTAL_TIMEOUT_MS, SYNC_BUDGET_MS, MAX_IMAGE_BYTES, MAX_BASE64_CHARS, MAX_OUTPUT_TOKENS }
}
