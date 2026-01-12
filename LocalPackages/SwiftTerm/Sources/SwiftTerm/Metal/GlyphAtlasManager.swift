//
//  GlyphAtlasManager.swift
//  SwiftTerm
//
//  글리프 텍스처 아틀라스 관리
//

#if os(macOS)
import Metal
import CoreText
import CoreGraphics
import AppKit
import simd

/// 글리프 텍스처 아틀라스 관리자
/// CoreText로 글리프를 래스터화하여 Metal 텍스처에 캐싱
public class GlyphAtlasManager {
    private let device: MTLDevice

    /// 아틀라스 텍스처
    private(set) var atlasTexture: MTLTexture!

    /// 글리프 캐시
    private var glyphCache: [GlyphKey: GlyphInfo] = [:]

    /// 아틀라스 설정
    private let atlasWidth: Int
    private let atlasHeight: Int

    /// 현재 위치 추적
    private var currentX: Int = 0
    private var currentY: Int = 0
    private var rowHeight: Int = 0

    /// 폰트 세트
    private var fonts: [CTFont] = []

    /// 스케일 팩터 (Retina 지원)
    private var scaleFactor: CGFloat = 2.0

    public init(device: MTLDevice, atlasSize: Int = 2048) throws {
        self.device = device
        self.atlasWidth = atlasSize
        self.atlasHeight = atlasSize

        try createAtlasTexture()
    }

    private func createAtlasTexture() throws {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r8Unorm,  // 단일 채널 (그레이스케일)
            width: atlasWidth,
            height: atlasHeight,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead]
        descriptor.storageMode = .managed

        guard let texture = device.makeTexture(descriptor: descriptor) else {
            throw MetalRendererError.failedToCreateTexture
        }
        atlasTexture = texture

        // 초기화 (투명하게)
        let zeroData = [UInt8](repeating: 0, count: atlasWidth * atlasHeight)
        let region = MTLRegion(
            origin: MTLOrigin(x: 0, y: 0, z: 0),
            size: MTLSize(width: atlasWidth, height: atlasHeight, depth: 1)
        )
        atlasTexture.replace(region: region, mipmapLevel: 0, withBytes: zeroData, bytesPerRow: atlasWidth)
    }

    /// 폰트 세트 설정
    public func setFonts(normal: CTFont, bold: CTFont, italic: CTFont, boldItalic: CTFont, scaleFactor: CGFloat = 2.0) {
        fonts = [normal, bold, italic, boldItalic]
        self.scaleFactor = scaleFactor
    }

    /// 폰트 인덱스로 폰트 가져오기
    private func font(for index: Int) -> CTFont? {
        guard index >= 0 && index < fonts.count else { return nil }
        return fonts[index]
    }

    /// 글리프 정보 가져오기 (캐시에 없으면 래스터화)
    public func getGlyph(character: UnicodeScalar, fontIndex: Int) -> GlyphInfo? {
        let key = GlyphKey(character: character, fontIndex: fontIndex)

        if let cached = glyphCache[key] {
            return cached
        }

        guard let font = font(for: fontIndex) else { return nil }
        return rasterizeGlyph(character: character, font: font, key: key)
    }

    /// 글리프 래스터화 및 아틀라스에 추가
    private func rasterizeGlyph(character: UnicodeScalar, font: CTFont, key: GlyphKey) -> GlyphInfo? {
        // 1. CGGlyph 얻기
        var chars = [UniChar](String(character).utf16)
        var glyphs = [CGGlyph](repeating: 0, count: chars.count)

        guard CTFontGetGlyphsForCharacters(font, &chars, &glyphs, chars.count) else {
            return nil
        }

        let glyph = glyphs[0]

        // 2. 글리프 바운딩 박스
        var boundingRect = CGRect.zero
        CTFontGetBoundingRectsForGlyphs(font, .default, [glyph], &boundingRect, 1)

        // 스케일 적용
        let scaledWidth = Int(ceil(boundingRect.width * scaleFactor)) + 4
        let scaledHeight = Int(ceil(boundingRect.height * scaleFactor)) + 4

        // 최소 크기 보장
        let glyphWidth = max(scaledWidth, 4)
        let glyphHeight = max(scaledHeight, 4)

        // 3. 아틀라스 공간 할당
        if currentX + glyphWidth > atlasWidth {
            currentX = 0
            currentY += rowHeight + 2
            rowHeight = 0
        }

        // 아틀라스가 가득 찼으면 실패
        if currentY + glyphHeight > atlasHeight {
            // TODO: 새 아틀라스 페이지 생성 또는 LRU 캐시 정리
            return nil
        }

        let uvOffset = simd_float2(
            Float(currentX) / Float(atlasWidth),
            Float(currentY) / Float(atlasHeight)
        )
        let uvSize = simd_float2(
            Float(glyphWidth) / Float(atlasWidth),
            Float(glyphHeight) / Float(atlasHeight)
        )

        // 4. CoreGraphics로 글리프 래스터화
        guard let bitmapData = rasterizeToBuffer(
            glyph: glyph,
            font: font,
            width: glyphWidth,
            height: glyphHeight,
            boundingRect: boundingRect
        ) else {
            return nil
        }

        // 5. 텍스처에 업로드
        let region = MTLRegion(
            origin: MTLOrigin(x: currentX, y: currentY, z: 0),
            size: MTLSize(width: glyphWidth, height: glyphHeight, depth: 1)
        )
        atlasTexture.replace(region: region, mipmapLevel: 0, withBytes: bitmapData, bytesPerRow: glyphWidth)

        // 6. Advance 계산
        var advances = CGSize.zero
        CTFontGetAdvancesForGlyphs(font, .default, [glyph], &advances, 1)

        // 7. 글리프 정보 생성 및 캐싱
        let info = GlyphInfo(
            uvOffset: uvOffset,
            uvSize: uvSize,
            bearing: simd_float2(
                Float(boundingRect.origin.x * scaleFactor),
                Float(boundingRect.origin.y * scaleFactor)
            ),
            advance: Float(advances.width * scaleFactor),
            pixelSize: simd_float2(Float(glyphWidth), Float(glyphHeight))
        )
        glyphCache[key] = info

        // 8. 위치 업데이트
        currentX += glyphWidth + 2
        rowHeight = max(rowHeight, glyphHeight)

        return info
    }

    /// 글리프를 비트맵 버퍼로 래스터화
    private func rasterizeToBuffer(
        glyph: CGGlyph,
        font: CTFont,
        width: Int,
        height: Int,
        boundingRect: CGRect
    ) -> [UInt8]? {
        var buffer = [UInt8](repeating: 0, count: width * height)

        let colorSpace = CGColorSpaceCreateDeviceGray()
        guard let context = CGContext(
            data: &buffer,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            return nil
        }

        // 안티앨리어싱 활성화
        context.setAllowsAntialiasing(true)
        context.setShouldAntialias(true)
        context.setShouldSmoothFonts(true)

        // 흰색으로 글리프 그리기
        context.setFillColor(gray: 1.0, alpha: 1.0)

        // 스케일 적용
        context.scaleBy(x: scaleFactor, y: scaleFactor)

        // 글리프 위치 계산 (바운딩 박스 오프셋 보정)
        var position = CGPoint(
            x: -boundingRect.origin.x + 1.0 / scaleFactor,
            y: -boundingRect.origin.y + 1.0 / scaleFactor
        )
        var glyphArray = [glyph]
        CTFontDrawGlyphs(font, &glyphArray, &position, 1, context)

        return buffer
    }

    /// 캐시 무효화
    public func invalidateCache() {
        glyphCache.removeAll()
        currentX = 0
        currentY = 0
        rowHeight = 0

        // 텍스처 초기화
        let zeroData = [UInt8](repeating: 0, count: atlasWidth * atlasHeight)
        let region = MTLRegion(
            origin: MTLOrigin(x: 0, y: 0, z: 0),
            size: MTLSize(width: atlasWidth, height: atlasHeight, depth: 1)
        )
        atlasTexture.replace(region: region, mipmapLevel: 0, withBytes: zeroData, bytesPerRow: atlasWidth)
    }

    /// 캐시된 글리프 수
    public var cachedGlyphCount: Int {
        glyphCache.count
    }

    /// 아틀라스 사용률 (0-1)
    public var atlasUsage: Float {
        let usedArea = currentY * atlasWidth + currentX * rowHeight
        let totalArea = atlasWidth * atlasHeight
        return Float(usedArea) / Float(totalArea)
    }
}

#endif
