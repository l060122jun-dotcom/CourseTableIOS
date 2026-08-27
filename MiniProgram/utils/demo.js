function createDemoDocument() {
  const course = (id, name, weekday, startPeriod, color = '#1677ff') => ({
    id, name, weekday, teacher: '', location: '', notes: '', color,
    timingMode: 'period', startPeriod, endPeriod: startPeriod,
    customStart: '', customEnd: '', startWeek: 1, endWeek: 18, reminderMinutes: 30
  })
  return {
    table: { name: '大三上', totalWeeks: 18, currentWeek: 8, semesterStart: '2026-09-01' },
    periods: [
      ['08:00', '09:45'], ['10:00', '10:45'], ['11:00', '11:45'], ['11:50', '12:35'],
      ['13:30', '14:15'], ['14:20', '15:05'], ['15:30', '16:15'], ['16:20', '17:05'],
      ['18:30', '19:15'], ['19:20', '20:05']
    ].map((time, index) => ({ index: index + 1, start: time[0], end: time[1] })),
    courses: [
      course('demo-1', '高等数学', 1, 1), course('demo-2', '英语', 3, 2),
      course('demo-3', '数据结构', 2, 5), course('demo-4', '体育', 5, 7),
      { ...course('demo-5', '实验（不规则）', 4, 1, '#e84a8a'), timingMode: 'custom', startPeriod: null, endPeriod: null, customStart: '16:40', customEnd: '18:10', location: '实验楼 B203' }
    ]
  }
}
module.exports = { createDemoDocument }
