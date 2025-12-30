import Foundation
import AVFoundation
import Vision
import AppKit

// MARK: - ExpressionType

/// 支持的表情类型
public enum ExpressionType: String, CaseIterable, Codable {
    case mouthOpen = "张嘴"
    case pout = "撅嘴"
    case leftEyeBlink = "左眼眨眼"
    case rightEyeBlink = "右眼眨眼"
    case bothEyesBlink = "双眼眨眼"
    case eyebrowRaise = "挑眉"
    case smile = "微笑"

    /// 默认阈值
    public var defaultThreshold: Float {
        switch self {
        case .mouthOpen: return 0.15  // 85% 灵敏度
        case .pout: return 0.15       // 85% 灵敏度
        case .leftEyeBlink, .rightEyeBlink, .bothEyesBlink: return 0.6
        case .eyebrowRaise: return 0.3
        case .smile: return 0.4
        }
    }

    /// 默认持续时间（秒）
    public var defaultMinDuration: TimeInterval {
        switch self {
        case .mouthOpen: return 0.3
        case .pout: return 0.3
        case .leftEyeBlink, .rightEyeBlink, .bothEyesBlink: return 0.15
        case .eyebrowRaise: return 0.3
        case .smile: return 0.5
        }
    }
}

// MARK: - ExpressionState

/// 表情状态
public struct ExpressionState {
    /// 各表情的系数 (0.0 ~ 1.0)
    public var coefficients: [ExpressionType: Float]

    /// 是否检测到人脸
    public var hasFace: Bool

    public init(coefficients: [ExpressionType: Float] = [:], hasFace: Bool = false) {
        self.coefficients = coefficients
        self.hasFace = hasFace
    }

    /// 检查某表情是否超过阈值
    public func isTriggered(_ type: ExpressionType, threshold: Float? = nil) -> Bool {
        let t = threshold ?? type.defaultThreshold
        return (coefficients[type] ?? 0) > t
    }
}

// MARK: - FaceExpressionMonitor

/// 面部表情监听器 - 通过摄像头检测面部表情触发回车
public class FaceExpressionMonitor: NSObject {
    private var captureSession: AVCaptureSession?
    private var videoOutput: AVCaptureVideoDataOutput?
    private let videoQueue = DispatchQueue(label: "face.expression.video", qos: .userInteractive)

    private let sequenceHandler = VNSequenceRequestHandler()
    private let settingsManager: SettingsManager
    private let keySimulator: KeySimulator

    /// 当前启用的触发表情
    public var triggerExpression: ExpressionType = .mouthOpen

    /// 触发阈值
    public var threshold: Float = 0.4

    /// 最小持续时间（秒）
    public var minDuration: TimeInterval = 0.3

    /// 冷却时间（秒）
    public var cooldown: TimeInterval = 1.0

    /// 是否启用
    public var isExpressionTriggerEnabled: Bool = false

    private var expressionStartTime: Date?
    private var lastTriggerTime: Date?
    private var lastExpressionState = ExpressionState()

    /// 触发回调
    public var onTrigger: ((String) -> Void)?

    /// 表情状态变化回调（用于 UI 显示）
    public var onExpressionChange: ((ExpressionState) -> Void)?

    /// 状态变化回调
    public var onStatusChange: ((Bool) -> Void)?

    /// 是否正在监听
    public private(set) var isMonitoring: Bool = false

    public override init() {
        self.settingsManager = SettingsManager()
        self.keySimulator = KeySimulator(eventPoster: CGEventPoster())
        super.init()
    }

    // MARK: - Public Methods

    /// 开始监听
    public func startMonitoring() -> Bool {
        guard !isMonitoring else { return true }

        // 检查摄像头权限
        guard checkCameraPermission() else {
            voiceLog("[FaceMonitor] 需要摄像头权限")
            return false
        }

        // 启动摄像头
        guard startCamera() else {
            voiceLog("[FaceMonitor] 无法启动摄像头")
            return false
        }

        isMonitoring = true
        onStatusChange?(true)

        voiceLog("[FaceMonitor] 开始监听面部表情，触发表情: \(triggerExpression.rawValue)，阈值: \(threshold)")
        return true
    }

    /// 停止监听
    public func stopMonitoring() {
        guard isMonitoring else { return }

        captureSession?.stopRunning()
        captureSession = nil
        videoOutput = nil

        isMonitoring = false
        onStatusChange?(false)

        voiceLog("[FaceMonitor] 停止监听")
    }

    /// 检查摄像头权限
    public func checkCameraPermission() -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        return status == .authorized
    }

    /// 检查是否有摄像头设备
    public func hasCameraDevice() -> Bool {
        // 检查前置摄像头
        if AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) != nil {
            return true
        }
        // 检查任意摄像头
        if AVCaptureDevice.default(for: .video) != nil {
            return true
        }
        return false
    }

    /// 请求摄像头权限
    public func requestCameraPermission(completion: @escaping (Bool) -> Void) {
        AVCaptureDevice.requestAccess(for: .video) { granted in
            DispatchQueue.main.async {
                completion(granted)
            }
        }
    }

    // MARK: - Private Methods

    private func startCamera() -> Bool {
        let session = AVCaptureSession()
        session.sessionPreset = .medium  // 低分辨率省电

        // 获取前置摄像头
        guard let camera = AVCaptureDevice.default(
            .builtInWideAngleCamera,
            for: .video,
            position: .front
        ) else {
            // 如果没有前置，尝试默认摄像头
            guard let defaultCamera = AVCaptureDevice.default(for: .video) else {
                voiceLog("[FaceMonitor] 找不到摄像头")
                return false
            }
            return setupCamera(defaultCamera, session: session)
        }

        return setupCamera(camera, session: session)
    }

    private func setupCamera(_ camera: AVCaptureDevice, session: AVCaptureSession) -> Bool {
        do {
            let input = try AVCaptureDeviceInput(device: camera)
            session.addInput(input)

            // 降低帧率省电
            try camera.lockForConfiguration()
            camera.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 15)  // 15fps
            camera.unlockForConfiguration()
        } catch {
            voiceLog("[FaceMonitor] 配置摄像头失败: \(error)")
            return false
        }

        // 配置视频输出
        let output = AVCaptureVideoDataOutput()
        output.setSampleBufferDelegate(self, queue: videoQueue)
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        session.addOutput(output)

        captureSession = session
        videoOutput = output

        // 在后台启动
        videoQueue.async {
            session.startRunning()
        }

        return true
    }

    private func processFrame(_ pixelBuffer: CVPixelBuffer) {
        // 如果没有启用表情触发，跳过处理
        guard isExpressionTriggerEnabled else { return }

        let request = VNDetectFaceLandmarksRequest()

        do {
            try sequenceHandler.perform([request], on: pixelBuffer, orientation: .up)
        } catch {
            return
        }

        guard let observation = request.results?.first,
              let landmarks = observation.landmarks else {
            // 没有检测到人脸
            DispatchQueue.main.async { [weak self] in
                let state = ExpressionState(hasFace: false)
                self?.lastExpressionState = state
                self?.onExpressionChange?(state)
                self?.expressionStartTime = nil
            }
            return
        }

        // 检查人脸是否正对摄像头（过滤侧脸）
        // 通过人脸框宽高比来判断：正脸时宽高比接近 1:1.2~1.5
        // 侧脸时宽度会明显变窄
        let faceBounds = observation.boundingBox
        let faceAspectRatio = faceBounds.width / faceBounds.height

        // 如果人脸宽高比小于 0.5，说明是侧脸，跳过检测
        // 正常正脸的宽高比约为 0.7~1.0
        if faceAspectRatio < 0.5 {
            DispatchQueue.main.async { [weak self] in
                let state = ExpressionState(hasFace: true)  // 有人脸但是侧脸
                self?.lastExpressionState = state
                self?.onExpressionChange?(state)
                self?.expressionStartTime = nil  // 重置计时
            }
            return
        }

        // 分析表情，传入人脸框用于归一化
        let state = analyzeExpression(landmarks: landmarks, faceBounds: faceBounds)

        DispatchQueue.main.async { [weak self] in
            self?.handleExpressionState(state)
        }
    }

    private func analyzeExpression(landmarks: VNFaceLandmarks2D, faceBounds: CGRect) -> ExpressionState {
        var coefficients: [ExpressionType: Float] = [:]

        // 计算张嘴程度（使用人脸框进行归一化）
        coefficients[.mouthOpen] = calculateMouthOpen(landmarks, faceBounds: faceBounds)

        // 计算撅嘴程度
        coefficients[.pout] = calculatePout(landmarks, faceBounds: faceBounds)

        // 计算眨眼
        coefficients[.leftEyeBlink] = calculateEyeBlink(landmarks.leftEye)
        coefficients[.rightEyeBlink] = calculateEyeBlink(landmarks.rightEye)
        coefficients[.bothEyesBlink] = min(
            coefficients[.leftEyeBlink] ?? 0,
            coefficients[.rightEyeBlink] ?? 0
        )

        // 计算挑眉
        coefficients[.eyebrowRaise] = calculateEyebrowRaise(landmarks)

        // 计算微笑
        coefficients[.smile] = calculateSmile(landmarks)

        return ExpressionState(coefficients: coefficients, hasFace: true)
    }

    /// 计算张嘴程度 (0.0 ~ 1.0)
    /// 使用人脸高度作为参考进行归一化，避免侧脸时嘴宽度变窄导致误判
    private func calculateMouthOpen(_ landmarks: VNFaceLandmarks2D, faceBounds: CGRect) -> Float {
        guard let innerLips = landmarks.innerLips else { return 0 }

        let innerPoints = innerLips.normalizedPoints

        guard innerPoints.count >= 6 else { return 0 }

        // 内嘴唇上下距离
        // innerLips 点的顺序：上唇中心 -> 右 -> 下唇中心 -> 左
        let topPoint = innerPoints[0]
        let bottomPoint = innerPoints[innerPoints.count / 2]
        let mouthHeight = abs(topPoint.y - bottomPoint.y)

        // 使用人脸框高度作为参考（更稳定，不受侧脸影响）
        // 特征点坐标是相对于人脸框的归一化坐标 (0-1)
        // 所以 mouthHeight 已经是相对于人脸框的比例

        // 正常闭嘴时嘴高度约为人脸高度的 0.02-0.04
        // 张大嘴时约为 0.15-0.25
        // 映射到 0-1 范围
        let normalized = min(max((mouthHeight - 0.04) / 0.15, 0), 1)

        return Float(normalized)
    }

    /// 计算撅嘴程度 (0.0 ~ 1.0)
    /// 撅嘴时嘴唇向前突出，嘴巴宽度变窄，嘴唇厚度增加
    /// 使用宽高比来检测：撅嘴时宽度变窄，高度增加，所以宽高比下降
    private func calculatePout(_ landmarks: VNFaceLandmarks2D, faceBounds: CGRect) -> Float {
        guard let outerLips = landmarks.outerLips else { return 0 }

        let outerPoints = outerLips.normalizedPoints
        guard outerPoints.count >= 8 else { return 0 }

        // 计算嘴巴宽度（外嘴唇左右角的距离）
        let leftCorner = outerPoints[outerPoints.count * 3 / 4]
        let rightCorner = outerPoints[outerPoints.count / 4]
        let mouthWidth = abs(rightCorner.x - leftCorner.x)

        // 计算嘴巴高度（外嘴唇上下距离）
        let topPoint = outerPoints[0]
        let bottomPoint = outerPoints[outerPoints.count / 2]
        let mouthHeight = abs(topPoint.y - bottomPoint.y)

        // 防止除零
        guard mouthHeight > 0.001 else { return 0 }

        // 计算宽高比
        // 正常闭嘴：宽度约 0.35-0.45，高度约 0.03-0.05，宽高比约 8-12
        // 撅嘴时：宽度变窄约 0.25-0.30，高度增加约 0.06-0.10，宽高比约 3-5
        let widthHeightRatio = mouthWidth / mouthHeight

        // 撅嘴检测：宽高比低于正常值
        // 正常宽高比 > 6，撅嘴宽高比 < 5
        // 映射到 0-1：宽高比从 6 降到 3 时，撅嘴程度从 0 升到 1
        let normalized = max(0, min((6.0 - widthHeightRatio) / 3.0, 1))

        return Float(normalized)
    }

    /// 计算眨眼程度 (0.0 = 睁眼, 1.0 = 闭眼)
    private func calculateEyeBlink(_ eyeRegion: VNFaceLandmarkRegion2D?) -> Float {
        guard let eye = eyeRegion else { return 0 }
        let points = eye.normalizedPoints

        guard points.count >= 6 else { return 0 }

        // 眼睛的上下点
        let topPoint = points[1]  // 上眼睑
        let bottomPoint = points[points.count - 2]  // 下眼睑

        let eyeHeight = abs(topPoint.y - bottomPoint.y)

        // 眼睛宽度
        let leftPoint = points[0]
        let rightPoint = points[points.count / 2]
        let eyeWidth = abs(rightPoint.x - leftPoint.x)

        guard eyeWidth > 0 else { return 0 }

        // 高宽比，闭眼时比值变小
        let ratio = eyeHeight / eyeWidth

        // 睁眼约 0.3，闭眼约 0.05
        // 映射到 0-1（反转，闭眼时为 1）
        let normalized = max(min((0.25 - ratio) / 0.2, 1), 0)

        return Float(normalized)
    }

    /// 计算挑眉程度
    private func calculateEyebrowRaise(_ landmarks: VNFaceLandmarks2D) -> Float {
        guard let leftEyebrow = landmarks.leftEyebrow,
              let rightEyebrow = landmarks.rightEyebrow,
              let leftEye = landmarks.leftEye,
              let rightEye = landmarks.rightEye else { return 0 }

        // 眉毛和眼睛的距离
        let leftBrowPoints = leftEyebrow.normalizedPoints
        let rightBrowPoints = rightEyebrow.normalizedPoints
        let leftEyePoints = leftEye.normalizedPoints
        let rightEyePoints = rightEye.normalizedPoints

        guard leftBrowPoints.count > 2, rightBrowPoints.count > 2,
              leftEyePoints.count > 0, rightEyePoints.count > 0 else { return 0 }

        // 计算眉毛中心到眼睛中心的距离
        let leftBrowCenter = leftBrowPoints[leftBrowPoints.count / 2]
        let rightBrowCenter = rightBrowPoints[rightBrowPoints.count / 2]
        let leftEyeCenter = leftEyePoints[0]
        let rightEyeCenter = rightEyePoints[0]

        let leftDist = leftBrowCenter.y - leftEyeCenter.y
        let rightDist = rightBrowCenter.y - rightEyeCenter.y
        let avgDist = (leftDist + rightDist) / 2

        // 正常约 0.08，挑眉约 0.12+
        let normalized = max(min((avgDist - 0.08) / 0.06, 1), 0)

        return Float(normalized)
    }

    /// 计算微笑程度
    private func calculateSmile(_ landmarks: VNFaceLandmarks2D) -> Float {
        guard let outerLips = landmarks.outerLips else { return 0 }

        let points = outerLips.normalizedPoints
        guard points.count >= 8 else { return 0 }

        // 嘴角位置
        let leftCorner = points[points.count * 3 / 4]
        let rightCorner = points[points.count / 4]

        // 嘴巴中心
        let topCenter = points[0]
        let bottomCenter = points[points.count / 2]
        let mouthCenterY = (topCenter.y + bottomCenter.y) / 2

        // 嘴角相对于嘴巴中心的高度
        let leftCornerHeight = leftCorner.y - mouthCenterY
        let rightCornerHeight = rightCorner.y - mouthCenterY
        let avgCornerHeight = (leftCornerHeight + rightCornerHeight) / 2

        // 微笑时嘴角上扬（y 值变大）
        // 正常约 0，微笑约 0.03+
        let normalized = max(min(avgCornerHeight / 0.04, 1), 0)

        return Float(normalized)
    }

    /// 当前触发音效
    public var triggerSound: TriggerSound = .tink

    /// 播放触发音效
    private func playTriggerSound() {
        // 如果音效设置为"无"，则不播放
        guard let soundName = triggerSound.systemName else {
            voiceLog("[FaceMonitor] 音效已关闭")
            return
        }

        if let sound = NSSound(named: soundName) {
            sound.play()
            voiceLog("[FaceMonitor] 播放触发音效: \(soundName)")
        } else {
            // 备用：使用系统警告音
            NSSound.beep()
            voiceLog("[FaceMonitor] 播放系统提示音（\(soundName) 不可用）")
        }
    }

    private func handleExpressionState(_ state: ExpressionState) {
        lastExpressionState = state
        onExpressionChange?(state)

        guard state.hasFace else {
            expressionStartTime = nil
            return
        }

        let coefficient = state.coefficients[triggerExpression] ?? 0
        let now = Date()

        // 检查是否超过阈值
        guard coefficient > threshold else {
            expressionStartTime = nil
            return
        }

        // 检查持续时间
        if expressionStartTime == nil {
            expressionStartTime = now
        }

        let duration = now.timeIntervalSince(expressionStartTime!)
        guard duration >= minDuration else {
            return
        }

        // 检查冷却时间
        if let lastTrigger = lastTriggerTime {
            let elapsed = now.timeIntervalSince(lastTrigger)
            guard elapsed >= cooldown else {
                return
            }
        }

        // 触发！
        lastTriggerTime = now
        expressionStartTime = nil

        voiceLog("[FaceMonitor] ✅ 检测到 \(triggerExpression.rawValue)，系数: \(coefficient)，触发回车")

        // 播放触发音效
        playTriggerSound()

        // 模拟按下回车键
        let success = keySimulator.simulateEnter()
        voiceLog("[FaceMonitor] 回车键发送\(success ? "成功" : "失败")")

        onTrigger?(triggerExpression.rawValue)
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension FaceExpressionMonitor: AVCaptureVideoDataOutputSampleBufferDelegate {
    public func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        processFrame(pixelBuffer)
    }
}
