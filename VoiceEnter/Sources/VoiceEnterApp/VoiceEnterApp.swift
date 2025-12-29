import SwiftUI
import AppKit
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
        popover?.contentSize = NSSize(width: 300, height: 520)
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

    // 主题设置
    @Published var themeMode: ThemeMode = .system

    // 音效设置
    @Published var triggerSound: TriggerSound = .tink

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
        self.triggerSound = settingsManager.triggerSound
        self.inputMonitor.faceMonitor.triggerSound = settingsManager.triggerSound

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

    func hasCameraDevice() -> Bool {
        inputMonitor.faceMonitor.hasCameraDevice()
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

    // MARK: - 主题设置

    func setThemeMode(_ mode: ThemeMode) {
        themeMode = mode
    }

    // MARK: - 音效设置

    func setTriggerSound(_ sound: TriggerSound) {
        triggerSound = sound
        settingsManager.triggerSound = sound
        inputMonitor.faceMonitor.triggerSound = sound
    }

    /// 预览音效（点击选择时播放）
    func previewSound(_ sound: TriggerSound) {
        guard let soundName = sound.systemName else { return }
        NSSound(named: soundName)?.play()
    }
}

// MARK: - ThemeMode

enum ThemeMode: String, CaseIterable {
    case system = "跟随系统"
    case light = "浅色"
    case dark = "深色"
}

// MARK: - Theme Colors

struct ThemeColors {
    let background: Color
    let cardBackground: Color
    let primaryText: Color
    let secondaryText: Color
    let tertiaryText: Color
    let accent: Color
    let accentGradient: LinearGradient
    let success: Color
    let warning: Color
    let danger: Color
    let border: Color
    let inputBackground: Color
    let inputText: Color

    static func colors(for colorScheme: ColorScheme) -> ThemeColors {
        if colorScheme == .dark {
            return ThemeColors(
                background: Color(white: 0.1),
                cardBackground: Color(white: 0.15),
                primaryText: Color(white: 0.95),
                secondaryText: Color(white: 0.7),
                tertiaryText: Color(white: 0.5),
                accent: Color(red: 0.3, green: 0.7, blue: 0.9),
                accentGradient: LinearGradient(
                    colors: [Color(red: 0.2, green: 0.7, blue: 0.7), Color(red: 0.3, green: 0.5, blue: 0.9)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                success: Color(red: 0.3, green: 0.8, blue: 0.5),
                warning: Color(red: 0.95, green: 0.6, blue: 0.2),
                danger: Color(red: 0.9, green: 0.3, blue: 0.35),
                border: Color(white: 0.25),
                inputBackground: Color(white: 0.2),
                inputText: Color(white: 0.95)
            )
        } else {
            return ThemeColors(
                background: Color(white: 0.96),
                cardBackground: Color.white,
                primaryText: Color(white: 0.1),
                secondaryText: Color(white: 0.4),
                tertiaryText: Color(white: 0.6),
                accent: Color(red: 0.2, green: 0.5, blue: 0.8),
                accentGradient: LinearGradient(
                    colors: [Color(red: 0.2, green: 0.6, blue: 0.7), Color(red: 0.3, green: 0.4, blue: 0.8)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                success: Color(red: 0.2, green: 0.7, blue: 0.4),
                warning: Color(red: 0.9, green: 0.5, blue: 0.1),
                danger: Color(red: 0.85, green: 0.25, blue: 0.3),
                border: Color(white: 0.85),
                inputBackground: Color(white: 0.95),
                inputText: Color(white: 0.1)
            )
        }
    }
}

// MARK: - MenuBarView

struct MenuBarView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.colorScheme) var systemColorScheme
    @State private var newTriggerWord: String = ""
    @State private var showingAddField: Bool = false

    private var effectiveColorScheme: ColorScheme {
        switch appState.themeMode {
        case .system: return systemColorScheme
        case .light: return .light
        case .dark: return .dark
        }
    }

    private var theme: ThemeColors {
        ThemeColors.colors(for: effectiveColorScheme)
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 16) {
                // 头部：标题和状态
                headerSection

                // 关键词触发区域
                keywordTriggerCard

                // 表情触发区域
                expressionTriggerCard

                // 底部：控制和退出
                footerSection
            }
            .padding(16)
        }
        .frame(width: 300, height: 520)
        .background(theme.background)
        .preferredColorScheme(effectiveColorScheme)
    }

    // MARK: - Header Section

    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("VoiceEnter")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(theme.primaryText)
                Text("语音触发助手")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(theme.tertiaryText)
            }
            Spacer()

            // 状态指示
            HStack(spacing: 6) {
                Circle()
                    .fill(appState.isMonitoring ? theme.success : theme.danger)
                    .frame(width: 8, height: 8)
                    .shadow(color: appState.isMonitoring ? theme.success.opacity(0.5) : .clear, radius: 3)
                Text(appState.isMonitoring ? "监听中" : "已停止")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(theme.secondaryText)
            }
        }
    }

    // MARK: - Keyword Trigger Card

    private var keywordTriggerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 标题
            HStack(spacing: 8) {
                Image(systemName: "text.bubble.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.accentGradient)
                Text("关键词触发")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(theme.tertiaryText)
                    .textCase(.uppercase)
                Spacer()
            }

            // 启用开关
            Toggle(isOn: Binding(
                get: { appState.isEnabled },
                set: { _ in appState.toggleEnabled() }
            )) {
                Text("启用关键词触发")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(theme.primaryText)
            }
            .toggleStyle(.switch)
            .tint(theme.success)

            // 触发范围
            VStack(alignment: .leading, spacing: 6) {
                Text("触发范围")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(theme.secondaryText)
                Picker("", selection: Binding(
                    get: { appState.triggerScope },
                    set: { appState.setTriggerScope($0) }
                )) {
                    ForEach(TriggerScope.allCases, id: \.self) { scope in
                        Text(scope.displayName).tag(scope)
                    }
                }
                .pickerStyle(.segmented)
            }

            // 触发词列表
            VStack(alignment: .leading, spacing: 8) {
                Text("触发词")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(theme.secondaryText)

                FlowLayout(spacing: 8) {
                    ForEach(appState.triggerWords, id: \.self) { word in
                        TriggerWordTag(
                            word: word,
                            theme: theme,
                            onRemove: { _ = appState.removeTriggerWord(word) },
                            canRemove: appState.triggerWords.count > 1
                        )
                    }
                }
            }

            // 添加触发词
            if showingAddField {
                HStack(spacing: 8) {
                    TextField("输入触发词", text: $newTriggerWord)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .foregroundColor(theme.inputText)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(theme.inputBackground)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .strokeBorder(theme.accent.opacity(0.5), lineWidth: 1)
                                )
                        )
                        .onSubmit { addTriggerWord() }

                    Button(action: { addTriggerWord() }) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(theme.success)
                    }
                    .buttonStyle(.plain)
                    .disabled(newTriggerWord.isEmpty)
                    .opacity(newTriggerWord.isEmpty ? 0.4 : 1)

                    Button(action: {
                        showingAddField = false
                        newTriggerWord = ""
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(theme.tertiaryText)
                    }
                    .buttonStyle(.plain)
                }
            } else {
                Button(action: { showingAddField = true }) {
                    HStack(spacing: 6) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 14))
                        Text("添加触发词")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(theme.accent)
                }
                .buttonStyle(.plain)
            }

            // 最近触发
            if !appState.lastTriggered.isEmpty {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(theme.success)
                    Text("最近触发:")
                        .font(.system(size: 11))
                        .foregroundColor(theme.tertiaryText)
                    Text(appState.lastTriggered)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundColor(theme.success)
                    Spacer()
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(theme.cardBackground)
                .shadow(color: Color.black.opacity(effectiveColorScheme == .dark ? 0.3 : 0.1), radius: 4, x: 0, y: 2)
        )
    }

    // MARK: - Expression Trigger Card

    private var expressionTriggerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 标题
            HStack(spacing: 8) {
                Image(systemName: "face.smiling.inverse")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.accentGradient)
                Text("表情触发")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(theme.tertiaryText)
                    .textCase(.uppercase)
                Spacer()
                if appState.isFaceExpressionEnabled {
                    Circle()
                        .fill(appState.hasFaceDetected ? theme.success : theme.warning)
                        .frame(width: 6, height: 6)
                }
            }

            // 启用开关
            Toggle(isOn: Binding(
                get: { appState.isFaceExpressionEnabled },
                set: { _ in appState.toggleFaceExpression() }
            )) {
                Text("启用表情触发")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(theme.primaryText)
            }
            .toggleStyle(.switch)
            .tint(theme.success)

            if appState.isFaceExpressionEnabled {
                if !appState.hasCameraDevice() {
                    // 无摄像头提示
                    VStack(spacing: 6) {
                        HStack(spacing: 6) {
                            Image(systemName: "video.slash.fill")
                                .foregroundColor(theme.danger)
                            Text("未检测到摄像头")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(theme.danger)
                        }
                        Text("可通过 USB 连接 iPhone 使用「连续互通相机」")
                            .font(.system(size: 10))
                            .foregroundColor(theme.tertiaryText)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(theme.danger.opacity(0.15))
                    )
                } else if !appState.checkCameraPermission() {
                    // 摄像头权限提示
                    Button(action: { appState.requestCameraPermission() }) {
                        HStack(spacing: 6) {
                            Image(systemName: "camera.fill")
                                .foregroundColor(theme.warning)
                            Text("需要摄像头权限")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(theme.warning)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(theme.warning.opacity(0.15))
                        )
                    }
                    .buttonStyle(.plain)
                } else {
                    VStack(spacing: 10) {
                        // 表情选择
                        HStack {
                            Text("触发表情")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(theme.secondaryText)
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
                            .tint(theme.accent)
                        }

                        // 灵敏度调节
                        VStack(spacing: 4) {
                            HStack {
                                Text("灵敏度")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(theme.secondaryText)
                                Spacer()
                                Text("\(Int((1 - appState.expressionThreshold) * 100))%")
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .foregroundColor(theme.accent)
                            }
                            Slider(
                                value: Binding(
                                    get: { appState.expressionThreshold },
                                    set: { appState.setExpressionThreshold($0) }
                                ),
                                in: 0.2...0.8
                            )
                            .tint(theme.accent)
                        }

                        // 检测值
                        VStack(spacing: 4) {
                            HStack {
                                Text("检测值")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(theme.secondaryText)
                                Spacer()
                                Text(appState.hasFaceDetected ? "\(Int(appState.currentExpressionValue * 100))%" : "无人脸")
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .foregroundColor(appState.currentExpressionValue > appState.expressionThreshold ? theme.success : theme.tertiaryText)
                            }
                            GeometryReader { geometry in
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(theme.border)
                                        .frame(height: 6)

                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(
                                            appState.currentExpressionValue > appState.expressionThreshold ?
                                            theme.accentGradient :
                                            LinearGradient(colors: [theme.tertiaryText], startPoint: .leading, endPoint: .trailing)
                                        )
                                        .frame(width: geometry.size.width * CGFloat(appState.currentExpressionValue), height: 6)

                                    Rectangle()
                                        .fill(theme.warning)
                                        .frame(width: 2, height: 10)
                                        .offset(x: geometry.size.width * CGFloat(appState.expressionThreshold) - 1)
                                }
                            }
                            .frame(height: 10)
                        }

                        // 触发音效选择
                        HStack {
                            Text("触发音效")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(theme.secondaryText)
                            Spacer()
                            Picker("", selection: Binding(
                                get: { appState.triggerSound },
                                set: { sound in
                                    appState.setTriggerSound(sound)
                                    appState.previewSound(sound)
                                }
                            )) {
                                ForEach(TriggerSound.allCases, id: \.self) { sound in
                                    Text(sound.displayName).tag(sound)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(width: 90)
                            .tint(theme.accent)
                        }

                        // 使用提示
                        HStack(spacing: 6) {
                            Image(systemName: "lightbulb.fill")
                                .font(.system(size: 10))
                                .foregroundColor(theme.warning)
                            Text(expressionUsageTip)
                                .font(.system(size: 10))
                                .foregroundColor(theme.tertiaryText)
                        }
                        .padding(.top, 4)
                    }
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(theme.cardBackground)
                .shadow(color: Color.black.opacity(effectiveColorScheme == .dark ? 0.3 : 0.1), radius: 4, x: 0, y: 2)
        )
    }

    /// 表情触发使用提示
    private var expressionUsageTip: String {
        if !appState.hasFaceDetected {
            return "请面向摄像头，确保人脸被检测到"
        } else if appState.currentExpressionValue < appState.expressionThreshold {
            let expressionName = appState.selectedExpression.rawValue
            return "做出「\(expressionName)」表情，检测值超过阈值线即触发回车"
        } else {
            return "表情已触发！检测值超过阈值时自动发送回车"
        }
    }

    // MARK: - Footer Section

    private var footerSection: some View {
        VStack(spacing: 12) {
            // 辅助功能权限提示
            if !appState.checkAccessibilityPermission() {
                Button(action: { appState.requestAccessibilityPermission() }) {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.shield.fill")
                            .foregroundColor(theme.warning)
                        Text("需要辅助功能权限")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(theme.warning)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(theme.warning.opacity(0.15))
                    )
                }
                .buttonStyle(.plain)
            }

            // 主题选择
            HStack {
                Text("外观")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(theme.secondaryText)
                Spacer()
                Picker("", selection: Binding(
                    get: { appState.themeMode },
                    set: { appState.setThemeMode($0) }
                )) {
                    ForEach(ThemeMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 180)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(theme.cardBackground)
            )

            // 停止监听和退出按钮
            HStack(spacing: 12) {
                // 停止/开始监听按钮
                Button(action: { appState.toggleMonitoring() }) {
                    HStack(spacing: 6) {
                        Image(systemName: appState.isMonitoring ? "stop.fill" : "play.fill")
                            .font(.system(size: 11, weight: .semibold))
                        Text(appState.isMonitoring ? "停止监听" : "开始监听")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(appState.isMonitoring ?
                                  LinearGradient(colors: [theme.danger, theme.danger.opacity(0.8)], startPoint: .top, endPoint: .bottom) :
                                  theme.accentGradient)
                    )
                }
                .buttonStyle(.plain)

                // 退出按钮
                Button(action: { NSApp.terminate(nil) }) {
                    HStack(spacing: 6) {
                        Image(systemName: "power")
                            .font(.system(size: 11, weight: .semibold))
                        Text("退出")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundColor(theme.primaryText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(theme.border)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func addTriggerWord() {
        if appState.addTriggerWord(newTriggerWord) {
            newTriggerWord = ""
            showingAddField = false
        }
    }
}

// MARK: - Trigger Word Tag

struct TriggerWordTag: View {
    let word: String
    let theme: ThemeColors
    let onRemove: () -> Void
    let canRemove: Bool

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 6) {
            Text(word)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundColor(theme.primaryText)

            if canRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(isHovering ? theme.danger : theme.tertiaryText)
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
                .fill(theme.inputBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(theme.border, lineWidth: 1)
                )
        )
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

// MARK: - SettingsView

struct SettingsView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Form {
            Section("关键词触发") {
                Toggle("启用关键词触发", isOn: Binding(
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

            Section("触发词列表") {
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

            Section("外观") {
                Picker("主题", selection: Binding(
                    get: { appState.themeMode },
                    set: { appState.setThemeMode($0) }
                )) {
                    ForEach(ThemeMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
            }
        }
        .padding()
        .frame(width: 400, height: 450)
    }
}
