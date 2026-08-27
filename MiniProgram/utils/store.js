const KEY = 'course-table-document-v1'
function load() {
  const stored = wx.getStorageSync(KEY)
  if (!stored) return require('./demo').createEmptyDocument()
  // Remove only the old built-in demo records; preserve every user-created course.
  if (Array.isArray(stored.courses)) {
    const courses = stored.courses.filter(item => !(typeof item.id === 'string' && item.id.indexOf('demo-') === 0))
    if (courses.length !== stored.courses.length) {
      const cleaned = { ...stored, courses }
      wx.setStorageSync(KEY, cleaned)
      return cleaned
    }
  }
  return stored
}
function save(document) { wx.setStorageSync(KEY, document); return document }
module.exports = { load, save, KEY }
