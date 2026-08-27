const ocrAdapter = require('../../utils/ocr-adapter')
const store = require('../../utils/store')
const palette = ['#ffd6dc', '#ffe4c2', '#d7f2df', '#dce9ff', '#f1ddff', '#fff0bd', '#d8f3f0', '#e5e5e5']

function courseColor(name) {
  const text = String(name || '')
  let hash = 0
  for (let i = 0; i < text.length; i += 1) hash = (hash * 31 + text.charCodeAt(i)) >>> 0
  return palette[hash % palette.length]
}

function normalizeCourse(course, index) {
  const hasCustomTime = course.customStart && course.customEnd && course.startPeriod == null && course.endPeriod == null
  const timingMode = course.timingMode === 'custom' || hasCustomTime ? 'custom' : 'period'
  const normalized = {
    ...course,
    id: course.id || 'ocr-' + Date.now() + '-' + index,
    weekday: Number(course.weekday) || 1,
    startPeriod: timingMode === 'period' ? (Number(course.startPeriod) || 1) : null,
    endPeriod: timingMode === 'period' ? (Number(course.endPeriod) || Number(course.startPeriod) || 1) : null,
    timingMode,
    weeks: Array.isArray(course.weeks) ? course.weeks.map(Number).filter(Number.isFinite) : course.weeks,
    startWeek: course.startWeek == null ? course.startWeek : Number(course.startWeek),
    endWeek: course.endWeek == null ? course.endWeek : Number(course.endWeek)
  }
  normalized.spanHeight = course.spanHeight || ((normalized.endPeriod || normalized.startPeriod || 1) - (normalized.startPeriod || 1) + 1) * 190 - 8
  normalized.color = course.color || courseColor(course.name)
  return normalized
}

Page({
  data: { message: '', healthMessage: '', draft: null, previewCourses: [], visibleCourses: [], currentWeek: 1, currentWeekIndex: 0, totalWeeks: 18, weekOptions: [], touchStartX: 0, touchStartY: 0, transitionClass: '', periods: [], days: ['一', '二', '三', '四', '五', '六', '日'] },
  onShow() { const document = store.load(); const totalWeeks = document.table.totalWeeks || 18; const currentWeek = Math.min(document.table.currentWeek || 1, totalWeeks); this.setData({ periods: document.periods || [], currentWeek, currentWeekIndex: currentWeek - 1, totalWeeks, weekOptions: Array.from({ length: totalWeeks }, (_, index) => `第 ${index + 1} 周`) }) },
  updateVisibleCourses(courses, week) {
    const visibleCourses = courses.filter(course => {
      const weeks = Array.isArray(course.weeks) ? course.weeks.filter(Number.isFinite) : []
      if (weeks.length) return weeks.indexOf(week) >= 0
      if (Number.isFinite(course.startWeek) || Number.isFinite(course.endWeek)) return week >= (course.startWeek || 1) && week <= (course.endWeek || this.data.totalWeeks)
      return true
    })
    this.setData({ visibleCourses })
  },
  switchWeek(week, direction) {
    if (week < 1 || week > this.data.totalWeeks || week === this.data.currentWeek) return
    this.setData({ currentWeek: week, currentWeekIndex: week - 1, transitionClass: direction ? `slide-${direction}` : '' })
    this.updateVisibleCourses(this.data.previewCourses, week)
    if (direction) setTimeout(() => this.setData({ transitionClass: '' }), 220)
  },
  weekChange(event) { this.switchWeek(Number(event.detail.value) + 1) },
  weekTouchStart(event) {
    const touch = event.touches && event.touches[0]
    if (touch) this.setData({ touchStartX: touch.pageX, touchStartY: touch.pageY })
  },
  weekTouchEnd(event) {
    const touch = event.changedTouches && event.changedTouches[0]
    if (!touch) return
    const dx = touch.pageX - this.data.touchStartX
    const dy = touch.pageY - this.data.touchStartY
    if (Math.abs(dx) < 50 || Math.abs(dx) <= Math.abs(dy)) return
    if (dx < 0) this.switchWeek(this.data.currentWeek + 1, 'left')
    else this.switchWeek(this.data.currentWeek - 1, 'right')
  },
  checkHealth() {
    this.setData({ healthMessage: '正在检查 OCR 服务…' })
    ocrAdapter.health()
      .then(result => {
        const health = result.health || result
        this.setData({ healthMessage: `OCR 服务：${health.functionVersion || '未知版本'} · arkConfigured=${health.arkConfigured ? 'true' : 'false'}` })
      })
      .catch(error => this.setData({ healthMessage: `OCR 服务检查失败：${error.message || '未知错误'}` }))
  },
  chooseImage() {
    wx.chooseMedia({
      count: 1, mediaType: ['image'], sourceType: ['album', 'camera'],
      success: result => {
        const path = result.tempFiles[0].tempFilePath
        this.setData({ message: '图片已选择，正在识别…', draft: null, healthMessage: '' })
        ocrAdapter.recognize(path).then(draft => {
          const courses = (draft.courses || []).map(normalizeCourse)
          this.setData({ draft, previewCourses: courses, message: '' })
          this.updateVisibleCourses(courses, this.data.currentWeek)
        }).catch(error => this.setData({ message: error.message || '识别失败' }))
      },
      fail: error => this.setData({ message: '未选择图片：' + error.errMsg })
    })
  },
  confirmImport() {
    if (!this.data.previewCourses.length) { wx.showToast({ title: '暂无可导入的课程', icon: 'none' }); return }
    const document = store.load()
    const oldIds = new Set(document.courses.map(c => c.id))
    const normalizedCourses = this.data.previewCourses.map(normalizeCourse)
    document.courses = document.courses.concat(normalizedCourses.filter(c => !oldIds.has(c.id)))
    store.save(document)
    wx.showToast({ title: '已导入课表', icon: 'success' })
    setTimeout(() => wx.switchTab({ url: '/pages/index/index' }), 500)
  },
  backToChoose() { this.setData({ draft: null, previewCourses: [], visibleCourses: [], message: '' }) }
})
