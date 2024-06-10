import UIKit
import SceneKit
import ARKit
import AVFoundation

class ViewController: UIViewController, ARSCNViewDelegate {
    @IBOutlet var sceneView: ARSCNView!
    @IBOutlet var recordButton: UIButton!
    @IBOutlet var shareButton: UIButton!
    @IBOutlet var tabBar: UITabBar!

    private var isRecording = false
    private var assetWriter: AVAssetWriter?
    private var assetWriterInput: AVAssetWriterInput?
    private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var displayLink: CADisplayLink?
    private var startTime: CMTime?
    private var videoURL: URL?
    private var blendShapeData = [[String: NSNumber]]()
    private var blendShapeFilePath: String?

    override func viewDidLoad() {
        super.viewDidLoad()

        sceneView.delegate = self
        sceneView.scene = SCNScene()

        setupARSession()
        setupBlendShapeFilePath()
        shareButton.isEnabled = false
    }

    private func setupARSession() {
        let configuration = ARFaceTrackingConfiguration()
        configuration.isLightEstimationEnabled = true
        sceneView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
    }

    private func setupBlendShapeFilePath() {
        let date = Date().timeIntervalSince1970
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        blendShapeFilePath = documentsDirectory.appendingPathComponent("blendshapes_\(date).csv").path
    }

    @IBAction func recordButtonTapped(_ sender: UIButton) {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
        isRecording.toggle()
        recordButton.setTitle(isRecording ? "Stop Recording" : "Start Recording", for: .normal)
    }

    private func startRecording() {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let date = Date().timeIntervalSince1970
                let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
                self.videoURL = documentsDirectory.appendingPathComponent("output_\(date).mov")

                self.assetWriter = try AVAssetWriter(outputURL: self.videoURL!, fileType: .mov)

                let outputSettings: [String: Any] = [
                    AVVideoCodecKey: AVVideoCodecType.h264,
                    AVVideoWidthKey: 1920,
                    AVVideoHeightKey: 1080
                ]
                self.assetWriterInput = AVAssetWriterInput(mediaType: .video, outputSettings: outputSettings)
                self.assetWriterInput?.expectsMediaDataInRealTime = true

                let sourcePixelBufferAttributes: [String: Any] = [
                    kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32ARGB),
                    kCVPixelBufferWidthKey as String: 1920,
                    kCVPixelBufferHeightKey as String: 1080,
                ]
                self.pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(
                    assetWriterInput: self.assetWriterInput!,
                    sourcePixelBufferAttributes: sourcePixelBufferAttributes
                )

                if self.assetWriter!.canAdd(self.assetWriterInput!) {
                    self.assetWriter!.add(self.assetWriterInput!)
                }

                self.assetWriter!.startWriting()
                self.startTime = CMTime.zero
                self.assetWriter!.startSession(atSourceTime: self.startTime!)

                DispatchQueue.main.async {
                    self.displayLink = CADisplayLink(target: self, selector: #selector(self.updateFrame))
                    self.displayLink?.preferredFramesPerSecond = 30
                    self.displayLink?.add(to: .main, forMode: .default)
                    self.shareButton.isEnabled = false
                }
            } catch {
                print("Error starting recording: \(error)")
            }
        }
    }

    @objc private func updateFrame() {
        guard let pixelBufferPool = pixelBufferAdaptor?.pixelBufferPool else {
            print("Error: Pixel Buffer Pool is nil")
            return
        }

        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBuffer(nil, pixelBufferPool, &pixelBuffer)

        guard let outputBuffer = pixelBuffer, status == kCVReturnSuccess else {
            print("Error: Could not create pixel buffer")
            return
        }

        CVPixelBufferLockBaseAddress(outputBuffer, [])

        let ciContext = CIContext()
        let uiImage = sceneView.snapshot()
        guard let ciImage = CIImage(image: uiImage) else {
            print("Error: Could not create CIImage")
            CVPixelBufferUnlockBaseAddress(outputBuffer, [])
            return
        }

        ciContext.render(ciImage, to: outputBuffer)
        CVPixelBufferUnlockBaseAddress(outputBuffer, [])

        let currentTime = CMTimeAdd(startTime!, CMTimeMake(value: Int64(displayLink!.timestamp * 1000), timescale: 1000))

        guard assetWriterInput!.isReadyForMoreMediaData else {
            print("Error: Not ready for more media data")
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            self.pixelBufferAdaptor?.append(outputBuffer, withPresentationTime: currentTime)
        }
    }

    private func stopRecording() {
        displayLink?.invalidate()
        displayLink = nil

        assetWriterInput?.markAsFinished()
        assetWriter?.finishWriting {
            print("Recording finished: \(String(describing: self.videoURL))")
            DispatchQueue.main.async {
                self.saveBlendShapeData()
                self.shareButton.isEnabled = true
            }
        }
    }

    private func saveBlendShapeData() {
        guard let blendShapeFilePath = blendShapeFilePath else { return }
        DispatchQueue.global(qos: .background).async {
            let csvURL = URL(fileURLWithPath: blendShapeFilePath)
            var csvText = "Timestamp"
            let blendShapeKeys = [
                "browDownLeft", "browDownRight", "browInnerUp", "browOuterUpLeft", "browOuterUpRight",
                "cheekPuff", "cheekSquintLeft", "cheekSquintRight", "eyeBlinkLeft", "eyeBlinkRight",
                "eyeLookDownLeft", "eyeLookDownRight", "eyeLookInLeft", "eyeLookInRight",
                "eyeLookOutLeft", "eyeLookOutRight", "eyeLookUpLeft", "eyeLookUpRight",
                "eyeSquintLeft", "eyeSquintRight", "eyeWideLeft", "eyeWideRight", "jawForward",
                "jawLeft", "jawOpen", "jawRight", "mouthClose", "mouthDimpleLeft", "mouthDimpleRight",
                "mouthFrownLeft", "mouthFrownRight", "mouthFunnel", "mouthLeft", "mouthLowerDownLeft",
                "mouthLowerDownRight", "mouthPressLeft", "mouthPressRight", "mouthPucker", "mouthRight",
                "mouthRollLower", "mouthRollUpper", "mouthShrugLower", "mouthShrugUpper",
                "mouthSmileLeft", "mouthSmileRight", "mouthStretchLeft", "mouthStretchRight",
                "mouthUpperUpLeft", "mouthUpperUpRight", "noseSneerLeft", "noseSneerRight",
                "tongueOut"
            ]
            csvText += "," + blendShapeKeys.joined(separator: ",") + "\n"

            for dataPoint in self.blendShapeData {
                let timestamp = dataPoint["timestamp"] ?? 0
                let row = blendShapeKeys.map { "\(dataPoint[$0] ?? 0)" }
                csvText += "\(timestamp)," + row.joined(separator: ",") + "\n"
            }

            do {
                try csvText.write(to: csvURL, atomically: true, encoding: .utf8)
                print("Blendshape data saved. CSV file path: \(self.blendShapeFilePath ?? "N/A")")
            } catch {
                print("Failed to create file: \(error)")
            }
        }
    }

    @IBAction func shareButtonTapped(_ sender: UIButton) {
        guard let videoURL = videoURL, let blendShapeFilePath = blendShapeFilePath else { return }
        let blendShapeURL = URL(fileURLWithPath: blendShapeFilePath)
        let activityViewController = UIActivityViewController(activityItems: [videoURL, blendShapeURL], applicationActivities: nil)
        present(activityViewController, animated: true, completion: nil)
    }

    // MARK: - ARSCNViewDelegate
    func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
        guard let faceAnchor = anchor as? ARFaceAnchor else { return }

        var currentBlendShapes = [String: NSNumber]()
        currentBlendShapes["timestamp"] = NSNumber(value: Date().timeIntervalSince1970)
        for (key, value) in faceAnchor.blendShapes {
            currentBlendShapes[key.rawValue] = value
        }

        if isRecording {
            blendShapeData.append(currentBlendShapes)
        }
    }
}
