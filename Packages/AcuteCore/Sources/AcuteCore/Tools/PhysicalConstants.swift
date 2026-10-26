import Foundation

/// A physical constant with its symbol, value and SI unit.
public struct PhysicalConstant: Hashable, Sendable, Identifiable {
    public var id: String { symbol + name }
    public var name: String
    public var symbol: String
    public var value: Double
    public var unit: String
    /// Exact by definition of the SI (2019).
    public var isExact: Bool
    public var group: Group

    public enum Group: String, CaseIterable, Sendable {
        case universal = "Splošne konstante"
        case electromagnetic = "Elektromagnetizem"
        case atomic = "Atomska in jedrska fizika"
        case thermodynamics = "Termodinamika"
        case astronomy = "Zemlja in vesolje"
    }
}

/// CODATA 2022 values (NIST, physics.nist.gov/constants) and IAU astronomical values.
public enum PhysicalConstants {
    public static let all: [PhysicalConstant] = [
        PhysicalConstant(name: "Hitrost svetlobe v vakuumu", symbol: "c", value: 299_792_458, unit: "m/s", isExact: true, group: .universal),
        PhysicalConstant(name: "Gravitacijska konstanta", symbol: "G", value: 6.674_30e-11, unit: "N m²/kg²", isExact: false, group: .universal),
        PhysicalConstant(name: "Normni težni pospešek", symbol: "g₀", value: 9.806_65, unit: "m/s²", isExact: true, group: .universal),
        PhysicalConstant(name: "Planckova konstanta", symbol: "h", value: 6.626_070_15e-34, unit: "J s", isExact: true, group: .universal),
        PhysicalConstant(name: "Reducirana Planckova konstanta", symbol: "ħ", value: 1.054_571_817e-34, unit: "J s", isExact: true, group: .universal),
        PhysicalConstant(name: "Osnovni naboj", symbol: "e₀", value: 1.602_176_634e-19, unit: "A s", isExact: true, group: .electromagnetic),
        PhysicalConstant(name: "Influenčna konstanta", symbol: "ε₀", value: 8.854_187_8188e-12, unit: "A s/(V m)", isExact: false, group: .electromagnetic),
        PhysicalConstant(name: "Indukcijska konstanta", symbol: "μ₀", value: 1.256_637_061_27e-6, unit: "V s/(A m)", isExact: false, group: .electromagnetic),
        PhysicalConstant(name: "Coulombova konstanta 1/(4πε₀)", symbol: "k", value: 8.987_551_7862e9, unit: "N m²/(A s)²", isExact: false, group: .electromagnetic),
        PhysicalConstant(name: "Faradayeva konstanta", symbol: "F", value: 96_485.332_12, unit: "A s/mol", isExact: true, group: .electromagnetic),
        PhysicalConstant(name: "Masa elektrona", symbol: "mₑ", value: 9.109_383_7139e-31, unit: "kg", isExact: false, group: .atomic),
        PhysicalConstant(name: "Masa protona", symbol: "mₚ", value: 1.672_621_925_95e-27, unit: "kg", isExact: false, group: .atomic),
        PhysicalConstant(name: "Masa nevtrona", symbol: "mₙ", value: 1.674_927_500_56e-27, unit: "kg", isExact: false, group: .atomic),
        PhysicalConstant(name: "Atomska masna enota", symbol: "u", value: 1.660_539_068_92e-27, unit: "kg", isExact: false, group: .atomic),
        PhysicalConstant(name: "Masa delca α", symbol: "m_α", value: 6.644_657_3450e-27, unit: "kg", isExact: false, group: .atomic),
        PhysicalConstant(name: "Elektronvolt", symbol: "eV", value: 1.602_176_634e-19, unit: "J", isExact: true, group: .atomic),
        PhysicalConstant(name: "Rydbergova konstanta", symbol: "R∞", value: 10_973_731.568_157, unit: "1/m", isExact: false, group: .atomic),
        PhysicalConstant(name: "Bohrov polmer", symbol: "r_B", value: 5.291_772_105_44e-11, unit: "m", isExact: false, group: .atomic),
        PhysicalConstant(name: "Konstanta fine strukture", symbol: "α", value: 7.297_352_5643e-3, unit: "", isExact: false, group: .atomic),
        PhysicalConstant(name: "Avogadrovo število", symbol: "N_A", value: 6.022_140_76e23, unit: "1/mol", isExact: true, group: .thermodynamics),
        PhysicalConstant(name: "Boltzmannova konstanta", symbol: "k_B", value: 1.380_649e-23, unit: "J/K", isExact: true, group: .thermodynamics),
        PhysicalConstant(name: "Splošna plinska konstanta", symbol: "R", value: 8.314_462_618, unit: "J/(mol K)", isExact: true, group: .thermodynamics),
        PhysicalConstant(name: "Stefanova konstanta", symbol: "σ", value: 5.670_374_419e-8, unit: "W/(m² K⁴)", isExact: true, group: .thermodynamics),
        PhysicalConstant(name: "Wienova konstanta", symbol: "k_W", value: 2.897_771_955e-3, unit: "m K", isExact: true, group: .thermodynamics),
        PhysicalConstant(name: "Normalni zračni tlak", symbol: "p₀", value: 101_325, unit: "Pa", isExact: true, group: .thermodynamics),
        PhysicalConstant(name: "Molska prostornina idealnega plina (0 °C, p₀)", symbol: "V_m", value: 22.413_969_54e-3, unit: "m³/mol", isExact: true, group: .thermodynamics),
        PhysicalConstant(name: "Astronomska enota", symbol: "au", value: 149_597_870_700, unit: "m", isExact: true, group: .astronomy),
        PhysicalConstant(name: "Svetlobno leto", symbol: "ly", value: 9.460_730_472_5808e15, unit: "m", isExact: true, group: .astronomy),
        PhysicalConstant(name: "Masa Zemlje", symbol: "M_Z", value: 5.9722e24, unit: "kg", isExact: false, group: .astronomy),
        PhysicalConstant(name: "Povprečni polmer Zemlje", symbol: "r_Z", value: 6.371e6, unit: "m", isExact: false, group: .astronomy),
        PhysicalConstant(name: "Masa Sonca", symbol: "M_S", value: 1.988_47e30, unit: "kg", isExact: false, group: .astronomy),
        PhysicalConstant(name: "Masa Lune", symbol: "M_L", value: 7.342e22, unit: "kg", isExact: false, group: .astronomy),
        PhysicalConstant(name: "Povprečna razdalja Zemlja–Luna", symbol: "r_ZL", value: 3.844e8, unit: "m", isExact: false, group: .astronomy),
    ]
}
