const store = require('../../utils/store')
const { assignCourseColors } = require('../../utils/course-color')
function pad(v) { return String(v).padStart(2, '0') }
function key(d) { return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}` }
function md(d) { return `${d.getMonth() + 1}/${d.getDate()}` }
function normalizeCourse(course) {
  const hasCustomTime = course.customStart && course.customEnd && course.startPeriod == null && course.endPeriod == null
  const timingMode = course.timingMode || (hasCustomTime ? 'custom' : 'period')
  const startPeriod = timingMode === 'period' ? (Number(course.startPeriod) || 1) : null
  const endPeriod = timingMode === 'period' ? (Number(course.endPeriod) || startPeriod) : null
  return { ...course, timingMode, weekday: Number(course.weekday) || 1, startPeriod, endPeriod, spanHeight: course.spanHeight || ((endPeriod || startPeriod || 1) - (startPeriod || 1) + 1) * 205 - 8 }
}
Page({
  data: { table: {}, periods: [], periodRows: [], courses: [], visibleCourses: [], customCourses: [], days: ['一', '二', '三', '四', '五', '六', '日'], weekPages: [], weekLabels: [], weekIndex: 0, currentWeek: 1, todayLabel: '', swiperHeight: 0 },
  onShow() { this.refresh(); setTimeout(() => wx.pageScrollTo({ scrollTop: 0, duration: 0 }), 0) },
  refresh() {
    const doc = store.load(); const table = doc.table || {}; const total = Number(table.totalWeeks || 18); const current = Number(table.currentWeek || 1); const periods = doc.periods || []; const courses = assignCourseColors((doc.courses || []).map(normalizeCourse)); const today = new Date(); const base = table.semesterStart ? new Date(`${table.semesterStart}T00:00:00`) : today
    const headers = week => { const start = new Date(base); start.setDate(start.getDate() + (week - 1) * 7); return this.data.days.map((label, i) => { const d = new Date(start); d.setDate(start.getDate() + i); return { label, date: md(d), current: key(d) === key(today) } }) }
    const pages = Array.from({ length: total }, (_, i) => { const week = i + 1; return { week, headers: headers(week), courses: courses.filter(c => !Array.isArray(c.weeks) || !c.weeks.length || c.weeks.indexOf(week) >= 0) } }); const page = pages[Math.min(total - 1, Math.max(0, current - 1))] || { headers: [], courses: [] }
    const swiperHeight = 112 + periods.length * 205 + (periods.filter(p => p.index === 4 || p.index === 8).length * 28)
    this.setData({ table, periods, periodRows: periods, courses, visibleCourses: page.courses, customCourses: page.courses.filter(c => c.timingMode === 'custom'), weekPages: pages, weekLabels: pages.map(p => `第 ${p.week} 周`), weekIndex: current - 1, currentWeek: current, dayHeaders: page.headers, todayLabel: `${today.getFullYear()}年${today.getMonth() + 1}月${today.getDate()}日`, swiperHeight })
  },
  weekChange(e) { this.setWeek(Number(e.detail.value) + 1) },
  weekSwipe(e) { this.setWeek(Number(e.detail.current) + 1) },
  setWeek(week) { if (week === this.data.currentWeek) return; const doc = store.load(); doc.table.currentWeek = week; store.save(doc); this.refresh() },
  newCourse() { wx.navigateTo({ url: '/pages/editor/editor' }) },
  openDetail(e) { wx.navigateTo({ url: '/pages/editor/editor?id=' + e.currentTarget.dataset.id }) },
  openSettings() { wx.switchTab({ url: '/pages/settings/settings' }) }
})
