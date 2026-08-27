const ocrAdapter = require('../../utils/ocr-adapter')
const store = require('../../utils/store')
const palette = ['#ffd6dc', '#ffe4c2', '#d7f2df', '#dce9ff', '#f1ddff', '#fff0bd', '#d8f3f0', '#e5e5e5']

function courseColor(name) {
  const text = String(name || '')
  let hash = 0
  for (let i = 0; i < text.length; i += 1) hash = (hash * 31 + text.charCodeAt(i)) >>> 0
  return palette[hash % palette.length]
}

Page({
  data: { message: '', healthMessage: '', draft: null, previewCourses: [], visibleCourses: [], currentWeek: 1, totalWeeks: 18, touchStartX: 0, touchStartY: 0, periods: [], days: ['一', '二', '三', '四', '五', '六', '日'] },
  onShow() { const document = store.load(); this.setData({ periods: document.periods || [], currentWeek: document.table.currentWeek || 1, totalWeeks: document.table.totalWeeks || 18 }) },
  updateVisibleCourses(courses, week) {
    const visibleCourses = courses.filter(course => {
      const weeks = Array.isArray(course.weeks) ? course.weeks.filter(Number.isFinite) : []
      if (weeks.length) return weeks.indexOf(week) >= 0
      if (Number.isFinite(course.startWeek) || Number.isFinite(course.endWeek)) return week >= (course.startWeek || 1) && week <= (course.endWeek || this.data.totalWeeks)
      return true
    })
    this.setData({ visibleCourses })
  },
  previousWeek() { if (this.data.currentWeek > 1) { const week = this.data.currentWeek - 1; this.setData({ currentWeek: week }); this.updateVisibleCourses(this.data.previewCourses, week) } },
  nextWeek() { if (this.data.currentWeek < this.data.totalWeeks) { const week = this.data.currentWeek + 1; this.setData({ currentWeek: week }); this.updateVisibleCourses(this.data.previewCourses, week) } },
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
    if (dx < 0) this.nextWeek()
    else this.previousWeek()
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
          const courses = (draft.courses || []).map((course, index) => ({
            ...course, color: course.color || courseColor(course.name),
            spanHeight: course.spanHeight || ((course.endPeriod || course.startPeriod || 1) - (course.startPeriod || 1) + 1) * 190 - 8,
            id: course.id || 'ocr-' + Date.now() + '-' + index
          }))
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
    document.courses = document.courses.concat(this.data.previewCourses.filter(c => !oldIds.has(c.id)))
    store.save(document)
    wx.showToast({ title: '已导入课表', icon: 'success' })
    setTimeout(() => wx.switchTab({ url: '/pages/index/index' }), 500)
  },
  backToChoose() { this.setData({ draft: null, previewCourses: [], visibleCourses: [], message: '' }) }
})
