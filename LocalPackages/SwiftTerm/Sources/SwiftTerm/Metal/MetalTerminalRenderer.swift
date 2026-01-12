//
//  MetalTerminalRenderer.swift
//  SwiftTerm
//
//  Metal 기반 터미널 렌더러 - 메인 클래스
//

#if os(macOS)
import Metal
import MetalKit
import QuartzCore
import AppKit
import CoreText

/// Metal 기반 터미널 렌더러
/// CVDisplayLink를 사용하여 디스플레이 주사율에 동기화된 렌더링
public class MetalTerminalRenderer {
    private let device: MTLDevice
    private let metalLayer: CAMetalLayer

    /// 컴포넌트
    private let glyphAtlas: GlyphAtlasManager
    private let cellBuffer: CellBufferManager
    private let pipeline: MetalRenderPipeline

    /// 터미널 참조
    private weak var terminal: Terminal?

    /// 렌더링 설정
    private var cellDimension: CGSize
    private var scaleFactor: CGFloat

    /// 디스플레이 링크
    private var displayLink: CVDisplayLink?
    private var needsRedraw: Bool = true
    private let renderLock = NSLock()

    /// 시간 (애니메이션용)
    private var startTime: CFTimeInterval = CACurrentMediaTime()

    /// 색상 매핑 클로저
    public var colorMapper: ((Attribute.Color, Bool, Bool) -> simd_float4)? {
        didSet {
            cellBuffer.colorMapper = colorMapper
        }
    }

    /// 배경색
    public var backgroundColor: simd_float4 = simd_float4(0, 0, 0, 1) {
        didSet { setNeedsDisplay() }
    }

    /// 커서 색상
    public var cursorColor: simd_float4 = simd_float4(1, 1, 1, 0.8)

    /// 커서 스타일
    public var cursorStyle: MetalCursorStyle = .block

    /// 커서 표시 여부
    public var showCursor: Bool = true

    /// 선택 영역 (시작, 끝 좌표)
    public var selectionRange: (start: (Int, Int), end: (Int, Int))? {
        didSet { setNeedsDisplay() }
    }

    public init(
        layer: CAMetalLayer,
        terminal: Terminal,
        cellDimension: CGSize,
        scaleFactor: CGFloat = 2.0
    ) throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw MetalRendererError.noMetalDevice
        }

        self.device = device
        self.metalLayer = layer
        self.terminal = terminal
        self.cellDimension = cellDimension
        self.scaleFactor = scaleFactor

        // Metal layer 설정
        layer.device = device
        layer.pixelFormat = .bgra8Unorm
        layer.framebufferOnly = true
        layer.contentsScale = scaleFactor

        // 컴포넌트 초기화
        self.glyphAtlas = try GlyphAtlasManager(device: device)
        self.cellBuffer = try CellBufferManager(device: device, maxCells: terminal.cols * (terminal.rows + 1000))
        self.pipeline = try MetalRenderPipeline(device: device)

        setupDisplayLink()
    }

    deinit {
        stopDisplayLink()
    }

    // MARK: - 폰트 설정

    /// 폰트 설정
    public func setFonts(normal: NSFont, bold: NSFont, italic: NSFont, boldItalic: NSFont) {
        let ctNormal = normal as CTFont
        let ctBold = bold as CTFont
        let ctItalic = italic as CTFont
        let ctBoldItalic = boldItalic as CTFont

        glyphAtlas.setFonts(
            normal: ctNormal,
            bold: ctBold,
            italic: ctItalic,
            boldItalic: ctBoldItalic,
            scaleFactor: scaleFactor
        )
        setNeedsDisplay()
    }

    /// 셀 크기 업데이트
    public func updateCellDimension(_ newDimension: CGSize) {
        cellDimension = newDimension
        setNeedsDisplay()
    }

    // MARK: - 디스플레이 링크

    private func setupDisplayLink() {
        var displayLink: CVDisplayLink?
        CVDisplayLinkCreateWithActiveCGDisplays(&displayLink)

        guard let link = displayLink else { return }
        self.displayLink = link

        let callback: CVDisplayLinkOutputCallback = { _, _, _, _, _, userInfo -> CVReturn in
            guard let userInfo = userInfo else { return kCVReturnSuccess }
            let renderer = Unmanaged<MetalTerminalRenderer>.fromOpaque(userInfo).takeUnretainedValue()
            renderer.displayLinkCallback()
            return kCVReturnSuccess
        }

        CVDisplayLinkSetOutputCallback(link, callback, Unmanaged.passUnretained(self).toOpaque())
        CVDisplayLinkStart(link)
    }

    private func stopDisplayLink() {
        if let link = displayLink {
            CVDisplayLinkStop(link)
            displayLink = nil
        }
    }

    private func displayLinkCallback() {
        renderLock.lock()
        let shouldRender = needsRedraw
        renderLock.unlock()

        if shouldRender {
            DispatchQueue.main.async { [weak self] in
                self?.render()
            }
        }
    }

    // MARK: - 렌더링

    /// 다시 그리기 요청
    public func setNeedsDisplay() {
        renderLock.lock()
        needsRedraw = true
        renderLock.unlock()
    }

    /// 렌더링 수행
    public func render() {
        renderLock.lock()
        needsRedraw = false
        renderLock.unlock()

        guard let terminal = terminal,
              let drawable = metalLayer.nextDrawable() else { return }

        // 셀 데이터 업데이트
        cellBuffer.updateCells(
            terminal: terminal,
            glyphAtlas: glyphAtlas,
            cellDimension: cellDimension,
            scaleFactor: scaleFactor
        )

        // 유니폼 업데이트
        let viewportSize = CGSize(
            width: metalLayer.drawableSize.width,
            height: metalLayer.drawableSize.height
        )
        let time = Float(CACurrentMediaTime() - startTime)
        cellBuffer.updateUniforms(
            viewportSize: viewportSize,
            cellSize: cellDimension,
            atlasSize: CGSize(width: 2048, height: 2048),
            time: time,
            scaleFactor: scaleFactor
        )

        // 배경색
        let clearColor = MTLClearColor(
            red: Double(backgroundColor.x),
            green: Double(backgroundColor.y),
            blue: Double(backgroundColor.z),
            alpha: Double(backgroundColor.w)
        )

        // 커서 정보
        var cursorInfo: CursorRenderInfo?
        if showCursor {
            let cursorX = terminal.buffer.x
            let cursorY = terminal.buffer.y - terminal.buffer.yDisp

            if cursorY >= 0 && cursorY < terminal.rows {
                cursorInfo = CursorRenderInfo(
                    position: simd_float2(
                        Float(cursorX) * Float(cellDimension.width * scaleFactor),
                        Float(cursorY) * Float(cellDimension.height * scaleFactor)
                    ),
                    color: cursorColor,
                    style: cursorStyle,
                    visible: true
                )
            }
        }

        // 선택 영역 변환
        let selectionRects = computeSelectionRects()

        // 렌더링
        pipeline.render(
            to: drawable,
            instanceBuffer: cellBuffer.instanceBufferRef,
            uniformBuffer: cellBuffer.uniformBufferRef,
            glyphTexture: glyphAtlas.atlasTexture,
            instanceCount: cellBuffer.currentInstanceCount,
            clearColor: clearColor,
            cursorInfo: cursorInfo,
            selectionRects: selectionRects
        )
    }

    /// 선택 영역을 렌더링 가능한 사각형으로 변환
    private func computeSelectionRects() -> [simd_float4]? {
        guard let range = selectionRange,
              let terminal = terminal else { return nil }

        var rects: [simd_float4] = []
        let (startCol, startRow) = range.start
        let (endCol, endRow) = range.end

        let scaledCellWidth = Float(cellDimension.width * scaleFactor)
        let scaledCellHeight = Float(cellDimension.height * scaleFactor)

        for row in startRow...endRow {
            let screenRow = row - terminal.buffer.yDisp
            if screenRow < 0 || screenRow >= terminal.rows { continue }

            let rowStartCol = (row == startRow) ? startCol : 0
            let rowEndCol = (row == endRow) ? endCol : terminal.cols - 1

            let rect = simd_float4(
                Float(rowStartCol) * scaledCellWidth,
                Float(screenRow) * scaledCellHeight,
                Float(rowEndCol - rowStartCol + 1) * scaledCellWidth,
                scaledCellHeight
            )
            rects.append(rect)
        }

        return rects.isEmpty ? nil : rects
    }

    // MARK: - 리사이즈

    /// 뷰포트 리사이즈
    public func resize(to size: CGSize) {
        metalLayer.drawableSize = CGSize(
            width: size.width * scaleFactor,
            height: size.height * scaleFactor
        )
        setNeedsDisplay()
    }

    /// 스케일 팩터 변경
    public func updateScaleFactor(_ newFactor: CGFloat) {
        scaleFactor = newFactor
        metalLayer.contentsScale = newFactor
        glyphAtlas.invalidateCache()
        setNeedsDisplay()
    }

    // MARK: - 캐시 관리

    /// 글리프 캐시 무효화
    public func invalidateGlyphCache() {
        glyphAtlas.invalidateCache()
        setNeedsDisplay()
    }

    /// 캐시 통계
    public var cacheStats: (glyphCount: Int, atlasUsage: Float) {
        (glyphAtlas.cachedGlyphCount, glyphAtlas.atlasUsage)
    }
}

#endif
