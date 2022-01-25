//
//  ContentView.swift
//  Wayfinding
//
//  Created by Nien Lam on 11/10/21.
//

import SwiftUI
import ARKit
import RealityKit
import Combine
import AVFoundation
import Firebase
import OSCKit


// MARK: - View model for handling communication between the UI and ARView.


class ViewModel: ObservableObject {
    
    
    @Published var distanceToTarget: Float = 0.0

    @Published var massValue: Float = 2.0
    @Published var forceValue: Float = 4
    @Published var score: Int32? = 0
    @Published var score2: Int32? = 0
    
    let uiSignal = PassthroughSubject<UISignal, Never>()

    enum UISignal {
        case didPressUndo
        case didPressShoot
    }
}


// MARK: - UI Layer.
struct ContentView : View {
    @StateObject var viewModel: ViewModel
    
    @State var showTestInterface: Bool = true
    
    var body: some View {
        ZStack {
                     // AR View.
            ARViewContainer(viewModel: viewModel)
            
           /* Image("crosshairs.png")
                .resizable()
                .padding(10)
                .frame(width: 44, height: 44)*/
                            
                
                Color.white.opacity(0.0001)
                    .frame(width: 100, height: 100)
                    .onTapGesture(count: 2) {
                        showTestInterface.toggle()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            
           
            
            
            
            
            
            
                
                
            Image("crosshairs")
                .resizable()
                .padding(10)
                .frame(width: 150, height: 150)
                
                Spacer()
                Spacer()
                Spacer()
                
            
                
            
            if showTestInterface {
                // Reset button.
                Button {
                    viewModel.uiSignal.send(.didPressUndo)
                } label: {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                        .font(.system(.title))
                        .foregroundColor(.white)
                        .labelStyle(IconOnlyLabelStyle())
                        .frame(width: 44, height: 44)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding()

               
                }
            
            // Add entities buttons.
            VStack {
                Spacer()
                Spacer()
                Spacer()
                HStack{
                    
                    Slider(value: $viewModel.massValue, in: 0...10)
                            .frame(width: 120, alignment: .center)
                        .rotationEffect(.radians(-.pi/2))
                    
                    Slider(value: $viewModel.forceValue, in: 0...25)
                        .frame(width: 120, alignment: .center)
                        .rotationEffect(.radians(-.pi/2))
                    
                        //Spacer()
                    Spacer()
                //Spacer()
               
                
                Button {
                    viewModel.uiSignal.send(.didPressShoot)
                } label: {
                    Text("Shoot")
                        .frame(maxWidth: 100, maxHeight: 100)
                        
                }
                    
            
            
            
            .background(.red)
            .foregroundColor(.white)
            .cornerRadius(20)
            }
            
            // Hide/show test interface.
            
              Spacer()
                HStack{
                    Spacer()
             Text("Score: \(viewModel.score2!)")
                        .font(.system(.title))
                        .foregroundColor(.white)
                        
                    Spacer()
                    Spacer()
                    Spacer()
                    Spacer()
                    Spacer()
                    Spacer()
            }
                
            }

            // Distance value. Visible if there are entities added to scene.
            
        }
        .edgesIgnoringSafeArea(.all)
        .statusBar(hidden: true)
    }

    // Helper methods for rendering icon.
    func buttonIcon(_ systemName: String, color: Color) -> some View {
        Image(systemName: systemName)
            .resizable()
            .padding(10)
            .frame(width: 44, height: 44)
            .foregroundColor(.white)
            .background(color)
            .cornerRadius(5)
    }
}


// MARK: - AR View.
struct ARViewContainer: UIViewRepresentable {
    let viewModel: ViewModel
    
    func makeUIView(context: Context) -> ARView {
        SimpleARView(frame: .zero, viewModel: viewModel)
    }
    
    func updateUIView(_ uiView: ARView, context: Context) {}
}

class SimpleARView: ARView, ARSessionDelegate {
    var viewModel: ViewModel
    var arView: ARView { return self }
    var originAnchor: AnchorEntity!
    var pov: AnchorEntity!
    var subscriptions = Set<AnyCancellable>()
    var cursor: Entity!
    var imageAnchorToEntity: [ARImageAnchor: AnchorEntity] = [:]
    var ambientIntensity: Double = 0
    
    
    var bullet: ModelEntity!

    var directionArrowEntity: ModelEntity!
    
    var sceneEntities = [ModelEntity]()
    var player: AVAudioPlayer!
    var bulletSoundEntity = Entity()
    var bulletEntity: ModelEntity!
    var bulletController: AudioPlaybackController!
    var timer:Timer!
    var timer2:Timer!
    
    var controllerClient: UDPClient?
    var controllerServer: UDPServer?
    
    
    
    var lastAddedEntity: ModelEntity? {
        sceneEntities.last
    }
    

    init(frame: CGRect, viewModel: ViewModel) {
        self.viewModel = viewModel
        super.init(frame: frame)
    }
    
    required init?(coder decoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    required init(frame frameRect: CGRect) {
        fatalError("init(frame:) has not been implemented")
    }
    
    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        
        UIApplication.shared.isIdleTimerDisabled = true
        
        setupScene()
        FirebaseApp.configure()
        
        let controllerHost = String("10.23.11.154")
        let controllerPort = UInt16 (8080)
        
       
        
       
        controllerClient = UDPClient(
            host: controllerHost,
            port: controllerPort,
            queue: DispatchQueue.global(qos: .userInteractive)
        )
        
        print("UDP client set up.")
        
        do {
            controllerServer = try UDPServer(
                host: "localhost",
                port: 8000,
                queue: DispatchQueue.global(qos: .userInteractive)
            )
        } catch {
            print("Error initializing UDP server:", error)
            return
        }
        
        controllerServer?.setHandler { [weak self] data in
            
            // incoming data handler is fired on the UDPServer's queue
            // but we want to deal with it on the main thread
            // to update UI as a result, etc. here
            
            DispatchQueue.main.async {
                
                do {
                    guard let oscPayload = try data.parseOSC() else { return }
                    self?.handleOSCPayload(oscPayload)
                    
                } catch let error as OSCBundle.DecodeError {
                    // handle bundle errors
                    switch error {
                    case .malformed(let verboseError):
                        print("Error:", verboseError)
                    }
                    
                } catch let error as OSCMessage.DecodeError {
                    // handle message errors
                    switch error {
                    case .malformed(let verboseError):
                        print("Error:", verboseError)
                        
                    case .unexpectedType(let oscType):
                        print("Error: unexpected OSC type tag:", oscType)
                        
                    }
                    
                } catch {
                    // handle other errors
                    print("Error:", error)
                }
                
            }
            
        }
        
        print("UDP server set up.")

        
        
           
            
        
    }
        
    func setupScene() {
        // Create an anchor at scene origin.
        originAnchor = AnchorEntity(world: .zero)
        arView.scene.addAnchor(originAnchor)
        
        cursor = Entity()
        originAnchor.addChild(cursor)
        
      

        // Add pov entity that follows the camera.
        pov = AnchorEntity(.camera)
        arView.scene.addAnchor(pov)

        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = []
        var set = Set<ARReferenceImage>()
        
        if let detectionImage = makeDetectionImage(named: "zombie1.png",
                                                   referenceName: "IMAGE_ALPHA",
                                                   physicalWidth: 0.2159) {
            set.insert(detectionImage)
        }
        
        configuration.detectionImages = set
        configuration.maximumNumberOfTrackedImages = 2
        
       
//
        arView.renderOptions = [ .disableMotionBlur, .disableCameraGrain, .disableDepthOfField, .disableGroundingShadows, .disableAREnvironmentLighting ]
        configuration.environmentTexturing = .none
        
        
                if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
                    configuration.sceneReconstruction = .mesh
//                    configuration.frameSemantics.insert(.personSegmentationWithDepth)
                } else {
                    print("ARWorldTrackingConfiguration: Does not support scene Reconstruction.")
                }
        
        arView.debugOptions = [.showSceneUnderstanding, .showStatistics]
        
        // TODO: Update target image and physical width in meters. //////////////////////////////////////
        let targetImage    = "zombie1"
        let physicalWidth  = 0.1524
        
        if let refImage = UIImage(named: targetImage)?.cgImage {
            print(">>>>>>>>")
            let arReferenceImage = ARReferenceImage(refImage, orientation: .up, physicalWidth: physicalWidth)
            var set = Set<ARReferenceImage>()
            set.insert(arReferenceImage)
            configuration.detectionImages = set
        } else {
            print("❗️ Error loading target image")
        }

               
        arView.environment.sceneUnderstanding.options = [.collision, .physics]
        
        arView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        // Called every frame.
        scene.subscribe(to: SceneEvents.Update.self) { event in
//            self.renderLoop()
//            self.updateCursor()
        }.store(in: &subscriptions)
        
        // Process UI signals.
        viewModel.uiSignal.sink { [weak self] in
            self?.processUISignal($0)
        }.store(in: &subscriptions)
        
        arView.scene.subscribe(to: CollisionEvents.Began.self) { event in
            // If entity with name block collides with anything.
            if event.entityA.name == "target"  {
                self.viewModel.score! += 1
                
                print("HIT TARGET")
            }
            
            if event.entityA.name == "bullet" || event.entityB.name == "bullet" {
                //self.viewModel.score! += 1
                print("BULLET HIT SOMETHING")
            }

            
        }.store(in: &subscriptions)
        
        bullet = makeBullet()
        
        timer = Timer.scheduledTimer(
            timeInterval: 0.1,
            target: self,
            selector: #selector(checkTime),
            userInfo: nil,
            repeats: true
            )
       
        timer2 = Timer.scheduledTimer(
            timeInterval: 4,
            target: self,
            selector: #selector(checkTime2),
            userInfo: nil,
            repeats: true
        )
        

        
        
        arView.session.delegate = self
         
        
    }
    
    func makeDetectionImage(named: String, referenceName: String, physicalWidth: CGFloat) -> ARReferenceImage? {
        guard let targetImage = UIImage(named: named)?.cgImage else {
            print("❗️ Error loading target image:", named)
            return nil
        }

        let arReferenceImage  = ARReferenceImage(targetImage, orientation: .up, physicalWidth: physicalWidth)
        arReferenceImage.name = referenceName

        return arReferenceImage
    }
    
    
    /*
    func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        // Handle image anchors.
        anchors.compactMap { $0 as? ARImageAnchor }.forEach {
            // Grab reference image name.
            guard let referenceImageName = $0.referenceImage.name else { return }

            // Create anchor and place at image location.
            let anchorEntity = AnchorEntity(world: $0.transform)
            arView.scene.addAnchor(anchorEntity)
            
            // Setup logic based on reference image.
            if referenceImageName == "IMAGE_ALPHA" {
                setupEntities(anchorEntity: anchorEntity)
        }
    }
    }*/
    
    func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        anchors.compactMap { $0 as? ARImageAnchor }.forEach {
            // Create anchor from image.
            let anchorEntity = AnchorEntity(anchor: $0)
            
            // Track image anchors added to scene.
            imageAnchorToEntity[$0] = anchorEntity
            
            // Add anchor to scene.
            arView.scene.addAnchor(anchorEntity)
            
            // Call setup method for entities.
            // IMPORTANT: Play USDZ animations after entity is added to the scene.
            setupEntities(anchorEntity: anchorEntity)
        }
    }
    
   
    
    
    func setupEntities(anchorEntity: AnchorEntity) {
        print("it works!")
        
        let boxMesh   = MeshResource.generateBox(width: 0.2, height: 0.025, depth: 0.2, cornerRadius: 0.002)
        let material  = OcclusionMaterial()
        
        let marker = ModelEntity(mesh: boxMesh, materials: [material])
        
        marker.collision = CollisionComponent(shapes: [.generateBox(width: 0.28, height: 0.025, depth: 0.3)])
        marker.physicsBody = PhysicsBodyComponent(shapes: [.generateBox(width: 0.28, height: 0.025, depth: 0.3)], mass: 1)
        marker.physicsBody?.mode = .static
        marker.name = "target"
        
        anchorEntity.addChild(marker)
        //marker.position.y = 0.1
        
        print("yup def working")
    }

    
    
    // Process UI signals.
    func processUISignal(_ signal: ViewModel.UISignal) {
        switch signal {
        case .didPressUndo:
            arView.scene.anchors.removeAll()
            sceneEntities.removeAll()
            
            originAnchor = AnchorEntity(world: .zero)
            arView.scene.addAnchor(originAnchor)
            
            pov = AnchorEntity(.camera)
            arView.scene.addAnchor(pov)
        
        case .didPressShoot:
            addBullet()
            self.viewModel.score! += 1
            playSound()
            
            sendScore(controllerClient!)
            //sendScore2(controllerClient!)
            
        }
    }
    

    // Add sample box entity.
    func playSound() {
           let url = Bundle.main.url(forResource: "swoosh", withExtension: "wav")
           player = try! AVAudioPlayer(contentsOf: url!)
           player.play()
        }
    
    func addBullet() {
        
        
        // Create plane anchor.
        let planeAnchor = AnchorEntity(plane: [.any])
        arView.scene.addAnchor(planeAnchor)

        // Create and shoot new bullet
        bulletEntity = bullet.clone(recursive: false)
        
        bulletEntity.position = pov.position(relativeTo: originAnchor)
        bulletEntity.orientation = pov.orientation(relativeTo: originAnchor)
        bulletEntity.setScale([2,2,2], relativeTo: originAnchor)
        
        originAnchor.addChild(bulletEntity)
        
        bulletEntity.applyLinearImpulse([0, 0.6, -viewModel.forceValue], relativeTo: bulletEntity)
        bulletEntity.addChild(bulletSoundEntity)
        
        
        // Append to array for reference.
        sceneEntities.append(bulletEntity)
        //bulletController.play()
        

       /* timer = Timer.scheduledTimer(
            timeInterval: 0.63,
            target: self,
            selector: #selector(checkTime),
            userInfo: nil,
            repeats: false
        )*/
        
        

        
    
    }
    
    

    @objc func checkTime() {
        
            
    }
    
    @objc func checkTime2() {
        
        arView.scene.anchors.removeAll()
        sceneEntities.removeAll()
        
        originAnchor = AnchorEntity(world: .zero)
        arView.scene.addAnchor(originAnchor)
        
        pov = AnchorEntity(.camera)
        arView.scene.addAnchor(pov)
        
    }
    func renderLoop() {
        
    }

    

    func makeBullet() -> ModelEntity {
        do{
            let bulletResource = try AudioFileResource.load(named: "swoosh.wav", in: nil, inputMode: .spatial, loadingStrategy: .preload, shouldLoop: true)
            bulletController = bulletSoundEntity.prepareAudio(bulletResource)
            print("Loading bullet sound")
        }catch {
            print("Error loading audio files")
        }
        
        var material = PhysicallyBasedMaterial()
        material.baseColor.tint = .blue


        let entity = try! Entity.loadModel(named: "sphere.usdz")
        
        entity.collision = CollisionComponent(shapes: [.generateSphere(radius: 0.11)])
        entity.physicsBody = PhysicsBodyComponent(shapes: [.generateSphere(radius: 0.11)], mass: viewModel.massValue)
        entity.model?.materials = [material]
        entity.name = "bullet"
        
                
        entity.physicsBody?.mode = .dynamic
        
        return entity
    }
    
    func makeBoxMarker(color: UIColor) -> Entity {
        let boxMesh   = MeshResource.generateBox(size: 0.025, cornerRadius: 0.002)
        let material  = SimpleMaterial(color: color, isMetallic: false)
        return ModelEntity(mesh: boxMesh, materials: [material])
    }


    
    
   
    
    func handleOSCPayload(_ oscPayload: OSCPayload) {
        
        switch oscPayload {
        case .bundle(let bundle):
            // recursively handle nested bundles and messages
            bundle.elements.forEach { handleOSCPayload($0) }
            
        case .message(let message):
            // handle message
            if message.address == "/scoreB"{
                print(message)
                let oscMessage = message.values.first!
               print(oscMessage)
                //let test = Int32(String("\(oscMessage)"))
                //print(test!)
                
                viewModel.score2 = Int32(String("\(oscMessage)"))
               // print(viewModel.score2!)
            }
                
        }
        
        
    }
    
   
    func sendScore(_ sender: Any) {
        
        let score = OSCMessage(
            address: "/scoreA",
            values: [.int32(viewModel.score!)]
        )
            .rawData
        
        controllerClient?.send(data: score)
        
    }
    
    func sendScore2(_ sender: Any) {
        
        let score = OSCMessage(
            address: "/scoreB",
            values: [.int32(viewModel.score2!)]
        )
            .rawData
        
        controllerClient?.send(data: score)
        
    }

}
