//
//  CellBufferManager.swift
//  SwiftTerm
//
//  GPU 버퍼 관리 - Terminal 데이터를 GPU 버퍼로 변환
//

#if os(macOS)
import Metal
import simd
import AppKit

/// GPU 버퍼 관리자
/// Terminal의 셀 데이터를 GPU가 읽을 수 있는 버퍼로 변환
public class CellBufferManager {
    private let device: MTLDevice

    /// 인스턴스 버퍼 (트리플 버퍼링)
    private var instanceBuffers: [MTLBuffer] = []
    private var currentBufferIndex: Int = 0

    /// 유니폼 버퍼
    private var uniformBuffer: MTLBuffer!

    /// 최대 인스턴스 수
    private let maxInstances: Int

    /// 현재 인스턴스 수
    private(set) var currentInstanceCount: Int = 0

    /// 색상 매핑 클로저
    public var colorMapper: ((Attribute.Color, Bool, Bool) -> simd_float4)?

    public init(device: MTLDevice, maxCells: Int = 20000) throws {
        self.device = device
        self.maxInstances = maxCells

        try createBuffers()
    }

    private func createBuffers() throws {
        let instanceBufferSize = MemoryLayout<GlyphInstance>.stride * maxInstances

        // 트리플 버퍼링을 위한 3개 버퍼 생성
        for _ in 0..<3 {
            guard let buffer = device.makeBuffer(length: instanceBufferSize, options: .storageModeShared) else {
                throw MetalRendererError.failedToCreateBuffer
            }
            instanceBuffers.append(buffer)
        }

        let uniformBufferSize = MemoryLayout<TerminalUniforms>.stride
        guard let uBuffer = device.makeBuffer(length: uniformBufferSize, options: .storageModeShared) else {
            throw MetalRendererError.failedToCreateBuffer
        }
        uniformBuffer = uBuffer
    }

    /// 다음 버퍼로 전환 (트리플 버퍼링)
    private func nextBuffer() -> MTLBuffer {
        currentBufferIndex = (currentBufferIndex + 1) % 3
        return instanceBuffers[currentBufferIndex]
    }

    /// Terminal 데이터로 버퍼 업데이트
    public func updateCells(
        terminal: Terminal,
        glyphAtlas: GlyphAtlasManager,
        cellDimension: CGSize,
        scaleFactor: CGFloat
    ) {
        let buffer = terminal.buffer
        let visibleRows = buffer.yDisp..<min(buffer.yDisp + terminal.rows, buffer.lines.count)

        var instances: [GlyphInstance] = []
        instances.reserveCapacity(terminal.cols * terminal.rows)

        let scaledCellWidth = Float(cellDimension.width * scaleFactor)
        let scaledCellHeight = Float(cellDimension.height * scaleFactor)

        for row in visibleRows {
            let line = buffer.lines[row]
            let screenRow = row - buffer.yDisp

            for col in 0..<terminal.cols {
                let charData = line[col]

                // 빈 셀은 스킵 (배경만 있는 경우는 처리)
                let char = charData.getCharacter()
                let isEmpty = char == " " || char == "\0" || charData.code == 0

                // 배경색이 기본값이 아니면 렌더링 필요
                let hasBgColor = !isEmpty || charData.attribute.bg != .defaultColor

                if isEmpty && !hasBgColor {
                    continue
                }

                // 폰트 인덱스 결정
                let fontIndex = getFontIndex(style: charData.attribute.style)

                // 글리프 정보 가져오기
                var glyphInfo: GlyphInfo?
                if !isEmpty {
                    if let scalar = char.unicodeScalars.first {
                        glyphInfo = glyphAtlas.getGlyph(character: scalar, fontIndex: fontIndex)
                    }
                }

                // 인스턴스 생성
                let instance = GlyphInstance(
                    position: simd_float2(
                        Float(col) * scaledCellWidth,
                        Float(screenRow) * scaledCellHeight
                    ),
                    atlasOffset: glyphInfo?.uvOffset ?? .zero,
                    atlasSize: glyphInfo?.uvSize ?? .zero,
                    foregroundColor: mapColor(charData.attribute.fg, isForeground: true, isBold: charData.attribute.style.contains(.bold)),
                    backgroundColor: mapColor(charData.attribute.bg, isForeground: false, isBold: false),
                    flags: encodeFlags(charData.attribute.style)
                )
                instances.append(instance)
            }
        }

        // GPU 버퍼에 복사
        currentInstanceCount = min(instances.count, maxInstances)
        if currentInstanceCount > 0 {
            let buffer = nextBuffer()
            let dataSize = MemoryLayout<GlyphInstance>.stride * currentInstanceCount
            memcpy(buffer.contents(), &instances, dataSize)
        }
    }

    /// 폰트 인덱스 결정 (0: normal, 1: bold, 2: italic, 3: boldItalic)
    private func getFontIndex(style: CharacterStyle) -> Int {
        let isBold = style.contains(.bold)
        let isItalic = style.contains(.italic)

        if isBold && isItalic {
            return 3
        } else if isBold {
            return 1
        } else if isItalic {
            return 2
        }
        return 0
    }

    /// 색상 매핑
    private func mapColor(_ color: Attribute.Color, isForeground: Bool, isBold: Bool) -> simd_float4 {
        if let mapper = colorMapper {
            return mapper(color, isForeground, isBold)
        }
        return defaultColorMapper(color, isForeground: isForeground, isBold: isBold)
    }

    /// 기본 색상 매퍼
    private func defaultColorMapper(_ color: Attribute.Color, isForeground: Bool, isBold: Bool) -> simd_float4 {
        switch color {
        case .defaultColor:
            return isForeground ? simd_float4(1, 1, 1, 1) : simd_float4(0, 0, 0, 1)
        case .defaultInvertedColor:
            return isForeground ? simd_float4(0, 0, 0, 1) : simd_float4(1, 1, 1, 1)
        case .ansi256(let code):
            return ansi256ToFloat4(code, isBold: isBold)
        case .trueColor(let r, let g, let b):
            return simd_float4(Float(r) / 255.0, Float(g) / 255.0, Float(b) / 255.0, 1.0)
        }
    }

    /// ANSI 256 색상을 float4로 변환
    private func ansi256ToFloat4(_ code: UInt8, isBold: Bool) -> simd_float4 {
        // 기본 16색
        if code < 16 {
            let colors: [(Float, Float, Float)] = [
                (0.0, 0.0, 0.0),       // 0: Black
                (0.8, 0.0, 0.0),       // 1: Red
                (0.0, 0.8, 0.0),       // 2: Green
                (0.8, 0.8, 0.0),       // 3: Yellow
                (0.0, 0.0, 0.8),       // 4: Blue
                (0.8, 0.0, 0.8),       // 5: Magenta
                (0.0, 0.8, 0.8),       // 6: Cyan
                (0.8, 0.8, 0.8),       // 7: White
                (0.5, 0.5, 0.5),       // 8: Bright Black
                (1.0, 0.0, 0.0),       // 9: Bright Red
                (0.0, 1.0, 0.0),       // 10: Bright Green
                (1.0, 1.0, 0.0),       // 11: Bright Yellow
                (0.0, 0.0, 1.0),       // 12: Bright Blue
                (1.0, 0.0, 1.0),       // 13: Bright Magenta
                (0.0, 1.0, 1.0),       // 14: Bright Cyan
                (1.0, 1.0, 1.0)        // 15: Bright White
            ]

            var index = Int(code)
            if isBold && index < 8 {
                index += 8  // Bold는 밝은 색상 사용
            }

            let (r, g, b) = colors[min(index, 15)]
            return simd_float4(r, g, b, 1.0)
        }

        // 216 색상 큐브 (16-231)
        if code < 232 {
            let cubeIndex = Int(code) - 16
            let r = cubeIndex / 36
            let g = (cubeIndex / 6) % 6
            let b = cubeIndex % 6

            let toFloat: (Int) -> Float = { $0 == 0 ? 0 : Float(55 + $0 * 40) / 255.0 }
            return simd_float4(toFloat(r), toFloat(g), toFloat(b), 1.0)
        }

        // 24 그레이스케일 (232-255)
        let gray = Float(8 + (Int(code) - 232) * 10) / 255.0
        return simd_float4(gray, gray, gray, 1.0)
    }

    /// 스타일 플래그 인코딩
    private func encodeFlags(_ style: CharacterStyle) -> UInt32 {
        var flags: UInt32 = 0
        if style.contains(.underline) { flags |= GlyphFlags.underline.rawValue }
        if style.contains(.crossedOut) { flags |= GlyphFlags.strikethrough.rawValue }
        if style.contains(.inverse) { flags |= GlyphFlags.inverse.rawValue }
        if style.contains(.blink) { flags |= GlyphFlags.blink.rawValue }
        if style.contains(.bold) { flags |= GlyphFlags.bold.rawValue }
        if style.contains(.italic) { flags |= GlyphFlags.italic.rawValue }
        if style.contains(.dim) { flags |= GlyphFlags.dim.rawValue }
        if style.contains(.invisible) { flags |= GlyphFlags.hidden.rawValue }
        return flags
    }

    /// 유니폼 버퍼 업데이트
    public func updateUniforms(
        viewportSize: CGSize,
        cellSize: CGSize,
        atlasSize: CGSize,
        time: Float,
        scaleFactor: CGFloat
    ) {
        var uniforms = TerminalUniforms(
            viewportSize: simd_float2(
                Float(viewportSize.width * scaleFactor),
                Float(viewportSize.height * scaleFactor)
            ),
            cellSize: simd_float2(
                Float(cellSize.width * scaleFactor),
                Float(cellSize.height * scaleFactor)
            ),
            atlasSize: simd_float2(Float(atlasSize.width), Float(atlasSize.height)),
            time: time
        )
        memcpy(uniformBuffer.contents(), &uniforms, MemoryLayout<TerminalUniforms>.stride)
    }

    /// 현재 인스턴스 버퍼
    public var instanceBufferRef: MTLBuffer {
        instanceBuffers[currentBufferIndex]
    }

    /// 유니폼 버퍼
    public var uniformBufferRef: MTLBuffer {
        uniformBuffer
    }
}

#endif
