import SwiftUI
import VoiceEnterCore

@main
struct VoiceEnterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
                .environmentObject(appDelegate.appState)
        }
    }
}

// MARK: - AppDelegate

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var popover: NSPopover?
    let appState = AppState()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 隐藏 Dock 图标
        NSApp.setActivationPolicy(.accessory)

        // 创建状态栏图标
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            updateStatusBarIcon()
            button.action = #selector(togglePopover)
            button.target = self
        }

        // 创建 Popover
        popover = NSPopover()
        popover?.contentSize = NSSize(width: 280, height: 480)
        popover?.behavior = .transient
        popover?.contentViewController = NSHostingController(
            rootView: MenuBarView().environmentObject(appState)
        )

        // 监听状态变化
        appState.onStatusChange = { [weak self] isEnabled in
            self?.updateStatusBarIcon()
        }

        // 检查权限并自动启动
        if appState.inputMonitor.checkAccessibilityPermission() {
            _ = appState.startMonitoring()
        }
    }

    @objc func togglePopover() {
        if let popover = popover, let button = statusItem?.button {
            if popover.isShown {
                popover.performClose(nil)
            } else {
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
                // 激活应用以确保 popover 获得焦点
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }

    func updateStatusBarIcon() {
        if let button = statusItem?.button {
            let icon = appState.isMonitoring ? "mic.fill" : "mic.slash"
            button.image = NSImage(systemSymbolName: icon, accessibilityDescription: "VoiceEnter")
        }
    }
}

// MARK: - AppState

class AppState: ObservableObject {
    @Published var isMonitoring: Bool = false
    @Published var isEnabled: Bool = true
    @Published var triggerWords: [String] = []
    @Published var lastTriggered: String = ""

    // 触发范围设置
    @Published var triggerScope: TriggerScope = .kittyOnly

    // 面部表情触发相关
    @Published var isFaceExpressionEnabled: Bool = false
    @Published var selectedExpression: ExpressionType = .mouthOpen
    @Published var expressionThreshold: Float = 0.4
    @Published var hasFaceDetected: Bool = false
    @Published var currentExpressionValue: Float = 0

    let inputMonitor: UniversalInputMonitor
    let settingsManager: SettingsManager

    var onStatusChange: ((Bool) -> Void)?

    init() {
        self.inputMonitor = UniversalInputMonitor()
        self.settingsManager = SettingsManager()

        // 同步设置
        self.isEnabled = settingsManager.isEnabled
        self.triggerWords = settingsManager.triggerWords
        self.triggerScope = settingsManager.triggerScope

        // 监听触发事件
        inputMonitor.onTrigger = { [weak self] word in
            DispatchQueue.main.async {
                self?.lastTriggered = word
            }
        }

        inputMonitor.onStatusChange = { [weak self] isMonitoring in
            DispatchQueue.main.async {
                self?.isMonitoring = isMonitoring
                self?.onStatusChange?(isMonitoring)
            }
        }

        // 监听表情变化
        inputMonitor.onExpressionChange = { [weak self] state in
            DispatchQueue.main.async {
                self?.hasFaceDetected = state.hasFace
                if let expression = self?.selectedExpression {
                    self?.currentExpressionValue = state.coefficients[expression] ?? 0
                }
            }
        }
    }

    func startMonitoring() -> Bool {
        let result = inputMonitor.startMonitoring()
        isMonitoring = result
        return result
    }

    func stopMonitoring() {
        inputMonitor.stopMonitoring()
        isMonitoring = false
    }

    func toggleMonitoring() {
        if isMonitoring {
            stopMonitoring()
        } else {
            _ = startMonitoring()
        }
    }

    func toggleEnabled() {
        isEnabled.toggle()
        settingsManager.isEnabled = isEnabled
    }

    func addTriggerWord(_ word: String) -> Bool {
        if settingsManager.addTriggerWord(word) {
            triggerWords = settingsManager.triggerWords
            return true
        }
        return false
    }

    func removeTriggerWord(_ word: String) -> Bool {
        if settingsManager.removeTriggerWord(word) {
            triggerWords = settingsManager.triggerWords
            return true
        }
        return false
    }

    func requestAccessibilityPermission() {
        inputMonitor.requestAccessibilityPermission()
    }

    func checkAccessibilityPermission() -> Bool {
        inputMonitor.checkAccessibilityPermission()
    }

    // MARK: - 面部表情触发

    func toggleFaceExpression() {
        isFaceExpressionEnabled.toggle()
        inputMonitor.faceMonitor.isExpressionTriggerEnabled = isFaceExpressionEnabled
    }

    func setSelectedExpression(_ expression: ExpressionType) {
        selectedExpression = expression
        inputMonitor.faceMonitor.triggerExpression = expression
        expressionThreshold = expression.defaultThreshold
        inputMonitor.faceMonitor.threshold = expressionThreshold
    }

    func setExpressionThreshold(_ threshold: Float) {
        expressionThreshold = threshold
        inputMonitor.faceMonitor.threshold = threshold
    }

    func checkCameraPermission() -> Bool {
        inputMonitor.faceMonitor.checkCameraPermission()
    }

    func requestCameraPermission() {
        inputMonitor.faceMonitor.requestCameraPermission { [weak self] granted in
            if granted {
                // 重新启动监听以启用摄像头
                self?.inputMonitor.faceMonitor.startMonitoring()
            }
        }
    }

    // MARK: - 触发范围设置

    func setTriggerScope(_ scope: TriggerScope) {
        triggerScope = scope
        settingsManager.triggerScope = scope
    }
}

// MARK: - Design System

private enum DesignColors {
    static let cardBackground = Color(white: 0.12)
    static let surfaceBackground = Color(white: 0.08)
    static let accentGradient = LinearGradient(
        colors: [Color(red: 0.2, green: 0.8, blue: 0.6), Color(red: 0.3, green: 0.6, blue: 0.9)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    static let dangerGradient = LinearGradient(
        colors: [Color(red: 0.9, green: 0.3, blue: 0.3), Color(red: 0.8, green: 0.2, blue: 0.4)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    static let subtleText = Color(white: 0.5)
    static let primaryText = Color(white: 0.95)
    static let secondaryText = Color(white: 0.7)
    static let activeGreen = Color(red: 0.3, green: 0.85, blue: 0.5)
    static let warningOrange = Color(red: 0.95, green: 0.6, blue: 0.2)
    static let inactiveRed = Color(red: 0.85, green: 0.3, blue: 0.35)
}

// MARK: - Card View Modifier

struct CardStyle: ViewModifier {
    var padding: CGFloat = 12

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(DesignColors.cardBackground)
                    .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
            )
    }
}

extension View {
    func cardStyle(padding: CGFloat = 12) -> some View {
        modifier(CardStyle(padding: padding))
    }
}

// MARK: - Status Indicator

struct StatusIndicator: View {
    let isActive: Bool
    let activeText: String
    let inactiveText: String

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(isActive ? DesignColors.activeGreen : DesignColors.inactiveRed)
                .frame(width: 8, height: 8)
                .shadow(color: isActive ? DesignColors.activeGreen.opacity(0.6) : .clear, radius: 4)
            Text(isActive ? activeText : inactiveText)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(DesignColors.secondaryText)
        }
    }
}

// MARK: - Section Header

struct SectionHeader: View {
    let icon: String
    let title: String
    var trailing: AnyView? = nil

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(DesignColors.accentGradient)
            Text(title)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(DesignColors.subtleText)
                .textCase(.uppercase)
                .tracking(0.5)
            Spacer()
            if let trailing = trailing {
                trailing
            }
        }
    }
}

// MARK: - Styled Toggle

struct StyledToggle: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(DesignColors.primaryText)
        }
        .toggleStyle(.switch)
        .tint(DesignColors.activeGreen)
    }
}

// MARK: - Trigger Word Tag

struct TriggerWordTag: View {
    let word: String
    let onRemove: () -> Void
    let canRemove: Bool

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 6) {
            Text(word)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundColor(DesignColors.primaryText)

            if canRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(isHovering ? DesignColors.inactiveRed : DesignColors.subtleText)
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isHovering = hovering
                    }
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
                )
        )
    }
}

// MARK: - Primary Action Button

struct PrimaryActionButton: View {
    let title: String
    let icon: String
    let isDestructive: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isDestructive ? DesignColors.dangerGradient : DesignColors.accentGradient)
                    .shadow(color: (isDestructive ? Color.red : Color.teal).opacity(isHovering ? 0.4 : 0.2), radius: isHovering ? 8 : 4, y: 2)
            )
            .scaleEffect(isHovering ? 1.02 : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                isHovering = hovering
            }
        }
    }
}

// MARK: - MenuBarView

struct MenuBarView: View {
    @EnvironmentObject var appState: AppState
    @State private var newTriggerWord: String = ""
    @State private var showingAddField: Bool = false
    @State private var isHoveringQuit = false

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 16) {
                // Header
                headerSection

                // Main Control Card
                mainControlCard

                // Trigger Words Card
                triggerWordsCard

                // Face Expression Card
                faceExpressionCard

                // Footer
                footerSection
            }
            .padding(16)
        }
        .frame(width: 300, height: 520)
        .background(DesignColors.surfaceBackground)
    }

    // MARK: - Header Section

    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("VoiceEnter")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(DesignColors.primaryText)
                Text("语音触发助手")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(DesignColors.subtleText)
            }
            Spacer()
            StatusIndicator(
                isActive: appState.isMonitoring,
                activeText: "运行中",
                inactiveText: "已停止"
            )
        }
    }

    // MARK: - Main Control Card

    private var mainControlCard: some View {
        VStack(spacing: 12) {
            SectionHeader(icon: "slider.horizontal.3", title: "控制")

            StyledToggle(
                title: "启用触发词检测",
                isOn: Binding(
                    get: { appState.isEnabled },
                    set: { _ in appState.toggleEnabled() }
                )
            )

            // Trigger Scope Picker
            HStack {
                Text("触发范围")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(DesignColors.primaryText)
                Spacer()
                Picker("", selection: Binding(
                    get: { appState.triggerScope },
                    set: { appState.setTriggerScope($0) }
                )) {
                    ForEach(TriggerScope.allCases, id: \.self) { scope in
                        Text(scope.displayName).tag(scope)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 100)
                .tint(DesignColors.activeGreen)
            }

            PrimaryActionButton(
                title: appState.isMonitoring ? "停止监听" : "开始监听",
                icon: appState.isMonitoring ? "stop.fill" : "play.fill",
                isDestructive: appState.isMonitoring,
                action: { appState.toggleMonitoring() }
            )

            // Permission Warning
            if !appState.checkAccessibilityPermission() {
                Button(action: { appState.requestAccessibilityPermission() }) {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.shield.fill")
                            .foregroundColor(DesignColors.warningOrange)
                        Text("需要辅助功能权限")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(DesignColors.warningOrange)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(DesignColors.warningOrange.opacity(0.15))
                    )
                }
                .buttonStyle(.plain)
            }

            // Last Triggered
            if !appState.lastTriggered.isEmpty {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(DesignColors.activeGreen)
                    Text("最近触发:")
                        .font(.system(size: 11))
                        .foregroundColor(DesignColors.subtleText)
                    Text(appState.lastTriggered)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundColor(DesignColors.activeGreen)
                    Spacer()
                }
            }
        }
        .cardStyle()
    }

    // MARK: - Trigger Words Card

    private var triggerWordsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(
                icon: "text.bubble.fill",
                title: "触发词",
                trailing: AnyView(
                    Text("\(appState.triggerWords.count)")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundColor(DesignColors.subtleText)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule().fill(Color.white.opacity(0.1))
                        )
                )
            )

            // Words Flow Layout
            FlowLayout(spacing: 8) {
                ForEach(appState.triggerWords, id: \.self) { word in
                    TriggerWordTag(
                        word: word,
                        onRemove: { _ = appState.removeTriggerWord(word) },
                        canRemove: appState.triggerWords.count > 1
                    )
                }
            }

            // Add New Word
            if showingAddField {
                HStack(spacing: 8) {
                    TextField("输入触发词", text: $newTriggerWord)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(DesignColors.primaryText)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.white.opacity(0.05))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .strokeBorder(DesignColors.activeGreen.opacity(0.5), lineWidth: 1)
                                )
                        )
                        .onSubmit { addTriggerWord() }

                    Button(action: { addTriggerWord() }) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(DesignColors.accentGradient)
                    }
                    .buttonStyle(.plain)
                    .disabled(newTriggerWord.isEmpty)
                    .opacity(newTriggerWord.isEmpty ? 0.4 : 1)

                    Button(action: { showingAddField = false }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(DesignColors.subtleText)
                    }
                    .buttonStyle(.plain)
                }
            } else {
                Button(action: { showingAddField = true }) {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .semibold))
                        Text("添加触发词")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(DesignColors.accentGradient)
                }
                .buttonStyle(.plain)
            }
        }
        .cardStyle()
    }

    // MARK: - Face Expression Card

    private var faceExpressionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(
                icon: "face.smiling.inverse",
                title: "表情触发",
                trailing: appState.isFaceExpressionEnabled ? AnyView(
                    Circle()
                        .fill(appState.hasFaceDetected ? DesignColors.activeGreen : DesignColors.warningOrange)
                        .frame(width: 6, height: 6)
                        .shadow(color: appState.hasFaceDetected ? DesignColors.activeGreen.opacity(0.5) : .clear, radius: 3)
                ) : nil
            )

            StyledToggle(
                title: "启用表情触发",
                isOn: Binding(
                    get: { appState.isFaceExpressionEnabled },
                    set: { _ in appState.toggleFaceExpression() }
                )
            )

            if appState.isFaceExpressionEnabled {
                if !appState.checkCameraPermission() {
                    Button(action: { appState.requestCameraPermission() }) {
                        HStack(spacing: 6) {
                            Image(systemName: "camera.fill")
                                .foregroundColor(DesignColors.warningOrange)
                            Text("需要摄像头权限")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(DesignColors.warningOrange)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(DesignColors.warningOrange.opacity(0.15))
                        )
                    }
                    .buttonStyle(.plain)
                } else {
                    VStack(spacing: 10) {
                        // Expression Picker
                        HStack {
                            Text("触发表情")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(DesignColors.secondaryText)
                            Spacer()
                            Picker("", selection: Binding(
                                get: { appState.selectedExpression },
                                set: { appState.setSelectedExpression($0) }
                            )) {
                                ForEach(ExpressionType.allCases, id: \.self) { type in
                                    Text(type.rawValue).tag(type)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(width: 90)
                            .tint(DesignColors.activeGreen)
                        }

                        // Sensitivity Slider
                        VStack(spacing: 4) {
                            HStack {
                                Text("灵敏度")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(DesignColors.secondaryText)
                                Spacer()
                                Text("\(Int((1 - appState.expressionThreshold) * 100))%")
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .foregroundColor(DesignColors.activeGreen)
                            }
                            Slider(
                                value: Binding(
                                    get: { appState.expressionThreshold },
                                    set: { appState.setExpressionThreshold($0) }
                                ),
                                in: 0.2...0.8
                            )
                            .tint(DesignColors.activeGreen)
                        }

                        // Detection Value
                        VStack(spacing: 4) {
                            HStack {
                                Text("检测值")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(DesignColors.secondaryText)
                                Spacer()
                                Text(appState.hasFaceDetected ? "\(Int(appState.currentExpressionValue * 100))%" : "无人脸")
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .foregroundColor(appState.currentExpressionValue > appState.expressionThreshold ? DesignColors.activeGreen : DesignColors.subtleText)
                            }
                            GeometryReader { geometry in
                                ZStack(alignment: .leading) {
                                    // Background
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(Color.white.opacity(0.1))
                                        .frame(height: 6)

                                    // Value Bar
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(
                                            appState.currentExpressionValue > appState.expressionThreshold ?
                                            DesignColors.accentGradient :
                                            LinearGradient(colors: [DesignColors.subtleText], startPoint: .leading, endPoint: .trailing)
                                        )
                                        .frame(width: geometry.size.width * CGFloat(appState.currentExpressionValue), height: 6)

                                    // Threshold Marker
                                    Rectangle()
                                        .fill(DesignColors.warningOrange)
                                        .frame(width: 2, height: 10)
                                        .offset(x: geometry.size.width * CGFloat(appState.expressionThreshold) - 1)
                                }
                            }
                            .frame(height: 10)
                        }
                    }
                }
            }
        }
        .cardStyle()
    }

    // MARK: - Footer Section

    private var footerSection: some View {
        HStack {
            Spacer()
            Button(action: { NSApp.terminate(nil) }) {
                HStack(spacing: 4) {
                    Image(systemName: "power")
                        .font(.system(size: 10, weight: .semibold))
                    Text("退出")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundColor(isHoveringQuit ? DesignColors.inactiveRed : DesignColors.subtleText)
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.15)) {
                    isHoveringQuit = hovering
                }
            }
            Spacer()
        }
        .padding(.top, 4)
    }

    private func addTriggerWord() {
        if appState.addTriggerWord(newTriggerWord) {
            newTriggerWord = ""
            showingAddField = false
        }
    }
}

// MARK: - Flow Layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = layout(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(proposal: proposal, subviews: subviews)
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.positions[index].x, y: bounds.minY + result.positions[index].y), proposal: .unspecified)
        }
    }

    private func layout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        var positions: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        let maxWidth = proposal.width ?? .infinity

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            if currentX + size.width > maxWidth && currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }

            positions.append(CGPoint(x: currentX, y: currentY))
            currentX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }

        return (CGSize(width: maxWidth, height: currentY + lineHeight), positions)
    }
}

// MARK: - FaceExpressionSection (Legacy - keeping for compatibility)

struct FaceExpressionSection: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        EmptyView()
    }
}

// MARK: - SettingsView

struct SettingsView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Form {
            Section("通用") {
                Toggle("启用触发词检测", isOn: Binding(
                    get: { appState.isEnabled },
                    set: { _ in appState.toggleEnabled() }
                ))

                Picker("触发范围", selection: Binding(
                    get: { appState.triggerScope },
                    set: { appState.setTriggerScope($0) }
                )) {
                    ForEach(TriggerScope.allCases, id: \.self) { scope in
                        Text(scope.displayName).tag(scope)
                    }
                }

                Text(appState.triggerScope.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("触发词") {
                ForEach(appState.triggerWords, id: \.self) { word in
                    Text(word)
                }
            }

            Section("表情触发") {
                Toggle("启用表情触发", isOn: Binding(
                    get: { appState.isFaceExpressionEnabled },
                    set: { _ in appState.toggleFaceExpression() }
                ))

                Picker("触发表情", selection: Binding(
                    get: { appState.selectedExpression },
                    set: { appState.setSelectedExpression($0) }
                )) {
                    ForEach(ExpressionType.allCases, id: \.self) { type in
                        Text(type.rawValue).tag(type)
                    }
                }

                HStack {
                    Text("灵敏度")
                    Slider(
                        value: Binding(
                            get: { appState.expressionThreshold },
                            set: { appState.setExpressionThreshold($0) }
                        ),
                        in: 0.2...0.8
                    )
                    Text("\(Int((1 - appState.expressionThreshold) * 100))%")
                }
            }
        }
        .padding()
        .frame(width: 400, height: 400)
    }
}
