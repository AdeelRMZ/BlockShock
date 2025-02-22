import SpriteKit
import UIKit
import GoogleMobileAds
import StoreKit
import FirebaseAnalytics
import UserMessagingPlatform

// MARK: - UIColor Extensions

extension UIColor {
    static let blockBlue = UIColor(red: 69/255, green: 138/255, blue: 255/255, alpha: 1.0)
    static let blockGreen = UIColor(red: 76/255, green: 187/255, blue: 23/255, alpha: 1.0)
    static let blockPurple = UIColor(red: 155/255, green: 89/255, blue: 182/255, alpha: 1.0)
    static let blockRed = UIColor(red: 231/255, green: 76/255, blue: 60/255, alpha: 1.0)
    static let blockOrange = UIColor(red: 243/255, green: 156/255, blue: 18/255, alpha: 1.0)
    static let blockLightBlue = UIColor(red: 52/255, green: 152/255, blue: 219/255, alpha: 1.0)
    static let blockYellow = UIColor(red: 241/255, green: 196/255, blue: 15/255, alpha: 1.0)
    static let blockDarkGreen = UIColor(red: 0/255, green: 80/255, blue: 157/255, alpha: 1.0)

    static let allCustomColors: [UIColor] = [
        blockGreen, blockPurple, blockRed, blockOrange, blockLightBlue, blockYellow, blockDarkGreen
    ]

    func adjusted(by percentage: CGFloat) -> UIColor {
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        if self.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha) {
            let newBrightness = min(max(brightness + percentage/100, 0.0), 1.0)
            return UIColor(hue: hue, saturation: saturation, brightness: newBrightness, alpha: alpha)
        }
        return self
    }

    func toHexString() -> String {
        guard let components = self.cgColor.components, components.count >= 3 else { return "#000000" }
        let r = components[0]
        let g = components[1]
        let b = components[2]
        return String(format: "#%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
    }

    convenience init?(hexString: String) {
        var hex = hexString
        if hex.hasPrefix("#") { hex.removeFirst() }
        guard hex.count == 6, let intCode = Int(hex, radix: 16) else { return nil }
        let red = CGFloat((intCode >> 16) & 0xFF) / 255.0
        let green = CGFloat((intCode >> 8) & 0xFF) / 255.0
        let blue = CGFloat(intCode & 0xFF) / 255.0
        self.init(red: red, green: green, blue: blue, alpha: 1.0)
    }
}

// MARK: - Saved Data Structures

struct SavedBlock: Codable {
    let row: Int
    let col: Int
    let color: String
}

struct SavedPiece: Codable {
    let baseIndex: Int
    let rotationIndex: Int
    let blockColor: String
    let originalSpawnPosition: CGPointCodable
    let displayScale: CGFloat
    let exceptionSpawn: Bool
    let isBlackSpawn: Bool
}

struct CGPointCodable: Codable {
    let x: CGFloat
    let y: CGFloat

    init(_ point: CGPoint) {
        self.x = point.x
        self.y = point.y
    }

    var point: CGPoint {
        return CGPoint(x: x, y: y)
    }
}

struct GameState: Codable {
    let score: Int
    let spawnCounter: Int
    let spawnThreshold: Int
    let blackSpawnCounter: Int
    let blackSpawnThreshold: Int
    let comboCounter: Int
    let reviveCount: Int
    let gridBlocks: [SavedBlock]
    let currentPiece: SavedPiece?
    let spawnOptions: [SavedPiece]
}

// MARK: - Tetromino Definitions

struct Offset: Codable, Hashable {
    let x: Int
    let y: Int
}

struct Tetromino: Codable, Equatable {
    let offsets: [Offset]
}

extension Tetromino {
    func normalized() -> Tetromino {
        let minX = offsets.map { $0.x }.min() ?? 0
        let minY = offsets.map { $0.y }.min() ?? 0
        let normalizedOffsets = offsets.map { Offset(x: $0.x - minX, y: $0.y - minY) }
        return Tetromino(offsets: normalizedOffsets)
    }

    func rotated90() -> Tetromino {
        let normalizedTetromino = normalized()
        let rotatedOffsets = normalizedTetromino.offsets.map { Offset(x: $0.y, y: -$0.x) }
        let minX = rotatedOffsets.map { $0.x }.min() ?? 0
        let minY = rotatedOffsets.map { $0.y }.min() ?? 0
        let normalizedRotatedOffsets = rotatedOffsets.map { Offset(x: $0.x - minX, y: $0.y - minY) }
        return Tetromino(offsets: normalizedRotatedOffsets)
    }

    var rotations: [Tetromino] {
        var result = [Tetromino]()
        var current = normalized()
        for _ in 0..<4 {
            if !result.contains(current) {
                result.append(current)
            }
            current = current.rotated90()
        }
        return result
    }
}

// MARK: - Helper: Draw Trapezoid

private func addTrapezoid(to node: SKNode, points: [CGPoint], fillColor: UIColor) {
    let path = CGMutablePath()
    guard let first = points.first else { return }
    path.move(to: first)
    for point in points.dropFirst() {
        path.addLine(to: point)
    }
    path.closeSubpath()
    let shape = SKShapeNode(path: path)
    shape.fillColor = fillColor
    shape.strokeColor = .clear
    node.addChild(shape)
}

// MARK: - SKNode Rotate Icon Extension

extension SKNode {
    func addRotateIcon(blockSize: CGFloat) {
        guard let isException = self.userData?["exceptionSpawn"] as? Bool, isException else { return }
        if childNode(withName: "rotateIcon") != nil { return }
        if let block = children.first(where: { $0.name != "shadow" }) {
            let rotateIcon = SKSpriteNode(imageNamed: "rotate.png")
            rotateIcon.name = "rotateIcon"
            rotateIcon.size = CGSize(width: blockSize * 0.8, height: blockSize * 0.8)
            rotateIcon.position = .zero
            rotateIcon.zPosition = 100
            block.addChild(rotateIcon)
        }
    }

    func removeRotateIcon() {
        childNode(withName: "rotateIcon")?.removeFromParent()
        for child in children {
            child.childNode(withName: "rotateIcon")?.removeFromParent()
        }
    }
}

// MARK: - GameOverPopupView

class GameOverPopupView: UIControl {
    var onRevive: (() -> Void)?
    var onRestart: (() -> Void)?

    let contentView = UIView()
    let scoreLabel = UILabel()
    let reviveButton = UIButton(type: .custom)
    let restartButton = UIButton(type: .custom)

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor.black.withAlphaComponent(0.5)
        setupContentView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        return true
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let contentPoint = contentView.convert(point, from: self)
        if contentView.bounds.contains(contentPoint) {
            return contentView.hitTest(contentPoint, with: event)
        }
        return self
    }

    private func setupContentView() {
        contentView.backgroundColor = UIColor(red: 0/255, green: 83/255, blue: 156/255, alpha: 1.0)
        contentView.layer.cornerRadius = 20
        contentView.layer.borderWidth = 4
        contentView.layer.borderColor = UIColor.blockLightBlue.cgColor
        addSubview(contentView)

        scoreLabel.text = "Score: 0"
        scoreLabel.font = UIFont.systemFont(ofSize: 24, weight: .medium)
        scoreLabel.textColor = .white
        scoreLabel.textAlignment = .center
        contentView.addSubview(scoreLabel)

        reviveButton.setTitle("Revive", for: .normal)
        reviveButton.setTitleColor(.white, for: .normal)
        reviveButton.titleLabel?.font = UIFont.systemFont(ofSize: 20, weight: .medium)
        reviveButton.backgroundColor = UIColor(red: 234/255, green: 176/255, blue: 66/255, alpha: 1.0)
        reviveButton.layer.cornerRadius = 10
        reviveButton.layer.shadowColor = UIColor.black.cgColor
        reviveButton.layer.shadowOpacity = 0.5
        reviveButton.layer.shadowOffset = CGSize(width: 2, height: 2)
        reviveButton.layer.shadowRadius = 3
        reviveButton.addTarget(self, action: #selector(reviveTapped), for: .touchUpInside)
        contentView.addSubview(reviveButton)

        restartButton.setTitle("Restart", for: .normal)
        restartButton.setTitleColor(.white, for: .normal)
        restartButton.titleLabel?.font = UIFont.systemFont(ofSize: 20, weight: .medium)
        restartButton.backgroundColor = UIColor(red: 234/255, green: 176/255, blue: 66/255, alpha: 1.0)
        restartButton.layer.cornerRadius = 10
        restartButton.layer.shadowColor = UIColor.black.cgColor
        restartButton.layer.shadowOpacity = 0.5
        restartButton.layer.shadowOffset = CGSize(width: 2, height: 2)
        restartButton.layer.shadowRadius = 3
        restartButton.addTarget(self, action: #selector(restartTapped), for: .touchUpInside)
        contentView.addSubview(restartButton)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let contentWidth = bounds.width * 0.8
        let contentHeight: CGFloat = 240
        contentView.frame = CGRect(x: (bounds.width - contentWidth) / 2,
                                   y: (bounds.height - contentHeight) / 2,
                                   width: contentWidth,
                                   height: contentHeight)
        let padding: CGFloat = 20
        scoreLabel.frame = CGRect(x: padding,
                                  y: padding,
                                  width: contentView.bounds.width - 2 * padding,
                                  height: 40)
        let buttonHeight: CGFloat = 40
        let spacing: CGFloat = 15
        let buttonWidth = contentView.bounds.width - 2 * padding
        reviveButton.frame = CGRect(x: padding,
                                    y: scoreLabel.frame.maxY + spacing,
                                    width: buttonWidth,
                                    height: buttonHeight)
        restartButton.frame = CGRect(x: padding,
                                     y: reviveButton.frame.maxY + spacing,
                                     width: buttonWidth,
                                     height: buttonHeight)
    }

    @objc private func reviveTapped() {
        UIView.animate(withDuration: 0.1, animations: {
            self.reviveButton.transform = CGAffineTransform(scaleX: 0.95, y: 0.95)
        }) { _ in
            UIView.animate(withDuration: 0.1, animations: {
                self.reviveButton.transform = .identity
            }) { _ in
                self.onRevive?()
            }
        }
    }

    @objc private func restartTapped() {
        UIView.animate(withDuration: 0.1, animations: {
            self.restartButton.transform = CGAffineTransform(scaleX: 0.95, y: 0.95)
        }) { _ in
            UIView.animate(withDuration: 0.1, animations: {
                self.restartButton.transform = .identity
            }) { _ in
                self.onRestart?()
                self.removeFromSuperview()
            }
        }
    }
}

// MARK: - SettingsPopupView

class SettingsPopupView: UIView {
    var onClose: (() -> Void)?
    var onSoundToggle: ((Bool) -> Void)?
    var onMusicToggle: ((Bool) -> Void)?
    var onRemoveAds: (() -> Void)?
    var onRestorePurchases: (() -> Void)?  // New closure for restore
    var onShowRatingPopup: (() -> Void)?
    var onContact: (() -> Void)?
    var onShare: (() -> Void)?

    let contentView = UIView()
    let soundSwitch = UISwitch()
    let musicSwitch = UISwitch()
    let removeAdsButton = UIButton(type: .custom)
    let shareButton = UIButton(type: .custom)

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor.black.withAlphaComponent(0.5)
        isUserInteractionEnabled = true
        setupContentView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }

    private func setupContentView() {
        contentView.backgroundColor = UIColor(red: 0/255, green:83/255, blue:156/255, alpha:1.0)
        contentView.layer.cornerRadius = 20
        contentView.layer.borderWidth = 4
        contentView.layer.borderColor = UIColor.blockLightBlue.cgColor
        addSubview(contentView)

        // Title label with app version
        let titleLabel = UILabel()
        titleLabel.tag = 111
        titleLabel.textAlignment = .center
        titleLabel.textColor = .white
        titleLabel.font = UIFont.systemFont(ofSize: 24, weight: .bold)
        if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
            titleLabel.text = "Block Shock \(version)"
        } else {
            titleLabel.text = "Block Shock 1.0"
        }
        contentView.addSubview(titleLabel)

        let closeButton = UIButton(type: .system)
        closeButton.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        closeButton.tintColor = .white
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        closeButton.tag = 100
        contentView.addSubview(closeButton)

        let soundIcon = UIImageView(image: UIImage(systemName: "speaker.wave.2.fill"))
        soundIcon.tintColor = .white
        soundIcon.tag = 101
        contentView.addSubview(soundIcon)

        let soundLabel = UILabel()
        soundLabel.text = "Sound"
        soundLabel.font = UIFont.systemFont(ofSize: 20, weight: .medium)
        soundLabel.textColor = .white
        soundLabel.tag = 102
        contentView.addSubview(soundLabel)

        soundSwitch.addTarget(self, action: #selector(soundSwitchChanged), for: .valueChanged)
        soundSwitch.tag = 103
        contentView.addSubview(soundSwitch)

        let musicIcon = UIImageView(image: UIImage(systemName: "music.note"))
        musicIcon.tintColor = .white
        musicIcon.tag = 104
        contentView.addSubview(musicIcon)

        let musicLabel = UILabel()
        musicLabel.text = "Music"
        musicLabel.font = UIFont.systemFont(ofSize: 20, weight: .medium)
        musicLabel.textColor = .white
        musicLabel.tag = 105
        contentView.addSubview(musicLabel)

        musicSwitch.addTarget(self, action: #selector(musicSwitchChanged), for: .valueChanged)
        musicSwitch.tag = 106
        contentView.addSubview(musicSwitch)

        let contactButton = UIButton(type: .custom)
        contactButton.setTitle("Contact", for: .normal)
        contactButton.setTitleColor(.white, for: .normal)
        contactButton.titleLabel?.font = UIFont.systemFont(ofSize: 20, weight: .medium)
        contactButton.backgroundColor = UIColor(red: 234/255, green:176/255, blue:66/255, alpha:1.0)
        contactButton.layer.cornerRadius = 10
        contactButton.layer.shadowColor = UIColor.black.cgColor
        contactButton.layer.shadowOpacity = 0.5
        contactButton.layer.shadowOffset = CGSize(width: 2, height: 2)
        contactButton.layer.shadowRadius = 3
        contactButton.addTarget(self, action: #selector(contactTapped(_:)), for: .touchUpInside)
        contactButton.tag = 109
        contentView.addSubview(contactButton)

        shareButton.setTitle("Share", for: .normal)
        shareButton.setTitleColor(.white, for: .normal)
        shareButton.titleLabel?.font = UIFont.systemFont(ofSize: 20, weight: .medium)
        shareButton.backgroundColor = UIColor(red: 234/255, green:176/255, blue:66/255, alpha:1.0)
        shareButton.layer.cornerRadius = 10
        shareButton.layer.shadowColor = UIColor.black.cgColor
        shareButton.layer.shadowOpacity = 0.5
        shareButton.layer.shadowOffset = CGSize(width: 2, height: 2)
        shareButton.layer.shadowRadius = 3
        shareButton.addTarget(self, action: #selector(shareTapped(_:)), for: .touchUpInside)
        shareButton.tag = 110 // Optional, if still needed elsewhere
        contentView.addSubview(shareButton)

        let rateButton = UIButton(type: .custom)
        rateButton.setTitle("Rate", for: .normal)
        rateButton.setTitleColor(.white, for: .normal)
        rateButton.titleLabel?.font = UIFont.systemFont(ofSize: 20, weight: .medium)
        rateButton.backgroundColor = UIColor(red: 234/255, green:176/255, blue:66/255, alpha:1.0)
        rateButton.layer.cornerRadius = 10
        rateButton.layer.shadowColor = UIColor.black.cgColor
        rateButton.layer.shadowOpacity = 0.5
        rateButton.layer.shadowOffset = CGSize(width: 2, height: 2)
        rateButton.layer.shadowRadius = 3
        rateButton.addTarget(self, action: #selector(rateTapped(_:)), for: .touchUpInside)
        rateButton.tag = 107
        contentView.addSubview(rateButton)

        let removeAdsButton = UIButton(type: .custom)
        removeAdsButton.setTitle("Remove Ads", for: .normal)
        removeAdsButton.setTitleColor(.white, for: .normal)
        removeAdsButton.titleLabel?.font = UIFont.systemFont(ofSize: 20, weight: .medium)
        removeAdsButton.backgroundColor = UIColor(red: 234/255, green:176/255, blue:66/255, alpha:1.0)
        removeAdsButton.layer.cornerRadius = 10
        removeAdsButton.layer.shadowColor = UIColor.black.cgColor
        removeAdsButton.layer.shadowOpacity = 0.5
        removeAdsButton.layer.shadowOffset = CGSize(width: 2, height: 2)
        removeAdsButton.layer.shadowRadius = 3
        removeAdsButton.addTarget(self, action: #selector(removeAdsTapped(_:)), for: .touchUpInside)
        removeAdsButton.tag = 108
        contentView.addSubview(removeAdsButton)

        let restoreButton = UIButton(type: .custom)
        restoreButton.setTitle("Restore", for: .normal)
        restoreButton.setTitleColor(.white, for: .normal)
        restoreButton.titleLabel?.font = UIFont.systemFont(ofSize: 20, weight: .medium)
        restoreButton.backgroundColor = UIColor(red: 234/255, green:176/255, blue:66/255, alpha:1.0)
        restoreButton.layer.cornerRadius = 10
        restoreButton.layer.shadowColor = UIColor.black.cgColor
        restoreButton.layer.shadowOpacity = 0.5
        restoreButton.layer.shadowOffset = CGSize(width: 2, height: 2)
        restoreButton.layer.shadowRadius = 3
        restoreButton.addTarget(self, action: #selector(restoreTapped(_:)), for: .touchUpInside)
        restoreButton.tag = 112
        restoreButton.isHidden = true  // Initially hidden
        contentView.addSubview(restoreButton)
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let contentPoint = contentView.convert(point, from: self)
        if contentView.bounds.contains(contentPoint) {
            return contentView.hitTest(contentPoint, with: event)
        }
        return self
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let contentWidth = bounds.width * 0.8
        let contentHeight: CGFloat = 350
        contentView.frame = CGRect(x: (bounds.width - contentWidth) / 2,
                                   y: (bounds.height - contentHeight) / 2,
                                   width: contentWidth,
                                   height: contentHeight)
        let iconSize: CGFloat = 30
        let padding: CGFloat = 20
        let spacing: CGFloat = 15

        if let titleLabel = contentView.viewWithTag(111) as? UILabel {
            titleLabel.frame = CGRect(x: 20, y: 10, width: contentView.bounds.width - 40, height: 30)
        }
        if let closeButton = contentView.viewWithTag(100) {
            closeButton.frame = CGRect(x: contentView.bounds.width - 40, y: 10, width: 30, height: 30)
        }
        if let soundIcon = contentView.viewWithTag(101) {
            soundIcon.frame = CGRect(x: padding, y: 60, width: iconSize, height: iconSize)
        }
        if let soundLabel = contentView.viewWithTag(102) {
            soundLabel.frame = CGRect(x: padding + iconSize + 10, y: 60, width: 100, height: iconSize)
        }
        if let sSwitch = contentView.viewWithTag(103) as? UISwitch {
            sSwitch.frame = CGRect(x: contentView.bounds.width - padding - sSwitch.intrinsicContentSize.width,
                                   y: 60,
                                   width: sSwitch.intrinsicContentSize.width,
                                   height: sSwitch.intrinsicContentSize.height)
        }
        if let musicIcon = contentView.viewWithTag(104) {
            musicIcon.frame = CGRect(x: padding, y: 110, width: iconSize, height: iconSize)
        }
        if let musicLabel = contentView.viewWithTag(105) {
            musicLabel.frame = CGRect(x: padding + iconSize + 10, y: 110, width: 100, height: iconSize)
        }
        if let mSwitch = contentView.viewWithTag(106) as? UISwitch {
            mSwitch.frame = CGRect(x: contentView.bounds.width - padding - mSwitch.intrinsicContentSize.width,
                                   y: 110,
                                   width: mSwitch.intrinsicContentSize.width,
                                   height: mSwitch.intrinsicContentSize.height)
        }
        if let contactButton = contentView.viewWithTag(109) {
            contactButton.frame = CGRect(x: padding,
                                         y: 160,
                                         width: contentView.bounds.width - (padding * 2),
                                         height: iconSize)
        }
        if let shareButton = contentView.viewWithTag(110) {
            shareButton.frame = CGRect(x: padding,
                                       y: 160 + iconSize + spacing,
                                       width: contentView.bounds.width - (padding * 2),
                                       height: iconSize)
        }
        if let rateButton = contentView.viewWithTag(107) {
            rateButton.frame = CGRect(x: padding,
                                      y: 160 + 2 * (iconSize + spacing),
                                      width: contentView.bounds.width - (padding * 2),
                                      height: iconSize)
        }
        if let removeAdsButton = contentView.viewWithTag(108) {
            removeAdsButton.frame = CGRect(x: padding,
                                           y: 160 + 3 * (iconSize + spacing),
                                           width: contentView.bounds.width - (padding * 2),
                                           height: iconSize)
        }
        if let restoreButton = contentView.viewWithTag(112) {
            restoreButton.frame = CGRect(x: padding,
                                         y: 160 + 3 * (iconSize + spacing),
                                         width: contentView.bounds.width - (padding * 2),
                                         height: iconSize)
        }
    }

    @objc private func restoreTapped(_ sender: UIButton) {
        UIView.animate(withDuration: 0.1, animations: {
            sender.transform = CGAffineTransform(scaleX: 0.95, y: 0.95)
        }) { _ in
            UIView.animate(withDuration: 0.1, animations: {
                sender.transform = .identity
            }) { _ in
                self.onRestorePurchases?()
            }
        }
    }

    @objc private func closeTapped() {
        onClose?()
    }

    @objc private func soundSwitchChanged() {
        onSoundToggle?(soundSwitch.isOn)
        UserDefaults.standard.set(soundSwitch.isOn, forKey: "isSoundEnabled")
    }

    @objc private func musicSwitchChanged() {
        onMusicToggle?(musicSwitch.isOn)
        UserDefaults.standard.set(musicSwitch.isOn, forKey: "isMusicEnabled")
    }

    @objc private func removeAdsTapped(_ sender: UIButton) {
        UIView.animate(withDuration: 0.1, animations: {
            sender.transform = CGAffineTransform(scaleX: 0.95, y: 0.95)
        }) { _ in
            UIView.animate(withDuration: 0.1, animations: {
                sender.transform = .identity
            }) { _ in
                self.onRemoveAds?()
            }
        }
    }

    @objc private func rateTapped(_ sender: UIButton) {
        UIView.animate(withDuration: 0.1, animations: {
            sender.transform = CGAffineTransform(scaleX: 0.95, y: 0.95)
        }) { _ in
            UIView.animate(withDuration: 0.1, animations: {
                sender.transform = .identity
            }) { _ in
                self.onShowRatingPopup?()
            }
        }
    }

    @objc private func contactTapped(_ sender: UIButton) {
        UIView.animate(withDuration: 0.1, animations: {
            sender.transform = CGAffineTransform(scaleX: 0.95, y: 0.95)
        }) { _ in
            UIView.animate(withDuration: 0.1, animations: {
                sender.transform = .identity
            }) { _ in
                self.onContact?()
            }
        }
    }

    @objc private func shareTapped(_ sender: UIButton) {
        UIView.animate(withDuration: 0.1, animations: {
            sender.transform = CGAffineTransform(scaleX: 0.95, y: 0.95)
        }) { _ in
            UIView.animate(withDuration: 0.1, animations: {
                sender.transform = .identity
            }) { _ in
                self.onShare?()
            }
        }
    }
}

// MARK: - RestartPopupView

class RestartPopupView: UIView {
    var onYes: (() -> Void)?
    var onNo: (() -> Void)?

    let contentView = UIView()
    let titleLabel = UILabel()
    let yesButton = UIButton(type: .custom)
    let noButton = UIButton(type: .custom)

    override init(frame: CGRect) {
        super.init(frame: frame)
        self.isUserInteractionEnabled = true
        self.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        setupContentView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        return true
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) { }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) { }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { }

    private func setupContentView() {
        contentView.backgroundColor = UIColor(red: 0/255, green:83/255, blue:156/255, alpha:1.0)
        contentView.layer.cornerRadius = 20
        contentView.layer.borderWidth = 4
        contentView.layer.borderColor = UIColor.blockLightBlue.cgColor
        addSubview(contentView)

        titleLabel.text = "Do you want to restart?"
        titleLabel.font = UIFont.systemFont(ofSize: 22, weight: .medium)
        titleLabel.textColor = .white
        titleLabel.textAlignment = .center
        contentView.addSubview(titleLabel)

        let commonBackground = UIColor(red: 234/255, green:176/255, blue:66/255, alpha:1.0)

        yesButton.setTitle("Yes", for: .normal)
        yesButton.setTitleColor(.white, for: .normal)
        yesButton.titleLabel?.font = UIFont.systemFont(ofSize: 20, weight: .medium)
        yesButton.backgroundColor = commonBackground
        yesButton.layer.cornerRadius = 10
        yesButton.layer.shadowColor = UIColor.black.cgColor
        yesButton.layer.shadowOpacity = 0.5
        yesButton.layer.shadowOffset = CGSize(width: 2, height: 2)
        yesButton.layer.shadowRadius = 3
        yesButton.addTarget(self, action: #selector(yesTapped), for: .touchUpInside)
        contentView.addSubview(yesButton)

        noButton.setTitle("No", for: .normal)
        noButton.setTitleColor(.white, for: .normal)
        noButton.titleLabel?.font = UIFont.systemFont(ofSize: 20, weight: .medium)
        noButton.backgroundColor = commonBackground
        noButton.layer.cornerRadius = 10
        noButton.layer.shadowColor = UIColor.black.cgColor
        noButton.layer.shadowOpacity = 0.5
        noButton.layer.shadowOffset = CGSize(width: 2, height: 2)
        noButton.layer.shadowRadius = 3
        noButton.addTarget(self, action: #selector(noTapped), for: .touchUpInside)
        contentView.addSubview(noButton)
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let contentPoint = contentView.convert(point, from: self)
        if contentView.bounds.contains(contentPoint) {
            return contentView.hitTest(contentPoint, with: event)
        }
        return self
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let contentWidth = bounds.width * 0.8
        let contentHeight: CGFloat = 150
        contentView.frame = CGRect(x: (bounds.width - contentWidth) / 2,
                                   y: (bounds.height - contentHeight) / 2,
                                   width: contentWidth,
                                   height: contentHeight)
        titleLabel.frame = CGRect(x: 20, y: 20, width: contentView.bounds.width - 40, height: 40)
        let buttonWidth = (contentView.bounds.width - 60) / 2
        let buttonHeight: CGFloat = 40
        yesButton.frame = CGRect(x: 20, y: contentView.bounds.height - buttonHeight - 20, width: buttonWidth, height: buttonHeight)
        noButton.frame = CGRect(x: yesButton.frame.maxX + 20, y: contentView.bounds.height - buttonHeight - 20, width: buttonWidth, height: buttonHeight)
    }

    @objc private func yesTapped() {
        UIView.animate(withDuration: 0.1, animations: {
            self.yesButton.transform = CGAffineTransform(scaleX: 0.95, y: 0.95)
        }) { _ in
            UIView.animate(withDuration: 0.1, animations: {
                self.yesButton.transform = .identity
            }) { _ in
                self.onYes?()
                self.removeFromSuperview()
            }
        }
    }

    @objc private func noTapped() {
        UIView.animate(withDuration: 0.1, animations: {
            self.noButton.transform = CGAffineTransform(scaleX: 0.95, y: 0.95)
        }) { _ in
            UIView.animate(withDuration: 0.1, animations: {
                self.noButton.transform = .identity
            }) { _ in
                self.onNo?()
                self.removeFromSuperview()
            }
        }
    }
}

// MARK: - SKProductsRequestDelegate

extension GameScene: SKProductsRequestDelegate {
    func productsRequest(_ request: SKProductsRequest, didReceive response: SKProductsResponse) {
        products = response.products
        if products.isEmpty {
            print("No products found")
        } else {
            print("Found \(products.count) products")
        }
    }
}

// MARK: - GameScene

class GameScene: SKScene, FullScreenContentDelegate, SKPaymentTransactionObserver {

    // MARK: - AdMob Interstitial Property
    private var interstitial: InterstitialAd?
    private var pendingAction: (() -> Void)?
    private var bannerView: BannerView?
    private var adsRemoved = UserDefaults.standard.bool(forKey: "adsRemoved") {
        didSet {
            UserDefaults.standard.set(adsRemoved, forKey: "adsRemoved")
            updateAdVisibility()
        }
    }

    // MARK: - IAP Properties
    private let productID = "com.blockshock.removeads" // Replace with your actual product ID
    private var products: [SKProduct] = []

    // MARK: - Persistent Background Music
    static var persistentBackgroundMusic: SKAudioNode?

    // MARK: - Game State & UI Nodes

    private var hasGameStarted = false
    private var isGameOver = false
    private var gameOverOverlay: SKNode?
    private var startButton: SKNode?
    private var scoreLabel: SKLabelNode?
    private var highScoreLabel: SKLabelNode?

    private var homeButton: SKSpriteNode?
    private var settingsButton: SKSpriteNode?

    private var homeButtonTouch: UITouch?
    private var settingsButtonTouch: UITouch?

    // MARK: - Settings Popup & Audio Toggles

    private var settingsPopupView: SettingsPopupView?
    private var isSoundEnabled: Bool = UserDefaults.standard.bool(forKey: "isSoundEnabled")
    private var isMusicEnabled: Bool = UserDefaults.standard.bool(forKey: "isMusicEnabled")

    // MARK: - Grid Properties

    private let numRows = 8, numColumns = 8
    private var blockSize: CGFloat = 40.0
    private var grid: [[SKNode?]] = []
    private var gridOrigin: CGPoint = .zero
    private var sizeMultiplier: CGFloat {
        return UIDevice.current.userInterfaceIdiom == .pad ? 2.0 : 1.0
    }

    private var gridOverlay: SKCropNode?

    // MARK: - Spawn Options & Current Piece

    private var spawnOptionPositions: [CGPoint] = []
    private var spawnOptions: [SKNode] = []
    private var currentPiece: SKNode?

    // MARK: - Projection & Drag Properties

    private let projectionOffset: CGFloat = 100.0
    private let spawnDragZPosition: CGFloat = 2500
    private var touchOffset: CGPoint?
    private var isProjected = false
    private var defaultTouchOffsetY: CGFloat = 0.0 // Store the initial Y offset

    // MARK: - Layout Constants

    private var safeBottom: CGFloat = 0.0, safeTop: CGFloat = 0.0
    private let gridMargin: CGFloat = 20.0

    // MARK: - Colors for Grid Area

    private let gridAreaColor = UIColor(red: 12/255, green: 45/255, blue: 72/255, alpha: 1.0)

    // MARK: - Highlight & Glow Nodes

    private var highlightNodes: [SKShapeNode] = []
    private var matchGlowNodes: [SKNode] = []
    private var currentGlowingCellIDs: Set<String> = Set()

    // MARK: - Tetromino Definitions

    private let tetrominoes: [Tetromino] = [
        Tetromino(offsets: [Offset(x: 0, y: 0), Offset(x: 1, y: 0), Offset(x: 2, y: 0), Offset(x: 3, y: 0)]),
        Tetromino(offsets: [Offset(x: 0, y: 0), Offset(x: 1, y: 0), Offset(x: 0, y: 1), Offset(x: 1, y: 1)]),
        Tetromino(offsets: [Offset(x: 0, y: 0), Offset(x: 1, y: 0), Offset(x: 2, y: 0), Offset(x: 1, y: 1)]),
        Tetromino(offsets: [Offset(x: 1, y: 0), Offset(x: 2, y: 0), Offset(x: 0, y: 1), Offset(x: 1, y: 1)]),
        Tetromino(offsets: [Offset(x: 0, y: 0), Offset(x: 1, y: 0), Offset(x: 1, y: 1), Offset(x: 2, y: 1)]),
        Tetromino(offsets: [Offset(x: 0, y: 0), Offset(x: 0, y: 1), Offset(x: 0, y: 2), Offset(x: 1, y: 2)]),
        Tetromino(offsets: [Offset(x: 1, y: 0), Offset(x: 1, y: 1), Offset(x: 1, y: 2), Offset(x: 0, y: 2)]),
        Tetromino(offsets: [Offset(x: 0, y: 0), Offset(x: 1, y: 0)]),
        Tetromino(offsets: [Offset(x: 0, y: 0), Offset(x: 0, y: 1)]),
        Tetromino(offsets: [Offset(x: 0, y: 0), Offset(x: 1, y: 0), Offset(x: 2, y: 0),
                            Offset(x: 0, y: 1), Offset(x: 1, y: 1), Offset(x: 2, y: 1),
                            Offset(x: 0, y: 2), Offset(x: 1, y: 2), Offset(x: 2, y: 2)]),
        Tetromino(offsets: [Offset(x: 0, y: 0)]),
        Tetromino(offsets: [Offset(x: 0, y: 0), Offset(x: 0, y: 1), Offset(x: 0, y: 2), Offset(x: 1, y: 2), Offset(x: 2, y: 2)]),
        Tetromino(offsets: [Offset(x: 0, y: 0), Offset(x: 0, y: 1), Offset(x: 1, y: 1)]),
        Tetromino(offsets: [Offset(x: 0, y: 0), Offset(x: 0, y: 1), Offset(x: 0, y: 2), Offset(x: 0, y: 3), Offset(x: 0, y: 4)]),
        Tetromino(offsets: [Offset(x: 0, y: 0), Offset(x: 1, y: 0), Offset(x: 0, y: 1), Offset(x: 1, y: 1), Offset(x: 0, y: 2), Offset(x: 1, y: 2)])
    ]

    // MARK: - Score & Combo

    private var score: Int = 0
    private var comboCounter: Int = 0

    // MARK: - Exception Spawn Properties

    private var exceptionSpawnNode: SKNode?
    private var exceptionSpawnInitialTouch: CGPoint?
    private var exceptionSpawnLongPressTimer: Timer?

    // MARK: - Spawn Counters

    private var spawnCounter: Int = 0
    private var spawnThreshold: Int = 0
    private var blackSpawnCounter: Int = 0
    private var blackSpawnThreshold: Int = 0

    // ★ New: Revive counter – only allow 3 revives per game session.
    private var reviveCount: Int = 0

    // MARK: - Spawn Metric

    private func isSquare(tetromino: Tetromino) -> Bool {
        let normalized = tetromino.normalized()
        let count = normalized.offsets.count
        if count == 1 { return true }
        let side = Int(sqrt(Double(count)))
        if side * side != count { return false }
        let xs = Set(normalized.offsets.map { $0.x })
        let ys = Set(normalized.offsets.map { $0.y })
        if xs.count != side || ys.count != side { return false }
        if let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() {
            return (maxX - minX + 1 == side) && (maxY - minY + 1 == side)
        }
        return false
    }

    // MARK: - Helper: Draw Tetromino Blocks

    private func drawTetromino(for piece: SKNode, with tetromino: Tetromino, color: UIColor) {
        piece.children.filter { $0.name != "shadow" }.forEach { $0.removeFromParent() }
        let offsets = tetromino.offsets
        let minX = offsets.map { $0.x }.min() ?? 0
        let maxX = offsets.map { $0.x }.max() ?? 0
        let minY = offsets.map { $0.y }.min() ?? 0
        let maxY = offsets.map { $0.y }.max() ?? 0
        let widthInBlocks = CGFloat(maxX - minX + 1)
        let heightInBlocks = CGFloat(maxY - minY + 1)
        let offsetX = widthInBlocks * blockSize / 2
        let offsetY = heightInBlocks * blockSize / 2
        for offset in offsets {
            let block = createCustomBlock(color: color, size: CGSize(width: blockSize, height: blockSize))
            let xPos = (CGFloat(offset.x - minX) * blockSize + blockSize/2) - offsetX
            let yPos = (CGFloat(offset.y - minY) * blockSize + blockSize/2) - offsetY
            block.position = CGPoint(x: xPos, y: yPos)
            piece.addChild(block)
        }
    }

    private func redrawPiece(_ piece: SKNode) {
        guard let baseIndex = piece.userData?["baseIndex"] as? Int,
              let rotationIndex = piece.userData?["rotationIndex"] as? Int,
              let color = piece.userData?["blockColor"] as? UIColor else { return }
        let baseTetromino = tetrominoes[baseIndex]
        let rotations = baseTetromino.rotations
        let newTetromino = rotations[rotationIndex]
        piece.zRotation = 0
        drawTetromino(for: piece, with: newTetromino, color: color)
        addShadow(to: piece)
        if let isException = piece.userData?["exceptionSpawn"] as? Bool, isException {
            piece.removeRotateIcon()
            piece.addRotateIcon(blockSize: blockSize)
        }
    }

    // MARK: - Exception Spawn Long Press Handler

    private func handleExceptionSpawnLongPress() {
        guard let exceptionNode = exceptionSpawnNode else { return }
        exceptionNode.removeRotateIcon()
        currentPiece = exceptionNode
        isProjected = false
        let scaleUp = SKAction.scale(to: 1.0, duration: 0.1)
        let moveUp = SKAction.moveBy(x: 0, y: projectionOffset, duration: 0.1)
        let groupAction = SKAction.group([scaleUp, moveUp])
        exceptionNode.run(groupAction) {
            self.isProjected = true
            if let initialTouch = self.exceptionSpawnInitialTouch {
                self.touchOffset = CGPoint(x: exceptionNode.position.x - initialTouch.x,
                                           y: exceptionNode.position.y - initialTouch.y)
            } else {
                self.touchOffset = .zero
            }
        }
        exceptionNode.zPosition = spawnDragZPosition
        exceptionNode.childNode(withName: "shadow")?.removeFromParent()
        if let index = spawnOptions.firstIndex(of: exceptionNode) {
            spawnOptions.remove(at: index)
        }
        exceptionSpawnLongPressTimer?.invalidate()
        exceptionSpawnLongPressTimer = nil
        exceptionSpawnNode = nil
    }

    // MARK: - Background Music

    private var backgroundMusic: SKAudioNode?

    private func setupBackgroundMusic() {
        if let music = GameScene.persistentBackgroundMusic {
            backgroundMusic = music
        } else if let musicURL = Bundle.main.url(forResource: "backgroundMusic", withExtension: "m4a") {
            let music = SKAudioNode(url: musicURL)
            music.autoplayLooped = true
            GameScene.persistentBackgroundMusic = music
            backgroundMusic = music
        }
        if let bgMusic = backgroundMusic, UserDefaults.standard.bool(forKey: "isMusicEnabled") {
            bgMusic.removeFromParent()
            addChild(bgMusic)
        }
        backgroundMusic?.isPaused = !UserDefaults.standard.bool(forKey: "isMusicEnabled")
    }

    @objc private func handleDidBecomeActive() {
        isSoundEnabled = UserDefaults.standard.bool(forKey: "isSoundEnabled")
        isMusicEnabled = UserDefaults.standard.bool(forKey: "isMusicEnabled")
        if isMusicEnabled {
            if let bgMusic = backgroundMusic {
                bgMusic.removeFromParent()
                bgMusic.isPaused = false
                addChild(bgMusic)
            }
        } else {
            backgroundMusic?.removeFromParent()
            backgroundMusic?.isPaused = true
        }
    }

    // MARK: - Saving and Restoring Game State

    @objc private func saveGameState() {
        guard hasGameStarted && !isGameOver else {
            deleteSavedGameState()
            return
        }
        var savedGridBlocks: [SavedBlock] = []
        for row in 0..<numRows {
            for col in 0..<numColumns {
                if let block = grid[row][col], let color = block.userData?["blockColor"] as? UIColor {
                    let hex = color.toHexString()
                    savedGridBlocks.append(SavedBlock(row: row, col: col, color: hex))
                }
            }
        }
        var savedCurrentPiece: SavedPiece? = nil
        if let piece = currentPiece, let saved = createSavedPiece(from: piece) {
            savedCurrentPiece = saved
        }
        var savedSpawnOptions: [SavedPiece] = []
        for piece in spawnOptions {
            if let saved = createSavedPiece(from: piece) {
                savedSpawnOptions.append(saved)
            }
        }
        let state = GameState(score: score,
                              spawnCounter: spawnCounter,
                              spawnThreshold: spawnThreshold,
                              blackSpawnCounter: blackSpawnCounter,
                              blackSpawnThreshold: blackSpawnThreshold,
                              comboCounter: comboCounter,
                              reviveCount: reviveCount,
                              gridBlocks: savedGridBlocks,
                              currentPiece: savedCurrentPiece,
                              spawnOptions: savedSpawnOptions)
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(state) {
            let url = getSavedGameURL()
            try? data.write(to: url)
        }
    }

    private func loadGameState() -> GameState? {
        let url = getSavedGameURL()
        if let data = try? Data(contentsOf: url) {
            let decoder = JSONDecoder()
            if let state = try? decoder.decode(GameState.self, from: data) {
                return state
            }
        }
        return nil
    }

    private func deleteSavedGameState() {
        let url = getSavedGameURL()
        try? FileManager.default.removeItem(at: url)
    }

    private func getSavedGameURL() -> URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return paths[0].appendingPathComponent("savedGame.json")
    }

    private func resumeGame(from state: GameState) {
        isSoundEnabled = UserDefaults.standard.bool(forKey: "isSoundEnabled")
        hasGameStarted = true
        score = state.score
        spawnCounter = state.spawnCounter
        spawnThreshold = state.spawnThreshold
        blackSpawnCounter = state.blackSpawnCounter
        blackSpawnThreshold = state.blackSpawnThreshold
        comboCounter = state.comboCounter
        reviveCount = state.reviveCount
        updateScoreLabel()

        grid = Array(repeating: Array(repeating: nil, count: numColumns), count: numRows)
        // Adjust grid origin using the banner height (defaulting to 50 if not set)
        let bannerHeight = bannerView?.frame.height ?? 50
        let bottomOffset = safeBottom + bannerHeight

        // Adjust grid width based on device type
        var gridWidth: CGFloat
        if UIDevice.current.userInterfaceIdiom == .pad {
            gridWidth = self.size.width * 0.75 // 3/4th of the screen width on iPad
        } else {
            gridWidth = self.size.width - (2 * gridMargin) // Existing calculation for non-iPad
        }

        blockSize = gridWidth / CGFloat(numColumns)
        let gridHeight = blockSize * CGFloat(numRows)
        let leftover = self.size.height - bottomOffset - gridHeight
        gridOrigin = CGPoint(x: (self.size.width - gridWidth) / 2, y: bottomOffset + leftover/2) // Center the grid on iPad
        setupScoreLabel()
        setupOrUpdateGridOverlay(gridWidth: gridWidth, gridHeight: gridHeight)

        let gap = gridOrigin.y - bottomOffset
        let spawnCenterY = bottomOffset + gap/2
        spawnOptionPositions = [
            CGPoint(x: gridOrigin.x + (gridWidth * 1/6), y: spawnCenterY),
            CGPoint(x: gridOrigin.x + (gridWidth * 3/6), y: spawnCenterY),
            CGPoint(x: gridOrigin.x + (gridWidth * 5/6), y: spawnCenterY)
        ]
        setupGridBackground(gridWidth: gridWidth, gridHeight: gridHeight)
        drawGridLines(gridWidth: gridWidth, gridHeight: gridHeight)
        addGridBorder(gridWidth: gridWidth, gridHeight: gridHeight)

        for savedBlock in state.gridBlocks {
            let pos = positionForGrid(row: savedBlock.row, col: savedBlock.col)
            if let color = UIColor(hexString: savedBlock.color) {
                let block = createCustomBlock(color: color, size: CGSize(width: blockSize, height: blockSize))
                block.position = pos
                block.zPosition = 3
                addChild(block)
                grid[savedBlock.row][savedBlock.col] = block
            }
        }

        if let savedPiece = state.currentPiece {
            currentPiece = restorePiece(from: savedPiece)
            currentPiece?.zPosition = spawnDragZPosition
            if let piece = currentPiece {
                addChild(piece)
            }
        }

        spawnOptions.forEach { $0.removeFromParent() }
        spawnOptions.removeAll()
        for savedPiece in state.spawnOptions {
            let piece = restorePiece(from: savedPiece)
            piece.setScale(savedPiece.displayScale)
            addChild(piece)
            spawnOptions.append(piece)
        }
        setupHomeButton()
        setupSettingsButton()
    }

    private func createSavedPiece(from piece: SKNode) -> SavedPiece? {
        let isBlackSpawn = piece.userData?["isBlackSpawn"] as? NSNumber ?? 0
        if isBlackSpawn.boolValue {
            guard let displayScale = piece.userData?["displayScale"] as? CGFloat,
                  let origVal = piece.userData?["originalSpawnPosition"] as? NSValue else { return nil }
            return SavedPiece(baseIndex: 0,
                              rotationIndex: 0,
                              blockColor: UIColor.black.toHexString(),
                              originalSpawnPosition: CGPointCodable(origVal.cgPointValue),
                              displayScale: displayScale,
                              exceptionSpawn: false,
                              isBlackSpawn: true)
        }
        guard let baseIndex = piece.userData?["baseIndex"] as? Int,
              let rotationIndex = piece.userData?["rotationIndex"] as? Int,
              let color = piece.userData?["blockColor"] as? UIColor,
              let origVal = piece.userData?["originalSpawnPosition"] as? NSValue,
              let displayScale = piece.userData?["displayScale"] as? CGFloat else { return nil }
        let origPos = origVal.cgPointValue
        let isException = piece.userData?["exceptionSpawn"] as? Bool ?? false
        return SavedPiece(baseIndex: baseIndex,
                          rotationIndex: rotationIndex,
                          blockColor: color.toHexString(),
                          originalSpawnPosition: CGPointCodable(origPos),
                          displayScale: displayScale,
                          exceptionSpawn: isException,
                          isBlackSpawn: false)
    }

    private func restorePiece(from savedPiece: SavedPiece) -> SKNode {
        if savedPiece.isBlackSpawn {
            let piece = createBlackSpawnPiece()
            piece.position = savedPiece.originalSpawnPosition.point
            piece.setScale(savedPiece.displayScale)
            piece.userData?["originalSpawnPosition"] = NSValue(cgPoint: savedPiece.originalSpawnPosition.point)
            addShadow(to: piece)
            runMagicAppearance(for: piece)
            return piece
        }
        let piece = SKNode()
        piece.name = "piece"
        piece.userData = NSMutableDictionary()
        piece.userData?["baseIndex"] = savedPiece.baseIndex
        piece.userData?["rotationIndex"] = savedPiece.rotationIndex
        if let color = UIColor(hexString: savedPiece.blockColor) {
            piece.userData?["blockColor"] = color
        }
        piece.userData?["originalSpawnPosition"] = NSValue(cgPoint: savedPiece.originalSpawnPosition.point)
        piece.userData?["displayScale"] = savedPiece.displayScale
        piece.userData?["exceptionSpawn"] = savedPiece.exceptionSpawn
        let baseTetromino = tetrominoes[savedPiece.baseIndex]
        let rotations = baseTetromino.rotations
        let newTetromino = rotations[savedPiece.rotationIndex]
        piece.zRotation = 0
        drawTetromino(for: piece, with: newTetromino, color: (piece.userData?["blockColor"] as! UIColor))
        addShadow(to: piece)
        if savedPiece.exceptionSpawn {
            piece.removeRotateIcon()
            piece.addRotateIcon(blockSize: blockSize)
        }
        piece.position = savedPiece.originalSpawnPosition.point
        return piece
    }

    // MARK: - Lifecycle

    func requestConsent() {
        // Set up UMP parameters
        let parameters = UMPRequestParameters()
        parameters.tagForUnderAgeOfConsent = false // Set to true if targeting kids

        // Optional: Debug settings for testing
#if DEBUG
        let debugSettings = UMPDebugSettings()
        debugSettings.testDeviceIdentifiers = ["F5399463-C348-40A5-9B00-808BA2326787"] // See note below
        debugSettings.geography = .EEA // Force EEA behavior
        parameters.debugSettings = debugSettings
#endif

        // Request consent info update
        UMPConsentInformation.sharedInstance.requestConsentInfoUpdate(with: parameters) { error in
            guard error == nil else {
                print("Consent info update failed: \(error?.localizedDescription ?? "")")
                return
            }

            // Load the consent form
            UMPConsentForm.load { [weak self] form, error in
                guard error == nil else {
                    print("Failed to load consent form: \(error?.localizedDescription ?? "")")
                    return
                }

                // Present the consent form if required
                if UMPConsentInformation.sharedInstance.consentStatus == .required {
                    form?.present(from: self?.view?.window?.windowScene?.windows.first!.rootViewController!) { error in
                        guard error == nil else {
                            print("Failed to present consent form: \(error?.localizedDescription ?? "")")
                            return
                        }
                        self?.loadAdsIfAllowed()
                    }
                } else {
                    // Consent not required (e.g., non-EEA user)
                    self?.loadAdsIfAllowed()
                }
            }
        }
    }

    var adSConsentGranted: Bool = false

    func loadAdsIfAllowed() {
        if UMPConsentInformation.sharedInstance.canRequestAds {
            print("Consent granted or not required, loading ads...")
            adSConsentGranted = true
            updateAdVisibility()
            // Call your ad-loading functions here
            // loadBannerAd()
            // loadInterstitialAd()
        } else {
            print("Consent denied or not obtained, skipping ads.")
            // Handle no-ads scenario (e.g., show a message)
            adSConsentGranted = false
        }
    }

    override func didMove(to view: SKView) {
        // Request UMP consent
        requestConsent()

        UserDefaults.standard.register(defaults: ["isSoundEnabled": true, "isMusicEnabled": true, "adsRemoved": false])
        isSoundEnabled = UserDefaults.standard.bool(forKey: "isSoundEnabled")
        isMusicEnabled = UserDefaults.standard.bool(forKey: "isMusicEnabled")
        adsRemoved = UserDefaults.standard.bool(forKey: "adsRemoved") // Set before ad logic

        SKPaymentQueue.default().add(self) // Add payment observer

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.size = view.bounds.size
            self.anchorPoint = .zero
            self.backgroundColor = UIColor(red: 0/255, green:83/255, blue:156/255, alpha:1.0)
            self.safeBottom = view.safeAreaInsets.bottom
            self.safeTop = view.safeAreaInsets.top + 20
            if view.safeAreaInsets.top > 20 {
                self.safeTop -= 20
            }

            //            self.setupBannerAd()
            self.requestProducts()
            self.setupHighScoreLabel()
            if GameScene.persistentBackgroundMusic == nil {
                self.setupBackgroundMusic()
            } else {
                self.backgroundMusic = GameScene.persistentBackgroundMusic
                if UserDefaults.standard.bool(forKey: "isMusicEnabled") {
                    self.backgroundMusic?.removeFromParent()
                    self.addChild(self.backgroundMusic!)
                    self.backgroundMusic?.isPaused = false
                } else {
                    self.backgroundMusic?.removeFromParent()
                    self.backgroundMusic?.isPaused = true
                }
            }
            self.backgroundMusic?.isPaused = !UserDefaults.standard.bool(forKey: "isMusicEnabled")
            NotificationCenter.default.addObserver(self, selector: #selector(self.saveGameState), name: UIApplication.willResignActiveNotification, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(self.handleDidBecomeActive), name: UIApplication.didBecomeActiveNotification, object: nil)
            self.startGame()
        }
    }

    deinit {
        SKPaymentQueue.default().remove(self)
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Ad Setup

    private func setupBannerAd() {
        guard adSConsentGranted else { return }
        guard !adsRemoved else {
            bannerView?.removeFromSuperview()
            bannerView = nil
            return
        }
        guard bannerView == nil else { return }
        bannerView = BannerView(adSize: AdSizeBanner)
        if let bannerView = bannerView {
            // Test Ad Unit ID ca-app-pub-3940256099942544/2934735716
            // Real Ad Unit ID ca-app-pub-3940256099942544/2435281174
            bannerView.adUnitID = "ca-app-pub-3940256099942544/2435281174" // Test ID
            bannerView.rootViewController = view?.window?.rootViewController
            bannerView.translatesAutoresizingMaskIntoConstraints = false
            view?.addSubview(bannerView)
            NSLayoutConstraint.activate([
                bannerView.bottomAnchor.constraint(equalTo: view!.safeAreaLayoutGuide.bottomAnchor),
                bannerView.centerXAnchor.constraint(equalTo: view!.centerXAnchor)
            ])
            bannerView.load(Request())
        }
    }

    private func updateAdVisibility() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            if self.adsRemoved {
                // Remove banner from superview and nil out the reference
                if let banner = self.bannerView {
                    banner.removeFromSuperview()
                    // Verify removal
                    if banner.superview != nil {
                        print("Warning: BannerView still has a superview after removal!")
                    }
                    self.bannerView = nil
                }
                self.interstitial = nil

                // Update settings popup buttons
                if let settingsPopup = self.settingsPopupView {
                    if let removeAdsBtn = settingsPopup.contentView.viewWithTag(108) as? UIButton,
                       let restoreBtn = settingsPopup.contentView.viewWithTag(112) as? UIButton {
                        removeAdsBtn.isHidden = true
                        restoreBtn.isHidden = false
                    }
                }

                // Force layout update
                self.view?.setNeedsLayout()
                self.view?.layoutIfNeeded()
            } else {
                // Only set up ads if they aren’t already present
                if self.bannerView == nil {
                    self.setupBannerAd()
                }
                self.loadInterstitialAd()

                // Update settings popup buttons
                if let settingsPopup = self.settingsPopupView {
                    if let removeAdsBtn = settingsPopup.contentView.viewWithTag(108) as? UIButton,
                       let restoreBtn = settingsPopup.contentView.viewWithTag(112) as? UIButton {
                        removeAdsBtn.isHidden = false
                        restoreBtn.isHidden = true
                    }
                }
            }
        }
    }

    // MARK: - StoreKit Integration

    private func requestProducts() {
        let request = SKProductsRequest(productIdentifiers: Set([productID]))
        request.delegate = self
        request.start()
    }

    private func purchaseRemoveAds() {
        Analytics.logEvent("remove_ads_purhcase_button_tapped", parameters: nil)
        guard let product = products.first(where: { $0.productIdentifier == productID }) else {
            Analytics.logEvent("remove_ads_purhcase_button_tapped_error", parameters: ["error": "product not found"])
            print("Product not found")
            return
        }
        let payment = SKPayment(product: product)
        SKPaymentQueue.default().add(payment)
    }

    private func restorePurchases() {
        SKPaymentQueue.default().restoreCompletedTransactions()
    }

    // MARK: - SKPaymentTransactionObserver

    func paymentQueue(_ queue: SKPaymentQueue, updatedTransactions transactions: [SKPaymentTransaction]) {
        for transaction in transactions {
            switch transaction.transactionState {
            case .purchased:
                Analytics.logEvent("remove_ads_purhcased", parameters: nil)
                completeTransaction(transaction)
            case .restored:
                Analytics.logEvent("remove_ads_restored", parameters: nil)
                restoreTransaction(transaction)
            case .failed:
                Analytics.logEvent("remove_ads_falied", parameters: nil)
                failTransaction(transaction)
            case .purchasing, .deferred:
                break
            @unknown default:
                break
            }
        }
    }

    // In GameScene class, update the completeTransaction method
    private func completeTransaction(_ transaction: SKPaymentTransaction) {
        if transaction.payment.productIdentifier == productID {
            adsRemoved = true
            updateAdVisibility() // Ensure this is called after setting adsRemoved
            SKPaymentQueue.default().finishTransaction(transaction)
            updateSettingsPopupButtons()
        }
    }

    // In GameScene class, update the restoreTransaction method
    private func restoreTransaction(_ transaction: SKPaymentTransaction) {
        if transaction.payment.productIdentifier == productID {
            adsRemoved = true
            updateAdVisibility() // Ensure this is called after setting adsRemoved
        }
        SKPaymentQueue.default().finishTransaction(transaction)
        updateSettingsPopupButtons()
    }

    private func failTransaction(_ transaction: SKPaymentTransaction) {
        if let error = transaction.error as NSError?, error.code != SKError.paymentCancelled.rawValue {
            print("Transaction Error: \(error.localizedDescription)")
        }
        SKPaymentQueue.default().finishTransaction(transaction)
    }

    private func updateSettingsPopupButtons() {
        if let popup = settingsPopupView {
            if let removeAdsBtn = popup.contentView.viewWithTag(108) as? UIButton,
               let restoreBtn = popup.contentView.viewWithTag(112) as? UIButton {
                removeAdsBtn.isHidden = adsRemoved
                restoreBtn.isHidden = !adsRemoved
            }
        }
    }

    // MARK: - Settings Popup (Updated)

    private func openSettings() {
        Analytics.logEvent("settings_button_tapped", parameters: nil)
        guard let view = self.view else { return }
        playClickSound()
        let popup = SettingsPopupView(frame: view.bounds)
        let storedSound = UserDefaults.standard.object(forKey: "isSoundEnabled") as? Bool ?? true
        let storedMusic = UserDefaults.standard.object(forKey: "isMusicEnabled") as? Bool ?? true
        popup.soundSwitch.isOn = storedSound
        popup.musicSwitch.isOn = storedMusic
        isSoundEnabled = storedSound
        isMusicEnabled = storedMusic

        // Set initial button visibility based on purchase status
        if let removeAdsBtn = popup.contentView.viewWithTag(108) as? UIButton,
           let restoreBtn = popup.contentView.viewWithTag(112) as? UIButton {
            removeAdsBtn.isHidden = adsRemoved
            restoreBtn.isHidden = !adsRemoved
        }

        popup.onClose = { [weak self, weak popup] in
            Analytics.logEvent("close_button_tapped", parameters: nil)
            self?.playClickSound()
            popup?.removeFromSuperview()
            self?.settingsPopupView = nil
        }
        popup.onSoundToggle = { [weak self] isOn in
            Analytics.logEvent("sound_button_tapped", parameters: ["isOn": isOn ? "true" : "false"])
            self?.playClickSound()
            self?.isSoundEnabled = isOn
            UserDefaults.standard.set(isOn, forKey: "isSoundEnabled")
        }
        popup.onMusicToggle = { [weak self] isOn in
            Analytics.logEvent("music_button_tapped", parameters: ["isOn": isOn ? "true" : "false"])
            self?.playClickSound()
            guard let self = self else { return }
            self.isMusicEnabled = isOn
            UserDefaults.standard.set(isOn, forKey: "isMusicEnabled")
            if isOn {
                if let bgMusic = self.backgroundMusic {
                    bgMusic.removeFromParent()
                    bgMusic.isPaused = false
                    self.addChild(bgMusic)
                }
            } else {
                self.backgroundMusic?.removeFromParent()
                self.backgroundMusic?.isPaused = true
            }
        }
        popup.onRemoveAds = { [weak self] in
            self?.playClickSound()
            self?.purchaseRemoveAds()
        }
        popup.onRestorePurchases = { [weak self] in
            Analytics.logEvent("restore_purchase_button_tapped", parameters: nil)
            self?.playClickSound()
            self?.restorePurchases()
        }
        popup.onShowRatingPopup = { [weak self] in
            Analytics.logEvent("show_rating_button_tapped", parameters: nil)
            self?.playClickSound()
            self?.showRatingPopup()
        }
        popup.onContact = { [weak self] in
            Analytics.logEvent("contact_button_tapped", parameters: nil)
            self?.playClickSound()
            if let url = URL(string: "mailto:block.shock.app@gmail.com?subject=Block%20Shock%20Support") {
                UIApplication.shared.open(url, options: [:], completionHandler: nil)
            }
        }
        popup.onShare = { [weak self] in
            Analytics.logEvent("share_button_tapped", parameters: nil)
            self?.playClickSound()
            let appLink = "https://apps.apple.com/app/id6742162544" // Replace with your app link
            guard let url = URL(string: appLink) else { return }
            let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)

            if let topVC = self?.view?.window?.windowScene?.windows.first!.rootViewController {
                // Configure for iPad
                if UIDevice.current.userInterfaceIdiom == .pad {
                    activityVC.popoverPresentationController?.sourceView = popup.shareButton // Anchor to the Share button
                    activityVC.popoverPresentationController?.sourceRect = popup.shareButton.bounds
                    activityVC.popoverPresentationController?.permittedArrowDirections = [.up, .down] // Adjust as needed
                }
                topVC.present(activityVC, animated: true, completion: nil)
            }
        }
        view.addSubview(popup)
        self.settingsPopupView = popup
    }

    // MARK: - Interstitial Loading
    func loadInterstitialAd() {
        guard adSConsentGranted else { return }
        Analytics.logEvent("load_interstitial_ad", parameters: nil)
        guard !adsRemoved else {
            interstitial = nil // Clear interstitial if ads are removed
            return
        }
        let request = Request()
        // Test Ad Unit ID "ca-app-pub-3940256099942544/4411468910"
        // Real Ad Unit ID "ca-app-pub-7707550266135905/3209485830"
        InterstitialAd.load(with: "ca-app-pub-7707550266135905/3209485830",
                            request: request) { [weak self] ad, error in
            guard let self = self else { return }
            if let error = error {
                Analytics.logEvent("load_interstitial_ad_error", parameters: ["error": error.localizedDescription])
                print("Failed to load interstitial ad: \(error.localizedDescription)")
                return
            }
            Analytics.logEvent("load_interstitial_ad_success", parameters: nil)
            if !self.adsRemoved { // Double-check before assigning
                self.interstitial = ad
                self.interstitial?.fullScreenContentDelegate = self
            }
        }
    }

    // MARK: - GADFullScreenContentDelegate Methods

    func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        Analytics.logEvent("interstitial_ad_dismissed", parameters: nil)
        resumeBackgroundMusic() // Resume music after ad dismissal
        if !adsRemoved {
            loadInterstitialAd()
        }
        guard let action = pendingAction else {
            resetGame()
            return
        }
        action()
        pendingAction = nil
    }

    func ad(_ ad: FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        Analytics.logEvent("interstitial_ad_failed_to_present", parameters: ["error": error.localizedDescription])
        resetGame()
        if !adsRemoved { // Only reload if ads are not removed
            loadInterstitialAd()
        }
    }

    // MARK: - High Score & Score Labels

    private func setupHighScoreLabel() {
        let savedHighScore = UserDefaults.standard.integer(forKey: "highScore")
        let trophyTexture = SKTexture(imageNamed: "trophy2d")
        let baseIconSize: CGFloat = 40 // Base size for non-iPad
        let iconSize = CGSize(width: baseIconSize * sizeMultiplier, height: baseIconSize * sizeMultiplier)
        let trophyIcon = SKSpriteNode(texture: trophyTexture)
        trophyIcon.size = iconSize
        let scoreText = "\(savedHighScore)"
        let scoreLabelNode = SKLabelNode(text: scoreText)
        scoreLabelNode.fontName = "Futura-Medium"
        scoreLabelNode.fontSize = 20 * sizeMultiplier // Scale font size
        scoreLabelNode.fontColor = UIColor(red: 1.0, green: 0.84, blue: 0.0, alpha: 1.0)
        scoreLabelNode.verticalAlignmentMode = .center
        scoreLabelNode.horizontalAlignmentMode = .center
        let gap: CGFloat = 10.0 * sizeMultiplier // Scale gap
        let totalWidth = trophyIcon.size.width + gap + scoreLabelNode.frame.width
        trophyIcon.position = CGPoint(x: -totalWidth / 2 + trophyIcon.size.width / 2, y: 0)
        scoreLabelNode.position = CGPoint(x: trophyIcon.position.x + trophyIcon.size.width / 2 + gap + scoreLabelNode.frame.width / 2, y: 0)
        let container = SKNode()
        container.addChild(trophyIcon)
        container.addChild(scoreLabelNode)
        container.position = CGPoint(x: self.size.width / 2, y: self.size.height - self.safeTop - iconSize.height / 2)
        container.zPosition = 1200
        addChild(container)
        highScoreLabel = scoreLabelNode
    }

    private func setupScoreLabel() {
        if scoreLabel == nil {
            let label = SKLabelNode(text: "\(score)")
            label.fontName = "Futura-Medium"
            label.fontSize = 30 * sizeMultiplier // Scale font size
            label.fontColor = .white
            label.horizontalAlignmentMode = .center
            label.zPosition = 1100
            addChild(label)
            scoreLabel = label
        }
        // Position the label centered horizontally in the scene
        scoreLabel?.position = CGPoint(x: self.size.width / 2, y: gridOrigin.y + blockSize * CGFloat(numRows) + 30 * sizeMultiplier)
    }

    // MARK: - Home & Settings Buttons

    private func setupHomeButton() {
        let homeTexture = SKTexture(imageNamed: "homeIcon")
        let baseButtonSize: CGFloat = 40 // Base size for non-iPad
        let buttonSize = CGSize(width: baseButtonSize * sizeMultiplier, height: baseButtonSize * sizeMultiplier)
        let homeButtonNode = SKSpriteNode(texture: homeTexture, color: .clear, size: buttonSize)
        let xPos = 20 + buttonSize.width / 2 // Adjust padding if needed
        let yPos = self.size.height - self.safeTop - buttonSize.height / 2
        homeButtonNode.position = CGPoint(x: xPos, y: yPos)
        homeButtonNode.zPosition = 1500
        addChild(homeButtonNode)
        homeButton = homeButtonNode
    }

    private func setupSettingsButton() {
        let settingsTexture = SKTexture(imageNamed: "settingsIcon")
        let baseButtonSize: CGFloat = 40 // Base size for non-iPad
        let buttonSize = CGSize(width: baseButtonSize * sizeMultiplier, height: baseButtonSize * sizeMultiplier)
        let settingsButtonNode = SKSpriteNode(texture: settingsTexture)
        settingsButtonNode.name = "settingsButton"
        settingsButtonNode.size = buttonSize
        let xPos = self.size.width - 20 - settingsButtonNode.size.width / 2 // Adjust padding if needed
        let yPos = self.size.height - self.safeTop - settingsButtonNode.size.height / 2
        settingsButtonNode.position = CGPoint(x: xPos, y: yPos)
        settingsButtonNode.zPosition = 1500
        addChild(settingsButtonNode)
        settingsButton = settingsButtonNode
    }

    // MARK: - Restart Popup Handling

    private func showRestartPopup() {
        Analytics.logEvent("restart_popup_button_tapped", parameters: nil)
        playClickSound()
        guard let view = self.view else { return }
        let popup = RestartPopupView(frame: view.bounds)

        popup.onYes = { [weak self] in
            Analytics.logEvent("restart_popup_yes_button_tapped", parameters: nil)
            self?.playClickSound()
            self?.restartGame()
        }
        popup.onNo = { [weak self] in
            Analytics.logEvent("restart_popup_no_button_tapped", parameters: nil)
            self?.playClickSound()
        }
        view.addSubview(popup)
    }

    private func restartGame() {
        guard let rootVC = view?.window?.rootViewController else {
            resetGame()
            return
        }
        if !adsRemoved, let interstitial = interstitial {
            pauseBackgroundMusic()
            interstitial.present(from: rootVC)
        } else {
            resetGame()
        }
    }

    private func goHome() {
        scoreLabel?.removeFromParent()
        scoreLabel = nil
        deleteSavedGameState()
        if let view = self.view {
            let transition = SKTransition.fade(withDuration: 0.5)
            let homeScene = GameScene(size: self.size)
            homeScene.scaleMode = .aspectFill
            view.presentScene(homeScene, transition: transition)
        }
    }

    private func thresholdForRotationSpawn() -> Int {
        Int.random(in: 5...7)
    }

    private func thresholdForBlackSpawn() -> Int {
        Int.random(in: 8...10)
    }

    private func startGame() {
        startButton?.removeFromParent()
        if let savedState = loadGameState() {
            resumeGame(from: savedState)
        } else {
            deleteSavedGameState()
            hasGameStarted = true
            score = 0
            updateScoreLabel()
            grid = Array(repeating: Array(repeating: nil, count: numColumns), count: numRows)

            // Use banner height (defaulting to 50) to compute the new bottom offset.
            let bannerHeight = bannerView?.frame.height ?? 50
            let bottomOffset = safeBottom + bannerHeight

            // Adjust grid width based on device type
            var gridWidth: CGFloat
            if UIDevice.current.userInterfaceIdiom == .pad {
                gridWidth = self.size.width * 0.75 // 3/4th of the screen width on iPad
            } else {
                gridWidth = self.size.width - 2 * gridMargin // Existing calculation for non-iPad
            }

            blockSize = gridWidth / CGFloat(numColumns)
            let gridHeight = blockSize * CGFloat(numRows)
            let leftover = self.size.height - bottomOffset - gridHeight
            gridOrigin = CGPoint(x: (self.size.width - gridWidth) / 2, y: bottomOffset + leftover/2) // Center the grid on iPad
            setupScoreLabel()
            setupOrUpdateGridOverlay(gridWidth: gridWidth, gridHeight: gridHeight)

            let gap = gridOrigin.y - bottomOffset
            let spawnCenterY = bottomOffset + gap/2
            spawnOptionPositions = [
                CGPoint(x: gridOrigin.x + (gridWidth * 1/6), y: spawnCenterY),
                CGPoint(x: gridOrigin.x + (gridWidth * 3/6), y: spawnCenterY),
                CGPoint(x: gridOrigin.x + (gridWidth * 5/6), y: spawnCenterY)
            ]
            spawnCounter = 0
            spawnThreshold = thresholdForRotationSpawn()
            blackSpawnCounter = 0
            blackSpawnThreshold = thresholdForBlackSpawn()
            reviveCount = 0
            spawnOptions.forEach { $0.removeFromParent() }
            spawnOptions.removeAll()
            refillSpawnOptions(displayScale: 0.4)
            setupHomeButton()
            setupSettingsButton()
            setupGridBackground(gridWidth: gridWidth, gridHeight: gridHeight)
            drawGridLines(gridWidth: gridWidth, gridHeight: gridHeight)
            addGridBorder(gridWidth: gridWidth, gridHeight: gridHeight)
        }
    }

    // MARK: - Grid Background & Border

    private func setupGridBackground(gridWidth: CGFloat, gridHeight: CGFloat) {
        let gridBG = SKSpriteNode(color: gridAreaColor, size: CGSize(width: gridWidth, height: gridHeight))
        gridBG.position = CGPoint(x: gridOrigin.x + gridWidth/2, y: gridOrigin.y + gridHeight/2)
        gridBG.zPosition = 1
        addChild(gridBG)
    }

    private func setupOrUpdateGridOverlay(gridWidth: CGFloat, gridHeight: CGFloat) {
        if gridOverlay == nil {
            let cropNode = SKCropNode()
            cropNode.position = gridOrigin
            cropNode.zPosition = 1100
            let mask = SKShapeNode(rect: CGRect(x: 0, y: 0, width: gridWidth, height: gridHeight))
            mask.fillColor = .white
            cropNode.maskNode = mask
            addChild(cropNode)
            gridOverlay = cropNode
        } else {
            gridOverlay!.position = gridOrigin
            if let mask = gridOverlay?.maskNode as? SKShapeNode {
                mask.path = CGPath(rect: CGRect(x: 0, y: 0, width: gridWidth, height: gridHeight), transform: nil)
            }
        }
    }

    private func drawGridLines(gridWidth: CGFloat, gridHeight: CGFloat) {
        let path = CGMutablePath()
        for row in 0..<numRows {
            for col in 0..<numColumns {
                let cellX = gridOrigin.x + CGFloat(col) * blockSize
                let cellY = gridOrigin.y + CGFloat(row) * blockSize
                let cellRect = CGRect(x: cellX, y: cellY, width: blockSize, height: blockSize)
                path.addPath(UIBezierPath(rect: cellRect).cgPath)
            }
        }
        let gridLines = SKShapeNode(path: path)
        gridLines.strokeColor = .black
        gridLines.lineWidth = 1.0
        gridLines.fillColor = .clear
        gridLines.zPosition = 2
        addChild(gridLines)
    }

    // MARK: - Add Grid Border with Drop Shadow

    private func addGridBorder(gridWidth: CGFloat, gridHeight: CGFloat) {
        let gridRect = CGRect(x: gridOrigin.x, y: gridOrigin.y, width: gridWidth, height: gridHeight)
        let borderWidth: CGFloat = 4.0
        let outerRect = gridRect.insetBy(dx: -borderWidth, dy: -borderWidth)

        let borderPath = UIBezierPath()
        borderPath.append(UIBezierPath(roundedRect: outerRect, cornerRadius: 0))
        borderPath.append(UIBezierPath(roundedRect: gridRect, cornerRadius: 0))
        borderPath.usesEvenOddFillRule = true

        let gridBorder = SKShapeNode(path: borderPath.cgPath)
        gridBorder.fillColor = .blockLightBlue
        gridBorder.strokeColor = .clear
        gridBorder.zPosition = 600
        addChild(gridBorder)

        let shadowOffset: CGFloat = 1.0
        let shadowOuterRect = outerRect.insetBy(dx: -shadowOffset, dy: -shadowOffset)
        let shadowPath = UIBezierPath()
        shadowPath.append(UIBezierPath(roundedRect: shadowOuterRect, cornerRadius: 0))
        shadowPath.append(UIBezierPath(roundedRect: outerRect, cornerRadius: 0))
        shadowPath.usesEvenOddFillRule = true

        let shadowNode = SKShapeNode(path: shadowPath.cgPath)
        shadowNode.fillColor = UIColor.black.withAlphaComponent(0.2)
        shadowNode.strokeColor = .clear
        shadowNode.zPosition = gridBorder.zPosition - 1
        addChild(shadowNode)
    }

    // MARK: - Tetromino Creation & Spawn

    private func createTetrominoPiece() -> SKNode {
        let baseIndex = Int.random(in: 0..<tetrominoes.count)
        let baseTetromino = tetrominoes[baseIndex]
        let rotations = baseTetromino.rotations
        let rotationIndex = Int.random(in: 0..<rotations.count)
        let tetromino = rotations[rotationIndex]
        let color = UIColor.allCustomColors.randomElement()!
        let piece = SKNode()
        piece.name = "piece"
        piece.userData = NSMutableDictionary()
        piece.userData?["baseIndex"] = baseIndex
        piece.userData?["rotationIndex"] = rotationIndex
        piece.userData?["blockColor"] = color
        piece.userData?["isBlackSpawn"] = NSNumber(value: false)
        drawTetromino(for: piece, with: tetromino, color: color)
        piece.userData?["originalSpawnPosition"] = NSValue(cgPoint: .zero)
        piece.userData?["displayScale"] = 0.4
        return piece
    }

    // MARK: - Black Spawn Creation

    private func createBlackSpawnPiece() -> SKNode {
        let piece = SKNode()
        piece.name = "piece"
        piece.userData = NSMutableDictionary()
        piece.userData?["isBlackSpawn"] = NSNumber(value: true)
        let sprite = SKSpriteNode(imageNamed: "blast.png")
        sprite.size = CGSize(width: blockSize, height: blockSize)
        sprite.position = .zero
        piece.addChild(sprite)
        piece.userData?["originalSpawnPosition"] = NSValue(cgPoint: .zero)
        piece.userData?["displayScale"] = 1.0
        return piece
    }

    private func createCustomBlock(color: UIColor, size: CGSize) -> SKNode {
        let blockNode = SKNode()
        blockNode.userData = NSMutableDictionary()
        blockNode.userData?["blockColor"] = color
        let borderThickness = size.width * 0.15
        let innerSize = CGSize(width: size.width - 2 * borderThickness, height: size.height - 2 * borderThickness)
        let innerSquare = SKSpriteNode(color: color, size: innerSize)
        innerSquare.position = .zero
        blockNode.addChild(innerSquare)
        let topPoints = [
            CGPoint(x: -size.width/2, y: size.height/2),
            CGPoint(x: size.width/2, y: size.height/2),
            CGPoint(x: innerSize.width/2, y: innerSize.height/2),
            CGPoint(x: -innerSize.width/2, y: innerSize.height/2)
        ]
        addTrapezoid(to: blockNode, points: topPoints, fillColor: color.adjusted(by: 20))
        let bottomPoints = [
            CGPoint(x: -size.width/2, y: -size.height/2),
            CGPoint(x: size.width/2, y: -size.height/2),
            CGPoint(x: innerSize.width/2, y: -innerSize.height/2),
            CGPoint(x: -innerSize.width/2, y: -innerSize.height/2)
        ]
        addTrapezoid(to: blockNode, points: bottomPoints, fillColor: color.adjusted(by: -20))
        let leftPoints = [
            CGPoint(x: -size.width/2, y: size.height/2),
            CGPoint(x: -innerSize.width/2, y: innerSize.height/2),
            CGPoint(x: -innerSize.width/2, y: -innerSize.height/2),
            CGPoint(x: -size.width/2, y: -size.height/2)
        ]
        addTrapezoid(to: blockNode, points: leftPoints, fillColor: color.adjusted(by: -10))
        let rightPoints = [
            CGPoint(x: size.width/2, y: size.height/2),
            CGPoint(x: size.width/2, y: -size.height/2),
            CGPoint(x: innerSize.width/2, y: -innerSize.height/2),
            CGPoint(x: innerSize.width/2, y: innerSize.height/2)
        ]
        addTrapezoid(to: blockNode, points: rightPoints, fillColor: color.adjusted(by: 10))
        let borderRect = CGRect(x: -size.width/2, y: -size.height/2, width: size.width, height: size.height)
        let borderNode = SKShapeNode(rect: borderRect)
        borderNode.strokeColor = color.adjusted(by: -50)
        borderNode.lineWidth = 1
        borderNode.fillColor = .clear
        blockNode.addChild(borderNode)
        return blockNode
    }

    // MARK: - Shadow Helpers for Spawn Pieces

    private func addShadow(to piece: SKNode) {
        piece.childNode(withName: "shadow")?.removeFromParent()
        if let isBlackSpawn = piece.userData?["isBlackSpawn"] as? Bool, isBlackSpawn {
            let shadowSprite = SKSpriteNode(imageNamed: "blast.png")
            shadowSprite.size = CGSize(width: blockSize, height: blockSize)
            shadowSprite.position = CGPoint(x: 5, y: -5)
            shadowSprite.zPosition = -1
            shadowSprite.alpha = 0.3
            shadowSprite.color = .black
            shadowSprite.colorBlendFactor = 1.0
            shadowSprite.name = "shadow"
            piece.addChild(shadowSprite)
            return
        }
        let localRects = piece.children.filter { $0.name != "shadow" }
            .map { child -> CGRect in
                let worldPos = piece.convert(child.position, to: self)
                let localPos = piece.convert(worldPos, from: self)
                return CGRect(x: localPos.x - blockSize/2, y: localPos.y - blockSize/2, width: blockSize, height: blockSize)
            }
        let newOutlinePath = CGMutablePath()
        if let first = localRects.first { newOutlinePath.addRect(first) }
        localRects.dropFirst().forEach { newOutlinePath.addRect($0) }
        let shadowNode = SKShapeNode(path: newOutlinePath)
        shadowNode.fillColor = .black
        shadowNode.strokeColor = .clear
        shadowNode.alpha = 0.3
        shadowNode.zPosition = -1
        shadowNode.name = "shadow"
        shadowNode.position = CGPoint(x: 5, y: -5)
        piece.addChild(shadowNode)
    }

    // MARK: - Refilling Spawn Options

    private func refillSpawnOptions(displayScale: CGFloat) {
        spawnOptions.forEach { $0.removeFromParent() }
        spawnOptions.removeAll()
        var exceptionSpawnAssigned = false
        for pos in spawnOptionPositions {
            var piece: SKNode
            if blackSpawnCounter >= blackSpawnThreshold {
                piece = createBlackSpawnPiece()
                blackSpawnCounter = 0
                blackSpawnThreshold = thresholdForBlackSpawn()
            } else {
                piece = createTetrominoPiece()
                spawnCounter += 1
                blackSpawnCounter += 1
                if !exceptionSpawnAssigned && spawnCounter >= spawnThreshold {
                    if let baseIndex = piece.userData?["baseIndex"] as? Int,
                       let rotationIndex = piece.userData?["rotationIndex"] as? Int {
                        let tetromino = tetrominoes[baseIndex].rotations[rotationIndex].normalized()
                        if !isSquare(tetromino: tetromino) {
                            piece.userData?["exceptionSpawn"] = true
                            piece.addRotateIcon(blockSize: blockSize)
                            exceptionSpawnAssigned = true
                            spawnCounter = 0
                            spawnThreshold = thresholdForRotationSpawn()
                        }
                    }
                }
            }
            piece.position = pos
            if let isBlack = piece.userData?["isBlackSpawn"] as? Bool, isBlack {
                piece.setScale(1.0)
                piece.userData?["displayScale"] = 1.0
                addShadow(to: piece)
            } else {
                piece.setScale(displayScale)
                piece.userData?["displayScale"] = displayScale
                addShadow(to: piece)
            }
            piece.alpha = 0
            piece.userData?["originalSpawnPosition"] = NSValue(cgPoint: pos)
            piece.zPosition = 10

            runMagicAppearance(for: piece)
            addChild(piece)
            spawnOptions.append(piece)
        }
    }

    // MARK: - Custom Blast Animation

    private func runBlastAnimation(on block: SKNode) {
        let explosionCount = 8
        for _ in 0..<explosionCount {
            let particle = SKShapeNode(circleOfRadius: 4)
            particle.fillColor = (block.userData?["blockColor"] as? UIColor) ?? .white
            particle.strokeColor = .clear
            particle.position = block.position
            particle.zPosition = block.zPosition + 1
            addChild(particle)
            let angle = CGFloat.random(in: 0..<(2 * .pi))
            let distance = CGFloat.random(in: 20...40)
            let dx = cos(angle) * distance, dy = sin(angle) * distance
            let move = SKAction.moveBy(x: dx, y: dy, duration: 0.7)
            let fade = SKAction.fadeOut(withDuration: 0.7)
            let group = SKAction.group([move, fade])
            particle.run(SKAction.sequence([group, SKAction.removeFromParent()]))
        }
        let scaleUp = SKAction.scale(to: 1.5, duration: 0.2)
        let fadeOut = SKAction.fadeOut(withDuration: 0.2)
        block.run(SKAction.sequence([SKAction.group([scaleUp, fadeOut]), SKAction.removeFromParent()]))
    }

    // MARK: - Energy Explosion Animation

    private func runEnergyExplosionFor(row: Int, col: Int) {
        let gridWidth = CGFloat(numColumns) * blockSize
        let gridHeight = CGFloat(numRows) * blockSize
        let center = CGPoint(x: gridOrigin.x + (CGFloat(col) + 0.5) * blockSize,
                             y: gridOrigin.y + (CGFloat(row) + 0.5) * blockSize)

        let horizontalBeam = SKShapeNode(rectOf: CGSize(width: gridWidth, height: blockSize/4))
        horizontalBeam.position = CGPoint(x: gridOrigin.x + gridWidth/2, y: center.y)
        horizontalBeam.fillColor = UIColor.cyan
        horizontalBeam.alpha = 0.0
        horizontalBeam.zPosition = 1200
        addChild(horizontalBeam)
        if isSoundEnabled {
            run(SKAction.playSoundFileNamed("explosion.mp3", waitForCompletion: false))
        }
        horizontalBeam.run(SKAction.sequence([
            SKAction.fadeAlpha(to: 1.0, duration: 0.05),
            SKAction.fadeOut(withDuration: 0.2),
            SKAction.removeFromParent()
        ]))

        let verticalBeam = SKShapeNode(rectOf: CGSize(width: blockSize/4, height: gridHeight))
        verticalBeam.position = CGPoint(x: center.x, y: gridOrigin.y + gridHeight/2)
        verticalBeam.fillColor = UIColor.cyan
        verticalBeam.alpha = 0.0
        verticalBeam.zPosition = 1200
        addChild(verticalBeam)
        verticalBeam.run(SKAction.sequence([
            SKAction.fadeAlpha(to: 1.0, duration: 0.05),
            SKAction.fadeOut(withDuration: 0.2),
            SKAction.removeFromParent()
        ]))

        let flash = SKShapeNode(circleOfRadius: 10)
        flash.position = center
        flash.fillColor = UIColor.white
        flash.strokeColor = UIColor.white
        flash.alpha = 0.8
        flash.zPosition = 1200
        addChild(flash)
        let flashAction = SKAction.group([
            SKAction.scale(to: 4.0, duration: 0.3),
            SKAction.fadeOut(withDuration: 0.3)
        ])
        flash.run(SKAction.sequence([flashAction, SKAction.removeFromParent()]))

        let emitter = SKEmitterNode()
        emitter.particleTexture = createParticleTexture()
        emitter.particleBirthRate = 200
        emitter.numParticlesToEmit = 100
        emitter.particleLifetime = 0.6
        emitter.particleLifetimeRange = 0.2
        emitter.emissionAngleRange = CGFloat.pi * 2
        emitter.particleSpeed = 100
        emitter.particleSpeedRange = 50
        emitter.particleAlpha = 0.9
        emitter.particleAlphaRange = 0.2
        emitter.particleAlphaSpeed = -1.0
        emitter.particleScale = 0.4
        emitter.particleScaleRange = 0.2
        emitter.particleScaleSpeed = -0.5
        emitter.particleColor = UIColor.white
        emitter.particleColorBlendFactor = 1.0
        emitter.position = center
        emitter.zPosition = 1200
        addChild(emitter)
        emitter.run(SKAction.sequence([
            SKAction.wait(forDuration: 0.1),
            SKAction.fadeOut(withDuration: 0.2),
            SKAction.removeFromParent()
        ]))
    }

    // MARK: - Particle Texture Helper

    private func createParticleTexture() -> SKTexture {
        let size = CGSize(width: 8, height: 8)
        UIGraphicsBeginImageContextWithOptions(size, false, 0)
        let context = UIGraphicsGetCurrentContext()!
        context.setFillColor(UIColor.white.cgColor)
        context.fillEllipse(in: CGRect(origin: .zero, size: size))
        let image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return SKTexture(image: image!)
    }

    // MARK: - Touch Handling for Spawn Pieces

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        if settingsPopupView != nil { return }
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)

        // Handle home button drag-out
        if let homeTouch = homeButtonTouch, touches.contains(homeTouch) {
            let homeLocation = homeTouch.location(in: self)
            if let homeButton = homeButton, !homeButton.contains(homeLocation) {
                homeButton.run(SKAction.scale(to: 1.0, duration: 0.1))
                homeButtonTouch = nil
            }
        }

        // Handle settings button drag-out
        if let settingsTouch = settingsButtonTouch, touches.contains(settingsTouch) {
            let settingsLocation = settingsTouch.location(in: self)
            if let settingsButton = settingsButton, !settingsButton.contains(settingsLocation) {
                settingsButton.run(SKAction.scale(to: 1.0, duration: 0.1))
                settingsButtonTouch = nil
            }
        }

        // Handle start button drag-out
        if !hasGameStarted, let startButton = startButton, !startButton.calculateAccumulatedFrame().contains(location) {
            startButton.run(SKAction.scale(to: 1.0, duration: 0.1))
            return
        }

        // Handle exception spawn drag detection
        if let exceptionNode = exceptionSpawnNode, let startPoint = exceptionSpawnInitialTouch {
            let distance = hypot(location.x - startPoint.x, location.y - startPoint.y)
            if distance > 10 {
                exceptionSpawnLongPressTimer?.invalidate()
                exceptionSpawnLongPressTimer = nil
                exceptionNode.removeRotateIcon()
                exceptionSpawnNode = nil
                currentPiece = exceptionNode
                isProjected = false
                let scaleUp = SKAction.scale(to: 1.0, duration: 0.1)
                let moveUp = SKAction.moveBy(x: 0, y: projectionOffset, duration: 0.1)
                let groupAction = SKAction.group([scaleUp, moveUp])
                exceptionNode.run(groupAction) {
                    self.isProjected = true
                    self.touchOffset = CGPoint(x: exceptionNode.position.x - location.x,
                                               y: exceptionNode.position.y - location.y)
                    self.defaultTouchOffsetY = self.touchOffset!.y // Store initial Y offset
                }
                exceptionNode.zPosition = spawnDragZPosition
                exceptionNode.childNode(withName: "shadow")?.removeFromParent()
                if let index = spawnOptions.firstIndex(of: exceptionNode) {
                    spawnOptions.remove(at: index)
                }
                return
            }
        }

        guard !isGameOver, let piece = currentPiece, isProjected, let offset = touchOffset else { return }

        // Calculate vertical drag direction and adjust offset
        let currentY = location.y + offset.y
        let previousY = piece.position.y
        let deltaY = currentY - previousY

        var adjustedOffsetY = offset.y
        if deltaY > 0 { // Dragging upwards
            adjustedOffsetY = min(offset.y + deltaY * 0.5, offset.y + 100) // Increase offset, max 100 extra
        } else if deltaY < 0 { // Dragging downwards
            adjustedOffsetY = max(offset.y + deltaY * 0.5, defaultTouchOffsetY) // Decrease to default
        }

        // Update piece position with adjusted offset
        piece.position = CGPoint(x: location.x + offset.x, y: location.y + adjustedOffsetY)
        piece.zPosition = spawnDragZPosition

        // Update touchOffset with the new adjusted Y value
        touchOffset = CGPoint(x: offset.x, y: adjustedOffsetY)

        highlightPotentialPlacement(for: piece)
        updatePotentialMatchGlow(for: piece)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        if settingsPopupView != nil { return }
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)

        if let homeButton = homeButton, homeButton.contains(location) {
            homeButtonTouch = touch
            homeButton.run(SKAction.scale(to: 0.9, duration: 0.1))
            return
        }

        if let settingsButton = settingsButton, settingsButton.contains(location) {
            settingsButtonTouch = touch
            settingsButton.run(SKAction.scale(to: 0.9, duration: 0.1))
            return
        }

        if !hasGameStarted, let startButton = startButton, startButton.calculateAccumulatedFrame().contains(location) {
            startButton.run(SKAction.scale(to: 0.9, duration: 0.1))
            return
        }

        if isGameOver { return }

        if currentPiece == nil {
            for option in spawnOptions {
                let frame = option.calculateAccumulatedFrame()
                let expandedFrame = frame.insetBy(dx: -frame.width * 0.5, dy: -frame.height * 0.5)
                if expandedFrame.contains(location) {
                    if isSoundEnabled {
                        run(SKAction.playSoundFileNamed("pickup.m4a", waitForCompletion: false))
                    }
                    if let isException = option.userData?["exceptionSpawn"] as? Bool, isException {
                        exceptionSpawnNode = option
                        exceptionSpawnInitialTouch = location
                        exceptionSpawnLongPressTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: false) { [weak self] _ in
                            self?.handleExceptionSpawnLongPress()
                        }
                    } else {
                        currentPiece = option
                        isProjected = false
                        let scaleUp = SKAction.scale(to: 1.0, duration: 0.1)
                        let moveUp = SKAction.moveBy(x: 0, y: projectionOffset, duration: 0.1)
                        let groupAction = SKAction.group([scaleUp, moveUp])
                        option.run(groupAction) {
                            self.isProjected = true
                            self.touchOffset = CGPoint(x: option.position.x - location.x,
                                                       y: option.position.y - location.y)
                            self.defaultTouchOffsetY = self.touchOffset!.y // Store initial Y offset
                        }
                        option.zPosition = spawnDragZPosition
                        option.childNode(withName: "shadow")?.removeFromParent()
                        if let index = spawnOptions.firstIndex(of: option) {
                            spawnOptions.remove(at: index)
                        }
                    }
                    break
                }
            }
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        if settingsPopupView != nil { return }
        clearHighlights()
        clearMatchGlow()
        currentGlowingCellIDs.removeAll()
        guard let touchEnd = touches.first else { return }
        let loc = touchEnd.location(in: self)
        exceptionSpawnLongPressTimer?.invalidate()
        exceptionSpawnLongPressTimer = nil
        if let homeTouch = homeButtonTouch, touches.contains(homeTouch) {
            if let homeButton = homeButton, homeButton.contains(loc) {
                homeButton.run(SKAction.scale(to: 1.0, duration: 0.1))
                if isGameOver {
                    goHome()
                } else {
                    showRestartPopup()
                }
            } else {
                homeButton?.run(SKAction.scale(to: 1.0, duration: 0.1))
            }
            homeButtonTouch = nil
            return
        }
        if let settingsTouch = settingsButtonTouch, touches.contains(settingsTouch) {
            if let settingsButton = settingsButton, settingsButton.contains(loc) {
                settingsButton.run(SKAction.scale(to: 1.0, duration: 0.1))
                openSettings()
            } else {
                settingsButton?.run(SKAction.scale(to: 1.0, duration: 0.1))
            }
            settingsButtonTouch = nil
            return
        }
        if isGameOver {
            let tappedNode = atPoint(loc)
            if tappedNode.name == "replayButton" {
                resetGame()
            }
            return
        }
        if !hasGameStarted, let startButton = startButton, startButton.calculateAccumulatedFrame().contains(loc) {
            startButton.run(SKAction.sequence([
                SKAction.scale(to: 0.9, duration: 0.1),
                SKAction.scale(to: 1.0, duration: 0.1),
                SKAction.run { self.startGame() }
            ]))
            return
        }
        if let exceptionNode = exceptionSpawnNode, let startPoint = exceptionSpawnInitialTouch {
            let distance = hypot(loc.x - startPoint.x, loc.y - startPoint.y)
            if distance <= 10 {
                let rotateAction = SKAction.rotate(byAngle: -CGFloat.pi/2, duration: 0.2)
                exceptionNode.run(rotateAction) {
                    Analytics.logEvent("rotation_action_completed", parameters: nil)
                    if let baseIndex = exceptionNode.userData?["baseIndex"] as? Int,
                       var rotationIndex = exceptionNode.userData?["rotationIndex"] as? Int {
                        rotationIndex = (rotationIndex + 1) % self.tetrominoes[baseIndex].rotations.count
                        exceptionNode.userData?["rotationIndex"] = rotationIndex
                    }
                    self.redrawPiece(exceptionNode)
                }
                exceptionSpawnNode = nil
                exceptionSpawnInitialTouch = nil
                return
            }
        }
        guard !isGameOver, let piece = currentPiece else { return }
        var allBlocksWithinGrid = true
        let actualBlocks = piece.children.filter { $0.name != "shadow" && $0.name != "rotateIcon" }
        for block in actualBlocks {
            let worldPos = piece.convert(block.position, to: self)
            if gridIndices(for: worldPos) == nil {
                allBlocksWithinGrid = false
                break
            }
        }
        var canPlace = true
        if allBlocksWithinGrid {
            for block in actualBlocks {
                let worldPos = piece.convert(block.position, to: self)
                if let (row, col) = gridIndices(for: worldPos), grid[row][col] != nil {
                    canPlace = false
                    break
                }
            }
        }
        if allBlocksWithinGrid && canPlace {
            let placedBlockCount = actualBlocks.count
            for block in actualBlocks {
                let worldPos = piece.convert(block.position, to: self)
                if let (row, col) = gridIndices(for: worldPos) {
                    let finalPos = positionForGrid(row: row, col: col)
                    block.removeFromParent()
                    block.position = finalPos
                    block.zPosition = 3
                    addChild(block)
                    grid[row][col] = block
                }
            }
            let isBlackSpawn = (piece.userData?["isBlackSpawn"] as? NSNumber)?.boolValue ?? false
            if !isBlackSpawn {
                var matchFound = false
                for row in 0..<numRows {
                    if grid[row].allSatisfy({ $0 != nil }) {
                        matchFound = true
                        break
                    }
                }
                if !matchFound {
                    for col in 0..<numColumns {
                        var colFull = true
                        for row in 0..<numRows {
                            if grid[row][col] == nil {
                                colFull = false
                                break
                            }
                        }
                        if colFull {
                            matchFound = true
                            break
                        }
                    }
                }
                if !matchFound, isSoundEnabled {
                    run(SKAction.playSoundFileNamed("drop.m4a", waitForCompletion: false))
                }
            }
            score += placedBlockCount
            updateScoreLabel()
            if isBlackSpawn,
               let placedBlock = actualBlocks.first,
               let (row, col) = gridIndices(for: placedBlock.position) {
                if isSoundEnabled {
                    run(SKAction.playSoundFileNamed("explosion.mp3", waitForCompletion: false))
                }
                runEnergyExplosionFor(row: row, col: col)
                for c in 0..<numColumns {
                    if let block = grid[row][c] {
                        block.removeFromParent()
                        grid[row][c] = nil
                        score += 1
                    }
                }
                for r in 0..<numRows {
                    if r == row { continue }
                    if let block = grid[r][col] {
                        block.removeFromParent()
                        grid[r][col] = nil
                        score += 1
                    }
                }
                updateScoreLabel()
            }
            piece.removeFromParent()
            currentPiece = nil
            checkAndRemoveMatches()
            if spawnOptions.isEmpty {
                refillSpawnOptions(displayScale: 0.4)
            }
            if !spawnOptions.contains(where: { self.canPlaceSpawnOption($0) }) {
                gameOver()
            }
            return
        } else {
            if let origVal = piece.userData?["originalSpawnPosition"] as? NSValue,
               let displayScale = piece.userData?["displayScale"] as? CGFloat {
                animatePieceBack(piece, to: origVal.cgPointValue, scale: displayScale)
            } else {
                let fallback = spawnOptionPositions.first ?? .zero
                animatePieceBack(piece, to: fallback, scale: 0.4)
            }
        }
        currentPiece = nil
        touchOffset = nil
        isProjected = false
        exceptionSpawnNode = nil
        exceptionSpawnInitialTouch = nil
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        touchesEnded(touches, with: event)
    }

    // MARK: - Helper: Adjust Label Position

    private func adjustedLabelPosition(for label: SKLabelNode, inRect rect: CGRect) -> CGPoint {
        let labelFrame = label.calculateAccumulatedFrame()
        let halfWidth = labelFrame.width / 2.0
        let halfHeight = labelFrame.height / 2.0
        var newX = label.position.x
        var newY = label.position.y
        if label.position.x - halfWidth < rect.minX {
            newX = rect.minX + halfWidth
        }
        if label.position.x + halfWidth > rect.maxX {
            newX = rect.maxX - halfWidth
        }
        if label.position.y - halfHeight < rect.minY {
            newY = rect.minY + halfHeight
        }
        if label.position.y + halfHeight > rect.maxY {
            newY = rect.maxY - halfHeight
        }
        return CGPoint(x: newX, y: newY)
    }

    // MARK: - Highlighting Potential Placement

    private func highlightPotentialPlacement(for piece: SKNode) {
        clearHighlights()
        var cellPositions: [CGPoint] = []
        var spawnColor: UIColor = .green
        if let firstBlock = piece.children.first, let color = firstBlock.userData?["blockColor"] as? UIColor {
            spawnColor = color
        }
        for block in piece.children {
            let worldPos = piece.convert(block.position, to: self)
            if let (row, col) = gridIndices(for: worldPos), grid[row][col] == nil {
                cellPositions.append(positionForGrid(row: row, col: col))
            } else {
                return
            }
        }
        for pos in cellPositions {
            let highlight = SKShapeNode(rectOf: CGSize(width: blockSize, height: blockSize))
            highlight.fillColor = spawnColor.withAlphaComponent(0.5)
            highlight.strokeColor = .clear
            highlight.zPosition = 1100
            highlight.position = pos
            addChild(highlight)
            highlightNodes.append(highlight)
        }
    }

    private func clearHighlights() {
        highlightNodes.forEach { $0.removeFromParent() }
        highlightNodes.removeAll()
    }

    private func clearMatchGlow() {
        matchGlowNodes.forEach { $0.removeFromParent() }
        matchGlowNodes.removeAll()
    }

    // MARK: - Highlight Helper with Optional Corner Radius

    private func addHighlight(at pos: CGPoint, withColor color: UIColor, cornerRadius: CGFloat = 0) {
        let highlightShape = SKShapeNode(rectOf: CGSize(width: blockSize, height: blockSize), cornerRadius: cornerRadius)
        highlightShape.fillColor = color.withAlphaComponent(0.5)
        highlightShape.strokeColor = .clear
        highlightShape.position = pos
        highlightShape.zPosition = 1100
        addChild(highlightShape)
        matchGlowNodes.append(highlightShape)
        let emitter = createHighlightEmitter(for: .white)
        emitter.position = .zero
        emitter.zPosition = 1110
        highlightShape.addChild(emitter)
    }

    private func createHighlightEmitter(for color: UIColor) -> SKEmitterNode {
        let emitter = SKEmitterNode()
        emitter.particleTexture = createParticleTexture()
        emitter.particleBirthRate = 15
        emitter.numParticlesToEmit = 0
        emitter.particleLifetime = 1.0
        emitter.particleLifetimeRange = 0.3
        emitter.emissionAngleRange = CGFloat.pi * 2
        emitter.particleSpeed = 20
        emitter.particleSpeedRange = 5
        emitter.particleAlpha = 0.8
        emitter.particleAlphaRange = 0.2
        emitter.particleAlphaSpeed = -0.8
        emitter.particleScale = 0.2
        emitter.particleScaleRange = 0.1
        emitter.particleScaleSpeed = -0.1
        emitter.particleColor = color
        emitter.particleColorBlendFactor = 1.0
        emitter.particlePositionRange = CGVector(dx: blockSize/2, dy: blockSize/2)
        emitter.advanceSimulationTime(1)
        return emitter
    }

    // MARK: - Update Potential Match Glow

    private func updatePotentialMatchGlow(for piece: SKNode) {
        if let isBlackSpawn = piece.userData?["isBlackSpawn"] as? Bool, isBlackSpawn {
            let spawnColor = UIColor.white
            if let indices = gridIndices(for: piece.position) {
                let row = indices.row, col = indices.col
                if grid[row][col] != nil {
                    clearMatchGlow()
                    currentGlowingCellIDs.removeAll()
                    return
                }
                var newGlowingCellIDs = Set<String>()
                var newGlowPositions = [String: CGPoint]()
                for c in 0..<numColumns {
                    let id = "\(row)-\(c)"
                    newGlowingCellIDs.insert(id)
                    newGlowPositions[id] = positionForGrid(row: row, col: c)
                }
                for r in 0..<numRows {
                    let id = "\(r)-\(col)"
                    newGlowingCellIDs.insert(id)
                    newGlowPositions[id] = positionForGrid(row: r, col: col)
                }
                if newGlowingCellIDs != currentGlowingCellIDs {
                    clearMatchGlow()
                    currentGlowingCellIDs = newGlowingCellIDs
                    for (_, pos) in newGlowPositions {
                        addHighlight(at: pos, withColor: spawnColor, cornerRadius: 0)
                    }
                }
            } else {
                clearMatchGlow()
                currentGlowingCellIDs.removeAll()
            }
            return
        }

        let blocks = piece.children.filter { $0.name != "shadow" && $0.name != "rotateIcon" }
        guard !blocks.isEmpty else {
            if !currentGlowingCellIDs.isEmpty {
                clearMatchGlow()
                currentGlowingCellIDs.removeAll()
            }
            return
        }
        var spawnColor: UIColor = .green
        if let firstBlock = piece.children.first, let color = firstBlock.userData?["blockColor"] as? UIColor {
            spawnColor = color
        }
        var pieceIndices: [(row: Int, col: Int)] = []
        for block in blocks {
            let worldPos = piece.convert(block.position, to: self)
            if let idx = gridIndices(for: worldPos), grid[idx.row][idx.col] == nil {
                pieceIndices.append(idx)
            } else {
                if !currentGlowingCellIDs.isEmpty {
                    clearMatchGlow()
                    currentGlowingCellIDs.removeAll()
                }
                return
            }
        }
        var rowsDict: [Int: Set<Int>] = [:]
        var colsDict: [Int: Set<Int>] = [:]
        for (row, col) in pieceIndices {
            rowsDict[row, default: []].insert(col)
            colsDict[col, default: []].insert(row)
        }
        var newGlowingCellIDs = Set<String>()
        var newGlowPositions = [String: CGPoint]()
        for (row, pieceCols) in rowsDict {
            var placedCols: Set<Int> = []
            for col in 0..<numColumns {
                if grid[row][col] != nil { placedCols.insert(col) }
            }
            let union = pieceCols.union(placedCols)
            if union.count == numColumns {
                for col in 0..<numColumns {
                    let id = "\(row)-\(col)"
                    newGlowingCellIDs.insert(id)
                    newGlowPositions[id] = positionForGrid(row: row, col: col)
                }
            }
        }
        for (col, pieceRows) in colsDict {
            var placedRows: Set<Int> = []
            for row in 0..<numRows {
                if grid[row][col] != nil { placedRows.insert(row) }
            }
            let union = pieceRows.union(placedRows)
            if union.count == numRows {
                for row in 0..<numRows {
                    let id = "\(row)-\(col)"
                    newGlowingCellIDs.insert(id)
                    newGlowPositions[id] = positionForGrid(row: row, col: col)
                }
            }
        }
        if newGlowingCellIDs.isEmpty {
            if !currentGlowingCellIDs.isEmpty {
                clearMatchGlow()
                currentGlowingCellIDs.removeAll()
            }
            return
        }
        if newGlowingCellIDs != currentGlowingCellIDs {
            clearMatchGlow()
            currentGlowingCellIDs = newGlowingCellIDs
            for (_, pos) in newGlowPositions {
                addHighlight(at: pos, withColor: spawnColor)
            }
        }
    }

    // MARK: - Match Removal

    private func checkAndRemoveMatches() {
        var fullRows = Set<Int>()
        var fullCols = Set<Int>()
        for row in 0..<numRows where grid[row].allSatisfy({ $0 != nil }) {
            fullRows.insert(row)
        }
        for col in 0..<numColumns {
            var colFull = true
            for row in 0..<numRows {
                if grid[row][col] == nil {
                    colFull = false
                    break
                }
            }
            if colFull { fullCols.insert(col) }
        }
        var removedCount = 0
        if !fullRows.isEmpty || !fullCols.isEmpty {
            if isSoundEnabled {
                run(SKAction.playSoundFileNamed("removeMatch.wav", waitForCompletion: false))
            }
        }
        for row in 0..<numRows {
            for col in 0..<numColumns {
                if (fullRows.contains(row) || fullCols.contains(col)), let block = grid[row][col] {
                    removedCount += 1
                    runBlastAnimation(on: block)
                    grid[row][col] = nil
                }
            }
        }
        if removedCount > 0 {
            score += removedCount
            updateScoreLabel()
            let gridWidth = CGFloat(numColumns) * blockSize
            let gridHeight = CGFloat(numRows) * blockSize
            let centerPos = CGPoint(x: gridOrigin.x + gridWidth / 2, y: gridOrigin.y + gridHeight / 2)
            comboCounter += 1
            if let overlay = gridOverlay {
                let localPos = CGPoint(x: centerPos.x - gridOrigin.x, y: centerPos.y - gridOrigin.y)
                let overlayRect = CGRect(x: 0, y: 0, width: gridWidth, height: gridHeight)
                if comboCounter > 1 {
                    let comboText = (comboCounter == 2) ? "Combo" : "Combo \(comboCounter - 1)"

                    // Create combo shadow label
                    let comboShadowLabel = SKLabelNode(text: comboText)
                    comboShadowLabel.fontName = scoreLabel?.fontName ?? "Futura-Medium"
                    comboShadowLabel.fontSize = (scoreLabel?.fontSize ?? 30) * 1.2
                    comboShadowLabel.fontColor = UIColor.black.withAlphaComponent(0.7)
                    comboShadowLabel.position = CGPoint(x: localPos.x + 2, y: localPos.y - 2)
                    comboShadowLabel.zPosition = 1299
                    overlay.addChild(comboShadowLabel)
                    comboShadowLabel.position = adjustedLabelPosition(for: comboShadowLabel, inRect: overlayRect)

                    // Create main combo label
                    let comboLabel = SKLabelNode(text: comboText)
                    comboLabel.fontName = scoreLabel?.fontName ?? "Futura-Medium"
                    comboLabel.fontSize = (scoreLabel?.fontSize ?? 30) * 1.2
                    comboLabel.fontColor = UIColor(red: 1.0, green: 0.84, blue: 0.0, alpha: 1.0)
                    comboLabel.position = localPos
                    comboLabel.zPosition = 1300
                    overlay.addChild(comboLabel)
                    comboLabel.position = adjustedLabelPosition(for: comboLabel, inRect: overlayRect)

                    // Combo fade-out sequence
                    let fadeOutCombo = SKAction.fadeOut(withDuration: 0.2)
                    let removeCombo = SKAction.removeFromParent()
                    let comboSequence = SKAction.sequence([
                        SKAction.wait(forDuration: 0.7),
                        fadeOutCombo,
                        removeCombo
                    ])
                    comboLabel.run(comboSequence)
                    comboShadowLabel.run(comboSequence)

                    // Instead of adding the score popup immediately, we add it after a delay.
                    let delayBeforePopup = SKAction.wait(forDuration: 1.0) // Wait until combo labels fade out
                    let addPopupAction = SKAction.run { [self] in
                        // Create popup shadow label with initial alpha = 0
                        let popUpShadowLabel = SKLabelNode(text: "+\(removedCount)")
                        popUpShadowLabel.fontName = scoreLabel?.fontName ?? "Futura-Medium"
                        popUpShadowLabel.fontSize = scoreLabel?.fontSize ?? 30
                        popUpShadowLabel.fontColor = UIColor.black.withAlphaComponent(0.7)
                        popUpShadowLabel.position = CGPoint(x: localPos.x + 2, y: localPos.y - 2)
                        popUpShadowLabel.zPosition = 1199
                        popUpShadowLabel.alpha = 0
                        overlay.addChild(popUpShadowLabel)
                        popUpShadowLabel.position = adjustedLabelPosition(for: popUpShadowLabel, inRect: overlayRect)

                        // Create main popup label with initial alpha = 0
                        let popUpLabel = SKLabelNode(text: "+\(removedCount)")
                        popUpLabel.fontName = scoreLabel?.fontName ?? "Futura-Medium"
                        popUpLabel.fontSize = scoreLabel?.fontSize ?? 30
                        popUpLabel.fontColor = .white
                        popUpLabel.position = localPos
                        popUpLabel.zPosition = 1200
                        popUpLabel.alpha = 0
                        overlay.addChild(popUpLabel)
                        popUpLabel.position = adjustedLabelPosition(for: popUpLabel, inRect: overlayRect)

                        // Fade in the popup labels, display them briefly, then fade out and remove.
                        let fadeInPopup = SKAction.fadeIn(withDuration: 0.2)
                        let waitPopup = SKAction.wait(forDuration: 0.5)
                        let fadeOutPopup = SKAction.fadeOut(withDuration: 0.2)
                        let removePopup = SKAction.removeFromParent()
                        let popupSequence = SKAction.sequence([
                            fadeInPopup,
                            waitPopup,
                            fadeOutPopup,
                            removePopup
                        ])
                        popUpLabel.run(popupSequence)
                        popUpShadowLabel.run(popupSequence)
                    }
                    let popupSequenceOverall = SKAction.sequence([delayBeforePopup, addPopupAction])
                    overlay.run(popupSequenceOverall)
                } else {
                    // When there is no combo (comboCounter == 1), show the popup immediately.
                    let popUpShadowLabel = SKLabelNode(text: "+\(removedCount)")
                    popUpShadowLabel.fontName = scoreLabel?.fontName ?? "Futura-Medium"
                    popUpShadowLabel.fontSize = scoreLabel?.fontSize ?? 30
                    popUpShadowLabel.fontColor = UIColor.black.withAlphaComponent(0.7)
                    popUpShadowLabel.position = CGPoint(x: localPos.x + 2, y: localPos.y - 2)
                    popUpShadowLabel.zPosition = 1199
                    overlay.addChild(popUpShadowLabel)
                    popUpShadowLabel.position = adjustedLabelPosition(for: popUpShadowLabel, inRect: overlayRect)

                    let popUpLabel = SKLabelNode(text: "+\(removedCount)")
                    popUpLabel.fontName = scoreLabel?.fontName ?? "Futura-Medium"
                    popUpLabel.fontSize = scoreLabel?.fontSize ?? 30
                    popUpLabel.fontColor = .white
                    popUpLabel.position = localPos
                    popUpLabel.zPosition = 1200
                    overlay.addChild(popUpLabel)
                    popUpLabel.position = adjustedLabelPosition(for: popUpLabel, inRect: overlayRect)

                    let fadeOutPopup = SKAction.fadeOut(withDuration: 0.2)
                    let removePopup = SKAction.removeFromParent()
                    let popupSequence = SKAction.sequence([
                        SKAction.wait(forDuration: 0.5),
                        fadeOutPopup,
                        removePopup
                    ])
                    popUpLabel.run(popupSequence)
                    popUpShadowLabel.run(popupSequence)
                }
            }
        } else {
            comboCounter = 0
        }
    }


    // MARK: - Score Update

    private func updateScoreLabel() {
        scoreLabel?.text = "\(score)"
        let currentHighScore = UserDefaults.standard.integer(forKey: "highScore")
        if score > currentHighScore {
            UserDefaults.standard.set(score, forKey: "highScore")
            highScoreLabel?.text = "\(score)"
        }
    }

    // MARK: - Piece Animation Helper

    private func animatePieceBack(_ piece: SKNode, to position: CGPoint, scale: CGFloat) {
        let moveBack = SKAction.move(to: position, duration: 0.2)
        let scaleBack = SKAction.scale(to: scale, duration: 0.2)
        piece.run(SKAction.group([moveBack, scaleBack])) {
            if !self.spawnOptions.contains(piece) {
                piece.zPosition = 10
                self.spawnOptions.append(piece)
            }
            self.addShadow(to: piece)
            if let isException = piece.userData?["exceptionSpawn"] as? Bool, isException {
                piece.removeRotateIcon()
                piece.addRotateIcon(blockSize: self.blockSize)
            }
        }
    }

    // MARK: - Game Over & Reset

    // Add this property to GameScene class to track if the rating popup has been shown
    private var hasShownRatingPopup = UserDefaults.standard.bool(forKey: "hasShownRatingPopup") {
        didSet {
            UserDefaults.standard.set(hasShownRatingPopup, forKey: "hasShownRatingPopup")
        }
    }

    // Add a method to pause music
    private func pauseBackgroundMusic() {
        if isMusicEnabled {
            backgroundMusic?.removeFromParent()
            backgroundMusic?.isPaused = true
        }
    }

    // Add a method to resume music
    private func resumeBackgroundMusic() {
        if isMusicEnabled {
            if let bgMusic = self.backgroundMusic {
                bgMusic.removeFromParent()
                bgMusic.isPaused = false
                self.addChild(bgMusic)
            }
        }
    }

    // Updated gameOver() method in GameScene class
    private func gameOver() {
        Analytics.logEvent("game_over_popup", parameters: ["score": score, "high-score": UserDefaults.standard.integer(forKey: "highScore")])
        guard !isGameOver else { return }
        isGameOver = true
        deleteSavedGameState()
        run(SKAction.sequence([
            SKAction.wait(forDuration: 1.0),
            SKAction.run {
                if self.isSoundEnabled {
                    self.run(SKAction.playSoundFileNamed("gameOverSound.mp3", waitForCompletion: false))
                }
                if let view = self.view {
                    if self.reviveCount >= 3 && !self.hasShownRatingPopup {
                        self.showRatingPopup()
                        self.hasShownRatingPopup = true
                    }
                    let popup = GameOverPopupView(frame: view.bounds)
                    popup.scoreLabel.text = "Score: \(self.score)"
                    popup.reviveButton.isHidden = (self.reviveCount >= 3)
                    popup.onRevive = { [weak self, weak popup] in
                        Analytics.logEvent("game_over_revive_button_tapped", parameters: ["count": self?.reviveCount ?? 0, "score": self?.score ?? 0])
                        self?.playClickSound()
                        guard let self = self,
                              let rootVC = self.view?.window?.rootViewController else { return }
                        popup?.removeFromSuperview()
                        self.pendingAction = {
                            self.reviveCount += 1
                            self.isGameOver = false
                            self.refillSpawnOptions(displayScale: 0.4)
                            if !self.spawnOptions.contains(where: { self.canPlaceSpawnOption($0) }) {
                                self.gameOver()
                            }
                        }
                        if !self.adsRemoved, let interstitial = self.interstitial {
                            self.pauseBackgroundMusic() // Pause music before showing ad
                            interstitial.present(from: rootVC)
                        } else {
                            self.pendingAction?()
                            self.pendingAction = nil
                        }
                    }
                    popup.onRestart = { [weak self, weak popup] in
                        Analytics.logEvent("game_over_restart_button_tapped", parameters: ["count": self?.reviveCount ?? 0, "score": self?.score ?? 0])
                        self?.playClickSound()
                        popup?.removeFromSuperview()
                        self?.restartGame()
                    }
                    view.addSubview(popup)
                }
            }
        ]))
    }

    // Add this new method to GameScene class to show the rating popup
    private func showRatingPopup() {
        if #available(iOS 14.0, *) {
            // Use SKStoreReviewController for iOS 14 and later
            if let scene = self.view?.window?.windowScene {
                SKStoreReviewController.requestReview(in: scene)
            }
        } else {
            // Fallback for older iOS versions: Open App Store review URL
            if let url = URL(string: "itms-apps://itunes.apple.com/app/id6742162544?action=write-review") {
                UIApplication.shared.open(url, options: [:], completionHandler: nil)
            }
        }
    }

    private func resetGame() {
        gameOverOverlay?.removeFromParent()
        gameOverOverlay = nil
        isGameOver = false
        score = 0
        spawnCounter = 0
        spawnThreshold = thresholdForRotationSpawn()
        blackSpawnCounter = 0
        blackSpawnThreshold = thresholdForBlackSpawn()
        reviveCount = 0
        updateScoreLabel()
        for row in 0..<numRows {
            for col in 0..<numColumns {
                grid[row][col]?.removeFromParent()
                grid[row][col] = nil
            }
        }
        currentPiece?.removeFromParent()
        currentPiece = nil
        spawnOptions.forEach { $0.removeFromParent() }
        spawnOptions.removeAll()
        homeButton?.removeFromParent()
        homeButton = nil
        settingsButton?.removeFromParent()
        settingsButton = nil
        deleteSavedGameState()
        refillSpawnOptions(displayScale: 0.4)
        setupHomeButton()
        setupSettingsButton()
    }

    // MARK: - Grid Helpers

    private func gridIndices(for point: CGPoint) -> (row: Int, col: Int)? {
        let xRel = point.x - gridOrigin.x
        let yRel = point.y - gridOrigin.y
        guard xRel >= 0, yRel >= 0 else { return nil }
        let col = Int(xRel / blockSize)
        let row = Int(yRel / blockSize)
        return (row < numRows && col < numColumns) ? (row, col) : nil
    }

    private func positionForGrid(row: Int, col: Int) -> CGPoint {
        return CGPoint(x: gridOrigin.x + CGFloat(col) * blockSize + blockSize/2,
                       y: gridOrigin.y + CGFloat(row) * blockSize + blockSize/2)
    }

    private func canPlaceTetromino(baseIndex: Int, rotationIndex: Int) -> Bool {
        let tetromino = tetrominoes[baseIndex].rotations[rotationIndex]
        let offsets = tetromino.offsets
        let minX = offsets.map { $0.x }.min() ?? 0
        let maxX = offsets.map { $0.x }.max() ?? 0
        let minY = offsets.map { $0.y }.min() ?? 0
        let maxY = offsets.map { $0.y }.max() ?? 0
        let widthInBlocks = CGFloat(maxX - minX + 1)
        let heightInBlocks = CGFloat(maxY - minY + 1)
        let offsetX = widthInBlocks * blockSize / 2
        let offsetY = heightInBlocks * blockSize / 2

        let blockPositions = offsets.map { CGPoint(x: (CGFloat($0.x - minX) * blockSize + blockSize/2) - offsetX,
                                                   y: (CGFloat($0.y - minY) * blockSize + blockSize/2) - offsetY) }

        for row in 0..<numRows {
            for col in 0..<numColumns {
                let basePos = positionForGrid(row: row, col: col)
                var valid = true
                for blockPos in blockPositions {
                    let finalPos = CGPoint(x: basePos.x + blockPos.x, y: basePos.y + blockPos.y)
                    if let (r, c) = gridIndices(for: finalPos) {
                        if grid[r][c] != nil {
                            valid = false
                            break
                        }
                    } else {
                        valid = false
                        break
                    }
                }
                if valid { return true }
            }
        }
        return false
    }

    private func canPlaceSpawnOption(_ piece: SKNode) -> Bool {
        if let isBlackValue = piece.userData?["isBlackSpawn"] as? Bool, isBlackValue {
            return true
        }
        guard let baseIndex = piece.userData?["baseIndex"] as? Int,
              let rotationIndex = piece.userData?["rotationIndex"] as? Int else { return false }
        if let exceptionSpawn = piece.userData?["exceptionSpawn"] as? Bool, exceptionSpawn {
            let rotations = tetrominoes[baseIndex].rotations
            for idx in 0..<rotations.count {
                if canPlaceTetromino(baseIndex: baseIndex, rotationIndex: idx) {
                    return true
                }
            }
            return false
        } else {
            return canPlaceTetromino(baseIndex: baseIndex, rotationIndex: rotationIndex)
        }
    }

    // MARK: - Run Magic Appearance

    private func runMagicAppearance(for piece: SKNode) {
        if let isBlackSpawn = piece.userData?["isBlackSpawn"] as? Bool, isBlackSpawn {
            let fadeInAction = SKAction.fadeIn(withDuration: 0.0)
            piece.run(fadeInAction)
            let shrink = SKAction.scale(to: 0.8, duration: 0.5)
            let expand = SKAction.scale(to: 1.0, duration: 0.5)
            let pulse = SKAction.sequence([shrink, expand])
            let repeatPulse = SKAction.repeatForever(pulse)
            piece.run(repeatPulse)
            return
        }
        let fadeInAction = SKAction.fadeIn(withDuration: 0.0)
        piece.run(fadeInAction)
        let localRects = piece.children.filter { $0.name != "shadow" && $0.name != "rotateIcon" }
            .map { child -> CGRect in
                let pos = child.position
                return CGRect(x: pos.x - blockSize/2, y: pos.y - blockSize/2, width: blockSize, height: blockSize)
            }
        let borderPath = CGMutablePath()
        if let first = localRects.first { borderPath.addRect(first) }
        localRects.dropFirst().forEach { borderPath.addRect($0) }
        let borderMagic = SKShapeNode(path: borderPath)
        borderMagic.strokeColor = UIColor.white
        borderMagic.lineWidth = 4
        borderMagic.glowWidth = 8
        borderMagic.alpha = 0
        borderMagic.zPosition = piece.zPosition + 1
        piece.addChild(borderMagic)
        let fadeInBorder = SKAction.fadeAlpha(to: 0.3, duration: 0.2)
        let wait = SKAction.wait(forDuration: 0.1)
        let fadeOutBorder = SKAction.fadeOut(withDuration: 0.2)
        borderMagic.run(SKAction.sequence([fadeInBorder, wait, fadeOutBorder, SKAction.removeFromParent()]))
    }

    private func playClickSound() {
        if isSoundEnabled {
            run(SKAction.playSoundFileNamed("click.wav", waitForCompletion: false))
        }
    }
}
