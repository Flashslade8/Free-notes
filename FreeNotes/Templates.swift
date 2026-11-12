import SwiftUI
import UIKit

// MARK: - Catalogue

enum TemplateCategory: String, CaseIterable, Identifiable {
    case basic = "Basic Templates"
    case planners = "Planners"
    case lists = "Lists"
    case study = "Study & Work"
    case selfCare = "Self Care"

    var id: String { rawValue }

    var shortName: String {
        switch self {
        case .basic: return "Basic"
        case .planners: return "Planners"
        case .lists: return "Lists"
        case .study: return "Study & Work"
        case .selfCare: return "Self Care"
        }
    }
}

enum TemplateCatalog {
    /// Shown under every template as "Made by …". Change this to your own name.
    static let creatorName = "Free Notes"
}

extension PageTemplate {
    var category: TemplateCategory {
        switch self {
        case .blank, .lined, .grid, .dotted: return .basic
        case .dailyPlanner, .weeklyPlanner, .monthlyPlanner, .studyTimetable: return .planners
        case .todoList, .shoppingList: return .lists
        case .cornellNotes, .meetingNotes: return .study
        case .dailyJournal, .gratitudeJournal, .habitTracker: return .selfCare
        }
    }

    static func templates(in category: TemplateCategory) -> [PageTemplate] {
        allCases.filter { $0.category == category }
    }

    /// Plain paper types, used by the editor's paper menu.
    static var basic: [PageTemplate] { templates(in: .basic) }
}

// MARK: - Paper view

/// Draws a template as sharp vector artwork at any size.
final class TemplateBackgroundView: UIView {
    var template: PageTemplate = .blank {
        didSet { if oldValue != template { setNeedsDisplay() } }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .white
        contentMode = .redraw       // redraw sharply whenever the zoom changes
        overrideUserInterfaceStyle = .light
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        UIColor.white.setFill()
        ctx.fill(bounds)
        TemplateRenderer.draw(template, in: ctx, size: bounds.size)
    }
}

struct PaperView: UIViewRepresentable {
    let template: PageTemplate

    func makeUIView(context: Context) -> TemplateBackgroundView {
        let view = TemplateBackgroundView()
        view.template = template
        return view
    }

    func updateUIView(_ view: TemplateBackgroundView, context: Context) {
        view.template = template
    }
}

// MARK: - Drawing helpers

/// Small drawing helpers. Everything is drawn in the current UIKit context.
private enum Pen {
    static let ink = UIColor(red: 0.27, green: 0.33, blue: 0.55, alpha: 1)
    static let paperBlue = UIColor(red: 0.20, green: 0.45, blue: 0.95, alpha: 1)

    static func line(_ x1: CGFloat, _ y1: CGFloat, _ x2: CGFloat, _ y2: CGFloat,
                     width: CGFloat = 0.8, alpha: CGFloat = 0.35, color: UIColor = Pen.ink) {
        let path = UIBezierPath()
        path.move(to: CGPoint(x: x1, y: y1))
        path.addLine(to: CGPoint(x: x2, y: y2))
        path.lineWidth = width
        color.withAlphaComponent(alpha).setStroke()
        path.stroke()
    }

    static func box(_ rect: CGRect, radius: CGFloat = 8, fill: CGFloat = 0,
                    width: CGFloat = 1, alpha: CGFloat = 0.45) {
        let path = UIBezierPath(roundedRect: rect, cornerRadius: radius)
        if fill > 0 {
            ink.withAlphaComponent(fill).setFill()
            path.fill()
        }
        path.lineWidth = width
        ink.withAlphaComponent(alpha).setStroke()
        path.stroke()
    }

    static func circle(centerX: CGFloat, centerY: CGFloat, radius: CGFloat, alpha: CGFloat = 0.5) {
        let path = UIBezierPath(ovalIn: CGRect(x: centerX - radius, y: centerY - radius,
                                               width: radius * 2, height: radius * 2))
        path.lineWidth = 0.9
        ink.withAlphaComponent(alpha).setStroke()
        path.stroke()
    }

    static func dot(_ x: CGFloat, _ y: CGFloat, radius: CGFloat, alpha: CGFloat, color: UIColor = ink) {
        color.withAlphaComponent(alpha).setFill()
        UIBezierPath(ovalIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)).fill()
    }

    static func checkbox(_ x: CGFloat, _ y: CGFloat, size: CGFloat = 12) {
        box(CGRect(x: x, y: y, width: size, height: size), radius: 3, width: 0.9, alpha: 0.55)
    }

    private static func attributes(size: CGFloat, weight: UIFont.Weight,
                                   alpha: CGFloat, kern: CGFloat) -> [NSAttributedString.Key: Any] {
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        let font = base.fontDescriptor.withDesign(.rounded).map { UIFont(descriptor: $0, size: size) } ?? base
        return [.font: font,
                .foregroundColor: ink.withAlphaComponent(alpha),
                .kern: kern]
    }

    static func text(_ string: String, _ x: CGFloat, _ y: CGFloat, size: CGFloat,
                     weight: UIFont.Weight = .semibold, alpha: CGFloat = 0.85, kern: CGFloat = 0) {
        let attrs = attributes(size: size, weight: weight, alpha: alpha, kern: kern)
        (string as NSString).draw(at: CGPoint(x: x, y: y), withAttributes: attrs)
    }

    static func width(of string: String, size: CGFloat, weight: UIFont.Weight, kern: CGFloat = 0) -> CGFloat {
        let attrs = attributes(size: size, weight: weight, alpha: 1, kern: kern)
        return (string as NSString).size(withAttributes: attrs).width
    }

    /// A small spaced-out capital label like "SCHEDULE".
    static func label(_ string: String, _ x: CGFloat, _ y: CGFloat) {
        text(string, x, y, size: 8.5, weight: .bold, alpha: 0.55, kern: 1.2)
    }

    /// "DATE ________" — a label followed by a line to write on.
    static func field(_ name: String, x: CGFloat, y: CGFloat, width fieldWidth: CGFloat) {
        label(name, x, y)
        let labelWidth = width(of: name, size: 8.5, weight: .bold, kern: 1.2)
        line(x + labelWidth + 8, y + 12, x + fieldWidth, y + 12, alpha: 0.4)
    }

    static func header(_ title: String) {
        text(title, 40, 32, size: 28, weight: .heavy, alpha: 0.9)
        line(40, 76, 572, 76, width: 1.4, alpha: 0.5)
    }
}

// MARK: - Renderer

/// Draws every template. Works in a 612 × 792 page and scales to whatever size it is given,
/// so the same artwork is used on screen, in thumbnails and in exported PDFs.
enum TemplateRenderer {
    static let pageW: CGFloat = 612
    static let pageH: CGFloat = 792

    static func draw(_ template: PageTemplate, in ctx: CGContext, size: CGSize) {
        guard template != .blank, size.width > 0, size.height > 0 else { return }
        ctx.saveGState()
        ctx.scaleBy(x: size.width / pageW, y: size.height / pageH)

        switch template {
        case .blank: break
        case .lined: lined()
        case .grid: grid()
        case .dotted: dotted()
        case .dailyPlanner: dailyPlanner()
        case .weeklyPlanner: weeklyPlanner()
        case .monthlyPlanner: monthlyPlanner()
        case .studyTimetable: studyTimetable()
        case .todoList: todoList()
        case .shoppingList: shoppingList()
        case .cornellNotes: cornellNotes()
        case .meetingNotes: meetingNotes()
        case .dailyJournal: dailyJournal()
        case .gratitudeJournal: gratitudeJournal()
        case .habitTracker: habitTracker()
        }
        ctx.restoreGState()
    }

    // MARK: Basic paper

    private static func lined() {
        var y: CGFloat = 56
        while y < pageH {
            Pen.line(0, y, pageW, y, width: 0.7, alpha: 0.18, color: Pen.paperBlue)
            y += 28
        }
    }

    private static func grid() {
        var y: CGFloat = 56
        while y < pageH {
            Pen.line(0, y, pageW, y, width: 0.7, alpha: 0.18, color: Pen.paperBlue)
            y += 28
        }
        var x: CGFloat = 28
        while x < pageW {
            Pen.line(x, 0, x, pageH, width: 0.7, alpha: 0.18, color: Pen.paperBlue)
            x += 28
        }
    }

    private static func dotted() {
        var y: CGFloat = 28
        while y < pageH {
            var x: CGFloat = 28
            while x < pageW {
                Pen.dot(x, y, radius: 1.4, alpha: 0.35, color: Pen.paperBlue)
                x += 28
            }
            y += 28
        }
    }

    // MARK: Planners

    private static func dailyPlanner() {
        Pen.header("Daily Planner")
        Pen.field("DATE", x: 400, y: 50, width: 172)

        Pen.label("SCHEDULE", 40, 88)
        let hours = ["6 AM", "7", "8", "9", "10", "11", "12 PM", "1", "2", "3", "4", "5", "6", "7", "8", "9"]
        for (i, hour) in hours.enumerated() {
            let y = 108 + CGFloat(i) * 40
            Pen.line(40, y, 320, y)
            Pen.text(hour, 44, y + 5, size: 8.5, weight: .medium, alpha: 0.6)
        }
        Pen.line(40, 748, 320, 748)
        Pen.line(76, 108, 76, 748, alpha: 0.3)

        Pen.label("TOP PRIORITIES", 345, 88)
        for i in 0..<3 {
            let y = 108 + CGFloat(i) * 30
            Pen.text("\(i + 1)", 347, y + 8, size: 9, weight: .bold, alpha: 0.6)
            Pen.line(362, y + 28, 572, y + 28)
        }

        Pen.label("TO DO", 345, 212)
        for i in 0..<9 {
            let y = 232 + CGFloat(i) * 30
            Pen.checkbox(347, y + 8)
            Pen.line(366, y + 26, 572, y + 26)
        }

        Pen.label("NOTES", 345, 524)
        Pen.box(CGRect(x: 345, y: 544, width: 227, height: 204))
    }

    private static func weeklyPlanner() {
        Pen.header("Weekly Planner")
        Pen.field("WEEK OF", x: 380, y: 50, width: 192)

        let names = ["MONDAY", "TUESDAY", "WEDNESDAY", "THURSDAY", "FRIDAY", "SATURDAY", "SUNDAY", "NOTES"]
        for (i, name) in names.enumerated() {
            let x: CGFloat = i % 2 == 0 ? 40 : 320
            let y: CGFloat = 92 + CGFloat(i / 2) * 166
            let box = CGRect(x: x, y: y, width: 252, height: 156)
            Pen.box(box, radius: 10, fill: i == 7 ? 0.05 : 0.0)
            Pen.label(name, x + 14, y + 12)
            var lineY = y + 44
            while lineY < y + 148 {
                Pen.line(x + 14, lineY, x + 238, lineY, alpha: 0.2)
                lineY += 26
            }
        }
    }

    private static func monthlyPlanner() {
        Pen.header("Monthly Planner")
        Pen.field("MONTH", x: 380, y: 50, width: 192)

        let days = ["MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN"]
        let colW: CGFloat = 532 / 7
        for (i, day) in days.enumerated() {
            let w = Pen.width(of: day, size: 8.5, weight: .bold, kern: 1.2)
            Pen.label(day, 40 + colW * CGFloat(i) + (colW - w) / 2, 94)
        }
        Pen.box(CGRect(x: 40, y: 112, width: 532, height: 440), radius: 6)
        for i in 1..<7 {
            Pen.line(40 + colW * CGFloat(i), 112, 40 + colW * CGFloat(i), 552, alpha: 0.3)
        }
        for i in 1..<5 {
            Pen.line(40, 112 + 88 * CGFloat(i), 572, 112 + 88 * CGFloat(i), alpha: 0.3)
        }

        Pen.label("GOALS", 40, 572)
        Pen.box(CGRect(x: 40, y: 590, width: 256, height: 158))
        Pen.label("NOTES", 316, 572)
        Pen.box(CGRect(x: 316, y: 590, width: 256, height: 158))
    }

    private static func studyTimetable() {
        Pen.header("Study Timetable")
        Pen.field("WEEK OF", x: 380, y: 50, width: 192)

        let timeW: CGFloat = 52
        let colW: CGFloat = (532 - timeW) / 7
        Pen.box(CGRect(x: 40, y: 92, width: 532, height: 24), radius: 6, fill: 0.08)
        Pen.box(CGRect(x: 40, y: 92, width: 532, height: 654), radius: 6)

        let days = ["MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN"]
        for (i, day) in days.enumerated() {
            let x = 40 + timeW + colW * CGFloat(i)
            let w = Pen.width(of: day, size: 8.5, weight: .bold, kern: 1.2)
            Pen.label(day, x + (colW - w) / 2, 99)
            Pen.line(x, 92, x, 746, alpha: 0.3)
        }
        Pen.line(40 + timeW, 92, 40 + timeW, 746, alpha: 0.4)

        for i in 0..<14 {
            let y = 116 + CGFloat(i) * 45
            Pen.line(40, y, 572, y, alpha: 0.3)
            Pen.text("\(7 + i):00", 45, y + 5, size: 8.5, weight: .medium, alpha: 0.6)
        }
    }

    // MARK: Lists

    private static func todoList() {
        Pen.header("To-Do List")
        Pen.field("DATE", x: 400, y: 50, width: 172)

        for i in 0..<17 {
            let y = 96 + CGFloat(i) * 32
            Pen.checkbox(42, y + 8)
            Pen.line(66, y + 26, 572, y + 26)
        }
        Pen.label("NOTES", 40, 652)
        Pen.box(CGRect(x: 40, y: 670, width: 532, height: 78))
    }

    private static func shoppingList() {
        Pen.header("Shopping List")
        Pen.field("STORE", x: 380, y: 50, width: 192)

        for column in 0..<2 {
            let x: CGFloat = column == 0 ? 40 : 322
            for i in 0..<15 {
                let y = 96 + CGFloat(i) * 34
                Pen.checkbox(x + 2, y + 10)
                Pen.line(x + 26, y + 28, x + 250, y + 28)
            }
        }
        Pen.label("NOTES", 40, 626)
        Pen.box(CGRect(x: 40, y: 644, width: 532, height: 104))
    }

    // MARK: Study and work

    private static func cornellNotes() {
        Pen.text("Cornell Notes", 40, 28, size: 24, weight: .heavy, alpha: 0.9)
        Pen.field("TOPIC", x: 200, y: 40, width: 160)
        Pen.field("DATE", x: 380, y: 40, width: 192)
        Pen.line(40, 76, 572, 76, width: 1.4, alpha: 0.5)

        Pen.line(190, 76, 190, 640, width: 1.2, alpha: 0.5)
        Pen.line(40, 640, 572, 640, width: 1.2, alpha: 0.5)
        Pen.label("CUES", 40, 88)
        Pen.label("NOTES", 204, 88)
        Pen.label("SUMMARY", 40, 652)

        var y: CGFloat = 116
        while y < 632 {
            Pen.line(190, y, 572, y, alpha: 0.18)
            y += 28
        }
        for i in 0..<3 {
            Pen.line(40, 690 + CGFloat(i) * 26, 572, 690 + CGFloat(i) * 26, alpha: 0.3)
        }
    }

    private static func meetingNotes() {
        Pen.header("Meeting Notes")
        Pen.field("MEETING", x: 40, y: 92, width: 330)
        Pen.field("DATE", x: 390, y: 92, width: 182)
        Pen.field("ATTENDEES", x: 40, y: 124, width: 532)

        Pen.label("AGENDA", 40, 158)
        Pen.box(CGRect(x: 40, y: 176, width: 532, height: 96))
        for i in 1..<3 {
            Pen.line(52, 176 + CGFloat(i) * 32, 560, 176 + CGFloat(i) * 32, alpha: 0.2)
        }

        Pen.label("NOTES", 40, 290)
        Pen.box(CGRect(x: 40, y: 308, width: 532, height: 268))
        var y: CGFloat = 308 + 27
        while y < 576 {
            Pen.line(52, y, 560, y, alpha: 0.18)
            y += 27
        }

        Pen.label("ACTION ITEMS", 40, 594)
        Pen.label("OWNER", 430, 594)
        Pen.label("DUE", 520, 594)
        for i in 0..<5 {
            let rowY = 612 + CGFloat(i) * 28
            Pen.checkbox(42, rowY + 6)
            Pen.line(66, rowY + 22, 420, rowY + 22)
            Pen.line(430, rowY + 22, 508, rowY + 22)
            Pen.line(516, rowY + 22, 572, rowY + 22)
        }
    }

    // MARK: Self care

    private static func dailyJournal() {
        Pen.header("Daily Journal")
        Pen.field("DATE", x: 400, y: 50, width: 172)

        Pen.label("MOOD", 40, 94)
        for i in 0..<5 {
            Pen.circle(centerX: 100 + CGFloat(i) * 32, centerY: 99, radius: 10)
        }
        var y: CGFloat = 136
        while y < 752 {
            Pen.line(40, y, 572, y, alpha: 0.25)
            y += 28
        }
    }

    private static func gratitudeJournal() {
        Pen.header("Gratitude Journal")
        Pen.field("DATE", x: 400, y: 50, width: 172)

        let prompts = ["I'M GRATEFUL FOR", "SOMETHING THAT WENT WELL", "TOMORROW I WILL"]
        for (i, prompt) in prompts.enumerated() {
            let y = 92 + CGFloat(i) * 180
            Pen.label(prompt, 40, y)
            Pen.box(CGRect(x: 40, y: y + 18, width: 532, height: 150), radius: 10)
            for line in 1..<5 {
                Pen.line(54, y + 18 + CGFloat(line) * 30, 558, y + 18 + CGFloat(line) * 30, alpha: 0.2)
            }
        }
        Pen.label("HIGHLIGHT OF MY DAY", 40, 636)
        Pen.box(CGRect(x: 40, y: 654, width: 532, height: 94), radius: 10, fill: 0.05)
    }

    private static func habitTracker() {
        Pen.header("Habit Tracker")
        Pen.field("MONTH", x: 380, y: 50, width: 192)

        let nameW: CGFloat = 140
        let colW: CGFloat = (532 - nameW) / 31
        let top: CGFloat = 120
        let rowH: CGFloat = 34
        let rows = 16

        Pen.label("HABIT", 46, 100)
        for day in 0..<31 {
            let x = 40 + nameW + colW * CGFloat(day)
            let text = "\(day + 1)"
            let w = Pen.width(of: text, size: 6.5, weight: .semibold)
            Pen.text(text, x + (colW - w) / 2, 102, size: 6.5, weight: .semibold, alpha: 0.6)
        }

        Pen.box(CGRect(x: 40, y: top, width: 532, height: rowH * CGFloat(rows)), radius: 6)
        for r in 1..<rows {
            Pen.line(40, top + rowH * CGFloat(r), 572, top + rowH * CGFloat(r), alpha: 0.25)
        }
        Pen.line(40 + nameW, top, 40 + nameW, top + rowH * CGFloat(rows), alpha: 0.45)
        for day in 1..<31 {
            let x = 40 + nameW + colW * CGFloat(day)
            Pen.line(x, top, x, top + rowH * CGFloat(rows), alpha: 0.18)
        }

        Pen.label("NOTES", 40, 678)
        Pen.box(CGRect(x: 40, y: 696, width: 532, height: 52))
    }
}

// MARK: - Template picker

struct TemplatePickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("favouriteTemplates") private var favouritesRaw = ""
    @State private var selected: PageTemplate = .blank
    @State private var showingMine = false

    let onPick: (PageTemplate) -> Void

    private var favourites: Set<String> {
        Set(favouritesRaw.split(separator: ",").map(String.init))
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()
            ZStack(alignment: .bottom) {
                if showingMine { myTemplates } else { allTemplates }
                tabPill.padding(.bottom, 14)
            }
        }
        .background(Color(.systemBackground))
        .presentationDetents([.large])
    }

    // MARK: Pieces

    private var topBar: some View {
        ZStack {
            Text("Templates").font(.headline)
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.body.weight(.semibold))
                        .frame(width: 40, height: 40)
                        .background(Color(.secondarySystemBackground), in: Circle())
                }
                .accessibilityLabel("Close")
                Spacer()
                Button {
                    onPick(selected)
                    dismiss()
                } label: {
                    Text("Create")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 10)
                        .background(Color.accentColor, in: Capsule())
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var allTemplates: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 30) {
                    HStack(spacing: 10) {
                        Text("Go to:").foregroundStyle(.secondary)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(TemplateCategory.allCases) { category in
                                    Button(category.shortName) {
                                        withAnimation { proxy.scrollTo(category, anchor: .top) }
                                    }
                                    .font(.subheadline)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .background(Color(.secondarySystemBackground), in: Capsule())
                                    .foregroundStyle(.primary)
                                }
                            }
                        }
                    }

                    ForEach(TemplateCategory.allCases) { category in
                        VStack(alignment: .leading, spacing: 16) {
                            Text(category.rawValue).font(.title3.weight(.bold))
                            templateGrid(PageTemplate.templates(in: category))
                        }
                        .id(category)
                    }
                }
                .padding(20)
                .padding(.bottom, 90)
            }
        }
    }

    private var myTemplates: some View {
        ScrollView {
            let mine = PageTemplate.allCases.filter { favourites.contains($0.rawValue) }
            if mine.isEmpty {
                ContentUnavailableView("No Saved Templates", systemImage: "heart",
                                       description: Text("Select a template and tap its star to keep it here."))
                    .padding(.top, 80)
            } else {
                templateGrid(mine).padding(20).padding(.bottom, 90)
            }
        }
    }

    private func templateGrid(_ list: [PageTemplate]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 230), spacing: 22)],
                  alignment: .leading, spacing: 26) {
            ForEach(list) { template in card(template) }
        }
    }

    private func card(_ template: PageTemplate) -> some View {
        let isSelected = selected == template
        let isFavourite = favourites.contains(template.rawValue)

        return VStack(alignment: .leading, spacing: 6) {
            PaperView(template: template)
                .aspectRatio(PageMetrics.size.width / PageMetrics.size.height, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color(.separator)))
                .overlay(RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.accentColor, lineWidth: isSelected ? 4 : 0))
                .overlay(alignment: .topTrailing) {
                    if isSelected || isFavourite {
                        Image(systemName: isFavourite ? "star.fill" : "star")
                            .font(.title3)
                            .foregroundStyle(Color.accentColor)
                            .padding(10)
                            .contentShape(Rectangle())
                            .onTapGesture { toggleFavourite(template) }
                            .accessibilityLabel(isFavourite ? "Remove from My Templates" : "Save to My Templates")
                    }
                }
            Text(template.rawValue)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            Text("Made by \(TemplateCatalog.creatorName)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            selected = template
            Haptics.tap()
        }
    }

    private var tabPill: some View {
        HStack(spacing: 4) {
            tabButton("Templates", symbol: "doc.text.image", active: !showingMine) { showingMine = false }
            tabButton("My Templates", symbol: "heart", active: showingMine) { showingMine = true }
        }
        .padding(6)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().stroke(.quaternary))
        .shadow(color: .black.opacity(0.1), radius: 8, y: 3)
    }

    private func tabButton(_ title: String, symbol: String, active: Bool,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .foregroundStyle(active ? Color.accentColor : Color.primary)
                .background(active ? Color.accentColor.opacity(0.15) : Color.clear, in: Capsule())
        }
    }

    private func toggleFavourite(_ template: PageTemplate) {
        var current = favourites
        if current.contains(template.rawValue) {
            current.remove(template.rawValue)
        } else {
            current.insert(template.rawValue)
        }
        favouritesRaw = current.sorted().joined(separator: ",")
        Haptics.tap()
    }
}
