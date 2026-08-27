// Stable light colors for the current course collection. The first 16 colors
// are hand-picked; larger collections continue with evenly-spaced HSL hues.
const palette = [
  '#ffd6dc', '#ffe4c2', '#d7f2df', '#dce9ff',
  '#f1ddff', '#fff0bd', '#d8f3f0', '#ffdfc8',
  '#e1dcff', '#d5f0ff', '#ffe0ed', '#e5f3cc',
  '#ffe8b6', '#d9e8ff', '#f4d9c6', '#dff1ed'
]

function colorForIndex(index) {
  if (index < palette.length) return palette[index]
  const hue = (index * 137.508) % 360
  return `hsl(${Math.round(hue)}, 72%, 88%)`
}

function assignCourseColors(courses) {
  const colorByName = Object.create(null)
  let nextIndex = 0
  return courses.map(course => {
    const name = String(course.name || '').trim() || `course-${nextIndex}`
    if (!colorByName[name]) {
      // Keep an already assigned non-gray color so import preview and the
      // persisted home page remain identical across refreshes.
      colorByName[name] = course.color && course.color !== '#e5e5e5' ? course.color : colorForIndex(nextIndex++)
    }
    return { ...course, color: colorByName[name] }
  })
}

module.exports = { assignCourseColors, colorForIndex }
