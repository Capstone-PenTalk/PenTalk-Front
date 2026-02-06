import UIKit

extension UIColor {
    convenience init(argb: UInt32) {
        let alpha = CGFloat((argb >> 24) & 0xFF) / 255.0
        let red = CGFloat((argb >> 16) & 0xFF) / 255.0
        let green = CGFloat((argb >> 8) & 0xFF) / 255.0
        let blue = CGFloat(argb & 0xFF) / 255.0
        self.init(red: red, green: green, blue: blue, alpha: alpha)
    }

    func argbInt() -> Int {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        let a = Int(alpha * 255.0) & 0xFF
        let r = Int(red * 255.0) & 0xFF
        let g = Int(green * 255.0) & 0xFF
        let b = Int(blue * 255.0) & 0xFF
        return (a << 24) | (r << 16) | (g << 8) | b
    }

    func hexRGB() -> String {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        let r = Int(red * 255.0) & 0xFF
        let g = Int(green * 255.0) & 0xFF
        let b = Int(blue * 255.0) & 0xFF
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
