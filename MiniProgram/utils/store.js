const KEY = 'course-table-document-v1'
function load() { return wx.getStorageSync(KEY) || require('./demo').createDemoDocument() }
function save(document) { wx.setStorageSync(KEY, document); return document }
module.exports = { load, save, KEY }
