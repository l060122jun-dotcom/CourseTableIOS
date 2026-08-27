module.exports = {
  // Copy this file to config.local.js. Never commit the local copy.
  ocr: {
    mode: 'cloud-function',
    envId: 'your-cloud-env-id',
    functionName: 'courseTableOCR'
  },
  subscribeMessageTemplateIds: [
    // Fill with the template ID created in WeChat Admin > 功能 > 订阅消息.
  ]
}
