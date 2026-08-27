const store = require('../../utils/store')
const reminder = require('../../utils/reminder-adapter')
const ics = require('../../utils/ics')
const presetPeriods = [['08:00', '08:45'], ['08:50', '09:35'], ['10:00', '10:45'], ['10:50', '11:35'], ['13:30', '14:15'], ['14:20', '15:05'], ['15:30', '16:15'], ['16:20', '17:05'], ['18:30', '19:15'], ['19:20', '20:05']]
Page({
  data: { document: {}, tableName: '', totalWeeks: 18, semesterStart: '', reminderMessage: '', countOptions: [], periodCountIndex: 0, periods: [] },
  onShow() { const document = store.load(); const periods = document.periods || []; const table = document.table || {}; this.setData({ document, tableName: table.name || '', totalWeeks: Number(table.totalWeeks || 18), semesterStart: table.semesterStart || new Date().toISOString().slice(0, 10), periods, countOptions: Array.from({ length: 14 }, (_, i) => String(i + 1)), periodCountIndex: Math.max(0, periods.length - 1) }) },
  tableField(event) { this.setData({ [event.currentTarget.dataset.key]: event.detail.value }) },
  semesterStartChange(event) { this.setData({ semesterStart: event.detail.value }) },
  saveTable() {
    const document = store.load(); const totalWeeks = Math.min(52, Math.max(1, Number(this.data.totalWeeks) || 18)); const table = { ...(document.table || {}), name: this.data.tableName.trim() || '我的课程表', totalWeeks, semesterStart: this.data.semesterStart || new Date().toISOString().slice(0, 10), currentWeek: Math.min(Number((document.table || {}).currentWeek || 1), totalWeeks) }
    document.table = table; store.save(document); this.setData({ document, tableName: table.name, totalWeeks, semesterStart: table.semesterStart }); wx.showToast({ title: '课程表设置已保存', icon: 'success' })
  },
  periodCountChange(event) {
    const count = Number(event.detail.value) + 1; const periods = this.data.periods.slice();
    while (periods.length < count) { const index = periods.length + 1; periods.push({ index, start: '08:00', end: '08:45' }) }
    this.setData({ periods: periods.slice(0, count), periodCountIndex: count - 1 })
  },
  periodTimeChange(event) { const periods = this.data.periods.slice(); const index = Number(event.currentTarget.dataset.index); periods[index][event.currentTarget.dataset.key] = event.detail.value; this.setData({ periods }) },
  restorePreset() { this.setData({ periods: presetPeriods.map((time, index) => ({ index: index + 1, start: time[0], end: time[1] })), periodCountIndex: 9 }) },
  savePeriods() { const document = store.load(); document.periods = this.data.periods.map((period, index) => ({ index: index + 1, start: period.start, end: period.end })); store.save(document); this.setData({ document, periods: document.periods }); wx.showToast({ title: '时间设置已保存', icon: 'success' }) },
  async exportCalendar() {
    const document = store.load()
    wx.showLoading({ title: '正在生成日历' })
    try {
      const content = ics.generateCalendar(document.courses || [], document.table || {}, document.periods || [])
      await ics.writeAndOpenCalendar(content, (document.table && document.table.name) || '整学期课程表')
    } catch (error) {
      wx.showModal({ title: '无法打开日历文件', content: error.message || '日历导出失败', showCancel: false })
    } finally {
      wx.hideLoading()
    }
  },
  subscribe() {
    this.setData({ reminderMessage: '正在请求订阅权限…' })
    reminder.requestSubscription()
      .then(result => {
        const accepted = Object.keys(result || {}).filter(key => result[key] === 'accept').length
        this.setData({ reminderMessage: accepted ? `已同意 ${accepted} 项课程提醒` : '未同意课程提醒授权' })
      })
      .catch(error => this.setData({ reminderMessage: error.message || '订阅请求失败' }))
  }
})
