//
//  ImageStorage.swift
//  Rugby AS
//
//  選手の顔写真 / チームのロゴ画像を端末のドキュメントディレクトリに
//  保存・読込・削除するユーティリティ。SwiftData にはファイル名だけを保持する。
//

import Foundation
import UIKit

enum ImageStorage {
    private static var directory: URL {
        URL.documentsDirectory
    }

    // body が再描画されるたびにディスクから読み直すと体感ラグが出るので、
    // 画像はファイル名をキーにメモリキャッシュしておく。
    private static let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 128
        return cache
    }()

    /// データをリサイズ（長辺 1024px）+ JPEG quality 0.8 で保存し、ファイル名を返す。失敗時 nil。
    static func save(_ data: Data) -> String? {
        guard let image = UIImage(data: data) else { return nil }
        let resized = resized(image, maxDimension: 1024)
        guard let jpegData = resized.jpegData(compressionQuality: 0.8) else { return nil }
        return write(jpegData, image: resized, fileExtension: "jpg")
    }

    /// 透明背景を保持したまま PNG で保存する。背景削除後の選手写真に使う。
    static func savePNG(_ data: Data) -> String? {
        guard let image = UIImage(data: data) else { return nil }
        let resized = resized(image, maxDimension: 1024)
        guard let pngData = resized.pngData() else { return nil }
        return write(pngData, image: resized, fileExtension: "png")
    }

    // 名簿カード用の縮小画像キャッシュ。原寸(最大1024px)を15枚並べて
    // 毎フレーム縮小合成すると重いので、表示サイズに近い縮小版を別に持つ。
    private static let thumbnailCache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 256
        return cache
    }()

    /// カード表示用の縮小版(長辺 maxDimension)。ファイル名は使い回されない
    /// (UUID)前提なのでキャッシュは名前+サイズをキーにする。
    static func thumbnail(named name: String, maxDimension: CGFloat = 360) -> UIImage? {
        let key = "thumb-\(Int(maxDimension))-\(name)" as NSString
        if let cached = thumbnailCache.object(forKey: key) {
            return cached
        }
        guard let original = image(named: name) else { return nil }
        let small = resized(original, maxDimension: maxDimension)
        thumbnailCache.setObject(small, forKey: key)
        return small
    }

    static func image(named name: String) -> UIImage? {
        let key = name as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }
        let url = directory.appendingPathComponent(name)
        guard let data = try? Data(contentsOf: url), let image = UIImage(data: data) else {
            return nil
        }
        cache.setObject(image, forKey: key)
        return image
    }

    static func delete(named name: String) {
        let url = directory.appendingPathComponent(name)
        try? FileManager.default.removeItem(at: url)
        cache.removeObject(forKey: name as NSString)
    }

    private static func write(_ data: Data, image: UIImage, fileExtension: String) -> String? {
        let name = UUID().uuidString + "." + fileExtension
        let url = directory.appendingPathComponent(name)
        do {
            try data.write(to: url)
            cache.setObject(image, forKey: name as NSString)
            return name
        } catch {
            return nil
        }
    }

    /// 長辺を maxDimension に収めるリサイズ。既に小さいときは原画を返す。
    private static func resized(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let originalSize = image.size
        let longestSide = max(originalSize.width, originalSize.height)
        guard longestSide > maxDimension else { return image }
        let scale = maxDimension / longestSide
        let newSize = CGSize(width: originalSize.width * scale, height: originalSize.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = false
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
