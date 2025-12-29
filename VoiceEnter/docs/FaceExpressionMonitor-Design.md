# FaceExpressionMonitor 技术方案

## 概述

通过 Mac 摄像头实时检测用户面部表情，当检测到预设表情（如吐舌头）时触发回车操作。作为触发词方案的补充，适用于安静环境或不方便说话的场景。

## 技术选型

### 方案对比

| 方案 | 框架 | 优点 | 缺点 | 推荐度 |
|------|------|------|------|--------|
| **Vision + AVFoundation** | Apple 原生 | 无依赖、省电、隐私好、稳定 | 无直接 BlendShape | ⭐⭐⭐ |
| **ARKit** | Apple ARKit | 52种 BlendShape、精度高 | 仅 iOS/iPadOS，Mac 不支持 | ❌ |
| **MediaPipe Face Mesh** | Google | 478 个面部关键点、跨平台 | 需要集成 C++/Python | ⭐⭐ |
| **CreateML + Core ML** | Apple | 可自定义训练 | 需要收集数据、训练模型 | ⭐⭐ |

### 推荐方案：Vision + AVFoundation

**原因：**
1. macOS 原生支持，无额外依赖
2. `VNDetectFaceLandmarksRequest` 可检测 76 个面部关键点
3. 通过关键点位置变化计算表情（如舌头伸出时嘴巴张开 + 下巴区域变化）
4. 低功耗，使用 Neural Engine 加速

## 可检测的表情

通过面部关键点位置关系，可以计算以下表情：

| 表情 | 检测方法 | 关键点 |
|------|----------|--------|
| **吐舌头** | 嘴巴张开 + 下唇下方区域变化 | innerLips + outerLips |
| **张嘴** | 上下唇距离 > 阈值 | innerLips top/bottom |
| **眨眼（左/右）** | 眼睛高度 < 阈值 | leftEye / rightEye |
| **挑眉** | 眉毛位置上移 | leftEyebrow / rightEyebrow |
| **嘟嘴** | 嘴巴宽度缩小 | outerLips left/right |
| **微笑** | 嘴角上扬 | outerLips 角度变化 |
| **皱鼻** | 鼻子区域变化 | nose 关键点 |

## 架构设计

```
┌─────────────────────────────────────────────────────────────┐
│                    UniversalInputMonitor                     │
├─────────────────────────────────────────────────────────────┤
│  TextMonitor          │ Accessibility API                   │
│  KittyTerminalMonitor │ kitty @ get-text                    │
│  TerminalAppMonitor   │ AppleScript                         │
│  FaceExpressionMonitor│ Vision + AVFoundation  ← 新增       │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│                   FaceExpressionMonitor                      │
├─────────────────────────────────────────────────────────────┤
│  CameraManager        │ 摄像头采集 (AVCaptureSession)        │
│  FaceDetector         │ 面部检测 (VNDetectFaceLandmarks)     │
│  ExpressionAnalyzer   │ 表情分析（关键点 → 表情系数）          │
│  TriggerMatcher       │ 触发匹配（表情系数 → 触发判定）        │
└─────────────────────────────────────────────────────────────┘
```

## 核心类设计

### 1. FaceExpressionMonitor

主监听器，集成到 UniversalInputMonitor。

```swift
public class FaceExpressionMonitor {
    private let cameraManager: CameraManager
    private let faceDetector: FaceDetector
    private let expressionAnalyzer: ExpressionAnalyzer
    private let settingsManager: SettingsManager

    /// 触发回调
    public var onTrigger: ((String) -> Void)?

    /// 表情变化回调（用于 UI 显示）
    public var onExpressionChange: ((ExpressionState) -> Void)?

    /// 是否正在监听
    public private(set) var isMonitoring: Bool = false

    /// 开始监听
    public func startMonitoring() -> Bool

    /// 停止监听
    public func stopMonitoring()

    /// 检查摄像头权限
    public func checkCameraPermission() -> Bool

    /// 请求摄像头权限
    public func requestCameraPermission()
}
```

### 2. ExpressionType 表情类型

```swift
public enum ExpressionType: String, CaseIterable, Codable {
    case tongueOut = "吐舌头"
    case mouthOpen = "张嘴"
    case leftEyeBlink = "左眼眨眼"
    case rightEyeBlink = "右眼眨眼"
    case bothEyesBlink = "双眼眨眼"
    case eyebrowRaise = "挑眉"
    case mouthPucker = "嘟嘴"
    case smile = "微笑"
    case noseWrinkle = "皱鼻"

    /// 默认阈值
    var defaultThreshold: Float {
        switch self {
        case .tongueOut: return 0.6
        case .mouthOpen: return 0.5
        case .leftEyeBlink, .rightEyeBlink, .bothEyesBlink: return 0.3
        case .eyebrowRaise: return 0.4
        case .mouthPucker: return 0.5
        case .smile: return 0.5
        case .noseWrinkle: return 0.4
        }
    }
}
```

### 3. ExpressionState 表情状态

```swift
public struct ExpressionState {
    /// 各表情的系数 (0.0 ~ 1.0)
    public var coefficients: [ExpressionType: Float]

    /// 检测到的人脸数量
    public var faceCount: Int

    /// 是否检测到人脸
    public var hasFace: Bool { faceCount > 0 }

    /// 检查某表情是否超过阈值
    public func isTriggered(_ type: ExpressionType, threshold: Float? = nil) -> Bool {
        let t = threshold ?? type.defaultThreshold
        return (coefficients[type] ?? 0) > t
    }
}
```

### 4. ExpressionTrigger 触发配置

```swift
public struct ExpressionTrigger: Codable {
    /// 触发 ID
    public let id: UUID

    /// 表情类型
    public var expressionType: ExpressionType

    /// 触发阈值 (0.0 ~ 1.0)
    public var threshold: Float

    /// 持续时间要求（秒），防止误触
    public var minDuration: TimeInterval

    /// 冷却时间（秒），防止连续触发
    public var cooldown: TimeInterval

    /// 是否启用
    public var isEnabled: Bool
}
```

### 5. ExpressionAnalyzer 表情分析器

```swift
public class ExpressionAnalyzer {
    /// 从面部关键点计算表情系数
    public func analyze(landmarks: VNFaceLandmarks2D) -> ExpressionState {
        var coefficients: [ExpressionType: Float] = [:]

        // 计算张嘴程度
        coefficients[.mouthOpen] = calculateMouthOpen(landmarks)

        // 计算吐舌头（张嘴 + 下唇下方区域）
        coefficients[.tongueOut] = calculateTongueOut(landmarks)

        // 计算眨眼
        coefficients[.leftEyeBlink] = calculateEyeBlink(landmarks.leftEye)
        coefficients[.rightEyeBlink] = calculateEyeBlink(landmarks.rightEye)
        coefficients[.bothEyesBlink] = min(
            coefficients[.leftEyeBlink] ?? 0,
            coefficients[.rightEyeBlink] ?? 0
        )

        // 计算挑眉
        coefficients[.eyebrowRaise] = calculateEyebrowRaise(landmarks)

        // 计算嘟嘴
        coefficients[.mouthPucker] = calculateMouthPucker(landmarks)

        // 计算微笑
        coefficients[.smile] = calculateSmile(landmarks)

        return ExpressionState(coefficients: coefficients, faceCount: 1)
    }

    // MARK: - 计算方法

    private func calculateMouthOpen(_ landmarks: VNFaceLandmarks2D) -> Float {
        guard let innerLips = landmarks.innerLips else { return 0 }
        let points = innerLips.normalizedPoints
        // 计算上下唇的垂直距离
        // ...
    }

    private func calculateTongueOut(_ landmarks: VNFaceLandmarks2D) -> Float {
        // 吐舌头检测比较复杂，需要：
        // 1. 嘴巴张开
        // 2. 下巴区域有额外突出（舌头）
        // 可能需要结合多帧检测
    }

    // ... 其他计算方法
}
```

## 吐舌头检测的特殊处理

Vision 框架没有直接的舌头检测，需要通过间接方式：

### 方案 A：基于关键点变化

```swift
/// 吐舌头检测
/// 原理：嘴巴张开时，如果舌头伸出，下唇下方的轮廓会有额外突出
private func calculateTongueOut(_ landmarks: VNFaceLandmarks2D) -> Float {
    guard let innerLips = landmarks.innerLips,
          let outerLips = landmarks.outerLips else { return 0 }

    // 1. 检查嘴巴是否张开
    let mouthOpen = calculateMouthOpen(landmarks)
    guard mouthOpen > 0.3 else { return 0 }

    // 2. 检查下唇相对位置
    // 吐舌头时，下唇会被舌头推出，位置会比正常张嘴时更低
    let outerPoints = outerLips.normalizedPoints
    let innerPoints = innerLips.normalizedPoints

    // 计算下唇的突出程度
    // ...

    return tongueScore
}
```

### 方案 B：结合机器学习

如果关键点方案精度不够，可以训练一个简单的 Core ML 模型：

1. 收集吐舌头/不吐舌头的面部图片
2. 使用 CreateML 训练分类模型
3. 输入：面部区域图片
4. 输出：吐舌头概率

## 防误触机制

```swift
public class TriggerMatcher {
    private var expressionStartTime: [ExpressionType: Date] = [:]
    private var lastTriggerTime: [ExpressionType: Date] = [:]

    /// 检查是否应该触发
    func shouldTrigger(
        expression: ExpressionType,
        coefficient: Float,
        trigger: ExpressionTrigger
    ) -> Bool {
        let now = Date()

        // 1. 检查是否超过阈值
        guard coefficient > trigger.threshold else {
            expressionStartTime[expression] = nil
            return false
        }

        // 2. 检查持续时间
        if expressionStartTime[expression] == nil {
            expressionStartTime[expression] = now
        }
        let duration = now.timeIntervalSince(expressionStartTime[expression]!)
        guard duration >= trigger.minDuration else {
            return false
        }

        // 3. 检查冷却时间
        if let lastTrigger = lastTriggerTime[expression] {
            let elapsed = now.timeIntervalSince(lastTrigger)
            guard elapsed >= trigger.cooldown else {
                return false
            }
        }

        // 触发！
        lastTriggerTime[expression] = now
        expressionStartTime[expression] = nil
        return true
    }
}
```

## 摄像头管理

```swift
public class CameraManager: NSObject {
    private var captureSession: AVCaptureSession?
    private var videoOutput: AVCaptureVideoDataOutput?

    weak var delegate: CameraManagerDelegate?

    func startCapture() -> Bool {
        let session = AVCaptureSession()
        session.sessionPreset = .medium  // 不需要高清，省电

        // 获取前置摄像头
        guard let camera = AVCaptureDevice.default(
            .builtInWideAngleCamera,
            for: .video,
            position: .front
        ) else { return false }

        // 配置输入
        guard let input = try? AVCaptureDeviceInput(device: camera) else { return false }
        session.addInput(input)

        // 配置输出
        let output = AVCaptureVideoDataOutput()
        output.setSampleBufferDelegate(self, queue: DispatchQueue(label: "face.detection"))
        output.alwaysDiscardsLateVideoFrames = true
        session.addOutput(output)

        // 降低帧率，省电
        camera.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 15) // 15fps

        captureSession = session
        videoOutput = output

        session.startRunning()
        return true
    }

    func stopCapture() {
        captureSession?.stopRunning()
        captureSession = nil
    }
}

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        delegate?.cameraManager(self, didCapture: pixelBuffer)
    }
}
```

## 面部检测

```swift
public class FaceDetector {
    private let sequenceHandler = VNSequenceRequestHandler()

    func detectFace(in pixelBuffer: CVPixelBuffer) -> VNFaceLandmarks2D? {
        let request = VNDetectFaceLandmarksRequest()
        request.revision = VNDetectFaceLandmarksRequestRevision3

        try? sequenceHandler.perform([request], on: pixelBuffer)

        guard let observation = request.results?.first else { return nil }
        return observation.landmarks
    }
}
```

## 设置界面

```swift
struct ExpressionSettingsView: View {
    @ObservedObject var settings: ExpressionSettings
    @State private var showingCalibration = false

    var body: some View {
        Form {
            Section("表情触发") {
                Toggle("启用表情触发", isOn: $settings.isEnabled)

                Picker("触发表情", selection: $settings.selectedExpression) {
                    ForEach(ExpressionType.allCases, id: \.self) { type in
                        Text(type.rawValue).tag(type)
                    }
                }

                HStack {
                    Text("灵敏度")
                    Slider(value: $settings.threshold, in: 0.3...0.9)
                    Text("\(Int(settings.threshold * 100))%")
                }

                HStack {
                    Text("持续时间")
                    Slider(value: $settings.minDuration, in: 0.1...1.0)
                    Text("\(String(format: "%.1f", settings.minDuration))秒")
                }

                HStack {
                    Text("冷却时间")
                    Slider(value: $settings.cooldown, in: 0.5...3.0)
                    Text("\(String(format: "%.1f", settings.cooldown))秒")
                }
            }

            Section("校准") {
                Button("校准表情") {
                    showingCalibration = true
                }

                Button("测试表情检测") {
                    // 打开实时预览窗口
                }
            }

            Section("状态") {
                HStack {
                    Text("摄像头")
                    Spacer()
                    Circle()
                        .fill(settings.cameraActive ? Color.green : Color.red)
                        .frame(width: 8, height: 8)
                    Text(settings.cameraActive ? "运行中" : "未启动")
                }

                HStack {
                    Text("人脸检测")
                    Spacer()
                    Text(settings.faceDetected ? "已检测到" : "未检测到")
                }
            }
        }
        .sheet(isPresented: $showingCalibration) {
            CalibrationView(settings: settings)
        }
    }
}
```

## 校准流程

```swift
struct CalibrationView: View {
    @ObservedObject var settings: ExpressionSettings
    @State private var step: CalibrationStep = .neutral
    @State private var samples: [ExpressionState] = []

    enum CalibrationStep {
        case neutral      // 采集正常表情
        case expression   // 采集目标表情
        case done
    }

    var body: some View {
        VStack(spacing: 20) {
            // 摄像头预览
            CameraPreviewView()
                .frame(width: 300, height: 225)
                .cornerRadius(12)

            switch step {
            case .neutral:
                Text("请保持正常表情")
                    .font(.headline)
                Text("我们需要采集您的正常表情作为基准")
                    .foregroundColor(.secondary)

                Button("开始采集") {
                    collectSamples(for: .neutral)
                }

            case .expression:
                Text("请做出 \(settings.selectedExpression.rawValue) 表情")
                    .font(.headline)
                Text("保持表情 3 秒钟")
                    .foregroundColor(.secondary)

                Button("开始采集") {
                    collectSamples(for: .expression)
                }

            case .done:
                Text("校准完成！")
                    .font(.headline)
                Text("系统已记录您的表情特征")
                    .foregroundColor(.secondary)

                Button("完成") {
                    // 保存校准数据
                }
            }
        }
        .padding()
    }
}
```

## 隐私与功耗考虑

### 隐私

1. **本地处理**：所有面部检测在本地完成，不上传任何数据
2. **不存储图像**：只处理实时帧，不保存任何面部图像
3. **可随时关闭**：用户可以随时禁用摄像头功能
4. **权限提示**：首次使用时明确告知用途

### 功耗优化

1. **低帧率**：15fps 足够检测表情，比默认 30fps 省电
2. **低分辨率**：使用 `.medium` 预设
3. **按需启动**：只在需要时启动摄像头
4. **智能暂停**：屏幕锁定或应用切到后台时自动停止

## 实现计划

### Phase 1: MVP（1-2天）

- [ ] 基础摄像头采集
- [ ] 面部关键点检测
- [ ] 张嘴表情检测（最简单）
- [ ] 集成到 UniversalInputMonitor

### Phase 2: 表情扩展（1天）

- [ ] 眨眼检测
- [ ] 挑眉检测
- [ ] 嘟嘴检测

### Phase 3: 吐舌头检测（1-2天）

- [ ] 基于关键点的吐舌头检测
- [ ] 如果精度不够，训练 Core ML 模型

### Phase 4: 用户界面（1天）

- [ ] 表情触发设置界面
- [ ] 校准流程
- [ ] 实时预览窗口

### Phase 5: 优化（持续）

- [ ] 功耗优化
- [ ] 精度调优
- [ ] 用户反馈迭代

## 风险与备选方案

| 风险 | 影响 | 备选方案 |
|------|------|----------|
| Vision 无法准确检测吐舌头 | 核心功能受限 | 训练 Core ML 模型 |
| 摄像头功耗过高 | 用户体验差 | 降帧率、按需启动 |
| 误触率高 | 用户体验差 | 增加持续时间、组合表情 |
| 光线不足检测失败 | 功能不可用 | 提示用户改善光线 |

## 总结

使用 Apple Vision 框架实现面部表情触发是可行的。MVP 阶段先实现张嘴触发，验证整体流程，然后逐步扩展到其他表情。吐舌头检测可能需要额外的机器学习模型支持。
