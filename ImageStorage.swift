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
        let name = UUID().uuidString + ".jpg"
        let url = directory.appendingPathComponent(name)
        do {
            try jpegData.write(to: url)
            cache.setObject(resized, forKey: name as NSString)
            return name
        } catch {
            return nil
        }
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

    /// 長辺を maxDimension に収めるリサイズ。既に小さいときは原画を返す。
    private static func resized(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let originalSize = image.size
        let longestSide = max(originalSize.width, originalSize.height)
        guard longestSide > maxDimension else { return image }
        let scale = maxDimension / longestSide
        let newSize = CGSize(width: originalSize.width * scale, height: originalSize.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
