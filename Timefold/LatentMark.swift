//
//  LatentMark.swift
//  Latent
//
//  The Latent logomark: two overlapping peaks.
//
//  Drawn as vectors rather than shipped as a raster, so one definition serves
//  the 20pt nameplate glyph, the widget, the share card and the 1024pt app
//  icon — and so the overlap can carry a colour of its own.
//

import SwiftUI

/// Proportions of the mark, normalised to the height of a single peak.
/// Measured off the logo artwork: each peak's half-base is 0.60 of its height,
/// the two apexes sit 0.486 apart, and every corner is rounded at 0.10.
enum LatentMarkGeometry {
    static let halfBase: CGFloat = 0.60
    static let apexGap:  CGFloat = 0.486
    static let corner:   CGFloat = 0.10

    /// Width-to-height ratio of the finished mark.
    static let aspect: CGFloat = halfBase * 2 + apexGap
}

/// A single peak. All three corners are rounded — that is what keeps the mark
/// feeling soft at a nameplate's 20pt rather than sharp like clip art.
struct LatentPeak: Shape {
    /// How far this peak's apex sits right of the left peak's, in units of
    /// peak height.
    var apexOffset: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let h = rect.height
        let r = LatentMarkGeometry.corner * h
        let apexX = rect.minX + (LatentMarkGeometry.halfBase + apexOffset) * h

        let apex  = CGPoint(x: apexX, y: rect.minY)
        let left  = CGPoint(x: apexX - LatentMarkGeometry.halfBase * h, y: rect.maxY)
        let right = CGPoint(x: apexX + LatentMarkGeometry.halfBase * h, y: rect.maxY)

        // Start at the middle of the base, then let each arc round the corner
        // it turns through. Passing the ideal (sharp) corners means the radius
        // is honoured exactly, whatever size the mark is drawn at.
        var path = Path()
        path.move(to: CGPoint(x: apexX, y: rect.maxY))
        path.addArc(tangent1End: right, tangent2End: apex,  radius: r)
        path.addArc(tangent1End: apex,  tangent2End: left,  radius: r)
        path.addArc(tangent1End: left,  tangent2End: right, radius: r)
        path.closeSubpath()
        return path
    }
}

/// The lens where the two peaks cross.
///
/// This is its own filled shape rather than a blend mode on the peaks above
/// it: multiplying the two peak colours lands on #F63431, and the artwork's
/// overlap is the softer, pinker #E4424C. The overlap is the whole idea of the
/// mark — two exposures on one frame — so it gets its own colour.
struct LatentPeakCore: Shape {
    func path(in rect: CGRect) -> Path {
        LatentPeak().path(in: rect)
            .intersection(LatentPeak(apexOffset: LatentMarkGeometry.apexGap).path(in: rect))
    }
}

struct LatentMark: View {
    /// Fill both peaks with a single colour instead of the brand gradients.
    /// Widget accessory families and tinted home-screen icons render
    /// monochrome, and a gradient turns to mud in them.
    var monochrome: Color?

    init(monochrome: Color? = nil) {
        self.monochrome = monochrome
    }

    var body: some View {
        ZStack {
            if let monochrome {
                LatentPeak().fill(monochrome)
                LatentPeak(apexOffset: LatentMarkGeometry.apexGap).fill(monochrome)
            } else {
                LatentPeak().fill(Self.leftPeak)
                LatentPeak(apexOffset: LatentMarkGeometry.apexGap).fill(Self.rightPeak)
                LatentPeakCore().fill(Self.core)
            }
        }
        .aspectRatio(LatentMarkGeometry.aspect, contentMode: .fit)
    }

    // MARK: Palette — sampled from the logo artwork, top to bottom of each peak.

    /// #FCAC85 → #FD8A5E
    static let leftPeak = LinearGradient(
        colors: [Color(red: 0.988, green: 0.675, blue: 0.522),
                 Color(red: 0.992, green: 0.541, blue: 0.369)],
        startPoint: .top, endPoint: .bottom)

    /// #F88A8D → #F85F84
    static let rightPeak = LinearGradient(
        colors: [Color(red: 0.973, green: 0.541, blue: 0.553),
                 Color(red: 0.973, green: 0.373, blue: 0.518)],
        startPoint: .top, endPoint: .bottom)

    /// #F3604D → #E4424C
    static let core = LinearGradient(
        colors: [Color(red: 0.953, green: 0.376, blue: 0.302),
                 Color(red: 0.894, green: 0.259, blue: 0.298)],
        startPoint: .top, endPoint: .bottom)
}

#Preview {
    VStack(spacing: 40) {
        LatentMark().frame(height: 20)
        LatentMark().frame(height: 80)
        LatentMark(monochrome: .primary).frame(height: 40)
    }
    .padding(40)
}

#if canImport(UIKit)
import UIKit

extension LatentPeak {
    /// The same outline as `path(in:)`, as a CGPath.
    ///
    /// The share card is drawn with UIKit into a 1080x1920 bitmap rather than
    /// by SwiftUI, and that image is the most public thing the app makes — it
    /// gets posted. Deriving it from this one definition is what stops the mark
    /// on a shared story from drifting away from the mark in the app.
    func cgPath(in rect: CGRect) -> CGPath {
        let h = rect.height
        let r = LatentMarkGeometry.corner * h
        let apexX = rect.minX + (LatentMarkGeometry.halfBase + apexOffset) * h

        let apex  = CGPoint(x: apexX, y: rect.minY)
        let left  = CGPoint(x: apexX - LatentMarkGeometry.halfBase * h, y: rect.maxY)
        let right = CGPoint(x: apexX + LatentMarkGeometry.halfBase * h, y: rect.maxY)

        let path = CGMutablePath()
        path.move(to: CGPoint(x: apexX, y: rect.maxY))
        path.addArc(tangent1End: right, tangent2End: apex,  radius: r)
        path.addArc(tangent1End: apex,  tangent2End: left,  radius: r)
        path.addArc(tangent1End: left,  tangent2End: right, radius: r)
        path.closeSubpath()
        return path
    }
}
#endif
