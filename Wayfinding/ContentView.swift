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


// MARK: - View model for handling communication between the UI and ARView.
class ViewModel: ObservableObject {
    @Published var distanceToTarget: Float = 0.0

    let uiSignal = PassthroughSubject<UISignal, Never>()

    enum UISignal {
        case didPressUndo
        case didPressAddEntityP
        case didPressAddEntityB
    }
}


// MARK: - UI Layer.
struct ContentView : View {
    @StateObject var viewModel: ViewModel
    
    var body: some View {
        ZStack {
            // AR View.
            ARViewContainer(viewModel: viewModel)
        
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
        
            // Distance value.
            Text("Distance: \(viewModel.distanceToTarget, specifier: "%.2f")")
                .font(.system(size: 16).weight(.light))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 20)

        
            // Controls.
            VStack {
                Button {
                    viewModel.uiSignal.send(.didPressAddEntityP)
                } label: {
                    buttonIcon("p.square", color: .black)
                }
                
                Button {
                    viewModel.uiSignal.send(.didPressAddEntityB)
                } label: {
                    buttonIcon("b.square", color: .orange)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            .padding(.horizontal, 20)
            .padding(.vertical, 30)
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

class SimpleARView: ARView {
    var viewModel: ViewModel
    var arView: ARView { return self }
    var originAnchor: AnchorEntity!
    var pov: AnchorEntity!
    var subscriptions = Set<AnyCancellable>()

    var directionArrowEntity: ModelEntity!
    
    var sceneEntities = [ModelEntity]()
    
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
    }
        
    func setupScene() {
        // Create an anchor at scene origin.
        originAnchor = AnchorEntity(world: .zero)
        arView.scene.addAnchor(originAnchor)

        // Add pov entity that follows the camera.
        pov = AnchorEntity(.camera)
        arView.scene.addAnchor(pov)

        // Setup world tracking and plane detection.
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal, .vertical]
        configuration.environmentTexturing = .automatic
        arView.renderOptions = [.disableDepthOfField, .disableMotionBlur]
        arView.session.run(configuration)
        
        // Called every frame.
        scene.subscribe(to: SceneEvents.Update.self) { event in
            self.renderLoop()
        }.store(in: &subscriptions)
        
        // Process UI signals.
        viewModel.uiSignal.sink { [weak self] in
            self?.processUISignal($0)
        }.store(in: &subscriptions)
        
        // Create direction arrow and to POV.
        directionArrowEntity = makeArrowEntity()
        directionArrowEntity.position.y = -0.25
        directionArrowEntity.position.z = -0.5
        pov.addChild(directionArrowEntity)
    }

    // Process UI signals.
    func processUISignal(_ signal: ViewModel.UISignal) {
        switch signal {
        case .didPressUndo:
            removeLastEntity()
        case .didPressAddEntityP:
            addEntityP()
        case .didPressAddEntityB:
            addEntityB()
        }
    }

    func addEntityP() {
        // Create plane anchor.
        let planeAnchor = AnchorEntity(plane: [.any])
        arView.scene.addAnchor(planeAnchor)

        // Create plane entity and add to anchor.
        let planeEntity = makePlaneEntity()
        planeAnchor.addChild(planeEntity)

        // Add gestures.
        arView.installGestures([.translation, .rotation, .scale], for: planeEntity)

        // Append to array for reference.
        sceneEntities.append(planeEntity)
    }

    func addEntityB() {
        // Create plane anchor.
        let planeAnchor = AnchorEntity(plane: [.any])
        arView.scene.addAnchor(planeAnchor)

        // Create box entity and add to anchor.
        let boxEntity = makeBoxEntity()
        planeAnchor.addChild(boxEntity)

        // Add gestures.
        arView.installGestures([.translation, .rotation, .scale], for: boxEntity)

        // Append to array for reference.
        sceneEntities.append(boxEntity)
    }

    
    func removeLastEntity() {
        if let entity = lastAddedEntity {
            entity.removeFromParent()
            sceneEntities.removeLast()
        }
    }

    func renderLoop() {
        // Make arrow look at last added entity.
        if let targetEntity = lastAddedEntity {
            let target  =  targetEntity.position(relativeTo: pov)
            let origin  =  directionArrowEntity.position
            directionArrowEntity.look(at: [origin.x + target.x,
                                           origin.y + target.y,
                                           origin.z + target.z], from: origin, upVector: [0,1,0], relativeTo: pov)

            // Get distance to target.
            viewModel.distanceToTarget = simd_distance(pov.position(relativeTo: originAnchor), targetEntity.position(relativeTo: originAnchor))
        } else {
            
        }
        
        for entity in sceneEntities {
            entity.position.y = entity.visualBounds(relativeTo: entity.parent).extents.y / 2
        }
    }

    func makePlaneEntity() -> ModelEntity {
        // Create transparent material.
        var material = UnlitMaterial()
        let texture = try! TextureResource.load(named: "arrow.png")
        material.color.texture = .init(texture)
        material.color.tint    = .white.withAlphaComponent(0.999)

        let entity = ModelEntity.init(mesh: .generatePlane(width: 0.5, depth: 0.5), materials: [material])

        entity.generateCollisionShapes(recursive: true)
        
        return entity
    }

    func makeBoxEntity() -> ModelEntity {
        var material = PhysicallyBasedMaterial()
        material.baseColor.tint = .orange

        let entity = ModelEntity.init(mesh: .generateBox(size: 0.25, cornerRadius: 0.02),
                                      materials: [material])

        entity.generateCollisionShapes(recursive: true)
        
        return entity
    }

    func makeArrowEntity() -> ModelEntity {
        var greenMaterial = PhysicallyBasedMaterial()
        greenMaterial.baseColor.tint = .green

        var redMaterial = PhysicallyBasedMaterial()
        redMaterial.baseColor.tint = .red

        let body = ModelEntity.init(mesh: .generateBox(size: [0.015, 0.015, 0.1]), materials: [greenMaterial])
        let back  = ModelEntity.init(mesh: .generateBox(size: [0.016, 0.016, 0.016]), materials: [redMaterial])
        back.position.z = -0.1 / 2
        body.addChild(back)
        
        return body
    }
}
