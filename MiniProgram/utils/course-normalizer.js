const DAY_MAP = {
  '一': 1, '二': 2, '三': 3, '四': 4, '五': 5, '六': 6, '日': 7, '天': 7,
  monday: 1, mon: 1, tuesday: 2, tue: 2, wednesday: 3, wed: 3,
  thursday: 4, thu: 4, friday: 5, fri: 5, saturday: 6, sat: 6, sunday: 7, sun: 7
}

function firstValue(source, keys) {
  for (let index = 0; index < keys.length; index += 1) {
    const value = source[keys[index]]
    if (value !== undefined && value !== null && value !== '') return value
  }
  return undefined
}

function parseWeekday(value) {
  const numeric = Number(value)
  if (Number.isInteger(numeric) && numeric >= 1 && numeric <= 7) return numeric
  const text = String(value || '').trim().toLowerCase()
  if (DAY_MAP[text]) return DAY_MAP[text]
  const chinese = text.match(/[周星期礼拜]([一二三四五六日天])/)
  if (chinese) return DAY_MAP[chinese[1]]
  const digit = text.match(/[1-7]/)
  return digit ? Number(digit[0]) : 1
}

function rangeNumbers(value, maximum) {
  if (Array.isArray(value)) {
    const numbers = value.reduce((items, item) => items.concat(rangeNumbers(item, maximum)), [])
    return Array.from(new Set(numbers)).sort((a, b) => a - b)
  }
  if (typeof value === 'number') return Number.isInteger(value) && value >= 1 && value <= maximum ? [value] : []
  const text = String(value || '').replace(/[\[\]【】()（）]/g, ' ')
  const values = []
  const rangePattern = /(\d{1,2})\s*(?:-|~|～|—|–|至|到)\s*(\d{1,2})/g
  let match
  while ((match = rangePattern.exec(text))) {
    const start = Number(match[1])
    const end = Number(match[2])
    const low = Math.min(start, end)
    const high = Math.max(start, end)
    for (let current = low; current <= high && current <= maximum; current += 1) if (current >= 1) values.push(current)
  }
  const withoutRanges = text.replace(rangePattern, ' ')
  ;(withoutRanges.match(/\d{1,2}/g) || []).forEach(item => {
    const number = Number(item)
    if (number >= 1 && number <= maximum) values.push(number)
  })
  let unique = Array.from(new Set(values)).sort((a, b) => a - b)
  if (/单周|odd/i.test(text)) unique = unique.filter(number => number % 2 === 1)
  if (/双周|even/i.test(text)) unique = unique.filter(number => number % 2 === 0)
  return unique
}

function periodRange(course) {
  const compound = firstValue(course, ['section', 'sections', 'period', 'periods', '节次', '上课节次'])
  const compoundNumbers = rangeNumbers(compound, 30)
  const startValue = firstValue(course, ['startPeriod', 'start_period', 'startSection', 'sectionStart', 'periodStart', '开始节次', 'start'])
  const endValue = firstValue(course, ['endPeriod', 'end_period', 'endSection', 'sectionEnd', 'periodEnd', '结束节次', 'end'])
  const startNumbers = String(startValue || '').includes(':') ? [] : rangeNumbers(startValue, 30)
  const endNumbers = String(endValue || '').includes(':') ? [] : rangeNumbers(endValue, 30)
  const start = startNumbers[0] || compoundNumbers[0] || 1
  const end = endNumbers[endNumbers.length - 1] || startNumbers[startNumbers.length - 1] || compoundNumbers[compoundNumbers.length - 1] || start
  return { start: Math.min(start, end), end: Math.max(start, end) }
}

function normalizeCourse(course, index) {
  const source = course && typeof course === 'object' ? course : { name: String(course || '') }
  const startTime = firstValue(source, ['customStart', 'startTime', 'timeStart', '开始时间'])
  const endTime = firstValue(source, ['customEnd', 'endTime', 'timeEnd', '结束时间'])
  const startAlias = firstValue(source, ['start'])
  const endAlias = firstValue(source, ['end'])
  const customStart = startTime || (String(startAlias || '').includes(':') ? startAlias : '')
  const customEnd = endTime || (String(endAlias || '').includes(':') ? endAlias : '')
  const timingMode = source.timingMode === 'custom' || (customStart && customEnd) ? 'custom' : 'period'
  const periods = periodRange(source)
  const weekValue = firstValue(source, ['weeks', 'week', 'weekRange', 'week_range', 'teachingWeeks', '周次', '上课周次'])
  const weeks = rangeNumbers(weekValue, 52)
  const startWeekNumbers = rangeNumbers(firstValue(source, ['startWeek', 'weekStart', '开始周']), 52)
  const endWeekNumbers = rangeNumbers(firstValue(source, ['endWeek', 'weekEnd', '结束周']), 52)
  const name = String(firstValue(source, ['name', 'courseName', 'course_name', 'title', 'subject', '课程名', '课程']) || `待确认课程 ${index + 1}`).trim()
  const normalized = {
    ...source,
    id: source.id || 'ocr-' + Date.now() + '-' + index,
    name,
    teacher: String(firstValue(source, ['teacher', 'instructor', 'lecturer', '教师', '老师']) || ''),
    location: String(firstValue(source, ['location', 'classroom', 'room', 'place', '教室', '地点']) || ''),
    weekday: parseWeekday(firstValue(source, ['weekday', 'weekDay', 'week_day', 'day', 'dayOfWeek', '星期', '周几'])),
    startPeriod: timingMode === 'period' ? periods.start : null,
    endPeriod: timingMode === 'period' ? periods.end : null,
    timingMode,
    customStart: timingMode === 'custom' ? String(customStart) : '',
    customEnd: timingMode === 'custom' ? String(customEnd) : '',
    scheduleLabel: timingMode === 'custom' ? `${customStart}–${customEnd}` : `第${periods.start}-${periods.end}节`,
    weeks,
    startWeek: weeks[0] || startWeekNumbers[0],
    endWeek: weeks[weeks.length - 1] || endWeekNumbers[endWeekNumbers.length - 1]
  }
  normalized.spanHeight = source.spanHeight || (normalized.endPeriod - normalized.startPeriod + 1) * 190 - 8
  return normalized
}

module.exports = { parseWeekday, rangeNumbers, periodRange, normalizeCourse }
