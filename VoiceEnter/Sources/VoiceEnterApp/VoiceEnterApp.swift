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

// MARK: - MenuBarView

struct MenuBarView: View {
    @EnvironmentObject var appState: AppState
    @State private var newTriggerWord: String = ""
    @State private var showingAddField: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 标题和状态
            HStack {
                Text("VoiceEnter")
                    .font(.headline)
                Spacer()
                Circle()
                    .fill(appState.isMonitoring ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
                Text(appState.isMonitoring ? "运行中" : "已停止")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Divider()

            // 开关
            Toggle("启用触发词检测", isOn: Binding(
                get: { appState.isEnabled },
                set: { _ in appState.toggleEnabled() }
            ))

            // 触发范围选择
            HStack {
                Text("触发范围:")
                    .font(.caption)
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
            }

            // 启动/停止按钮
            Button(action: { appState.toggleMonitoring() }) {
                HStack {
                    Image(systemName: appState.isMonitoring ? "stop.fill" : "play.fill")
                    Text(appState.isMonitoring ? "停止监听" : "开始监听")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(appState.isMonitoring ? .red : .green)

            Divider()

            // 触发词列表
            Text("触发词")
                .font(.subheadline)
                .foregroundColor(.secondary)

            ForEach(appState.triggerWords, id: \.self) { word in
                HStack {
                    Text(word)
                    Spacer()
                    Button(action: {
                        _ = appState.removeTriggerWord(word)
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .disabled(appState.triggerWords.count <= 1)
                }
                .padding(.vertical, 2)
            }

            // 添加触发词
            if showingAddField {
                HStack {
                    TextField("新触发词", text: $newTriggerWord)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit {
                            addTriggerWord()
                        }
                    Button("添加") {
                        addTriggerWord()
                    }
                    .disabled(newTriggerWord.isEmpty)
                }
            } else {
                Button(action: { showingAddField = true }) {
                    HStack {
                        Image(systemName: "plus")
                        Text("添加触发词")
                    }
                }
                .buttonStyle(.plain)
                .foregroundColor(.blue)
            }

            Divider()

            // 最近触发
            if !appState.lastTriggered.isEmpty {
                HStack {
                    Text("最近触发:")
                        .foregroundColor(.secondary)
                    Text(appState.lastTriggered)
                        .foregroundColor(.green)
                }
                .font(.caption)
            }

            // 权限按钮
            if !appState.checkAccessibilityPermission() {
                Button(action: { appState.requestAccessibilityPermission() }) {
                    HStack {
                        Image(systemName: "lock.shield")
                        Text("授予辅助功能权限")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }

            Divider()

            // 面部表情触发
            FaceExpressionSection()

            Divider()

            // 退出按钮
            Button(action: { NSApp.terminate(nil) }) {
                HStack {
                    Image(systemName: "power")
                    Text("退出")
                }
            }
            .buttonStyle(.plain)
            .foregroundColor(.red)
        }
        .padding()
        .frame(width: 260)
    }

    private func addTriggerWord() {
        if appState.addTriggerWord(newTriggerWord) {
            newTriggerWord = ""
            showingAddField = false
        }
    }
}

// MARK: - FaceExpressionSection

struct FaceExpressionSection: View {
    @EnvironmentObject var appState: AppState
    @State private var showingExpressionPicker = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 标题
            HStack {
                Image(systemName: "face.smiling")
                Text("表情触发")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
                if appState.isFaceExpressionEnabled {
                    Circle()
                        .fill(appState.hasFaceDetected ? Color.green : Color.orange)
                        .frame(width: 6, height: 6)
                }
            }

            // 开关
            Toggle("启用表情触发", isOn: Binding(
                get: { appState.isFaceExpressionEnabled },
                set: { _ in appState.toggleFaceExpression() }
            ))
            .toggleStyle(.switch)

            if appState.isFaceExpressionEnabled {
                // 摄像头权限
                if !appState.checkCameraPermission() {
                    Button(action: { appState.requestCameraPermission() }) {
                        HStack {
                            Image(systemName: "camera")
                            Text("授予摄像头权限")
                        }
                        .font(.caption)
                    }
                    .buttonStyle(.bordered)
                } else {
                    // 表情选择
                    HStack {
                        Text("触发表情:")
                            .font(.caption)
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
                        .frame(width: 100)
                    }

                    // 灵敏度
                    HStack {
                        Text("灵敏度:")
                            .font(.caption)
                        Slider(
                            value: Binding(
                                get: { appState.expressionThreshold },
                                set: { appState.setExpressionThreshold($0) }
                            ),
                            in: 0.2...0.8
                        )
                        Text("\(Int((1 - appState.expressionThreshold) * 100))%")
                            .font(.caption)
                            .frame(width: 35)
                    }

                    // 实时检测值
                    HStack {
                        Text("检测值:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        ProgressView(value: Double(appState.currentExpressionValue))
                            .progressViewStyle(.linear)
                        Text(appState.hasFaceDetected ? "\(Int(appState.currentExpressionValue * 100))%" : "无人脸")
                            .font(.caption)
                            .foregroundColor(appState.currentExpressionValue > appState.expressionThreshold ? .green : .secondary)
                            .frame(width: 45)
                    }
                }
            }
        }
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
