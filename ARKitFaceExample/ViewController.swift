import UIKit
import SceneKit
import ARKit

class ViewController: UIViewController, ARSCNViewDelegate {
    @IBOutlet var sceneView: ARSCNView!
    @IBOutlet var recordButton: UIButton!
    @IBOutlet var shareButton: UIButton!
    @IBOutlet var tabBar: UITabBar!

    private var isRecording = false
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
            recordButton.setTitle("Start Recording", for: .normal)
        } else {
            startRecording()
            recordButton.setTitle("Stop Recording", for: .normal)
        }
        isRecording.toggle()
    }

    private func startRecording() {
        blendShapeData.removeAll()
        shareButton.isEnabled = false
    }

    private func stopRecording() {
        saveBlendShapeData()
        shareButton.isEnabled = true
    }

    private func saveBlendShapeData() {
        guard let blendShapeFilePath = blendShapeFilePath else { return }
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

    @IBAction func shareButtonTapped(_ sender: UIButton) {
        guard let blendShapeFilePath = blendShapeFilePath else { return }
        let blendShapeURL = URL(fileURLWithPath: blendShapeFilePath)
        let activityViewController = UIActivityViewController(activityItems: [blendShapeURL], applicationActivities: nil)
        present(activityViewController, animated: true, completion: nil)
    }

    // MARK: - ARSCNViewDelegate
    func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
        guard let faceAnchor = anchor as? ARFaceAnchor, isRecording else { return }

        var currentBlendShapes = [String: NSNumber]()
        currentBlendShapes["timestamp"] = NSNumber(value: Date().timeIntervalSince1970)
        for (key, value) in faceAnchor.blendShapes {
            currentBlendShapes[key.rawValue] = value
        }
        blendShapeData.append(currentBlendShapes)
        print("Blendshape data received.")
    }
}
