const assert = require('node:assert/strict')
const { escapeText, foldLine, resolvedWeeks, generateCalendar } = require('./ics')

const table = { name: '大三,上', totalWeeks: 4, semesterStart: '2026-09-07' }
const periods = [{ index: 1, start: '08:00', end: '08:45' }, { index: 2, start: '08:50', end: '09:35' }]
const regular = { id: 'math', name: '高数,一班', teacher: '张老师', location: 'A;101', weekday: 1, timingMode: 'period', startPeriod: 1, endPeriod: 2, weeks: [1, 3], reminderMinutes: 30 }
const custom = { id: 'lab', name: '实验课', weekday: 2, timingMode: 'custom', customStart: '16:40', customEnd: '18:10', startWeek: 1, endWeek: 4, weekType: 'even' }
const output = generateCalendar([regular, custom], table, periods, { now: '2026-08-27T00:00:00Z' })

assert.equal((output.match(/BEGIN:VEVENT/g) || []).length, 4)
assert.match(output, /DTSTART:20260907T000000Z/)
assert.match(output, /DTEND:20260907T013500Z/)
assert.match(output, /DTSTART:20260915T084000Z/)
assert.match(output, /SUMMARY:高数\\,一班/)
assert.match(output, /LOCATION:A\\;101/)
assert.match(output, /TRIGGER:-PT30M/)
assert.equal(escapeText('a\\b,c;d\ne'), 'a\\\\b\\,c\\;d\\ne')
assert.deepEqual(resolvedWeeks({ startWeek: 1, endWeek: 6, intervalWeeks: 2 }, 8), [1, 3, 5])
assert.match(foldLine('SUMMARY:' + '课'.repeat(30)), /\r\n /)
assert.ok(output.endsWith('END:VCALENDAR\r\n'))

console.log('ICS calendar tests passed')
