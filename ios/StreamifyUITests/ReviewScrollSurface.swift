import XCTest

extension XCUIApplication {
    /// iPad sheets have their own viewport. A drag at 98% of the display lands
    /// outside that sheet, so screen reviews must scroll the actual content.
    var reviewScrollSurface: XCUIElement {
        let navigation = navigationBars.allElementsBoundByIndex.last { $0.exists && $0.isHittable }
        let width = navigation?.frame.width ?? frame.width
        let surfaces = scrollViews.allElementsBoundByIndex + collectionViews.allElementsBoundByIndex + tables.allElementsBoundByIndex
        return surfaces.first { surface in
            let bounds = surface.frame
            return surface.exists && bounds.height > 200 && abs(bounds.width - width) < 40 && surface.isHittable
        } ?? self
    }
}
