//
//  TiImagecropModule.swift
//  titanium-image-crop
//
//  Created by Hans Knöchel
//  Copyright (c) 2019-present Hans Knöchel. All rights reserved.
//

import UIKit
import TitaniumKit

import TOCropViewController

@objc(TiImagecropModule)
class TiImagecropModule: TiModule {

  // MARK: Public constants
  
  @objc public let CropViewCroppingStyleDefault: Int = TOCropViewCroppingStyle.default.rawValue

  @objc public let CropViewCroppingStyleCircular: Int = TOCropViewCroppingStyle.circular.rawValue
    
  // MARK: Private config

  private var cropViewController: TOCropViewController?

  private var waitingToPresent = false

  func moduleGUID() -> String {
    return "0b0ea922-0b5a-493e-826b-596a54904a8c"
  }

  override func moduleId() -> String! {
    return "ti.imagecrop"
  }

  // MARK: Public APIs

  @objc(showCropDialog:)
  func showCropDialog(arguments: Array<Any>?) {
    // Titanium can invoke module methods from its JavaScript thread.
    DispatchQueue.main.async { [weak self] in
      self?.showCropDialogOnMainThread(arguments: arguments)
    }
  }

  private func showCropDialogOnMainThread(arguments: Array<Any>?) {
    // Validate basic usage
    guard let params = arguments?.first as? [String: Any], let image = params["image"] else {
      reportError("invalidImage", message: "No valid image provided")
      return
    }

    // List proxy properties
    let croppingStyle = params["croppingStyle"] as? String

    let aspectRatio = params["aspectRatio"]
    let aspectRatioLocked = params["aspectRatioLocked"] as? Bool ?? false
    let doneButtonTitle = params["doneButtonTitle"] ?? NSLocalizedString("done", comment: "done")
    let cancelButtonTitle = params["cancelButtonTitle"] ?? NSLocalizedString("cancel", comment: "done")

    if let existing = cropViewController {
      if !waitingToPresent && existing.presentingViewController == nil &&
         !existing.isBeingPresented && !existing.isBeingDismissed {
        // Recover if another controller dismissed the crop dialog externally.
        existing.delegate = nil
        cropViewController = nil
      } else {
        debugPrint("[WARN] ti.imagecrop: A crop dialog is already opening or open")
        return
      }
    }

    guard let nativeImage = TiUtils.image(image, proxy: self) else {
      reportError("invalidImage", message: "Could not load the supplied image")
      return
    }

    if croppingStyle == "circular" {
      cropViewController = TOCropViewController(croppingStyle: .circular, image: nativeImage)
    } else {
      cropViewController = TOCropViewController(croppingStyle: .default, image: nativeImage)
    }

    guard let cropViewController = cropViewController else { return }

    // Apply general config
    cropViewController.delegate = self
    cropViewController.doneButtonTitle = doneButtonTitle as? String
    cropViewController.cancelButtonTitle = cancelButtonTitle as? String
    
    // Handle aspect ratios
    if aspectRatioLocked {
      cropViewController.aspectRatioPreset = CGSize(width: 1, height: 1)
    }

    if let aspectRatio = aspectRatio {
      if let aspectRatio = aspectRatio as? [String: Int],
         let x = aspectRatio["x"], let y = aspectRatio["y"], x > 0, y > 0 {
        cropViewController.aspectRatioPreset = CGSize(width: x, height: y)
      } else {
        debugPrint("[ERROR] No valid aspect ratio provided!")
      }
    }

    if aspectRatioLocked {
      // Keep the selected ratio through resizing, reset, and image rotation.
      cropViewController.aspectRatioLockDimensionSwapEnabled = false
      cropViewController.resetAspectRatioEnabled = false
      cropViewController.aspectRatioLockEnabled = true
      cropViewController.aspectRatioPickerButtonHidden = true
    }

    waitingToPresent = true

    // A missing presenter or unfinished transition must not leave the module busy forever.
    DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self, weak cropViewController] in
      guard let self = self, let cropViewController = cropViewController,
            self.cropViewController === cropViewController, self.waitingToPresent else { return }
      self.failPresentation(cropViewController, message: "Timed out waiting for an attached presenter to finish its transition")
    }
    presentCropDialog(cropViewController)
  }

  private func presentCropDialog(_ cropViewController: TOCropViewController) {
    guard self.cropViewController === cropViewController, waitingToPresent else { return }

    guard let root = TiApp.controller(), let presenter = root.topPresentedController() else {
      retryPresentation(cropViewController)
      return
    }

    // Inspect the modal chain too: the top controller may already exclude a dismissing picker.
    var controllers = [UIViewController]()
    var current: UIViewController? = root
    while let controller = current {
      controllers.append(controller)
      current = controller.presentedViewController
    }
    current = presenter
    while let controller = current {
      if !controllers.contains(where: { $0 === controller }) {
        controllers.append(controller)
      }
      current = controller.parent
    }

    if let coordinator = controllers.compactMap({ $0.transitionCoordinator }).first {
      let joined = coordinator.animate(alongsideTransition: nil) { [weak self, weak cropViewController] _ in
        // Leave UIKit's completion callback before requesting another presentation.
        DispatchQueue.main.async {
          guard let cropViewController = cropViewController else { return }
          self?.presentCropDialog(cropViewController)
        }
      }
      if joined { return }
      retryPresentation(cropViewController)
      return
    }

    guard UIApplication.shared.applicationState == .active,
          presenter.viewIfLoaded?.window != nil,
          presenter.presentedViewController == nil,
          !controllers.contains(where: { $0.isBeingPresented || $0.isBeingDismissed }) else {
      retryPresentation(cropViewController)
      return
    }

    presenter.present(cropViewController, animated: true)
    waitingToPresent = false
    if cropViewController.presentingViewController == nil {
      failPresentation(cropViewController, message: "UIKit declined to present the crop dialog")
    }
  }

  private func retryPresentation(_ cropViewController: TOCropViewController) {
    // Poll only when UIKit has no transition coordinator to join. The timeout bounds the wait.
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self, weak cropViewController] in
      guard let cropViewController = cropViewController else { return }
      self?.presentCropDialog(cropViewController)
    }
  }

  private func failPresentation(_ cropViewController: TOCropViewController, message: String) {
    guard self.cropViewController === cropViewController else { return }
    cropViewController.delegate = nil
    self.cropViewController = nil
    waitingToPresent = false
    reportError("presentationFailed", message: message)
  }

  private func reportError(_ code: String, message: String) {
    debugPrint("[ERROR] ti.imagecrop: \(message)")
    fireEvent("error", with: ["code": code, "message": message])
  }

  private func dismissCropDialog(_ cropViewController: TOCropViewController) {
    guard self.cropViewController === cropViewController else { return }
    cropViewController.dismiss(animated: true) { [weak self] in
      guard let self = self, self.cropViewController === cropViewController else { return }
      cropViewController.delegate = nil
      self.cropViewController = nil
      self.waitingToPresent = false
      // A close listener may immediately request the next crop dialog.
      self.fireEvent("close")
    }
  }
}

// MARK: CropViewControllerDelegate

extension TiImagecropModule : TOCropViewControllerDelegate {

    func cropViewController(_ cropViewController: TOCropViewController, didCropTo image: UIImage, with cropRect: CGRect, angle: Int) {
    guard self.cropViewController === cropViewController else { return }
    guard let blob = TiBlob(image: image) else {
      reportError("invalidImage", message: "Could not create a blob from the cropped image")
      dismissCropDialog(cropViewController)
      return
    }

    self.fireEvent("done", with: ["image": blob, "cancel": false])

    dismissCropDialog(cropViewController)
  }

    func cropViewController(_ cropViewController: TOCropViewController, didCropToCircularImage image: UIImage, with cropRect: CGRect, angle: Int) {
      guard self.cropViewController === cropViewController else { return }
      guard let blob = TiBlob(image: image) else {
        reportError("invalidImage", message: "Could not create a blob from the cropped image")
        dismissCropDialog(cropViewController)
        return
      }

      self.fireEvent("done", with: ["image": blob, "cancel": false])

      dismissCropDialog(cropViewController)
    }

    
    
  func cropViewController(_ cropViewController: TOCropViewController, didFinishCancelled cancelled: Bool) {
    guard self.cropViewController === cropViewController else { return }
    self.fireEvent("done", with: ["cancel": true])

    dismissCropDialog(cropViewController)
  }
}
