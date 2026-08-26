import Foundation

public enum MeetingRuleValidationError: Error, Equatable, LocalizedError {
    case invalidWeekday
    case emptyWeekSet
    case weekOutsideSemester
    case missingPeriod
    case invalidPeriodRange
    case unknownPeriod
    case missingCustomTime
    case invalidCustomTime
    case staleTimingFields

    public var errorDescription: String? {
        switch self {
        case .invalidWeekday: return "星期必须在 1 到 7 之间。"
        case .emptyWeekSet: return "至少选择一个上课周次。"
        case .weekOutsideSemester: return "上课周次超出学期范围。"
        case .missingPeriod: return "节次模式必须填写开始和结束节次。"
        case .invalidPeriodRange: return "开始节次不能晚于结束节次。"
        case .unknownPeriod: return "课程引用了不存在的节次。"
        case .missingCustomTime: return "不规则时间课程必须填写开始和结束时间。"
        case .invalidCustomTime: return "开始时间必须早于结束时间，且课程不能跨日。"
        case .staleTimingFields: return "两种计时模式的字段必须互斥。"
        }
    }
}
public enum MeetingRuleValidator {
    public static func validate(
        _ rule: MeetingRule,
        in table: CourseTable,
        periods: [Period]
    ) throws {
        guard (1...7).contains(rule.weekday) else {
            throw MeetingRuleValidationError.invalidWeekday
        }
        guard !rule.weekSet.isEmpty else {
            throw MeetingRuleValidationError.emptyWeekSet
        }
        guard rule.weekSet.allSatisfy({ (1...table.totalWeeks).contains($0) }) else {
            throw MeetingRuleValidationError.weekOutsideSemester
        }

        switch rule.timingMode {
        case .period:
            guard rule.customStartMinute == nil, rule.customEndMinute == nil else {
                throw MeetingRuleValidationError.staleTimingFields
            }
            guard let start = rule.startPeriod, let end = rule.endPeriod else {
                throw MeetingRuleValidationError.missingPeriod
            }
            guard start <= end else {
                throw MeetingRuleValidationError.invalidPeriodRange
            }
            let known = Set(periods.map(\.index))
            guard known.contains(start), known.contains(end) else {
                throw MeetingRuleValidationError.unknownPeriod
            }

        case .custom:
            guard rule.startPeriod == nil, rule.endPeriod == nil else {
                throw MeetingRuleValidationError.staleTimingFields
            }
            guard let start = rule.customStartMinute, let end = rule.customEndMinute else {
                throw MeetingRuleValidationError.missingCustomTime
            }
            guard (0...1439).contains(start), (1...1440).contains(end), start < end else {
                throw MeetingRuleValidationError.invalidCustomTime
            }
        }
    }

    public static func resolve(
        _ rule: MeetingRule,
        periods: [Period]
    ) throws -> ResolvedMeetingTime {
        switch rule.timingMode {
        case .custom:
            guard let start = rule.customStartMinute, let end = rule.customEndMinute else {
                throw MeetingRuleValidationError.missingCustomTime
            }
            guard (0...1439).contains(start), (1...1440).contains(end), start < end else {
                throw MeetingRuleValidationError.invalidCustomTime
            }
            return ResolvedMeetingTime(startMinuteOfDay: start, endMinuteOfDay: end)

        case .period:
            guard let startIndex = rule.startPeriod, let endIndex = rule.endPeriod else {
                throw MeetingRuleValidationError.missingPeriod
            }
            guard startIndex <= endIndex else {
                throw MeetingRuleValidationError.invalidPeriodRange
            }
            guard
                let start = periods.first(where: { $0.index == startIndex }),
                let end = periods.first(where: { $0.index == endIndex })
            else {
                throw MeetingRuleValidationError.unknownPeriod
            }
            return ResolvedMeetingTime(
                startMinuteOfDay: start.startMinuteOfDay,
                endMinuteOfDay: end.endMinuteOfDay
            )
        }
    }
}
