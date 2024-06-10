import ARKit
import SceneKit
import UIKit
import AVFoundation

class ViewController: UIViewController, ARSessionDelegate, ARSCNViewDelegate {

    // MARK: Outlets
    @IBOutlet var sceneView: ARSCNView!
    @IBOutlet weak var tabBar: UITabBar!
    @IBOutlet weak var recordButton: UIButton!
    @IBOutlet weak var shareButton: UIButton!

    // MARK: Properties
    var faceAnchorsAndContentControllers: [ARFaceAnchor: VirtualContentController] = [:]
    var selectedVirtualContent: VirtualContentType! {
        didSet {
            guard oldValue != nil, oldValue != selectedVirtualContent else { return }
            for contentController in faceAnchorsAndContentControllers.values {
                contentController.contentNode?.removeFromParentNode()
            }
            for anchor in faceAnchorsAndContentControllers.keys {
                let contentController = selectedVirtualContent.makeController()
                if let node = sceneView.node(for: anchor),
                   let contentNode = contentController.renderer(sceneView, nodeFor: anchor) {
                    node.addChildNode(contentNode)
                    faceAnchorsAndContentControllers[anchor] = contentController
                }
            }
        }
    }

    var isRecording = false
    var videoOutput: AVCaptureMovieFileOutput?
    var session: AVCaptureSession?
    var blendShapeData: [ARFaceAnchor.BlendShapeLocation: NSNumber] = [:]

    override func viewDidLoad() {
        super.viewDidLoad()
        sceneView.delegate = self
        sceneView.session.delegate = self
        sceneView.automaticallyUpdatesLighting = true
        tabBar.selectedItem = tabBar.items!.first!
        selectedVirtualContent = VirtualContentType(rawValue: tabBar.selectedItem!.tag)
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
        sceneView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        faceAnchorsAndContentControllers.removeAll()
    }

    // MARK: - Error handling
    func displayErrorMessage(title: String, message: String) {
        let alertController = UIAlertController(title: title, message: message, preferredStyle: .alert)
        let restartAction = UIAlertAction(title: "Restart Session", style: .default) { _ in
            alertController.dismiss(animated: true, completion: nil)
            self.resetTracking()
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
        isRecording = true
        recordButton.setTitle("Stop Recording", for: .normal)
        // Add video recording setup here
        startVideoRecording()
    }

    func stopRecording() {
        isRecording = false
        recordButton.setTitle("Start Recording", for: .normal)
        // Add video recording stop logic here
        stopVideoRecording()
    }

    func startVideoRecording() {
        session = AVCaptureSession()
        guard let captureDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) else { return }
        guard let input = try? AVCaptureDeviceInput(device: captureDevice) else { return }
        session?.addInput(input)

        videoOutput = AVCaptureMovieFileOutput()
        session?.addOutput(videoOutput!)
        session?.startRunning()

        let outputPath = NSTemporaryDirectory() + "output.mov"
        let outputURL = URL(fileURLWithPath: outputPath)
        videoOutput?.startRecording(to: outputURL, recordingDelegate: self)
    }

    func stopVideoRecording() {
        videoOutput?.stopRecording()
        session?.stopRunning()
        session = nil
    }

    @IBAction func shareButtonTapped(_ sender: UIButton) {
        let outputPath = NSTemporaryDirectory() + "output.mov"
        let outputURL = URL(fileURLWithPath: outputPath)
        let csvPath = NSTemporaryDirectory() + "blendshapes.csv"
        let csvURL = URL(fileURLWithPath: csvPath)
        let activityViewController = UIActivityViewController(activityItems: [outputURL, csvURL], applicationActivities: nil)
        present(activityViewController, animated: true, completion: nil)
    }

    // MARK: - BlendShape Data Handling
    func saveBlendShapeData() {
        let csvPath = NSTemporaryDirectory() + "blendshapes.csv"
        let csvURL = URL(fileURLWithPath: csvPath)
        var csvText = "BlendShapeLocation,Value\n"
        for (location, value) in blendShapeData {
            csvText += "\(location),\(value)\n"
        }
        do {
            try csvText.write(to: csvURL, atomically: true, encoding: .utf8)
        } catch {
            print("Failed to create file")
            print("\(error)")
        }
    }

    // MARK: - ARSCNViewDelegate
    func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
        guard let faceAnchor = anchor as? ARFaceAnchor else { return }
        blendShapeData = faceAnchor.blendShapes
        if isRecording {
            saveBlendShapeData()
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
