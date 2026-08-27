function createEmptyDocument() {
  return {
    table: { name: '大三上', totalWeeks: 18, currentWeek: 8, semesterStart: '2026-09-01' },
    periods: [
      ['08:00', '08:45'], ['08:50', '09:35'], ['10:00', '10:45'], ['10:50', '11:35'],
      ['13:30', '14:15'], ['14:20', '15:05'], ['15:30', '16:15'], ['16:20', '17:05'],
      ['18:30', '19:15'], ['19:20', '20:05']
    ].map((time, index) => ({ index: index + 1, start: time[0], end: time[1] })),
    courses: []
  }
}
module.exports = { createEmptyDocument }
