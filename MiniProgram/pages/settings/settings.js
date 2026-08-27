const store = require('../../utils/store')
const reminder = require('../../utils/reminder-adapter')
const presetPeriods = [['08:00', '08:45'], ['08:50', '09:35'], ['10:00', '10:45'], ['10:50', '11:35'], ['13:30', '14:15'], ['14:20', '15:05'], ['15:30', '16:15'], ['16:20', '17:05'], ['18:30', '19:15'], ['19:20', '20:05']]
Page({
  data: { document: {}, reminderMessage: '', countOptions: [], periodCountIndex: 0, periods: [] },
  onShow() { const document = store.load(); const periods = document.periods || []; this.setData({ document, periods, countOptions: Array.from({ length: 14 }, (_, i) => String(i + 1)), periodCountIndex: Math.max(0, periods.length - 1) }) },
  periodCountChange(event) {
    const count = Number(event.detail.value) + 1; const periods = this.data.periods.slice();
    while (periods.length < count) { const index = periods.length + 1; periods.push({ index, start: '08:00', end: '08:45' }) }
    this.setData({ periods: periods.slice(0, count), periodCountIndex: count - 1 })
  },
  periodTimeChange(event) { const periods = this.data.periods.slice(); const index = Number(event.currentTarget.dataset.index); periods[index][event.currentTarget.dataset.key] = event.detail.value; this.setData({ periods }) },
  restorePreset() { this.setData({ periods: presetPeriods.map((time, index) => ({ index: index + 1, start: time[0], end: time[1] })), periodCountIndex: 9 }) },
  savePeriods() { const document = store.load(); document.periods = this.data.periods.map((period, index) => ({ index: index + 1, start: period.start, end: period.end })); store.save(document); this.setData({ document, periods: document.periods }); wx.showToast({ title: '时间设置已保存', icon: 'success' }) },
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
