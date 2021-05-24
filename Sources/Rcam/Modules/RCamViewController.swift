//
//  Copyright © 2021 Rosberry. All rights reserved.
//

import UIKit
import AVFoundation
import Framezilla

public protocol RCamViewControllerDelegate: class {
    func rCamViewController(_ viewController: RCamViewController, imageCaptured image: UIImage)
}

public final class RCamViewController: UIViewController {

    public override var prefersStatusBarHidden: Bool {
        true
    }

    public weak var delegate: RCamViewControllerDelegate?

    private var focusViewTimer: Timer?

    private lazy var pinchGestureRecognizer: UIPinchGestureRecognizer = {
        let pinchGestureRecognizer = UIPinchGestureRecognizer(target: self, action: #selector(viewPinched))
        pinchGestureRecognizer.delegate = self
        pinchGestureRecognizer.cancelsTouchesInView = false
        return pinchGestureRecognizer
    }()

    private lazy var tapGestureRecognizer: UITapGestureRecognizer = {
        let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(videoViewTapped))
        tapGestureRecognizer.delegate = self
        tapGestureRecognizer.cancelsTouchesInView = false
        return tapGestureRecognizer
    }()

    private let cameraService: Camera = CameraImpl()

    // MARK: - Subviews

    private lazy var cameraPreviewLayer: AVCaptureVideoPreviewLayer = .init()
    private lazy var cameraView: UIView = {
        let view = UIView()
        view.layer.addSublayer(cameraPreviewLayer)
        return view
    }()
    private lazy var cameraContainerView: UIView = .init()

    private lazy var captureButtonContainerView: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor.black.withAlphaComponent(0.3)
        return view
    }()

    private lazy var captureButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(named: "ic62TakePhoto"), for: .normal)
        button.addTarget(self, action: #selector(captureButtonTouchedUp), for: .touchUpInside)
        button.tintColor = .white
        button.backgroundColor = UIColor.black.withAlphaComponent(0.3)
        return button
    }()

    private lazy var torchCameraButton: UIButton = {
        let button = UIButton(type: .system)
        button.addTarget(self, action: #selector(torchCameraButtonPressed), for: .touchUpInside)
        button.backgroundColor = .white
        button.titleLabel?.font = .systemFont(ofSize: 16, weight: .regular)
        return button
    }()

    private lazy var flipCameraButton: UIButton = {
        let button = UIButton()
        button.setImage(UIImage(named: "ic32Swichcamera"), for: .normal)
        button.addTarget(self, action: #selector(flipCameraButtonPressed), for: .touchUpInside)
        button.tintColor = .white
        button.backgroundColor = UIColor.black.withAlphaComponent(0.3)
        return button
    }()

    private lazy var focusView: UIView = {
        let view = UIView()
        view.isUserInteractionEnabled = false
        view.layer.borderWidth = 1
        view.layer.borderColor = UIColor.systemRed.cgColor
        return view
    }()

    private lazy var flashLightModeButton: UIButton = {
        let button = UIButton()
        button.setImage(UIImage(named: "ic32FlashAuto"), for: .normal)
        button.tintColor = .white
        button.backgroundColor = UIColor.black.withAlphaComponent(0.3)
        button.addTarget(self, action: #selector(flashModeButtonPressed), for: .touchUpInside)
        return button
    }()

    private lazy var resultImageView: UIImageView = .init()

    private lazy var zoomSlider: UISlider = {
        let slider = UISlider()
        slider.minimumValue = 1
        slider.maximumValue = 16
        slider.value = 1
        slider.addTarget(self, action: #selector(zoomSliderValueChanged), for: .valueChanged)
        return slider
    }()

    private lazy var zoomLabelContainerView: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor.black.withAlphaComponent(0.3)
        return view
    }()

    private lazy var zoomLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 12, weight: .semibold)
        label.text = "1 X"
        return label
    }()

    // MARK: - Lifecycle

    public init() {
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .black

        cameraContainerView.addGestureRecognizer(tapGestureRecognizer)

        cameraContainerView.addGestureRecognizer(pinchGestureRecognizer)

        cameraContainerView.addSubview(cameraView)
        zoomLabelContainerView.addSubview(zoomLabel)
        view.addSubview(cameraContainerView)
        view.addSubview(captureButton)
        view.addSubview(torchCameraButton)
        view.addSubview(flashLightModeButton)
        view.addSubview(flipCameraButton)
        view.addSubview(resultImageView)
        view.addSubview(zoomSlider)
        view.addSubview(zoomLabelContainerView)

        cameraService.startSession()
        cameraPreviewLayer.session = cameraService.captureSession

        updateFlashModeIcon(for: cameraService.flashMode)
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.isNavigationBarHidden = true
    }

    // MARK: - Layout

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        let availableRect = view.bounds.inset(by: view.safeAreaInsets)
        let width = availableRect.width
        let aspect: CGFloat = 9 / 16
        let height = width / aspect
        cameraContainerView.configureFrame { maker in
            maker.size(width: width, height: height)
                .centerY(between: view.nui_safeArea.top, view.nui_safeArea.bottom)
        }
        cameraView.frame = cameraContainerView.bounds
        cameraPreviewLayer.frame = cameraView.bounds

        captureButton.configureFrame { maker in
            let actualSize = captureButton.sizeThatFits(view.bounds.size)
            maker.size(width: actualSize.width + 20, height: actualSize.height + 20)
                .centerX().bottom(to: view.nui_safeArea.bottom, inset: 70).cornerRadius(byHalf: .height)
        }

        torchCameraButton.configureFrame { maker in
            maker.size(width: 76, height: 36)
                 .cornerRadius(byHalf: .height)
                 .top(to: view.nui_safeArea.top, inset: 12)
                 .right(inset: 24)
        }

        flashLightModeButton.configureFrame { maker in
            let actualSize = flashLightModeButton.sizeThatFits(view.bounds.size)
            maker.size(width: actualSize.width + 20, height: actualSize.height + 20)
                .left(inset: 45).centerY(to: captureButton.nui_centerY).sizeToFit().cornerRadius(byHalf: .height)
        }

        flipCameraButton.configureFrame { maker in
            let actualSize = flipCameraButton.sizeThatFits(view.bounds.size)
            maker.size(width: actualSize.width + 20, height: actualSize.height + 20)
                 .right(inset: 45).centerY(to: captureButton.nui_centerY).cornerRadius(byHalf: .height)
        }

        resultImageView.configureFrame { maker in
            maker.left().top(to: view.nui_safeArea.top, inset: 10).size(width: 100, height: 200)
        }

        let zoomLabelSize = zoomLabel.sizeThatFits(view.bounds.size)

        zoomLabelContainerView.configureFrame { maker in
            let side = max(zoomLabelSize.width, 38) + 4
            maker.centerX().bottom(to: captureButton.nui_top, inset: 24)
                .size(width: side, height: side).cornerRadius(byHalf: .height)
        }

        zoomLabel.configureFrame { maker in
            maker.center().sizeToFit()
        }

        zoomSlider.configureFrame { maker in
            maker.left(inset: 30).right(inset: 30).heightToFit().bottom(to: zoomLabelContainerView.nui_top, inset: 10)
        }
        zoomSlider.subviews.first?.frame = zoomSlider.bounds
    }

    // MARK: - Actions

    @objc private func captureButtonTouchedUp() {
        cameraService.capturePhoto { [weak self] pixelBuffer, orientation in
            guard let self = self,
                  let pixelBuffer = pixelBuffer,
                  let orientation = orientation,
                  let uiImageOrientation = UIImage.Orientation(rawValue: Int(orientation)) else {
                return
            }

            let ciImage = CIImage(cvPixelBuffer: pixelBuffer).oriented(.downMirrored)
            let context = CIContext()
            guard let cgImage = context.createCGImage(ciImage, from: .init(x: 0,
                                                                           y: 0,
                                                                           width: CVPixelBufferGetWidth(pixelBuffer),
                                                                           height: CVPixelBufferGetHeight(pixelBuffer))) else {
                return
            }
            let image = UIImage(cgImage: cgImage, scale: 1, orientation: uiImageOrientation)
            self.resultImageView.image = image
            self.delegate?.rCamViewController(self, imageCaptured: image)
        }
    }

    @objc private func torchCameraButtonPressed() {
        torchCameraButton.isSelected.toggle()
        if torchCameraButton.isSelected {
            cameraService.torchMode = .on
        }
        else {
            cameraService.torchMode = .off
        }
    }

    @objc private func flipCameraButtonPressed() {
        guard let cameraSnapshotView = cameraContainerView.snapshotView(afterScreenUpdates: true) else {
            return
        }

        cameraSnapshotView.frame = cameraContainerView.frame
        view.insertSubview(cameraSnapshotView, aboveSubview: cameraContainerView)
        cameraContainerView.isHidden = true

        let blurView = UIVisualEffectView(effect: nil)
        blurView.frame = view.bounds
        view.insertSubview(blurView, aboveSubview: cameraSnapshotView)

        UIView.animate(withDuration: 0.4, animations: {
            blurView.effect = UIBlurEffect(style: .prominent)
        }, completion: { _ in
            try? self.cameraService.flipCamera()
            UIView.animate(withDuration: 0.2, animations: {
                cameraSnapshotView.frame = self.cameraContainerView.frame
            }, completion: { _ in
                cameraSnapshotView.removeFromSuperview()
                blurView.removeFromSuperview()
                self.cameraContainerView.isHidden = false
            })
        })
    }

    // MARK: - Recognizers

    @objc private func videoViewTapped(recognizer: UITapGestureRecognizer) {
        let point = recognizer.location(in: cameraContainerView)

        focusView.bounds = .init(origin: .zero, size: .init(width: 100, height: 100))
        focusView.center = cameraContainerView.convert(point, to: view)
        view.addSubview(focusView)

        focusView.transform = .init(scaleX: 2, y: 2)
        UIView.animate(withDuration: 0.2, animations: {
            self.focusView.transform = .identity
        }, completion: nil)

        focusViewTimer?.invalidate()
        focusViewTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { [weak self] _ in
            UIView.animate(withDuration: 0.2, animations: {
                self?.focusView.alpha = 0
            }, completion: { _ in
                self?.focusView.removeFromSuperview()
                self?.focusView.alpha = 1
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
                zoomSlider.setValue(Float(scale), animated: true)
                updateZoomLevelLabel()
            default:
                break
        }
    }

    @objc private func zoomSliderValueChanged(_ slider: UISlider) {
        cameraService.zoomLevel = CGFloat(slider.value)
        updateZoomLevelLabel()
    }

    @objc private func flashModeButtonPressed() {
        let currentFlashMode = cameraService.flashMode.rawValue
        var newFlashMode = currentFlashMode + 1
        if newFlashMode > 2 {
            newFlashMode = 0
        }

        if let flashMode = AVCaptureDevice.FlashMode(rawValue: newFlashMode) {
            updateFlashModeIcon(for: flashMode)
            cameraService.flashMode = flashMode
        }
    }

    private func updateZoomLevelLabel() {
        guard let zoomLevel = cameraService.zoomLevel else {
            return
        }

        zoomLabel.text = String(format: "%.1f X", zoomLevel)
        view.setNeedsLayout()
        view.layoutIfNeeded()
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
        flashLightModeButton.setImage(UIImage(named: flashModeImageName), for: .normal)
    }

    private func cubicEaseIn<T: FloatingPoint>(_ x: T) -> T {
        x * x * x
    }

    private func deCubicEaseIn(_ x: CGFloat) -> CGFloat {
        pow(x, CGFloat(1) / CGFloat(3))
    }
}

// MARK: - UIGestureRecognizerDelegate

extension RCamViewController: UIGestureRecognizerDelegate {
    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                                  shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        true
    }
}
