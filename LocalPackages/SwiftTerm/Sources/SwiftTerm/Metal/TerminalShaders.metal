//
//  TerminalShaders.metal
//  SwiftTerm
//
//  Metal 셰이더 - 터미널 렌더링용
//

#include <metal_stdlib>
using namespace metal;

// MARK: - 데이터 구조체

/// 글리프 인스턴스 데이터 (Swift의 GlyphInstance와 일치)
struct GlyphInstance {
    float2 position;
    float2 atlasOffset;
    float2 atlasSize;
    float4 foregroundColor;
    float4 backgroundColor;
    uint flags;
    float3 padding;
};

/// 유니폼 데이터
struct TerminalUniforms {
    float2 viewportSize;
    float2 cellSize;
    float2 atlasSize;
    float time;
    float padding;
};

/// Vertex 출력
struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
    float4 foregroundColor;
    float4 backgroundColor;
    uint flags;
};

/// 배경 전용 Vertex 출력
struct BackgroundVertexOut {
    float4 position [[position]];
    float4 backgroundColor;
};

// MARK: - 플래그 상수
constant uint FLAG_UNDERLINE = 0x01;
constant uint FLAG_STRIKETHROUGH = 0x02;
constant uint FLAG_INVERSE = 0x04;
constant uint FLAG_BLINK = 0x08;

// MARK: - 글리프 셰이더

/// 글리프 Vertex Shader - 인스턴스드 쿼드 렌더링
vertex VertexOut glyphVertexShader(
    uint vertexID [[vertex_id]],
    uint instanceID [[instance_id]],
    constant GlyphInstance* instances [[buffer(0)]],
    constant TerminalUniforms& uniforms [[buffer(1)]]
) {
    // 쿼드 정점 (2개 삼각형 = 6 정점)
    float2 positions[6] = {
        float2(0, 0), float2(1, 0), float2(0, 1),
        float2(1, 0), float2(1, 1), float2(0, 1)
    };

    float2 texCoords[6] = {
        float2(0, 0), float2(1, 0), float2(0, 1),
        float2(1, 0), float2(1, 1), float2(0, 1)
    };

    GlyphInstance inst = instances[instanceID];

    // 정점 위치 계산 (픽셀 좌표)
    float2 pos = inst.position + positions[vertexID] * uniforms.cellSize;

    // NDC로 변환 (-1 to 1)
    float2 ndc = (pos / uniforms.viewportSize) * 2.0 - 1.0;
    ndc.y = -ndc.y; // Y축 반전 (Metal은 상단이 -1)

    // UV 좌표 계산
    float2 uv = inst.atlasOffset + texCoords[vertexID] * inst.atlasSize;

    VertexOut out;
    out.position = float4(ndc, 0.0, 1.0);
    out.texCoord = uv;
    out.foregroundColor = inst.foregroundColor;
    out.backgroundColor = inst.backgroundColor;
    out.flags = inst.flags;

    return out;
}

/// 글리프 Fragment Shader
fragment float4 glyphFragmentShader(
    VertexOut in [[stage_in]],
    texture2d<float> glyphAtlas [[texture(0)]]
) {
    constexpr sampler texSampler(mag_filter::linear, min_filter::linear);

    // 글리프 알파 샘플링 (R 채널만 사용)
    float alpha = glyphAtlas.sample(texSampler, in.texCoord).r;

    // inverse 플래그 처리
    float4 fg = in.foregroundColor;
    float4 bg = in.backgroundColor;

    if ((in.flags & FLAG_INVERSE) != 0) {
        float4 temp = fg;
        fg = bg;
        bg = temp;
    }

    // 배경과 전경 혼합
    float4 color = mix(bg, fg, alpha);

    return color;
}

// MARK: - 배경 셰이더 (최적화: 배경만 먼저 그리기)

vertex BackgroundVertexOut backgroundVertexShader(
    uint vertexID [[vertex_id]],
    uint instanceID [[instance_id]],
    constant GlyphInstance* instances [[buffer(0)]],
    constant TerminalUniforms& uniforms [[buffer(1)]]
) {
    float2 positions[6] = {
        float2(0, 0), float2(1, 0), float2(0, 1),
        float2(1, 0), float2(1, 1), float2(0, 1)
    };

    GlyphInstance inst = instances[instanceID];
    float2 pos = inst.position + positions[vertexID] * uniforms.cellSize;
    float2 ndc = (pos / uniforms.viewportSize) * 2.0 - 1.0;
    ndc.y = -ndc.y;

    BackgroundVertexOut out;
    out.position = float4(ndc, 0.0, 1.0);

    // inverse 플래그 처리
    if ((inst.flags & FLAG_INVERSE) != 0) {
        out.backgroundColor = inst.foregroundColor;
    } else {
        out.backgroundColor = inst.backgroundColor;
    }

    return out;
}

fragment float4 backgroundFragmentShader(BackgroundVertexOut in [[stage_in]]) {
    return in.backgroundColor;
}

// MARK: - 장식 셰이더 (언더라인, 취소선)

struct DecorationVertexOut {
    float4 position [[position]];
    float4 color;
    float decorationType; // 0: none, 1: underline, 2: strikethrough
};

vertex DecorationVertexOut decorationVertexShader(
    uint vertexID [[vertex_id]],
    uint instanceID [[instance_id]],
    constant GlyphInstance* instances [[buffer(0)]],
    constant TerminalUniforms& uniforms [[buffer(1)]]
) {
    GlyphInstance inst = instances[instanceID];

    // 언더라인 또는 취소선 플래그 확인
    bool hasUnderline = (inst.flags & FLAG_UNDERLINE) != 0;
    bool hasStrikethrough = (inst.flags & FLAG_STRIKETHROUGH) != 0;

    DecorationVertexOut out;

    if (!hasUnderline && !hasStrikethrough) {
        // 장식이 없으면 화면 밖으로
        out.position = float4(-2, -2, 0, 1);
        out.decorationType = 0;
        return out;
    }

    // 라인 위치 계산
    float lineY, lineHeight;
    if (hasUnderline) {
        lineY = 0.85; // 셀 하단 근처
        lineHeight = 0.08;
        out.decorationType = 1;
    } else {
        lineY = 0.45; // 셀 중간
        lineHeight = 0.08;
        out.decorationType = 2;
    }

    float2 linePositions[6] = {
        float2(0, lineY), float2(1, lineY), float2(0, lineY + lineHeight),
        float2(1, lineY), float2(1, lineY + lineHeight), float2(0, lineY + lineHeight)
    };

    float2 pos = inst.position + linePositions[vertexID] * uniforms.cellSize;
    float2 ndc = (pos / uniforms.viewportSize) * 2.0 - 1.0;
    ndc.y = -ndc.y;

    out.position = float4(ndc, 0.0, 1.0);

    // inverse 플래그 처리
    if ((inst.flags & FLAG_INVERSE) != 0) {
        out.color = inst.backgroundColor;
    } else {
        out.color = inst.foregroundColor;
    }

    return out;
}

fragment float4 decorationFragmentShader(DecorationVertexOut in [[stage_in]]) {
    if (in.decorationType == 0) {
        discard_fragment();
    }
    return in.color;
}

// MARK: - 커서 셰이더

struct CursorVertexOut {
    float4 position [[position]];
    float4 color;
    float2 localPos; // 셀 내 로컬 좌표 (0-1)
};

vertex CursorVertexOut cursorVertexShader(
    uint vertexID [[vertex_id]],
    constant float2& cursorPosition [[buffer(0)]],
    constant TerminalUniforms& uniforms [[buffer(1)]],
    constant float4& cursorColor [[buffer(2)]]
) {
    float2 positions[6] = {
        float2(0, 0), float2(1, 0), float2(0, 1),
        float2(1, 0), float2(1, 1), float2(0, 1)
    };

    float2 pos = cursorPosition + positions[vertexID] * uniforms.cellSize;
    float2 ndc = (pos / uniforms.viewportSize) * 2.0 - 1.0;
    ndc.y = -ndc.y;

    CursorVertexOut out;
    out.position = float4(ndc, 0.0, 1.0);
    out.color = cursorColor;
    out.localPos = positions[vertexID];

    return out;
}

fragment float4 cursorFragmentShader(
    CursorVertexOut in [[stage_in]],
    constant TerminalUniforms& uniforms [[buffer(0)]],
    constant uint& cursorStyle [[buffer(1)]] // 0: block, 1: underline, 2: bar
) {
    float4 color = in.color;

    // 커서 깜빡임 (0.5초 주기)
    float blink = sin(uniforms.time * 3.14159 * 2.0) * 0.5 + 0.5;

    switch (cursorStyle) {
        case 0: // Block
            color.a *= blink;
            break;
        case 1: // Underline
            if (in.localPos.y < 0.85) {
                discard_fragment();
            }
            break;
        case 2: // Bar
            if (in.localPos.x > 0.15) {
                discard_fragment();
            }
            break;
    }

    return color;
}

// MARK: - 선택 영역 셰이더

vertex float4 selectionVertexShader(
    uint vertexID [[vertex_id]],
    uint instanceID [[instance_id]],
    constant float4* selectionRects [[buffer(0)]], // x, y, width, height
    constant TerminalUniforms& uniforms [[buffer(1)]]
) {
    float2 positions[6] = {
        float2(0, 0), float2(1, 0), float2(0, 1),
        float2(1, 0), float2(1, 1), float2(0, 1)
    };

    float4 rect = selectionRects[instanceID];
    float2 pos = float2(rect.x, rect.y) + positions[vertexID] * float2(rect.z, rect.w);
    float2 ndc = (pos / uniforms.viewportSize) * 2.0 - 1.0;
    ndc.y = -ndc.y;

    return float4(ndc, 0.0, 1.0);
}

fragment float4 selectionFragmentShader(
    float4 position [[position]],
    constant float4& selectionColor [[buffer(0)]]
) {
    return selectionColor;
}
