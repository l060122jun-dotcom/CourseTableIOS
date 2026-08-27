const store = require('../../utils/store')
const ics = require('../../utils/ics')

function makeWeekOptions(totalWeeks, selectedWeeks) {
  const selected = new Set(selectedWeeks)
  return Array.from({ length: totalWeeks }, (_, index) => {
    const week = index + 1
    return { value: String(week), label: '第 ' + week + ' 周', checked: selected.has(week) }
  })
}

Page({
  data: {
    id: '', name: '', teacher: '', location: '', weekdayIndex: 0,
    dayNames: ['周一', '周二', '周三', '周四', '周五', '周六', '周日'],
    timingMode: 'period', periodNames: [], weekOptions: [], selectedWeeks: [],
    startPeriodIndex: 0, endPeriodIndex: 0, customStart: '16:40', customEnd: '18:10',
    reminderMinutes: 30
  },
  onLoad(options) {
    const document = store.load()
    const totalWeeks = document.table.totalWeeks || 18
    const item = options.id ? document.courses.find(course => course.id === options.id) : null
    const selectedWeeks = item && Array.isArray(item.weeks) && item.weeks.length
      ? item.weeks.map(Number)
      : Array.from({ length: totalWeeks }, (_, index) => index + 1)
    this.setData({
      periodNames: document.periods.map(period => '第 ' + period.index + ' 节'),
      weekOptions: makeWeekOptions(totalWeeks, selectedWeeks), selectedWeeks
    })
    if (item) {
      this.setData({
        id: item.id, name: item.name, teacher: item.teacher, location: item.location,
        weekdayIndex: item.weekday - 1, timingMode: item.timingMode,
        startPeriodIndex: (item.startPeriod || 1) - 1, endPeriodIndex: (item.endPeriod || 1) - 1,
        customStart: item.customStart || '16:40', customEnd: item.customEnd || '18:10',
        reminderMinutes: item.reminderMinutes
      })
    }
  },
  field(event) { this.setData({ [event.currentTarget.dataset.key]: event.detail.value }) },
  dayChange(event) { this.setData({ weekdayIndex: Number(event.detail.value) }) },
  modeChange(event) { this.setData({ timingMode: event.currentTarget.dataset.mode }) },
  startPeriodChange(event) { this.setData({ startPeriodIndex: Number(event.detail.value) }) },
  endPeriodChange(event) { this.setData({ endPeriodIndex: Number(event.detail.value) }) },
  weeksChange(event) {
    const selectedWeeks = event.detail.value.map(Number).sort((a, b) => a - b)
    const weekOptions = this.data.weekOptions.map(item => ({ ...item, checked: selectedWeeks.includes(Number(item.value)) }))
    this.setData({ selectedWeeks, weekOptions })
  },
  timeChange(event) { this.setData({ [event.currentTarget.dataset.key]: event.detail.value }) },
  async exportCalendar() {
    const document = store.load()
    const course = (document.courses || []).find(item => item.id === this.data.id)
    if (!course) { wx.showToast({ title: '请先保存课程', icon: 'none' }); return }
    wx.showLoading({ title: '正在生成日历' })
    try {
      const content = ics.generateCalendar([course], document.table || {}, document.periods || [])
      await ics.writeAndOpenCalendar(content, course.name || '课程')
    } catch (error) {
      wx.showModal({ title: '无法打开日历文件', content: error.message || '日历导出失败', showCancel: false })
    } finally {
      wx.hideLoading()
    }
  },
  save() {
    if (!this.data.name.trim()) { wx.showToast({ title: '请填写课程名称', icon: 'none' }); return }
    if (!this.data.selectedWeeks.length) { wx.showToast({ title: '至少选择一周', icon: 'none' }); return }
    const document = store.load()
    const old = document.courses.find(item => item.id === this.data.id)
    const weeks = this.data.selectedWeeks.slice().sort((a, b) => a - b)
    const course = {
      id: this.data.id || 'course-' + Date.now(), name: this.data.name.trim(), teacher: this.data.teacher,
      location: this.data.location, notes: old ? old.notes : '', color: old ? old.color : '#1677ff',
      weekday: this.data.weekdayIndex + 1, timingMode: this.data.timingMode,
      startPeriod: this.data.timingMode === 'period' ? this.data.startPeriodIndex + 1 : null,
      endPeriod: this.data.timingMode === 'period' ? this.data.endPeriodIndex + 1 : null,
      customStart: this.data.timingMode === 'custom' ? this.data.customStart : '',
      customEnd: this.data.timingMode === 'custom' ? this.data.customEnd : '',
      weeks, startWeek: weeks[0], endWeek: weeks[weeks.length - 1], reminderMinutes: this.data.reminderMinutes
    }
    const index = document.courses.findIndex(item => item.id === course.id)
    if (index >= 0) document.courses[index] = course
    else document.courses.push(course)
    store.save(document)
    wx.navigateBack()
  }
})
