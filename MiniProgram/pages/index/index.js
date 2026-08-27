const store = require('../../utils/store')
Page({
  data: { table: {}, periods: [], courses: [], customCourses: [], periodRows: [], days: ['一', '二', '三', '四', '五', '六', '日'] },
  onShow() { this.refresh() },
  refresh() { const document = store.load(); this.setData({ table: document.table, periods: document.periods, periodRows: document.periods, courses: document.courses, customCourses: document.courses.filter(item => item.timingMode === 'custom') }) },
  newCourse() { wx.navigateTo({ url: '/pages/editor/editor' }) },
  openDetail(event) { wx.navigateTo({ url: '/pages/editor/editor?id=' + event.currentTarget.dataset.id }) }
})
