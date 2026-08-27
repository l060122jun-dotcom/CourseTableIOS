function recognize() {
  return Promise.reject(new Error('尚未配置 OCR 服务。请在 utils/ocr-adapter.js 接入云函数或自有 OCR API。'))
}
module.exports = { recognize }
