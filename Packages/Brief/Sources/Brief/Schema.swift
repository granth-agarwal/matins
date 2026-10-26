import Foundation

public struct BriefDocument: Codable, Sendable, Equatable {
    public var date: String
    public var weekday: String
    public var greeting_line: String
    public var focus: Focus
    public var todos: [Todo]
    public var updates: [Update]
    public var schedule: [Meeting]
    public var replies: [Reply]
    public var skip_today: [String]
    public var carry_over: [CarryOver]
    public var sources_used: [String]
    public var failed_sources: [String]
    public init(date: String, weekday: String, greeting_line: String, focus: Focus, todos: [Todo], updates: [Update], schedule: [Meeting], replies: [Reply], skip_today: [String], carry_over: [CarryOver], sources_used: [String], failed_sources: [String]) {
        self.date = date
        self.weekday = weekday
        self.greeting_line = greeting_line
        self.focus = focus
        self.todos = todos
        self.updates = updates
        self.schedule = schedule
        self.replies = replies
        self.skip_today = skip_today
        self.carry_over = carry_over
        self.sources_used = sources_used
        self.failed_sources = failed_sources
    }
}

public struct Focus: Codable, Sendable, Equatable {
    public var title: String
    public var detail: String
    public var action: String
    public var source_id: String
    public init(title: String, detail: String, action: String, source_id: String) {
        self.title = title
        self.detail = detail
        self.action = action
        self.source_id = source_id
    }
}

public struct Todo: Codable, Sendable, Equatable {
    public var id: String
    public var title: String
    public var label: String
    public var priority: Int
    public var due: String?
    public var source: String
    public var source_url: String
    public init(id: String, title: String, label: String, priority: Int, due: String?, source: String, source_url: String) {
        self.id = id
        self.title = title
        self.label = label
        self.priority = priority
        self.due = due
        self.source = source
        self.source_url = source_url
    }
}

public struct Update: Codable, Sendable, Equatable {
    public var title: String
    public var detail: String
    public var source: String
    public var source_url: String
    public init(title: String, detail: String, source: String, source_url: String) {
        self.title = title
        self.detail = detail
        self.source = source
        self.source_url = source_url
    }
}

public struct Meeting: Codable, Sendable, Equatable {
    public var event_id: String
    public var start: String
    public var end: String
    public var title: String
    public var prep: [String]
    public var join_url: String
    public var has_prep_action: Bool
    public init(event_id: String, start: String, end: String, title: String, prep: [String], join_url: String, has_prep_action: Bool) {
        self.event_id = event_id
        self.start = start
        self.end = end
        self.title = title
        self.prep = prep
        self.join_url = join_url
        self.has_prep_action = has_prep_action
    }
}

public struct Reply: Codable, Sendable, Equatable {
    public var person: String
    public var ask: String
    public var thread_url: String
    public init(person: String, ask: String, thread_url: String) {
        self.person = person
        self.ask = ask
        self.thread_url = thread_url
    }
}

public struct CarryOver: Codable, Sendable, Equatable {
    public var id: String
    public var title: String
    public var age_days: Int
    public init(id: String, title: String, age_days: Int) {
        self.id = id
        self.title = title
        self.age_days = age_days
    }
}


