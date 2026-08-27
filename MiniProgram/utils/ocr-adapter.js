let localConfig = {}
try { localConfig = require('../config.local') } catch (error) { localConfig = {} }

function recognize(imagePath) {
  const ocr = localConfig.ocr || {}
  if (ocr.mode !== 'cloud-function' || !ocr.envId || ocr.envId === 'your-cloud-env-id' || !ocr.functionName) return Promise.reject(new Error('尚未配置 OCR 服务。请检查 config.local.js 中的云环境和云函数名。'))
  if (!wx.cloud) return Promise.reject(new Error('当前基础库没有云开发能力，请升级微信开发者工具。'))
  return wx.cloud.uploadFile({ cloudPath: 'ocr/' + Date.now() + '.jpg', filePath: imagePath })
    .then(upload => wx.cloud.callFunction({ name: ocr.functionName, data: { fileID: upload.fileID } }))
    .then(response => { const result = response.result || {}; if (result.error) throw new Error(result.error); return result.draft || result })
}

module.exports = { recognize }
