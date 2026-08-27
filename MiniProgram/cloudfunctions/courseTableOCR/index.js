const cloud = require('wx-server-sdk')
const https = require('https')

cloud.init({ env: cloud.DYNAMIC_CURRENT_ENV })

function arkRequest(apiKey, endpointId, imageBase64) {
  const body = JSON.stringify({
    model: endpointId,
    temperature: 0,
    max_tokens: 4096,
    messages: [{ role: 'user', content: [
      { type: 'text', text: '请读取这张课程表图片，严格只输出 JSON，不要 Markdown。按视觉上的星期列和节次行识别每门课程。格式：{"courses":[{"name":"课程名","weekday":1,"startPeriod":1,"endPeriod":2,"teacher":"教师","location":"教室","weeks":[1,2,3]}] ,"warning":""}。weekday 为 1-7，weeks 只填写图片明确出现的周次；无法确定时使用空数组。不要把图片标题、学期名称、星期标题或节次标题当作课程。' },
      { type: 'image_url', image_url: { url: `data:image/jpeg;base64,${imageBase64}` } }
    ] }]
  })
  return new Promise((resolve, reject) => {
    const request = https.request({ hostname: 'ark.cn-beijing.volces.com', path: '/api/v3/chat/completions', method: 'POST', headers: { Authorization: `Bearer ${apiKey}`, 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(body) } }, response => {
      let output = ''; response.on('data', chunk => { output += chunk }); response.on('end', () => { try { const data = JSON.parse(output); if (data.error) return reject(new Error(data.error.message || '火山方舟调用失败')); resolve(data) } catch (error) { reject(new Error('火山方舟返回了无法解析的结果')) } })
    })
    request.on('error', reject); request.write(body); request.end()
  })
}

exports.main = async (event) => {
  try {
    if (!event.fileID) return { error: '没有收到图片 fileID' }
    if (!process.env.ARK_API_KEY || !process.env.ARK_ENDPOINT_ID) return { error: '未配置 ARK_API_KEY 或 ARK_ENDPOINT_ID' }
    const file = await cloud.downloadFile({ fileID: event.fileID })
    const response = await arkRequest(process.env.ARK_API_KEY, process.env.ARK_ENDPOINT_ID, file.fileContent.toString('base64'))
    const content = response.choices && response.choices[0] && response.choices[0].message && response.choices[0].message.content
    if (!content) return { error: '火山方舟没有返回识别内容' }
    const jsonText = String(content).replace(/^```json\s*/i, '').replace(/```\s*$/i, '').trim()
    const draft = JSON.parse(jsonText)
    return { draft: { text: content, warning: draft.warning || '请确认识别出的课程和周次', courses: Array.isArray(draft.courses) ? draft.courses : [] } }
  } catch (error) {
    return { error: error.message || '课程表识别失败' }
  }
}
