const STORAGE_KEY = 'course-table-document-v1'

let localConfig = {}
try { localConfig = require('./config.local') } catch (error) { localConfig = {} }

App({
  globalData: { storageKey: STORAGE_KEY, config: localConfig },
  onLaunch() {
    const ocr = localConfig.ocr || {}
    if (ocr.mode === 'cloud-function' && ocr.envId && ocr.envId !== 'your-cloud-env-id' && wx.cloud) {
      wx.cloud.init({ env: ocr.envId, traceUser: true })
    }
    if (!wx.getStorageSync(STORAGE_KEY)) {
      wx.setStorageSync(STORAGE_KEY, require('./utils/demo').createDemoDocument())
    }
  }
})
