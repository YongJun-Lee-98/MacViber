//
//  MetalTypes.swift
//  SwiftTerm
//
//  GPU 공유 데이터 구조 정의
//

#if os(macOS)
import simd
import Metal

/// GPU에서 사용할 글리프 인스턴스 데이터 (64 bytes aligned)
public struct GlyphInstance {
    /// 화면 위치 (픽셀)
    public var position: simd_float2
    /// 아틀라스 내 UV 오프셋
    public var atlasOffset: simd_float2
    /// 아틀라스 내 UV 크기
    public var atlasSize: simd_float2
    /// 전경색 (RGBA)
    public var foregroundColor: simd_float4
    /// 배경색 (RGBA)
    public var backgroundColor: simd_float4
    /// 플래그 (underline, strikethrough 등)
    public var flags: UInt32
    /// 64 bytes alignment를 위한 패딩
    public var padding: simd_float3

    public init(
        position: simd_float2 = .zero,
        atlasOffset: simd_float2 = .zero,
        atlasSize: simd_float2 = .zero,
        foregroundColor: simd_float4 = simd_float4(1, 1, 1, 1),
        backgroundColor: simd_float4 = simd_float4(0, 0, 0, 1),
        flags: UInt32 = 0
    ) {
        self.position = position
        self.atlasOffset = atlasOffset
        self.atlasSize = atlasSize
        self.foregroundColor = foregroundColor
        self.backgroundColor = backgroundColor
        self.flags = flags
        self.padding = .zero
    }
}

/// 유니폼 버퍼 데이터
public struct TerminalUniforms {
    /// 뷰포트 크기 (픽셀)
    public var viewportSize: simd_float2
    /// 셀 크기 (픽셀)
    public var cellSize: simd_float2
    /// 아틀라스 텍스처 크기
    public var atlasSize: simd_float2
    /// 시간 (커서 깜빡임용)
    public var time: Float
    /// 패딩
    public var padding: Float

    public init(
        viewportSize: simd_float2 = .zero,
        cellSize: simd_float2 = .zero,
        atlasSize: simd_float2 = simd_float2(2048, 2048),
        time: Float = 0
    ) {
        self.viewportSize = viewportSize
        self.cellSize = cellSize
        self.atlasSize = atlasSize
        self.time = time
        self.padding = 0
    }
}

/// 글리프 스타일 플래그
public struct GlyphFlags: OptionSet {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    public static let underline = GlyphFlags(rawValue: 1 << 0)
    public static let strikethrough = GlyphFlags(rawValue: 1 << 1)
    public static let inverse = GlyphFlags(rawValue: 1 << 2)
    public static let blink = GlyphFlags(rawValue: 1 << 3)
    public static let bold = GlyphFlags(rawValue: 1 << 4)
    public static let italic = GlyphFlags(rawValue: 1 << 5)
    public static let dim = GlyphFlags(rawValue: 1 << 6)
    public static let hidden = GlyphFlags(rawValue: 1 << 7)
}

/// 글리프 캐시 키
public struct GlyphKey: Hashable {
    public let character: UnicodeScalar
    public let fontIndex: Int  // 0: normal, 1: bold, 2: italic, 3: boldItalic

    public init(character: UnicodeScalar, fontIndex: Int) {
        self.character = character
        self.fontIndex = fontIndex
    }
}

/// 글리프 정보 (아틀라스 내 위치 및 메트릭)
public struct GlyphInfo {
    /// 아틀라스 내 UV 오프셋 (0-1 범위)
    public let uvOffset: simd_float2
    /// 아틀라스 내 UV 크기 (0-1 범위)
    public let uvSize: simd_float2
    /// 글리프 베어링 (오프셋)
    public let bearing: simd_float2
    /// 글리프 advance
    public let advance: Float
    /// 글리프 픽셀 크기
    public let pixelSize: simd_float2

    public init(
        uvOffset: simd_float2,
        uvSize: simd_float2,
        bearing: simd_float2,
        advance: Float,
        pixelSize: simd_float2
    ) {
        self.uvOffset = uvOffset
        self.uvSize = uvSize
        self.bearing = bearing
        self.advance = advance
        self.pixelSize = pixelSize
    }
}

/// Metal 렌더러 에러
public enum MetalRendererError: Error {
    case noMetalDevice
    case failedToCreateCommandQueue
    case failedToLoadShaderLibrary
    case failedToCreatePipelineState
    case failedToCreateTexture
    case failedToCreateBuffer
}

#endif
