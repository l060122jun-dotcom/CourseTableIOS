let localConfig = {}
try {
  localConfig = require('../config.local.js') || {}
} catch (_) {
  // 本地配置文件不应提交到仓库，未配置时由 requestSubscription 返回明确提示。
}

function requestSubscription() {
  const ids = localConfig.subscribeMessageTemplateIds
  if (!Array.isArray(ids) || ids.length === 0) {
    return Promise.reject(new Error('尚未配置订阅消息模板 ID。请复制 config.example.js 为 config.local.js 并填写 subscribeMessageTemplateIds。'))
  }
  if (typeof wx.requestSubscribeMessage !== 'function') {
    return Promise.reject(new Error('当前基础库不支持订阅消息，请升级微信或在真机中测试。'))
  }
  return new Promise((resolve, reject) => {
    wx.requestSubscribeMessage({
      tmplIds: ids,
      success: resolve,
      fail: reject
    })
  })
}

module.exports = { requestSubscription }
