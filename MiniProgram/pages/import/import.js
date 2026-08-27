const ocrAdapter = require('../../utils/ocr-adapter')
const store = require('../../utils/store')
Page({
  data: { message: '', draft: null, previewCourses: [], periods: [], days: ['一', '二', '三', '四', '五', '六', '日'] },
  onShow() { this.setData({ periods: store.load().periods || [] }) },
  chooseImage() { wx.chooseMedia({ count: 1, mediaType: ['image'], sourceType: ['album', 'camera'], success: result => { const path = result.tempFiles[0].tempFilePath; this.setData({ message: '图片已选择，正在识别…', draft: null }); ocrAdapter.recognize(path).then(draft => { const courses = (draft.courses || []).map((course, index) => ({ ...course, id: course.id || 'ocr-' + Date.now() + '-' + index })); this.setData({ draft, previewCourses: courses, message: '' }) }).catch(error => this.setData({ message: error.message || '识别失败' })) }, fail: error => this.setData({ message: '未选择图片：' + error.errMsg }) }) },
  confirmImport() { if (!this.data.previewCourses.length) { wx.showToast({ title: '暂无可导入的课程', icon: 'none' }); return } const document = store.load(); const oldIds = new Set(document.courses.map(c => c.id)); document.courses = document.courses.concat(this.data.previewCourses.filter(c => !oldIds.has(c.id))); store.save(document); wx.showToast({ title: '已导入课表', icon: 'success' }); setTimeout(() => wx.switchTab({ url: '/pages/index/index' }), 500) },
  backToChoose() { this.setData({ draft: null, previewCourses: [], message: '' }) }
})
