const store = require('../../utils/store')
function pad(value) { return String(value).padStart(2, '0') }
function dateKey(date) { return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}` }
function displayDate(date) { return `${date.getMonth() + 1}/${date.getDate()}` }
Page({
  data: { table: {}, periods: [], periodRows: [], courses: [], visibleCourses: [], customCourses: [], days: ['一', '二', '三', '四', '五', '六', '日'], dayHeaders: [], weekLabels: [], weekIndex: 0, currentWeek: 1, todayLabel: '' },
  onShow() { this.refresh() },
  refresh() {
    const document = store.load(); const table = document.table || {}; const currentWeek = Number(table.currentWeek || 1); const totalWeeks = Number(table.totalWeeks || 18)
    const weekLabels = Array.from({ length: totalWeeks }, (_, index) => `第 ${index + 1} 周`); const periods = document.periods || []; const courses = document.courses || []; const today = new Date()
    const semesterStart = table.semesterStart ? new Date(`${table.semesterStart}T00:00:00`) : today; const start = new Date(semesterStart); start.setDate(start.getDate() + (currentWeek - 1) * 7)
    const dayHeaders = this.data.days.map((label, index) => { const date = new Date(start); date.setDate(start.getDate() + index); return { label, date: displayDate(date), current: dateKey(date) === dateKey(today) } })
    const visibleCourses = courses.filter(course => !Array.isArray(course.weeks) || course.weeks.length === 0 || course.weeks.indexOf(currentWeek) !== -1)
    this.setData({ table, periods, periodRows: periods, courses, visibleCourses, customCourses: visibleCourses.filter(item => item.timingMode === 'custom'), weekLabels, weekIndex: Math.max(0, currentWeek - 1), currentWeek, dayHeaders, todayLabel: `${today.getFullYear()}年${today.getMonth() + 1}月${today.getDate()}日` })
  },
  weekChange(event) { const currentWeek = Number(event.detail.value) + 1; const document = store.load(); document.table.currentWeek = currentWeek; store.save(document); this.refresh() },
  newCourse() { wx.navigateTo({ url: '/pages/editor/editor' }) },
  openDetail(event) { wx.navigateTo({ url: '/pages/editor/editor?id=' + event.currentTarget.dataset.id }) },
  openSettings() { wx.switchTab({ url: '/pages/settings/settings' }) }
})
