let localConfig = {}
try { localConfig = require('../config.local') } catch (error) { localConfig = {} }

const MAX_UPLOAD_BYTES = 2 * 1024 * 1024

function configuredOCR() {
  const ocr = localConfig.ocr || {}
  if (ocr.mode !== 'cloud-function' || !ocr.envId || ocr.envId === 'your-cloud-env-id' || !ocr.functionName) throw new Error('尚未配置 OCR 服务。请检查 config.local.js 是否位于 MiniProgram 根目录且已重新编译。')
  if (!wx.cloud) throw new Error('当前基础库没有云开发能力，请升级微信开发者工具。')
  return ocr
}

function getFileSize(filePath) {
  return new Promise((resolve, reject) => {
    wx.getFileInfo({ filePath, success: result => resolve(result.size), fail: reject })
  })
}

function compress(filePath, quality) {
  return new Promise((resolve, reject) => {
    wx.compressImage({ src: filePath, quality, success: result => resolve(result.tempFilePath), fail: reject })
  })
}

async function prepareImage(imagePath) {
  const originalBytes = await getFileSize(imagePath)
  let filePath = imagePath
  let compressedBytes = originalBytes

  if (typeof wx.compressImage === 'function') {
    try {
      filePath = await compress(imagePath, 70)
      compressedBytes = await getFileSize(filePath)
      if (compressedBytes > MAX_UPLOAD_BYTES) {
        filePath = await compress(imagePath, 40)
        compressedBytes = await getFileSize(filePath)
      }
    } catch (error) {
      // PNG or unusual formats may not be supported by compressImage. Keeping
      // the original is safe only when it is already below the hard limit.
      if (originalBytes > MAX_UPLOAD_BYTES) throw new Error('图片无法压缩且超过 2 MB，请裁剪或转换为 JPG 后重试。')
      filePath = imagePath
      compressedBytes = originalBytes
    }
  }

  if (compressedBytes > MAX_UPLOAD_BYTES) throw new Error('图片压缩后仍超过 2 MB，请裁剪后重试。')
  console.info('[courseTableOCR] image prepared', { originalBytes, compressedBytes })
  return { filePath, originalBytes, compressedBytes }
}

async function recognize(imagePath) {
  const ocr = configuredOCR()
  const prepared = await prepareImage(imagePath)
  const upload = await wx.cloud.uploadFile({
    cloudPath: `ocr/${Date.now()}-${Math.random().toString(36).slice(2, 8)}.jpg`,
    filePath: prepared.filePath
  })

  try {
    const response = await wx.cloud.callFunction({
      name: ocr.functionName,
      data: { fileID: upload.fileID, clientVersion: '2026.08.27-compress-v1' }
    })
    const result = response.result || {}
    if (result.meta) console.info('[courseTableOCR] cloud response', result.meta)
    if (result.error) {
      const error = new Error(result.error)
      error.code = result.errorCode || 'OCR_FAILED'
      error.details = result.details || {}
      throw error
    }
    return result.draft || result
  } finally {
    // OCR source images are transient. Best-effort cleanup prevents cloud
    // storage from growing indefinitely and never masks the recognition result.
    wx.cloud.deleteFile({ fileList: [upload.fileID] }).catch(error => {
      console.warn('[courseTableOCR] temporary image cleanup failed', error && error.errMsg)
    })
  }
}

async function health() {
  const ocr = configuredOCR()
  const response = await wx.cloud.callFunction({ name: ocr.functionName, data: { action: 'health' } })
  return response.result || {}
}

module.exports = { recognize, health, prepareImage, MAX_UPLOAD_BYTES }
