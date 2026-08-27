const store = require('../../utils/store')
const reminder = require('../../utils/reminder-adapter')
Page({
  data: { document: {}, reminderMessage: '' },
  onShow() { this.setData({ document: store.load() }) },
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
