const SHANGHAI_OFFSET_HOURS = 8
const DAY_MS = 24 * 60 * 60 * 1000

function escapeText(value) {
  return String(value == null ? '' : value)
    .replace(/\\/g, '\\\\')
    .replace(/\r?\n/g, '\\n')
    .replace(/,/g, '\\,')
    .replace(/;/g, '\\;')
}

function utf8Bytes(character) {
  const code = character.codePointAt(0)
  if (code <= 0x7f) return 1
  if (code <= 0x7ff) return 2
  if (code <= 0xffff) return 3
  return 4
}

function foldLine(line) {
  const output = []
  let part = ''
  let bytes = 0
  let limit = 75
  Array.from(line).forEach(character => {
    const size = utf8Bytes(character)
    if (part && bytes + size > limit) {
      output.push(part)
      part = ' ' + character
      bytes = 1 + size
      limit = 75
    } else {
      part += character
      bytes += size
    }
  })
  output.push(part)
  return output.join('\r\n')
}

function dateParts(value) {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(String(value || ''))
  if (!match) throw new Error('请先在设置中填写正确的第一周日期')
  const result = { year: Number(match[1]), month: Number(match[2]), day: Number(match[3]) }
  const checked = new Date(Date.UTC(result.year, result.month - 1, result.day))
  if (checked.getUTCFullYear() !== result.year || checked.getUTCMonth() !== result.month - 1 || checked.getUTCDate() !== result.day) {
    throw new Error('请先在设置中填写正确的第一周日期')
  }
  return result
}

function timeParts(value, label) {
  const match = /^(\d{1,2}):(\d{2})$/.exec(String(value || ''))
  const hour = match ? Number(match[1]) : -1
  const minute = match ? Number(match[2]) : -1
  if (!match || hour > 23 || minute > 59) throw new Error(`${label || '课程'}时间格式不正确`)
  return { hour, minute }
}

function utcDateForShanghai(base, dayOffset, time) {
  return new Date(Date.UTC(base.year, base.month - 1, base.day + dayOffset, time.hour - SHANGHAI_OFFSET_HOURS, time.minute))
}

function formatUtc(value) {
  return value.toISOString().replace(/[-:]/g, '').replace(/\.\d{3}Z$/, 'Z')
}

function resolvedWeeks(course, totalWeeks) {
  let weeks = Array.isArray(course.weeks)
    ? course.weeks.map(Number).filter(week => Number.isInteger(week) && week >= 1 && week <= totalWeeks)
    : []
  if (!weeks.length) {
    const start = Math.max(1, Number(course.startWeek) || 1)
    const end = Math.min(totalWeeks, Number(course.endWeek) || totalWeeks)
    weeks = Array.from({ length: Math.max(0, end - start + 1) }, (_, index) => start + index)
  }

  const mode = String(course.weekType || course.weekPattern || '').toLowerCase()
  if (mode === 'odd' || mode === 'single' || mode === '单周') weeks = weeks.filter(week => week % 2 === 1)
  if (mode === 'even' || mode === 'double' || mode === '双周') weeks = weeks.filter(week => week % 2 === 0)
  const interval = Math.max(1, Number(course.intervalWeeks) || 1)
  if (interval > 1 && weeks.length) {
    const first = weeks[0]
    weeks = weeks.filter(week => (week - first) % interval === 0)
  }
  return Array.from(new Set(weeks)).sort((a, b) => a - b)
}

function courseTimes(course, periods) {
  const custom = course.timingMode === 'custom' || (course.customStart && course.customEnd && course.startPeriod == null)
  if (custom) return { start: timeParts(course.customStart, course.name), end: timeParts(course.customEnd, course.name) }
  const startPeriod = periods.find(period => Number(period.index) === Number(course.startPeriod || 1))
  const endPeriod = periods.find(period => Number(period.index) === Number(course.endPeriod || course.startPeriod || 1))
  if (!startPeriod || !endPeriod) throw new Error(`${course.name || '课程'}缺少对应节次时间`)
  return { start: timeParts(startPeriod.start, course.name), end: timeParts(endPeriod.end, course.name) }
}

function safeUidPart(value) {
  const normalized = String(value || 'course').replace(/[^A-Za-z0-9._-]/g, '-')
  return normalized.slice(0, 80) || 'course'
}

function eventLines(course, week, base, periods, stamp) {
  const weekday = Number(course.weekday)
  if (!Number.isInteger(weekday) || weekday < 1 || weekday > 7) throw new Error(`${course.name || '课程'}的星期设置不正确`)
  const times = courseTimes(course, periods)
  const dayOffset = (week - 1) * 7 + weekday - 1
  const start = utcDateForShanghai(base, dayOffset, times.start)
  let end = utcDateForShanghai(base, dayOffset, times.end)
  if (end <= start) end = new Date(end.getTime() + DAY_MS)
  const description = [course.teacher ? `教师：${course.teacher}` : '', course.notes || ''].filter(Boolean).join('\n')
  const lines = [
    'BEGIN:VEVENT',
    `UID:${safeUidPart(course.id || course.name)}-w${week}@coursetable.local`,
    `DTSTAMP:${stamp}`,
    `DTSTART:${formatUtc(start)}`,
    `DTEND:${formatUtc(end)}`,
    `SUMMARY:${escapeText(course.name || '未命名课程')}`,
    `LOCATION:${escapeText(course.location || '')}`
  ]
  if (description) lines.push(`DESCRIPTION:${escapeText(description)}`)
  lines.push(`CATEGORIES:${escapeText('课程')}`)
  const reminder = Math.max(0, Math.min(10080, Number(course.reminderMinutes)))
  if (Number.isFinite(reminder)) {
    lines.push('BEGIN:VALARM', `TRIGGER:-PT${Math.round(reminder)}M`, 'ACTION:DISPLAY', `DESCRIPTION:${escapeText(course.name || '课程提醒')}`, 'END:VALARM')
  }
  lines.push('END:VEVENT')
  return lines
}

function generateCalendar(courses, table, periods, options) {
  const base = dateParts(table && table.semesterStart)
  const totalWeeks = Math.max(1, Math.min(52, Number(table && table.totalWeeks) || 18))
  const stamp = formatUtc(options && options.now ? new Date(options.now) : new Date())
  const events = []
  ;(Array.isArray(courses) ? courses : []).forEach(course => {
    resolvedWeeks(course, totalWeeks).forEach(week => events.push(...eventLines(course, week, base, periods || [], stamp)))
  })
  if (!events.length) throw new Error('没有可导出的课程')
  const lines = [
    'BEGIN:VCALENDAR',
    'PRODID:-//CourseTable//Course Schedule//ZH-CN',
    'VERSION:2.0',
    'CALSCALE:GREGORIAN',
    'METHOD:PUBLISH',
    'X-WR-TIMEZONE:Asia/Shanghai',
    `X-WR-CALNAME:${escapeText((table && table.name) || '课程表')}`,
    ...events,
    'END:VCALENDAR'
  ]
  return lines.map(foldLine).join('\r\n') + '\r\n'
}

function callWx(method, options) {
  return new Promise((resolve, reject) => method({ ...options, success: resolve, fail: reject }))
}

async function writeAndOpenCalendar(content, fileName) {
  if (typeof wx === 'undefined' || !wx.getFileSystemManager || !wx.env || !wx.env.USER_DATA_PATH) {
    throw new Error('当前环境不支持生成日历文件，请在微信真机中重试')
  }
  const safeName = String(fileName || '课程表').replace(/[\\/:*?"<>|]/g, '-').slice(0, 60) || '课程表'
  const filePath = `${wx.env.USER_DATA_PATH}/${safeName}.ics`
  const fileSystem = wx.getFileSystemManager()
  await callWx(fileSystem.writeFile.bind(fileSystem), { filePath, data: content, encoding: 'utf8' })
  try {
    await callWx(wx.openDocument, { filePath, showMenu: true })
    return { filePath, opened: true }
  } catch (openError) {
    let savedFilePath = filePath
    if (typeof wx.saveFile === 'function') {
      try {
        const saved = await callWx(wx.saveFile, { tempFilePath: filePath })
        savedFilePath = saved.savedFilePath || filePath
        await callWx(wx.openDocument, { filePath: savedFilePath, showMenu: true })
        return { filePath: savedFilePath, opened: true }
      } catch (_) {
        // Keep the generated path so the UI can explain that WeChat could not preview ICS.
      }
    }
    const error = new Error('ICS 已生成，但当前微信版本无法直接打开；请在真机中通过文件菜单导入系统日历')
    error.filePath = savedFilePath
    throw error
  }
}

module.exports = { escapeText, foldLine, resolvedWeeks, generateCalendar, writeAndOpenCalendar }
