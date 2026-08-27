const cloud = require('wx-server-sdk')
const tencentcloud = require('tencentcloud-sdk-nodejs-ocr')

cloud.init({
  env: cloud.DYNAMIC_CURRENT_ENV
})

const OcrClient = tencentcloud.ocr.v20181119.Client

function center(item) {
  const points = item.Polygon || item.ItemPolygon || []
  if (!points.length) return { x: 0, y: 0 }
  return { x: points.reduce((sum, point) => sum + point.X, 0) / points.length, y: points.reduce((sum, point) => sum + point.Y, 0) / points.length }
}

function parseCourses(detections) {
  const items = (detections || []).map(item => ({ text: String(item.DetectedText || '').trim(), ...center(item) })).filter(item => item.text)
  const weekdayMap = { '一': 1, '二': 2, '三': 3, '四': 4, '五': 5, '六': 6, '日': 7, '天': 7 }
  const weekdays = items.filter(item => /^星期[一二三四五六日天]$/.test(item.text)).map(item => ({ ...item, weekday: weekdayMap[item.text.slice(2)] }))
  const periods = items.map(item => { const match = item.text.match(/^第(\d+)(?:[-－](\d+))?节$/); return match ? { ...item, startPeriod: Number(match[1]), endPeriod: Number(match[2] || match[1]) } : null }).filter(Boolean)
  const ignored = /^(星期[一二三四五六日天]|第\d+(?:[-－]\d+)?节|\[?\d+(?:[-－]\d+)?\]?$|\[?\d+-\d+周\]?|午休|晚休)$/
  return periods.map((period, index) => {
    const weekday = weekdays.length ? weekdays.reduce((best, day) => Math.abs(day.x - period.x) < Math.abs(best.x - period.x) ? day : best, weekdays[0]).weekday : ((index % 7) + 1)
    const nearby = items.filter(item => item !== period && item.y < period.y && item.y > period.y - 260 && Math.abs(item.x - period.x) < 220 && !ignored.test(item.text) && !/^\[.*\]$/.test(item.text)).sort((a, b) => a.y - b.y)
    if (!nearby.length) return null
    const name = nearby[0].text
    const location = (nearby.find(item => /楼|室|教室|场|馆/.test(item.text)) || {}).text || ''
    return { id: `ocr-${Date.now()}-${index}`, name, weekday, startPeriod: period.startPeriod, endPeriod: period.endPeriod, location, weeks: [] }
  }).filter(Boolean)
}

exports.main = async (event) => {
  try {
    if (!event.fileID) {
      return {
        error: '没有收到图片 fileID'
      }
    }

    const file = await cloud.downloadFile({
      fileID: event.fileID
    })

    const client = new OcrClient({
      credential: {
        secretId: process.env.TENCENT_SECRET_ID,
        secretKey: process.env.TENCENT_SECRET_KEY
      },
      region: 'ap-beijing',
      profile: {
        httpProfile: {
          endpoint: 'ocr.tencentcloudapi.com'
        }
      }
    })

    const result = await client.GeneralAccurateOCR({
      ImageBase64: file.fileContent.toString('base64')
    })

    const detections = result.TextDetections || []
    const text = detections
      .map(item => item.DetectedText)
      .join('\n')

    return {
      draft: {
        text,
        warning: '请确认课程名称、星期和节次',
        courses: parseCourses(detections)
      }
    }
  } catch (error) {
    return {
      error: error.message || 'OCR 识别失败'
    }
  }
}
