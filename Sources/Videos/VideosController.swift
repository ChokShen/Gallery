import UIKit
import Photos
import AVKit
import MobileCoreServices

protocol VideosControllerDelegate: class {
    func didFinishRecordingdVideo( url: URL?)
}

class VideosController: UIViewController {

  lazy var gridView: GridView = self.makeGridView()
  lazy var videoBox: VideoBox = self.makeVideoBox()
  lazy var infoLabel: UILabel = self.makeInfoLabel()

  var items: [Video] = []
  let library = VideosLibrary()
  let once = Once()
  let cart: Cart
  weak var delegate: VideosControllerDelegate?

  // MARK: - Init

  public required init(cart: Cart) {
    self.cart = cart
    super.init(nibName: nil, bundle: nil)
  }

  public required init?(coder aDecoder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  // MARK: - Life cycle

  override func viewDidLoad() {
    super.viewDidLoad()

    setup()
  }

  // MARK: - Setup

  func setup() {
    view.backgroundColor = UIColor.white

    view.addSubview(gridView)

    [videoBox, infoLabel].forEach {
      gridView.bottomView.addSubview($0)
    }

    gridView.g_pinEdges()

    videoBox.g_pin(size: CGSize(width: 44, height: 44))
    videoBox.g_pin(on: .centerY)
    videoBox.g_pin(on: .left, constant: 38)

    infoLabel.g_pin(on: .centerY)
    infoLabel.g_pin(on: .left, view: videoBox, on: .right, constant: 11)
    infoLabel.g_pin(on: .right, constant: -50)

    gridView.closeButton.addTarget(self, action: #selector(closeButtonTouched(_:)), for: .touchUpInside)
    gridView.recordVideoButton.addTarget(self, action: #selector(recordVideoButtonTouched(_:)), for: .touchUpInside)
    gridView.doneButton.addTarget(self, action: #selector(doneButtonTouched(_:)), for: .touchUpInside)

    gridView.collectionView.dataSource = self
    gridView.collectionView.delegate = self
    gridView.collectionView.register(VideoCell.self, forCellWithReuseIdentifier: String(describing: VideoCell.self))

    gridView.arrowButton.updateText("Gallery.AllVideos".g_localize(fallback: "ALL VIDEOS"))
    gridView.arrowButton.arrow.isHidden = true
  }

  // MARK: - Action

  @objc func closeButtonTouched(_ button: UIButton) {
    EventHub.shared.close?()
  }
    
  // FIXME: 录制视频
  @objc func recordVideoButtonTouched(_ button: UIButton) {
    switch Permission.Camera.status {
    case .notDetermined:
        Permission.Camera.request {
            DispatchQueue.main.async {
                self.openCameraToRecord()
            }
        }
    case .authorized:
        openCameraToRecord()
    case .denied, .restricted:
        let alertVC = UIAlertController(title: "GalleryCamera.Permission.Alert.Title".g_localize(fallback: "Tips"), message: "GalleryCamera.Permission.Alert.Message".g_localize(fallback: "The camera permission is not enabled. Please open the switch in the system [Settings] > [Privacy] > [Camera] to open the camera function."), preferredStyle: .alert)
        let openAction = UIAlertAction(title: "GalleryCamera.Permission.Alert.Open".g_localize(fallback: "Open"), style: .default) { (alert) in
            UIApplication.shared.openURL(URL(string: UIApplication.openSettingsURLString)!)
        }
        let cancelAction = UIAlertAction(title: "GalleryCamera.Permission.Alert.Cancel".g_localize(fallback: "Cancel"), style: .cancel, handler: nil)
        alertVC.addAction(openAction)
        alertVC.addAction(cancelAction)
        present(alertVC, animated: true, completion: nil)
    }
  }
    
    private func openCameraToRecord() {
        let cameraVC = UIImagePickerController()
        cameraVC.sourceType = .camera
        cameraVC.mediaTypes = [(kUTTypeMovie as String)]
        cameraVC.videoMaximumDuration = 30
        cameraVC.videoQuality = .typeHigh
        cameraVC.cameraCaptureMode = .video
        cameraVC.delegate = self
        present(cameraVC, animated: true, completion: nil)
    }

  @objc func doneButtonTouched(_ button: UIButton) {
    EventHub.shared.doneWithVideos?()
  }

  // MARK: - View

  func refreshView() {
    if let selectedItem = cart.video {
      videoBox.imageView.g_loadImage(selectedItem.asset)
    } else {
      videoBox.imageView.image = nil
    }

    let hasVideo = (cart.video != nil)
    gridView.bottomView.g_fade(visible: hasVideo)
    gridView.collectionView.g_updateBottomInset(hasVideo ? gridView.bottomView.frame.size.height : 0)

    cart.video?.fetchDuration { [weak self] duration in
      self?.infoLabel.isHidden = duration <= Config.VideoEditor.maximumDuration
    }
  }

  // MARK: - Controls

  func makeGridView() -> GridView {
    let view = GridView()
    view.bottomView.alpha = 0
    view.recordVideoButton.isHidden = false
    return view
  }

  func makeVideoBox() -> VideoBox {
    let videoBox = VideoBox()
    videoBox.delegate = self

    return videoBox
  }

  func makeInfoLabel() -> UILabel {
    let label = UILabel()
    label.textColor = UIColor.white
    label.font = Config.Font.Text.regular.withSize(12)
    label.text = String(format: "Gallery.Videos.MaxiumDuration".g_localize(fallback: "FIRST %d SECONDS"),
                        (Int(Config.VideoEditor.maximumDuration)))

    return label
  }
}

extension VideosController: PageAware {

  func pageDidShow() {
    once.run {
      library.reload {
        self.gridView.loadingIndicator.stopAnimating()
        self.items = self.library.items
        self.gridView.collectionView.reloadData()
        self.gridView.emptyView.isHidden = !self.items.isEmpty
      }
    }
  }
}

extension VideosController: VideoBoxDelegate {

  func videoBoxDidTap(_ videoBox: VideoBox) {
    cart.video?.fetchPlayerItem { item in
      guard let item = item else { return }

      DispatchQueue.main.async {
        let controller = AVPlayerViewController()
        let player = AVPlayer(playerItem: item)
        controller.player = player

        self.present(controller, animated: true) {
          player.play()
        }
      }
    }
  }
}

extension VideosController: UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {

  // MARK: - UICollectionViewDataSource

  func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
    return items.count
  }

  func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {

    let cell = collectionView.dequeueReusableCell(withReuseIdentifier: String(describing: VideoCell.self), for: indexPath)
      as! VideoCell
    let item = items[(indexPath as NSIndexPath).item]

    cell.configure(item)
    cell.frameView.label.isHidden = true
    configureFrameView(cell, indexPath: indexPath)

    return cell
  }

  // MARK: - UICollectionViewDelegateFlowLayout

  func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {

    let size = (collectionView.bounds.size.width - (Config.Grid.Dimension.columnCount - 1) * Config.Grid.Dimension.cellSpacing)
      / Config.Grid.Dimension.columnCount
    return CGSize(width: size, height: size)
  }

  func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
    let item = items[(indexPath as NSIndexPath).item]

    if let selectedItem = cart.video , selectedItem == item {
      cart.video = nil
    } else {
      cart.video = item
    }

    refreshView()
    configureFrameViews()
  }

  func configureFrameViews() {
    for case let cell as VideoCell in gridView.collectionView.visibleCells {
      if let indexPath = gridView.collectionView.indexPath(for: cell) {
        configureFrameView(cell, indexPath: indexPath)
      }
    }
  }

  func configureFrameView(_ cell: VideoCell, indexPath: IndexPath) {
    let item = items[(indexPath as NSIndexPath).item]

    if let selectedItem = cart.video , selectedItem == item {
      cell.frameView.g_quickFade()
    } else {
      cell.frameView.alpha = 0
    }
  }
}


// MARK: - UIImagePickerControllerDelegate
extension VideosController: UIImagePickerControllerDelegate, UINavigationControllerDelegate{
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
        picker.dismiss(animated: true) {
            if let medieType = info[UIImagePickerController.InfoKey.mediaType] as? String {
                if medieType == (kUTTypeMovie as String) {
                    if let videoURL = info[UIImagePickerController.InfoKey.mediaURL] as? URL {
                        self.delegate?.didFinishRecordingdVideo(url: videoURL)
                    }
                }
            }
        }

    }
}
