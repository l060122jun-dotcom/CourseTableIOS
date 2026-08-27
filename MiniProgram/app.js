const STORAGE_KEY = 'course-table-document-v1'

App({
  globalData: { storageKey: STORAGE_KEY },
  onLaunch() {
    if (!wx.getStorageSync(STORAGE_KEY)) {
      wx.setStorageSync(STORAGE_KEY, require('./utils/demo').createDemoDocument())
    }
  }
})
