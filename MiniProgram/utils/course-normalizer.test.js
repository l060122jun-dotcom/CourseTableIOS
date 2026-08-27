const assert = require('node:assert/strict')
const { parseWeekday, rangeNumbers, periodRange, normalizeCourse } = require('./course-normalizer')

assert.equal(parseWeekday('星期三'), 3)
assert.equal(parseWeekday('Sunday'), 7)
assert.deepEqual(rangeNumbers('[1-16周]', 52), Array.from({ length: 16 }, (_, index) => index + 1))
assert.deepEqual(rangeNumbers('1-8周（双周）', 52), [2, 4, 6, 8])
assert.deepEqual(rangeNumbers('1,3,5,7周', 52), [1, 3, 5, 7])
assert.deepEqual(periodRange({ section: '第1-2节' }), { start: 1, end: 2 })
assert.deepEqual(periodRange({ startPeriod: '第7-8节' }), { start: 7, end: 8 })
assert.deepEqual(periodRange({ start: '3', end: '4' }), { start: 3, end: 4 })

const aliased = normalizeCourse({
  courseName: '网页设计', weekDay: '周四', section: '第5-6节', weekRange: '[1-16周]',
  lecturer: '李老师', classroom: '实训楼 301'
}, 0)
assert.equal(aliased.name, '网页设计')
assert.equal(aliased.weekday, 4)
assert.equal(aliased.startPeriod, 5)
assert.equal(aliased.endPeriod, 6)
assert.equal(aliased.weeks.length, 16)
assert.equal(aliased.teacher, '李老师')
assert.equal(aliased.location, '实训楼 301')

const custom = normalizeCourse({ title: '讲座', day: 'Fri', start: '16:40', end: '18:10', weeks: '2-4周' }, 1)
assert.equal(custom.timingMode, 'custom')
assert.equal(custom.weekday, 5)
assert.equal(custom.customStart, '16:40')
assert.equal(custom.customEnd, '18:10')

console.log('course normalizer tests passed')
