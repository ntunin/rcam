//
//  Copyright © 2021 Rosberry. All rights reserved.
//

import UIKit
import AVFoundation
import Framezilla

public protocol CameraViewControllerDelegate: AnyObject {
    func cameraViewController(_ viewController: CameraViewController, imageCaptured image: UIImage)
    func cameraViewControllerCloseEventTriggered(_ viewController: CameraViewController)
}

public final class CameraViewController: UIViewController {

    public override var prefersStatusBarHidden: Bool {
        true
    }

    public weak var delegate: CameraViewControllerDelegate?

    private var focusViewTimer: Timer?

    private lazy var bundle: Bundle = .init(for: Self.self)

    private lazy var pinchGestureRecognizer: UIPinchGestureRecognizer = {
        let pinchGestureRecognizer = UIPinchGestureRecognizer(target: self, action: #selector(viewPinched))
        pinchGestureRecognizer.delegate = self
        pinchGestureRecognizer.cancelsTouchesInView = false
        return pinchGestureRecognizer
    }()

    private lazy var tapGestureRecognizer: UITapGestureRecognizer = {
        let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(cameraViewTapped))
        tapGestureRecognizer.delegate = self
        tapGestureRecognizer.cancelsTouchesInView = false
        return tapGestureRecognizer
    }()

    private let cameraService: Camera

    // MARK: - Subviews

    public private(set) lazy var closeButton: UIButton = {
        let button = UIButton(type: .system)
        let image = UIImage(named: "ic_close_xs", in: bundle, compatibleWith: nil)
        button.setImage(image, for: .normal)
        button.addTarget(self, action: #selector(closeButtonPressed), for: .touchUpInside)
        button.tintColor = .white
        button.backgroundColor = UIColor.black.withAlphaComponent(0.3)
        return button
    }()

    public private(set) lazy var cameraPreviewLayer: AVCaptureVideoPreviewLayer = .init()

    public private(set) lazy var cameraView: UIView = {
        let view = UIView()
        view.layer.addSublayer(cameraPreviewLayer)
        return view
    }()
    public private(set) lazy var cameraContainerView: UIView = .init()

    public private(set) lazy var focusImageView: UIImageView = {
        let image = UIImage(named: "elementFocus", in: bundle, compatibleWith: nil)
        let view = UIImageView(image: image)
        view.isUserInteractionEnabled = false
        return view
    }()

    public private(set) lazy var zoomLabelContainerView: ZoomLabelView = .init()

    public private(set) lazy var blurView: UIVisualEffectView = .init(effect: nil)
    public private(set) lazy var footerContainerView: FooterView = {
        let view = FooterView()
        view.captureButtonView.captureButtonEventHandler = { [weak self] in
            self?.captureButtonPressed()
        }
        view.flashModeEventHandler = { [weak self] in
            self?.flashModeButtonPressed()
        }
        view.flipCameraEventHandler = { [weak self] in
            self?.flipCameraButtonPressed()
        }
        return view
    }()

    // MARK: - Lifecycle

    public init(cameraService: Camera = CameraImpl()) {
        self.cameraService = cameraService
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        focusViewTimer?.invalidate()
        focusViewTimer = nil
    }

    public override func viewDidLoad() {
        super.viewDidLoad()

        cameraContainerView.addSubview(cameraView)

        view.addSubview(footerContainerView)

        view.backgroundColor = .black
        cameraContainerView.addGestureRecognizer(tapGestureRecognizer)
        cameraContainerView.addGestureRecognizer(pinchGestureRecognizer)

        view.addSubview(blurView)
        view.addSubview(closeButton)
        view.addSubview(cameraContainerView)
        view.addSubview(zoomLabelContainerView)

        cameraService.startSession()
        cameraPreviewLayer.session = cameraService.captureSession

        updateFlashModeIcon(for: cameraService.flashMode)
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.isNavigationBarHidden = true
    }

    public override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        if let videoPreviewLayerConnection = cameraPreviewLayer.connection {
            let deviceOrientation = UIDevice.current.orientation
            let newVideoOrientation = AVCaptureVideoOrientation(deviceOrientation: deviceOrientation)
            guard deviceOrientation.isPortrait || deviceOrientation.isLandscape else {
                return
            }

            cameraService.orientation = newVideoOrientation
            videoPreviewLayerConnection.videoOrientation = newVideoOrientation
        }
    }

    // MARK: - Layout

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        closeButton.configureFrame { maker in
            maker.size(width: 40, height: 40).cornerRadius(byHalf: .height)
            switch UIDevice.current.orientation {
            case .landscapeLeft:
                maker.top(inset: 24).left(inset: 24)
            case .landscapeRight:
                maker.top(inset: 24).right(inset: 24)
            default:
                maker.top(inset: 24).left(inset: 24)
            }
        }

        footerContainerView.configureFrame { maker in
            let footerContainerViewHeight: CGFloat = 96 + 36 + 36
            switch UIDevice.current.orientation {
            case .landscapeLeft:
                maker.width(footerContainerViewHeight).right(to: view.nui_safeArea.right).top().bottom()
            case .landscapeRight:
                maker.width(footerContainerViewHeight).left(to: view.nui_safeArea.left).top().bottom()
            default:
                maker.height(footerContainerViewHeight).bottom(to: view.nui_safeArea.bottom).left().right()
            }
        }

        cameraContainerView.configureFrame { maker in
            switch UIDevice.current.orientation {
            case .landscapeLeft:
                let measure = view.bounds.height
                maker.size(width: measure * 4 / 3, height: measure)
                     .right(to: footerContainerView.nui_left)
                     .centerY()
            case .landscapeRight:
                let measure = view.bounds.height
                maker.size(width: measure * 4 / 3, height: measure)
                     .left(to: footerContainerView.nui_right)
                     .centerY()
            default:
                let measure = view.bounds.width
                maker.size(width: measure, height: measure * 4 / 3)
                     .bottom(to: footerContainerView.nui_top)
                     .centerX()
            }
        }
        cameraView.frame = cameraContainerView.bounds
        cameraPreviewLayer.frame = cameraView.bounds

        zoomLabelContainerView.configureFrame { maker in
            let side = 38
            maker.size(width: side, height: side).cornerRadius(byHalf: .height)
            switch UIDevice.current.orientation {
            case .landscapeLeft:
                maker.centerY(to: footerContainerView.nui_centerY)
                     .right(to: cameraContainerView.nui_right, inset: 4)
            case .landscapeRight:
                maker.centerY(to: footerContainerView.nui_centerY)
                     .left(to: cameraContainerView.nui_left, inset: 4)
            default:
                maker.centerX(to: footerContainerView.nui_centerX)
                     .bottom(to: cameraContainerView.nui_bottom, inset: 4)
            }
        }

        blurView.frame = cameraContainerView.frame
    }

    // MARK: - Actions

    @objc private func closeButtonPressed() {
        delegate?.cameraViewControllerCloseEventTriggered(self)
    }

    private func captureButtonPressed() {
        cameraService.capturePhoto { [weak self] capturePhoto in
            guard let self = self,
                  let data = capturePhoto.fileDataRepresentation(),
                  let image = UIImage(data: data) else {
                return
            }

            self.delegate?.cameraViewController(self, imageCaptured: image)
        }
    }

    private func flipCameraButtonPressed() {
        guard let cameraSnapshotView = cameraContainerView.snapshotView(afterScreenUpdates: true) else {
            return
        }
        view.isUserInteractionEnabled = false
        cameraSnapshotView.frame = cameraContainerView.frame
        view.insertSubview(cameraSnapshotView, aboveSubview: cameraView)
        cameraContainerView.alpha = 0

        view.insertSubview(blurView, aboveSubview: cameraSnapshotView)

        UIView.animate(withDuration: 0.4, animations: {
            self.blurView.effect = UIBlurEffect(style: .dark)
        }, completion: { _ in
            try? self.cameraService.flipCamera()
            self.updateZoomLevelLabel()
            UIView.animate(withDuration: 0.2, animations: {
                self.cameraContainerView.alpha = 1
                cameraSnapshotView.alpha = 0
                self.blurView.effect = nil
            }, completion: { _ in
                cameraSnapshotView.removeFromSuperview()
                self.blurView.removeFromSuperview()
                self.view.isUserInteractionEnabled = true
            })
        })
    }

    private func flashModeButtonPressed() {
        let currentFlashMode = cameraService.flashMode.rawValue
        let newFlashMode = (currentFlashMode + 1) % 3

        if let flashMode = AVCaptureDevice.FlashMode(rawValue: newFlashMode) {
            updateFlashModeIcon(for: flashMode)
            cameraService.flashMode = flashMode
        }
    }

    @objc private func zoomSliderValueChanged(_ slider: UISlider) {
        cameraService.zoomLevel = CGFloat(slider.value)
        updateZoomLevelLabel()
    }

    // MARK: - Recognizers

    @objc private func cameraViewTapped(recognizer: UITapGestureRecognizer) {
        let point = recognizer.location(in: cameraContainerView)

        focusImageView.bounds = .init(origin: .zero, size: .init(width: 100, height: 100))
        focusImageView.center = cameraContainerView.convert(point, to: view)
        view.addSubview(focusImageView)

        focusImageView.transform = .init(scaleX: 2, y: 2)
        UIView.animate(withDuration: 0.2, animations: {
            self.focusImageView.transform = .identity
        }, completion: nil)

        focusViewTimer?.invalidate()
        focusViewTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { [weak self] _ in
            UIView.animate(withDuration: 0.2, animations: {
                self?.focusImageView.alpha = 0
            }, completion: { _ in
                self?.focusImageView.removeFromSuperview()
                self?.focusImageView.alpha = 1
            })
        }

        let normalizedPoint = CGPoint(x: point.x / cameraContainerView.bounds.width,
                                      y: point.y / cameraContainerView.bounds.height)
        cameraService.updateFocalPoint(with: normalizedPoint)
    }

    @objc private func viewPinched(recognizer: UIPinchGestureRecognizer) {
        switch recognizer.state {
        case .began:
            if let zoomLevel = cameraService.zoomLevel {
                recognizer.scale = zoomLevel
            }
        case .changed:
            let scale = recognizer.scale
            cameraService.zoomLevel = scale
            updateZoomLevelLabel()
        default:
            break
        }
    }

    // MARK: - Private

    private func updateZoomLevelLabel() {
        guard let zoomLevel = cameraService.zoomLevel else {
            return
        }

        zoomLabelContainerView.zoomValueLabel.text = String(format: "%.1f", zoomLevel)
        zoomLabelContainerView.setNeedsLayout()
        zoomLabelContainerView.layoutIfNeeded()
    }

    private func updateFlashModeIcon(for flashMode: AVCaptureDevice.FlashMode) {
        let flashModeImageName: String
        switch flashMode {
        case .auto:
            flashModeImageName = "ic32FlashAuto"
        case .on:
            flashModeImageName = "ic32FlashOn"
        case .off:
            flashModeImageName = "ic32FlashOff"
        @unknown default:
            flashModeImageName = "unknown"
        }
        footerContainerView.flashLightModeButton.setImage(UIImage(named: flashModeImageName, in: bundle, compatibleWith: nil), for: .normal)
    }
}

// MARK: - UIGestureRecognizerDelegate

extension CameraViewController: UIGestureRecognizerDelegate {
    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                                  shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        true
    }
}

private extension AVCaptureVideoOrientation {
    init(deviceOrientation: UIDeviceOrientation) {
        switch deviceOrientation {
        case .landscapeLeft:
            self = .landscapeRight
        case .landscapeRight:
            self = .landscapeLeft
        case .portrait:
            self = .portrait
        case .portraitUpsideDown:
            self = .portraitUpsideDown
        default:
            self = .portrait
        }
    }
}
