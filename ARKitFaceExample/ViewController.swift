import ARKit
import SceneKit
import UIKit
import AVFoundation

class ViewController: UIViewController, ARSessionDelegate, ARSCNViewDelegate {

    // MARK: Outlets
    @IBOutlet var sceneView: ARSCNView!
    @IBOutlet weak var recordButton: UIButton!
    @IBOutlet weak var shareButton: UIButton!
    @IBOutlet weak var tabBar: UITabBar!

    // MARK: Properties
    var faceAnchorsAndContentControllers: [ARFaceAnchor: VirtualContentController] = [:]
    var selectedVirtualContent: VirtualContentType! {
        didSet {
            guard oldValue != nil, oldValue != selectedVirtualContent else { return }
            DispatchQueue.global(qos: .userInitiated).async {
                for contentController in self.faceAnchorsAndContentControllers.values {
                    contentController.contentNode?.removeFromParentNode()
                }
                for anchor in self.faceAnchorsAndContentControllers.keys {
                    let contentController = self.selectedVirtualContent.makeController()
                    if let node = self.sceneView.node(for: anchor),
                       let contentNode = contentController.renderer(self.sceneView, nodeFor: anchor) {
                        node.addChildNode(contentNode)
                        self.faceAnchorsAndContentControllers[anchor] = contentController
                    }
                }
            }
        }
    }

    var isRecording = false
    var blendShapeData: [[String: NSNumber]] = []
    var videoFilePath: String = ""
    var blendShapeFilePath: String = ""

    var scnRenderer: SCNRenderer!
    var displayLink: CADisplayLink!
    var assetWriter: AVAssetWriter!
    var assetWriterInput: AVAssetWriterInput!
    var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor!
    var recordingStartTime: CMTime?

    override func viewDidLoad() {
        super.viewDidLoad()
        sceneView.delegate = self
        sceneView.session.delegate = self
        sceneView.automaticallyUpdatesLighting = true

        shareButton.isHidden = true
        print("App started, share button hidden.")
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        UIApplication.shared.isIdleTimerDisabled = true
        resetTracking()
    }

    // MARK: - ARSessionDelegate
    func session(_ session: ARSession, didFailWithError error: Error) {
        guard error is ARError else { return }
        let errorWithInfo = error as NSError
        let messages = [
            errorWithInfo.localizedDescription,
            errorWithInfo.localizedFailureReason,
            errorWithInfo.localizedRecoverySuggestion
        ]
        let errorMessage = messages.compactMap({ $0 }).joined(separator: "\n")
        DispatchQueue.main.async {
            self.displayErrorMessage(title: "The AR session failed.", message: errorMessage)
        }
    }

    func resetTracking() {
        guard ARFaceTrackingConfiguration.isSupported else { return }
        let configuration = ARFaceTrackingConfiguration()
        configuration.isLightEstimationEnabled = true
        DispatchQueue.main.async {
            self.sceneView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
            self.faceAnchorsAndContentControllers.removeAll()
            print("AR tracking reset.")
        }
    }

    // MARK: - Error handling
    func displayErrorMessage(title: String, message: String) {
        let alertController = UIAlertController(title: title, message: message, preferredStyle: .alert)
        let restartAction = UIAlertAction(title: "Restart Session", style: .default) { _ in
            alertController.dismiss(animated: true, completion: nil)
            DispatchQueue.global(qos: .userInitiated).async {
                self.resetTracking()
            }
        }
        alertController.addAction(restartAction)
        present(alertController, animated: true, completion: nil)
    }

    override var prefersHomeIndicatorAutoHidden: Bool {
        return true
    }

    override var prefersStatusBarHidden: Bool {
        return true
    }

    // MARK: - Recording Methods
    @IBAction func recordButtonTapped(_ sender: UIButton) {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    func startRecording() {
        guard let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let timestamp = Date().timeIntervalSince1970
        videoFilePath = documentsDirectory.appendingPathComponent("output_\(timestamp).mov").path
        blendShapeFilePath = documentsDirectory.appendingPathComponent("blendshapes_\(timestamp).csv").path
        let outputURL = URL(fileURLWithPath: videoFilePath)

        do {
            assetWriter = try AVAssetWriter(outputURL: outputURL, fileType: .mov)
            let videoSettings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: 1920,
                AVVideoHeightKey: 1080
            ]
            assetWriterInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
            assetWriterInput.expectsMediaDataInRealTime = true

            let attributes: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: 1920,
                kCVPixelBufferHeightKey as String: 1080
            ]
            pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: assetWriterInput, sourcePixelBufferAttributes: attributes)

            if assetWriter.canAdd(assetWriterInput) {
                assetWriter.add(assetWriterInput)
            }

            assetWriter.startWriting()
            assetWriter.startSession(atSourceTime: CMTime.zero)
            recordingStartTime = CMTime.zero

            isRecording = true
            DispatchQueue.main.async {
                self.recordButton.setTitle("Stop Recording", for: .normal)
                self.shareButton.isHidden = true
            }

            scnRenderer = SCNRenderer(device: MTLCreateSystemDefaultDevice(), options: nil)
            scnRenderer.scene = sceneView.scene
            scnRenderer.pointOfView = sceneView.pointOfView

            displayLink = CADisplayLink(target: self, selector: #selector(updateFrame))
            displayLink.add(to: .main, forMode: .common)

            resetTracking()
        } catch {
            print("Error starting recording: \(error)")
        }
    }

    func stopRecording() {
        isRecording = false
        displayLink.invalidate()
        assetWriterInput.markAsFinished()
        assetWriter.finishWriting {
            DispatchQueue.main.async {
                self.recordButton.setTitle("Start Recording", for: .normal)
                self.shareButton.isHidden = false
                print("Recording stopped.")
            }
        }
        saveBlendShapeData()
    }

    @objc func updateFrame() {
        let currentTime = CACurrentMediaTime()
        let time = CMTime(seconds: currentTime, preferredTimescale: 1000)
        if recordingStartTime == nil {
            recordingStartTime = time
        }

        if assetWriterInput.isReadyForMoreMediaData {
            let pixelBuffer = pixelBufferFromImage(image: scnRenderer.snapshot(atTime: currentTime, with: sceneView.bounds.size, antialiasingMode: .multisampling4X))
            pixelBufferAdaptor.append(pixelBuffer, withPresentationTime: time)
        }
    }

    func pixelBufferFromImage(image: UIImage) -> CVPixelBuffer {
        let width = Int(image.size.width)
        let height = Int(image.size.height)
        var pixelBuffer: CVPixelBuffer?

        let attributes: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue!,
            kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue!,
            kCVPixelBufferWidthKey: width,
            kCVPixelBufferHeightKey: height,
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32ARGB
        ]

        CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32ARGB, attributes as CFDictionary, &pixelBuffer)

        let context = CIContext()
        context.render(CIImage(cgImage: image.cgImage!), to: pixelBuffer!)

        return pixelBuffer!
    }

    @IBAction func shareButtonTapped(_ sender: UIButton) {
        let outputURL = URL(fileURLWithPath: videoFilePath)
        let csvURL = URL(fileURLWithPath: blendShapeFilePath)

        guard FileManager.default.fileExists(atPath: videoFilePath), FileManager.default.fileExists(atPath: blendShapeFilePath) else {
            print("Files do not exist.")
            return
        }

        let activityViewController = UIActivityViewController(activityItems: [outputURL, csvURL], applicationActivities: nil)
        present(activityViewController, animated: true, completion: nil)

        print("Share button tapped. Video file path: \(videoFilePath), CSV file path: \(blendShapeFilePath)")
    }

    // MARK: - BlendShape Data Handling
    func saveBlendShapeData() {
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

        for dataPoint in blendShapeData {
            let timestamp = dataPoint["timestamp"] ?? 0
            let row = blendShapeKeys.map { "\(dataPoint[$0] ?? 0)" }
            csvText += "\(timestamp)," + row.joined(separator: ",") + "\n"
        }

        do {
            try csvText.write(to: csvURL, atomically: true, encoding: .utf8)
            print("Blendshape data saved. CSV file path: \(blendShapeFilePath)")
        } catch {
            print("Failed to create file: \(error)")
        }
    }

    // MARK: - ARSCNViewDelegate
    func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
        guard let faceAnchor = anchor as? ARFaceAnchor else { return }

        var currentBlendShapes = [String: NSNumber]()
        currentBlendShapes["timestamp"] = NSNumber(value: Date().timeIntervalSince1970)
        for (key, value) in faceAnchor.blendShapes {
            currentBlendShapes[key.rawValue] = value
        }
        blendShapeData.append(currentBlendShapes)

        if isRecording {
            DispatchQueue.global(qos: .userInitiated).async {
                self.saveBlendShapeData()
            }
            print("Blendshape data received and saved.")
        } else {
            print("Blendshape data received.")
        }
    }
}

extension ViewController: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        if let error = error {
            print("Recording error: \(error.localizedDescription)")
        } else {
            print("Recording finished: \(outputFileURL)")
        }
    }
}
